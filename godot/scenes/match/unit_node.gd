class_name UnitNode
extends Node2D
## One node per live unit (placeholder art): team-colored ring, element body, master
## pip, an HP bar, and a row of status pips. Bound to a GameState unit record via
## bind(); call refresh() after the record changes. Real sprites replace the _draw
## body at M10 — the node interface stays the same.

const Hex = preload("res://core/hex.gd")
const Sprites = preload("res://core/sprites.gd")
const Relics = preload("res://data/relics.gd")

## Team ring colors — AZURE / CRIMSON (JS PLAYERS palette p0/p1).
const TEAM_COLORS := [Color("#5aa8d8"), Color("#cc6a4a")]
## Status pip colors (keys from data/statuses.gd).
const STATUS_COLORS := {
	"burn": Color("#e0662e"), "slow": Color("#6aa0e0"), "mark": Color("#e0d050"),
	"bulwark": Color("#9aa0b0"), "ward": Color("#d0d0f0"), "regen": Color("#70d070"),
}

var unit   # GameState unit record (untyped — node<->RefCounted preload cycle avoidance)

func bind(u) -> void:
	unit = u
	refresh()

func refresh() -> void:
	if unit != null:
		position = Hex.axial_to_pixel(Vector2i(unit["q"], unit["r"]))
	queue_redraw()

func _draw() -> void:
	if unit == null:
		return
	var radius := Hex.SIZE * 0.62
	# Team-colored base disc (faction identity) — the transparent-bg token sits on it.
	draw_circle(Vector2.ZERO, radius, TEAM_COLORS[unit["owner"]])
	# Real creature art (faction-neutral; archon splits on owner inside Sprites).
	var tex := Sprites.token(unit["sprite"], unit["owner"])
	if tex != null:
		var s := radius * 2.0          # token fills the team disc; transparent edges show the ring
		draw_texture_rect(tex, Rect2(-s / 2.0, -s / 2.0, s, s), false)
	_draw_hp_bar(radius)
	_draw_status_pips(radius)

func _draw_hp_bar(radius: float) -> void:
	var w := radius * 1.6
	var h := 4.0
	var top_left := Vector2(-w / 2.0, -radius - 8.0)
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0, 0, 0, 0.6))
	var frac := clampf(float(unit["hp"]) / float(Relics.max_hp(unit)), 0.0, 1.0)
	var col := Color("#5ad06a") if frac > 0.5 else (Color("#e0d050") if frac > 0.25 else Color("#e05050"))
	draw_rect(Rect2(top_left, Vector2(w * frac, h)), col)

func _draw_status_pips(radius: float) -> void:
	if unit == null or not unit.has("status"):
		return
	var i := 0
	for k in unit["status"]:
		if unit["status"][k] <= 0:
			continue
		var c: Color = STATUS_COLORS.get(k, Color(1, 1, 1))
		draw_circle(Vector2(-radius + i * 7.0, radius + 6.0), 3.0, c)
		i += 1
