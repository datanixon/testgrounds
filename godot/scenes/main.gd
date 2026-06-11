extends Node2D
## Root match controller (M5): owns a GameState, renders the board + move overlay
## + unit tokens, and handles click select/move/attack/capture, Enter -> end_turn,
## and A -> cast ability (instant fires now; enemy/tile arm then resolve on click),
## all through the pure core. Placeholder interactive slice — the action menu +
## `acted` enforcement (M7), AI (M6), and the gameover screen (M9) are still to come.

const Hex = preload("res://core/hex.gd")
const Maps = preload("res://data/maps.gd")
const GameState = preload("res://core/game_state.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const Combat = preload("res://core/combat.gd")
const Abilities = preload("res://data/abilities.gd")
const AbilityResolve = preload("res://core/ability_resolve.gd")
const BoardScript = preload("res://scenes/board/board.gd")
const UnitsLayerScript = preload("res://scenes/match/units_layer.gd")
const OverlayScript = preload("res://scenes/match/overlay.gd")

var state: GameState
var overlay: Overlay
var units_layer: UnitsLayer
var cam: Camera2D
var selected = null
var armed = null   # {ab: Dictionary, kind: String, targets: Dictionary} when an enemy/tile ability is armed

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(Hex.pixel_to_axial(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		state.end_turn()
		_center_on_master()
		_finish_action()
	# --- TEMP M4 verification keys (remove when M5 summoning + a real camera land) ---
	elif event is InputEventKey and event.pressed and event.keycode == KEY_D:
		_debug_spawn_combat()   # drop an ally + adjacent enemy by your master
	elif event is InputEventKey and event.pressed and event.keycode == KEY_T:
		_debug_goto_tower()     # jump to the nearest neutral tower + a unit beside it
	elif event is InputEventKey and event.pressed and event.keycode == KEY_A:
		_cast_ability()

func _center_on_master() -> void:
	var m = state.master_of(state.current_player)
	if m != null:
		cam.position = Hex.axial_to_pixel(Vector2i(m["q"], m["r"]))

# TEMP (M4 verification): there is no summoning yet (M5), so spawn a friendly + an
# adjacent enemy beside the current player's master to exercise attack/counter on
# screen. Removed once summoning provides the real way to field units.
func _debug_spawn_combat() -> void:
	var m = state.master_of(state.current_player)
	if m == null:
		return
	var foe := 1 - state.current_player
	var me := state.current_player
	# [type, owner] on free neighbors: ally cinderling (ignite/enemy-target), enemy
	# cinderling (a target), ally hexwisp (blink — its teleport is the clearest
	# on-screen proof a cast fired), ally geomaul (quake — instant area).
	var to_place := [["cinderling", me], ["cinderling", foe], ["hexwisp", me], ["geomaul", me]]
	for n in Hex.neighbors(Vector2i(m["q"], m["r"])):
		if to_place.is_empty():
			break
		if not state.in_bounds(n.x, n.y) or state.unit_at(n.x, n.y) != null:
			continue
		var cell = state.cell_at(n.x, n.y)
		if cell == null or cell["terrain"] == "water":
			continue
		var spec = to_place.pop_front()
		state.spawn_unit(spec[0], spec[1], n.x, n.y)
	units_layer.set_state(state)

# TEMP (M4 verification): pan to the nearest neutral tower and drop a current-player
# flyer next to it, so one click-move onto the tower captures it.
func _debug_goto_tower() -> void:
	var m = state.master_of(state.current_player)
	if m == null or state.map["towers"].is_empty():
		return
	var best: Vector2i = state.map["towers"][0]
	var best_d := 99999
	for t in state.map["towers"]:
		var d: int = Hex.distance(Vector2i(m["q"], m["r"]), t)
		if d < best_d:
			best_d = d
			best = t
	for n in Hex.neighbors(best):
		if state.in_bounds(n.x, n.y) and state.unit_at(n.x, n.y) == null:
			var cell = state.cell_at(n.x, n.y)
			if cell != null and cell["terrain"] != "water":
				state.spawn_unit("galewisp", state.current_player, n.x, n.y)
				break
	cam.position = Hex.axial_to_pixel(best)
	units_layer.set_state(state)

func _cast_ability() -> void:
	# TEMP verification feedback via print() — there is no HUD/log yet (M7). Tokens have
	# no HP bar or status icon, so most cast effects aren't visible on-screen; these prints
	# confirm what fired. Blink (a teleport) and a lethal hit (token vanishes) ARE visible.
	if selected == null:
		print("cast: nothing selected")
		return
	var ab = Abilities.ability_for(selected)
	if ab == null:
		print("cast: %s has no ability" % selected["name"])
		return
	if selected["cd"] > 0:
		print("cast: %s on cooldown (%d turns)" % [ab["key"], selected["cd"]])
		return
	match ab["target"]:
		"none":
			AbilityResolve.resolve_instant(state, selected, ab)
			selected["cd"] = ab["cd"]
			print("cast %s (instant) — effect applied" % ab["key"])
			_finish_action()
		"enemy":
			var targets := Pathfinding.compute_attack_targets(state, selected, selected["q"], selected["r"])
			if not targets.is_empty():
				armed = {"ab": ab, "kind": "enemy", "targets": targets}
				print("armed %s — click an enemy in range" % ab["key"])
			else:
				print("cast %s: no enemy in range" % ab["key"])
		"tile":
			var tiles := AbilityResolve.blink_targets(state, selected)
			if not tiles.is_empty():
				armed = {"ab": ab, "kind": "tile", "targets": tiles}
				print("armed %s — click a tile to teleport" % ab["key"])
			else:
				print("cast %s: nowhere to blink" % ab["key"])

func _resolve_armed(a: Vector2i) -> void:
	if armed["targets"].has(Hex.key(a)):
		if armed["kind"] == "enemy":
			var foe = state.unit_at(a.x, a.y)
			if foe != null:
				Combat.resolve_attack(state, selected, foe, armed["ab"].get("status", ""), armed["ab"].get("status_turns", 0))
				selected["cd"] = armed["ab"]["cd"]
		else:   # tile (blink)
			AbilityResolve.do_blink(selected, a.x, a.y)
			selected["cd"] = armed["ab"]["cd"]
		armed = null
		_finish_action()
		return
	# Miss: cancel the armed state silently.
	armed = null
	_clear_selection()

func _on_click(a: Vector2i) -> void:
	if armed != null:
		_resolve_armed(a)
		return
	# With a unit selected: attack an enemy in range, else move (and maybe capture).
	if selected != null:
		# Attack: clicked tile holds an enemy within attack range.
		var targets := Pathfinding.compute_attack_targets(state, selected, selected["q"], selected["r"])
		if targets.has(Hex.key(a)):
			var foe = state.unit_at(a.x, a.y)
			if foe != null:
				Combat.resolve_attack(state, selected, foe)
				_finish_action()
				return
		# Move: clicked a reachable tile (not the unit's own).
		var reach := Pathfinding.compute_reachable(state, selected)
		var is_own_tile: bool = (a.x == selected["q"] and a.y == selected["r"])
		if reach.has(Hex.key(a)) and not is_own_tile:
			selected["q"] = a.x
			selected["r"] = a.y
			# Capture a tower we landed on that isn't already ours.
			var cell = state.cell_at(a.x, a.y)
			if cell != null and cell["terrain"] == "tower" and cell.get("owner", -1) != selected["owner"]:
				state.capture_tower(selected, cell)
			_clear_selection()
			units_layer.set_state(state)
			return
	# Otherwise (re)select the current player's unit under the cursor.
	var u = state.unit_at(a.x, a.y)
	if u != null and u["owner"] == state.current_player:
		selected = u
		overlay.set_highlights(Pathfinding.compute_reachable(state, u), u)
	else:
		_clear_selection()

func _clear_selection() -> void:
	selected = null
	overlay.set_highlights({}, null)

func _finish_action() -> void:
	_clear_selection()
	units_layer.set_state(state)
	if state.winner != -1:
		print("WINNER: player %d" % state.winner)
