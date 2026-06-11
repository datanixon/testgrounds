extends Node2D
## Root match controller (M4): owns a GameState, renders the board + move overlay
## + unit tokens, and handles click-to-select / click-to-move / click-to-attack
## and Enter -> end_turn through the pure core. Placeholder interactive slice —
## `acted` enforcement, AI, and the gameover screen arrive in M5/M6/M9.

const Hex = preload("res://core/hex.gd")
const Maps = preload("res://data/maps.gd")
const GameState = preload("res://core/game_state.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const Combat = preload("res://core/combat.gd")
const BoardScript = preload("res://scenes/board/board.gd")
const UnitsLayerScript = preload("res://scenes/match/units_layer.gd")
const OverlayScript = preload("res://scenes/match/overlay.gd")

var state: GameState
var overlay: Overlay
var units_layer: UnitsLayer
var selected = null

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
	var cam := Camera2D.new()
	var m = state.master_of(0)
	cam.position = Hex.axial_to_pixel(Vector2i(m["q"], m["r"]))
	add_child(cam)
	cam.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(Hex.pixel_to_axial(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		state.end_turn()
		_clear_selection()
		units_layer.set_state(state)
		if state.winner != -1:
			print("WINNER: player %d" % state.winner)

func _on_click(a: Vector2i) -> void:
	# With a unit selected: attack an enemy in range, else move (and maybe capture).
	if selected != null:
		# Attack: clicked tile holds an enemy within attack range.
		var targets := Pathfinding.compute_attack_targets(state, selected, selected["q"], selected["r"])
		if targets.has(Hex.key(a)):
			var foe = state.unit_at(a.x, a.y)
			if foe != null:
				Combat.resolve_attack(state, selected, foe)
				_clear_selection()
				units_layer.set_state(state)
				if state.winner != -1:
					print("WINNER: player %d" % state.winner)
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
