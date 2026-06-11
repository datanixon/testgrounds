class_name UnitsLayer
extends Node2D
## Placeholder unit tokens: an element-colored body inside a team-colored ring,
## with a white pip on archons. Real sprites swap in at the art milestone (M10);
## only this layer changes. Reads unit records straight from the GameState.

const Hex = preload("res://core/hex.gd")

## Team ring colors — AZURE / CRIMSON, from the JS PLAYERS palette (PAL.p0 / p1).
const TEAM_COLORS := [Color("#5aa8d8"), Color("#cc6a4a")]
## Placeholder element fills for board readability until real art lands.
const ELEMENT_COLORS := {
	"pyro": Color("#d8662e"), "hydro": Color("#3a7ad8"), "terra": Color("#9a8a52"),
	"zephyr": Color("#7fd0c0"), "arcane": Color("#a06ad8"),
}

var state   # GameState (untyped to avoid a node<->RefCounted preload cycle)

func set_state(s) -> void:
	state = s
	queue_redraw()

func _draw() -> void:
	if state == null:
		return
	for u in state.units:
		if u["hp"] <= 0:
			continue
		var c := Hex.axial_to_pixel(Vector2i(u["q"], u["r"]))
		var ring: Color = TEAM_COLORS[u["owner"]]
		var fill: Color = ELEMENT_COLORS.get(u["element"], Color("#cccccc"))
		var radius := Hex.SIZE * 0.62
		draw_circle(c, radius, ring)               # team ring
		draw_circle(c, radius * 0.74, fill)        # element body
		if u["is_master"]:
			draw_circle(c, radius * 0.30, Color(1, 1, 1, 0.9))  # master pip
