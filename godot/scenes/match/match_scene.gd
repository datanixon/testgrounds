class_name MatchScene
extends Node2D
## M9 match controller (was scenes/main.gd). Driven by the router: receives a
## GameState + Session via init() instead of self-starting a skirmish. Reads
## state.is_ai for the AI branch, autosaves at end of turn, honors the
## battle-scene setting, and emits match_ended(winner) for the gameover handoff.

signal match_ended(winner: int)

const Hex = preload("res://core/hex.gd")
const Maps = preload("res://data/maps.gd")
const GameState = preload("res://core/game_state.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const Combat = preload("res://core/combat.gd")
const Abilities = preload("res://data/abilities.gd")
const AbilityResolve = preload("res://core/ability_resolve.gd")
const AI = preload("res://core/ai.gd")
const UnitTypes = preload("res://data/unit_types.gd")
const UiQueries = preload("res://core/ui_queries.gd")
const BoardScript = preload("res://scenes/board/board.gd")
const UnitsLayerScript = preload("res://scenes/match/units_layer.gd")
const OverlayScript = preload("res://scenes/match/overlay.gd")
const TopBarScript = preload("res://scenes/hud/top_bar.gd")
const InfoCardScript = preload("res://scenes/hud/info_card.gd")
const ActionMenuScript = preload("res://scenes/hud/action_menu.gd")
const SummonListScript = preload("res://scenes/hud/summon_list.gd")
const BattleSceneScript = preload("res://scenes/battle/battle_scene.gd")
const SaveGame = preload("res://core/save_game.gd")
const SettingsPanelScript = preload("res://scenes/hud/settings_panel.gd")

var state: GameState
var session = null   # set by init(); used for the battle-scene setting + on_match_won
var board: BoardScript
var overlay: Overlay
var units_layer: UnitsLayer
var cam: Camera2D
var hud: CanvasLayer
var battle_scene: BattleSceneScript
var _busy := false   # blocks board input while a cutaway or move-slide plays
var top_bar: TopBarScript
var info_card: InfoCardScript
var action_menu: ActionMenuScript
var summon_list: SummonListScript
var settings_panel = null
var selected = null
var armed = null   # {ab: Dictionary, kind: String, targets: Dictionary} when an enemy/tile ability is armed
var undo_snapshot = null   # {unit, q, r} — the pre-move position, live until the action commits
var _match_over := false   # one-shot guard so _end_match is idempotent
var _viewer := 0   # the human side (non-AI); the board renders from its vision under fog

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.1
var _panning := false

func init(p_state, p_session) -> void:
	state = p_state
	session = p_session

func _ready() -> void:
	# state was provided by init() before the node entered the tree.
	# Draw order: board (bottom) -> overlay -> tokens (top).
	board = BoardScript.new()
	board.set_map(state.map)
	add_child(board)
	overlay = OverlayScript.new()
	add_child(overlay)
	units_layer = UnitsLayerScript.new()
	_viewer = state.is_ai.find(false)
	if _viewer < 0:
		_viewer = 0
	units_layer.viewer = _viewer
	units_layer.set_state(state)
	add_child(units_layer)
	cam = Camera2D.new()
	var m = state.master_of(state.current_player)
	cam.position = Hex.axial_to_pixel(Vector2i(m["q"], m["r"]))
	add_child(cam)
	cam.make_current()
	hud = CanvasLayer.new()
	add_child(hud)
	top_bar = TopBarScript.new()
	top_bar.end_turn_pressed.connect(_on_end_turn)
	hud.add_child(top_bar)
	info_card = InfoCardScript.new()
	hud.add_child(info_card)
	action_menu = ActionMenuScript.new()
	hud.add_child(action_menu)
	summon_list = SummonListScript.new()
	hud.add_child(summon_list)
	top_bar.refresh(state)
	action_menu.action_chosen.connect(_on_action_chosen)
	summon_list.summon_chosen.connect(_on_summon_chosen)
	summon_list.back.connect(_on_summon_back)
	battle_scene = BattleSceneScript.new()
	hud.add_child(battle_scene)
	settings_panel = SettingsPanelScript.new()
	hud.add_child(settings_panel)
	top_bar.settings_pressed.connect(func(): settings_panel.open(session))
	_refresh_fog()

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	# --- Camera: middle/right-drag pans, wheel zooms. ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam.zoom = (cam.zoom * ZOOM_STEP).clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam.zoom = (cam.zoom / ZOOM_STEP).clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
			return
	if event is InputEventMouseMotion and _panning:
		cam.position -= event.relative / cam.zoom
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(Hex.pixel_to_axial(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		_on_end_turn()

func _on_end_turn() -> void:
	if _busy:
		return
	if state.winner != -1:
		return
	state.revealed.clear()
	state.end_turn()
	# Run the AI's whole turn synchronously if it's an AI player, replay its battles, then hand back.
	if state.winner == -1 and state.is_ai[state.current_player]:
		AI.take_turn(state)
		_finish_action()
		await _play_battles()
		if state.winner == -1:
			state.end_turn()
	_center_on_master()
	_finish_action()
	if state.winner != -1:
		_end_match()
	else:
		SaveGame.save(state)

func _center_on_master() -> void:
	var m = state.master_of(state.current_player)
	if m != null:
		cam.position = Hex.axial_to_pixel(Vector2i(m["q"], m["r"]))

## World hex -> screen position for anchoring a HUD popup at a unit (CanvasLayer is not
## affected by the camera, so convert through the canvas transform).
func _hex_screen_pos(q: int, r: int) -> Vector2:
	return get_viewport().get_canvas_transform() * Hex.axial_to_pixel(Vector2i(q, r))

func _open_menu_for(unit) -> void:
	var has_undo: bool = undo_snapshot != null and undo_snapshot["unit"] == unit
	var actions := UiQueries.available_actions(state, unit, has_undo)
	selected = unit
	action_menu.open(actions, _hex_screen_pos(unit["q"], unit["r"]))

func _on_click(a: Vector2i) -> void:
	if _busy:
		return
	# An armed ability/attack is waiting for a target click.
	if armed != null:
		_resolve_armed(a)
		return
	# The action menu is open — clicks on the board are ignored (use the menu).
	if action_menu.visible or summon_list.visible:
		return
	# With a unit selected (and not yet acted): move onto a reachable tile.
	if selected != null and not selected["acted"]:
		var reach := Pathfinding.compute_reachable(state, selected)
		var is_own_tile: bool = (a.x == selected["q"] and a.y == selected["r"])
		if reach.has(Hex.key(a)) and not is_own_tile:
			undo_snapshot = {"unit": selected, "q": selected["q"], "r": selected["r"]}
			var from_px := Hex.axial_to_pixel(Vector2i(selected["q"], selected["r"]))
			var to_px := Hex.axial_to_pixel(a)
			selected["q"] = a.x
			selected["r"] = a.y
			overlay.set_highlights({}, selected)
			await _slide_unit(selected, from_px, to_px)
			var got := state.pick_up_relic(selected)
			if got != "":
				Audio.beep(720.0, 0.08, "triangle", 0.2)
				_refresh_fog()
				board.queue_redraw()
				info_card.show_unit(selected)
			state.check_win_condition()
			if state.winner != -1:
				_finish_action()
				_end_match()
				return
			_open_menu_for(selected)
			return
		if is_own_tile:
			_open_menu_for(selected)   # act without moving
			return
	# Otherwise (re)select the current player's un-acted unit under the cursor.
	var u = state.unit_at(a.x, a.y)
	if u != null and u["owner"] == state.current_player and not u["acted"]:
		selected = u
		undo_snapshot = null
		overlay.set_highlights(Pathfinding.compute_reachable(state, u), u)
		info_card.show_unit(u)
	else:
		_clear_selection()

func _on_action_chosen(kind: String) -> void:
	action_menu.close()
	var unit = selected
	if unit == null:
		return
	match kind:
		"attack":
			var targets := Pathfinding.compute_attack_targets(state, unit, unit["q"], unit["r"])
			if targets.is_empty():
				_open_menu_for(unit)   # nothing in range after all — back to the menu
				return
			armed = {"ab": null, "kind": "enemy", "targets": targets}
			overlay.set_armed(targets)
		"ability":
			_arm_ability(unit)
		"capture":
			var cell = state.cell_at(unit["q"], unit["r"])
			if cell != null and UiQueries.can_capture(state, unit, cell):
				state.capture_tower(unit, cell)
				Audio.beep(520.0, 0.12, "triangle", 0.18)
			_commit(unit)
		"summon":
			summon_list.open(UiQueries.summon_options(state, unit), _hex_screen_pos(unit["q"], unit["r"]))
		"undo":
			if undo_snapshot != null and undo_snapshot["unit"] == unit:
				unit["q"] = undo_snapshot["q"]
				unit["r"] = undo_snapshot["r"]
				undo_snapshot = null
				_refresh_fog()
				selected = unit
				overlay.set_highlights(Pathfinding.compute_reachable(state, unit), unit)
				info_card.show_unit(unit)
		"wait":
			_commit(unit)

func _arm_ability(unit) -> void:
	var ab = Abilities.ability_for(unit)
	if ab == null or unit["cd"] > 0:
		_open_menu_for(unit)
		return
	match ab["target"]:
		"none":
			AbilityResolve.resolve_instant(state, unit, ab)
			unit["cd"] = ab["cd"]
			Audio.beep(700.0, 0.1, "triangle", 0.2)
			# Skitter / Gale Rush grant a second move-only action: keep the unit selected
			# with fresh (boosted) reach so the next reachable click moves it again, after
			# which available_actions' second-move branch (Capture/Wait) opens. Other
			# instants (heal/quake/bulwark/ward) commit immediately.
			if unit.get("second_move", false):
				undo_snapshot = null
				_refresh_fog()
				selected = unit
				overlay.set_highlights(Pathfinding.compute_reachable(state, unit), unit)
				info_card.show_unit(unit)
				return
			info_card.show_unit(unit)
			_commit(unit)
		"enemy":
			var targets := Pathfinding.compute_attack_targets(state, unit, unit["q"], unit["r"])
			if targets.is_empty():
				_open_menu_for(unit)
				return
			armed = {"ab": ab, "kind": "enemy", "targets": targets}
			overlay.set_armed(targets)
		"tile":
			var tiles := AbilityResolve.blink_targets(state, unit)
			if tiles.is_empty():
				_open_menu_for(unit)
				return
			armed = {"ab": ab, "kind": "tile", "targets": tiles}
			overlay.set_armed(tiles)

func _on_summon_chosen(key: String) -> void:
	var unit = selected
	if unit == null:
		return
	var slot = AI.find_summon_slot(state, unit)
	if slot == null:
		return   # no open hex; leave the list open for another pick or Back
	unit["mp"] -= UnitTypes.UNIT_TYPES[key]["cost"]
	var u := state.spawn_unit(key, unit["owner"], slot.x, slot.y)
	u["acted"] = true
	Audio.beep(660.0, 0.08, "triangle", 0.18)
	summon_list.close()
	_commit(unit)

func _on_summon_back() -> void:
	summon_list.close()
	if selected != null:
		_open_menu_for(selected)

## _play_battles — drain GameState.battle_log, awaiting one cutaway per recorded battle.
## Blocks board input via _busy. Refreshes the board + HUD afterward. No state mutation
## (combat already resolved; the cutaway is pure animation).
## If battle_scene is OFF in settings, drains the log silently and returns immediately.
func _play_battles() -> void:
	if state.battle_log.is_empty():
		return
	var show: bool = session == null or session.settings.get("battle_scene", true)
	if not show:
		for rec in state.battle_log:
			if state.fog and rec.has("attacker_pos"):
				state.revealed[Hex.key(rec["attacker_pos"])] = true
		state.battle_log.clear()   # combat already resolved; skip the animation
		_refresh_fog()
		if top_bar != null:
			top_bar.refresh(state)
		if state.winner != -1:
			_end_match()
		return
	_busy = true
	while not state.battle_log.is_empty():
		var rec: Dictionary = state.battle_log.pop_front()
		battle_scene.play(rec)
		await battle_scene.finished
		if state.fog and rec.has("attacker_pos"):
			state.revealed[Hex.key(rec["attacker_pos"])] = true
		_refresh_fog()
	_busy = false
	if top_bar != null:
		top_bar.refresh(state)
	if state.winner != -1:
		_end_match()

## _slide_unit — animate the moving unit's UnitNode from from_px to to_px, then snap the
## layer to final state. A straight glide (per-hex path-following is a later polish).
func _slide_unit(unit, from_px: Vector2, to_px: Vector2) -> void:
	_busy = true
	units_layer.set_state(state)              # rebuild so the node exists at the new record
	var node: Node2D = _unit_node_for(unit)
	if node != null:
		node.position = from_px
		var tw := create_tween()
		tw.tween_property(node, "position", to_px, 0.18)
		await tw.finished
	_busy = false
	_refresh_fog()

## _unit_node_for — find the UnitNode bound to `unit` in the units layer (or null).
func _unit_node_for(unit):
	for child in units_layer.get_children():
		if child.unit == unit:
			return child
	return null

func _resolve_armed(a: Vector2i) -> void:
	var unit = selected
	if armed["targets"].has(Hex.key(a)):
		if armed["kind"] == "enemy":
			var foe = state.unit_at(a.x, a.y)
			if foe == null:
				armed = null
				overlay.set_armed({})
				if unit != null:
					_open_menu_for(unit)
				return
			var ab = armed["ab"]
			if ab != null:
				Combat.resolve_attack(state, unit, foe, ab.get("status", ""), ab.get("status_turns", 0))
				unit["cd"] = ab["cd"]
			else:
				Combat.resolve_attack(state, unit, foe)
		else:   # tile (blink)
			AbilityResolve.do_blink(unit, a.x, a.y)
			unit["cd"] = armed["ab"]["cd"]
		armed = null
		overlay.set_armed({})
		_commit(unit)
		await _play_battles()
		return
	# Miss: cancel the arm and RE-OPEN the menu without freeing the unit (exploit-fix).
	armed = null
	overlay.set_armed({})
	if unit != null:
		_open_menu_for(unit)

func _commit(unit) -> void:
	if unit != null:
		unit["acted"] = true
	undo_snapshot = null
	armed = null
	action_menu.close()
	summon_list.close()
	overlay.clear_all()
	_finish_action()

func _clear_selection() -> void:
	selected = null
	undo_snapshot = null
	armed = null
	if action_menu != null:
		action_menu.close()
	if summon_list != null:
		summon_list.close()
	if overlay != null:
		overlay.clear_all()
	if info_card != null:
		info_card.clear()

func _finish_action() -> void:
	_clear_selection()
	_refresh_fog()
	if top_bar != null:
		top_bar.refresh(state)

## _refresh_fog — recompute the viewer's vision (when fog is on), push the dim overlay, and
## rebuild the unit nodes (hiding enemies outside vision). Called on match start and after
## every move/summon/death/turn. A no-op overlay when fog is off.
func _refresh_fog() -> void:
	units_layer.viewer = _viewer
	if state.fog:
		state.recompute_visibility(_viewer)
		var fogged := {}
		for k in state.map.get("cells", {}):
			if not state.visibility.has(k):
				fogged[k] = true
		overlay.set_fog(fogged)
	else:
		overlay.set_fog({})
	units_layer.set_state(state)

## _end_match — a winner was decided. Advance campaign progress + clear the
## autosave (via Session), then tell the router to show the gameover screen.
## Idempotent: the one-shot _match_over guard prevents double-emission when
## both _play_battles and _on_end_turn detect a winner in the AI-won path.
func _end_match() -> void:
	if _match_over:
		return
	_match_over = true
	Audio.fanfare([
		{"freq": 440.0, "dur": 0.2, "wave": "triangle", "gain": 0.25},
		{"freq": 660.0, "dur": 0.3, "wave": "triangle", "gain": 0.25, "delay": 0.2},
	])
	if session != null:
		session.on_match_won(state.winner)
	match_ended.emit(state.winner)
