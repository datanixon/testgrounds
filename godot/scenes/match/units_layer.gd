class_name UnitsLayer
extends Node2D
## Manages one UnitNode per live unit. set_state() rebuilds the node set from the
## GameState (cheap — armies are small), so spawns/deaths/moves all reflect on the
## next call. Reads unit records straight from the GameState.

const UnitNodeScript = preload("res://scenes/match/unit_node.gd")
const Hex = preload("res://core/hex.gd")

var state   # GameState (untyped — node<->RefCounted preload cycle avoidance)
var viewer: int = 0   # the human side; enemies outside its vision are not drawn under fog

func set_state(s) -> void:
	state = s
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.free()
	if state == null:
		return
	for u in state.units:
		if u["hp"] <= 0:
			continue
		if state.fog and u["owner"] != viewer and not state.visibility.has(Hex.key(Vector2i(u["q"], u["r"]))):
			continue
		var node: Node2D = UnitNodeScript.new()
		add_child(node)
		node.bind(u)
