extends Node2D
## Root: generate a skirmish map with a fixed seed and show it with a camera.

const MapGen = preload("res://core/map_gen.gd")
const Maps = preload("res://data/maps.gd")
const Hex = preload("res://core/hex.gd")
const BoardScript = preload("res://scenes/board/board.gd")

func _ready() -> void:
	var def: Dictionary = Maps.MAPS[0]
	var m := MapGen.generate(42, def)
	var board := BoardScript.new()
	board.set_map(m)
	add_child(board)
	var cam := Camera2D.new()
	cam.position = Hex.axial_to_pixel(Vector2i(def["cols"] / 2, def["rows"] / 2))
	add_child(cam)
	cam.make_current()
