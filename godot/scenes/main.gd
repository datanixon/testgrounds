extends Node2D
## Root match controller (M7): owns a GameState; renders the board + overlay + per-unit
## nodes + a CanvasLayer HUD (topbar / info card / action menu / summon list); a real
## pan/zoom Camera2D. Interaction: click select -> click reachable tile to move -> the
## post-move action menu (Attack / Ability / Capture / Summon / Undo / Wait, built from
## UiQueries.available_actions) drives the rest; Attack/enemy-ability/blink arm then
## resolve on click (a mis-click backs out to the menu). Enter / End-Turn runs the enemy
## AI (player 1) synchronously then hands back. The battle cutaway + move-slide animation
## are M8; title / gameover / save / difficulty-select are M9; real art is M10.

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

var state: GameState
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
var selected = null
var armed = null   # {ab: Dictionary, kind: String, targets: Dictionary} when an enemy/tile ability is armed
var undo_snapshot = null   # {unit, q, r} — the pre-move position, live until the action commits

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.1
var _panning := false

func _ready() -> void:
	state = GameState.new_skirmish(Maps.MAPS[0], 42)
	# Draw order: board (bottom) -> overlay -> tokens (top).
	var board := BoardScript.new()
	board.set_map(state.map)
	add_child(board)
	overlay = OverlayScript.new()
	add_child(overlay)
	units_layer = UnitsLayerScript.new()
	units_layer.set_state(state)
	add_child(units_layer)
	cam = Camera2D.new()
	var m = state.master_of(0)
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
	state.end_turn()
	# M6: player 1 is the AI. Run its whole turn synchronously, replay its battles, then hand back.
	if state.winner == -1 and state.current_player == 1:
		AI.take_turn(state)
		_finish_action()
		await _play_battles()
		if state.winner == -1:
			state.end_turn()
	_center_on_master()
	_finish_action()

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
			_commit(unit)
		"summon":
			summon_list.open(UiQueries.summon_options(state, unit), _hex_screen_pos(unit["q"], unit["r"]))
		"undo":
			if undo_snapshot != null and undo_snapshot["unit"] == unit:
				unit["q"] = undo_snapshot["q"]
				unit["r"] = undo_snapshot["r"]
				undo_snapshot = null
				units_layer.set_state(state)
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
			# Skitter / Gale Rush grant a second move-only action: keep the unit selected
			# with fresh (boosted) reach so the next reachable click moves it again, after
			# which available_actions' second-move branch (Capture/Wait) opens. Other
			# instants (heal/quake/bulwark/ward) commit immediately.
			if unit.get("second_move", false):
				undo_snapshot = null
				units_layer.set_state(state)
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
	summon_list.close()
	_commit(unit)

func _on_summon_back() -> void:
	summon_list.close()
	if selected != null:
		_open_menu_for(selected)

## _play_battles — drain GameState.battle_log, awaiting one cutaway per recorded battle.
## Blocks board input via _busy. Refreshes the board + HUD afterward. No state mutation
## (combat already resolved; the cutaway is pure animation).
func _play_battles() -> void:
	if state.battle_log.is_empty():
		return
	_busy = true
	while not state.battle_log.is_empty():
		var rec: Dictionary = state.battle_log.pop_front()
		battle_scene.play(rec)
		await battle_scene.finished
	_busy = false
	units_layer.set_state(state)
	if top_bar != null:
		top_bar.refresh(state)

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
	units_layer.set_state(state)

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
	units_layer.set_state(state)
	if top_bar != null:
		top_bar.refresh(state)
	if state.winner != -1:
		print("WINNER: player %d" % state.winner)
