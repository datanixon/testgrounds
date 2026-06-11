class_name Overlay
extends Node2D
## Move/selection highlights, drawn above the board and below the tokens.
## Reachable tiles get a translucent blue fill; the selected unit's tile gets a
## bright yellow outline. Fed by main.gd from Pathfinding.compute_reachable.

const Hex = preload("res://core/hex.gd")
const BoardLib = preload("res://scenes/board/board.gd")

var reachable: Dictionary = {}    # compute_reachable() result
var selected: Variant = null      # the selected unit record, or null

func set_highlights(reach: Dictionary, sel) -> void:
	reachable = reach
	selected = sel
	queue_redraw()

func _draw() -> void:
	for key in reachable:
		var v: Dictionary = reachable[key]
		var pts := BoardLib.hex_corners(Hex.axial_to_pixel(Vector2i(v["q"], v["r"])))
		draw_colored_polygon(pts, Color(0.4, 0.7, 1.0, 0.28))
	if selected != null:
		var outline := BoardLib.hex_corners(Hex.axial_to_pixel(Vector2i(selected["q"], selected["r"])))
		outline.append(outline[0])
		draw_polyline(outline, Color(1.0, 1.0, 0.4, 0.95), 3.0)
