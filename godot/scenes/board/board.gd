class_name Board
extends Node2D
## Thin presentation: draws each map cell as a hex polygon colored by terrain.
## Color mapping + corner geometry are static so they are headless-testable.

const Hex = preload("res://core/hex.gd")
const Terrain = preload("res://data/terrain.gd")

var map: Dictionary = {}

func set_map(m: Dictionary) -> void:
	map = m
	queue_redraw()

static func terrain_color(terrain: String) -> Color:
	var t: Dictionary = Terrain.TERRAIN.get(terrain, {})
	return Color(t.get("color", "#ff00ff"))

static func hex_corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * Hex.SIZE)
	return pts

func _draw() -> void:
	if map.is_empty():
		return
	for key in map["cells"]:
		var cell: Dictionary = map["cells"][key]
		var center := Hex.axial_to_pixel(Vector2i(cell["q"], cell["r"]))
		var pts := hex_corners(center)
		draw_colored_polygon(pts, terrain_color(cell["terrain"]))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.35), 1.0)
