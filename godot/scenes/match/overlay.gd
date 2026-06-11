class_name Overlay
extends Node2D
## Board highlights, drawn above the board and below the unit nodes:
##  - reachable tiles  -> translucent blue fill
##  - attack-range tiles -> translucent red fill
##  - armed-target tiles (ability/blink/summon-slot) -> translucent gold fill
##  - the selected unit's tile -> bright yellow outline
## Fed by main.gd. All sets are { "q,r": <any> } dictionaries (compute_* results or
## plain key sets); only their keys are read.

const Hex = preload("res://core/hex.gd")
const BoardLib = preload("res://scenes/board/board.gd")

var reachable: Dictionary = {}
var armed: Dictionary = {}
var selected: Variant = null

func set_highlights(reach: Dictionary, sel) -> void:
	reachable = reach
	selected = sel
	queue_redraw()

func set_armed(tiles: Dictionary) -> void:
	armed = tiles
	queue_redraw()

func clear_all() -> void:
	reachable = {}
	armed = {}
	selected = null
	queue_redraw()

func _fill(tiles: Dictionary, col: Color) -> void:
	for key in tiles:
		var parts: PackedStringArray = (key as String).split(",")
		var p := Vector2i(int(parts[0]), int(parts[1]))
		draw_colored_polygon(BoardLib.hex_corners(Hex.axial_to_pixel(p)), col)

func _draw() -> void:
	_fill(reachable, Color(0.4, 0.7, 1.0, 0.28))
	_fill(armed, Color(1.0, 0.82, 0.30, 0.42))
	if selected != null:
		var outline := BoardLib.hex_corners(Hex.axial_to_pixel(Vector2i(selected["q"], selected["r"])))
		outline.append(outline[0])
		draw_polyline(outline, Color(1.0, 1.0, 0.4, 0.95), 3.0)
