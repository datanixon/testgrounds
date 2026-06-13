class_name BattleSprites
extends RefCounted
## Battle portrait renderer — M10 art: draws real PNG portraits via Sprites loader.
## Keeps the idle bob + charge/impact lunge; mirrors for the defender (facing -1).
## All procedural _draw_<sprite> bodies removed; Sprites.battle() resolves the art.
##
## Player palettes (owner 0 = AZURE, owner 1 = CRIMSON), matching PAL in game.js:
##   AZURE:   color=#5aa8d8  dark=#1f4870  trim=#bce0ff
##   CRIMSON: color=#cc6a4a  dark=#6a2818  trim=#ffc4a0

const Sprites = preload("res://core/sprites.gd")

## SCALE — JS draws at pixel-art scale 5; we use 5 px per "pixel" just like the source.
const SCALE := 5

## _pal — returns {color, dark, trim} Color dict for the given owner index.
static func _pal(owner: int) -> Dictionary:
	if owner == 0:
		return {"color": Color("#5aa8d8"), "dark": Color("#1f4870"), "trim": Color("#bce0ff")}
	else:
		return {"color": Color("#cc6a4a"), "dark": Color("#6a2818"), "trim": Color("#ffc4a0")}

## draw_unit — render one combatant's real portrait centered with feet at (cx,cy).
## Keeps the idle bob + charge/impact lunge; mirrors for the defender (facing -1).
## A team-colored backing glow gives battle-scene faction identity (monsters are
## faction-neutral art; the archon portrait is already bespoke per faction).
## `view` carries sprite/owner/is_master; `pose` ∈ idle/charge/impact/recover; t = phase 0..1.
const PORTRAIT_H := 320.0   # on-screen portrait height (1024² source scaled down)

static func draw_unit(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, pose: String, t: float) -> void:
	var bob := sin(t * 42.0 / 14.0) * 1.2
	var lunge := 0.0
	if pose == "charge":
		lunge = facing * 6.0 * SCALE
	elif pose == "impact":
		lunge = facing * -8.0 * SCALE
	var ocx := cx + lunge
	var ocy := cy + bob
	var sprite_id: String = "archon" if view.get("is_master", false) else view["sprite"]
	var tex := Sprites.battle(sprite_id, view.get("owner", 0))
	var p := _pal(view.get("owner", 0))
	# Backing glow (team identity): a soft team-colored ellipse behind the portrait.
	var glow: Color = p["color"]
	glow.a = 0.22
	_draw_ellipse(ci, Vector2(ocx, ocy - PORTRAIT_H * 0.42), PORTRAIT_H * 0.34, PORTRAIT_H * 0.5, glow)
	# Ground shadow.
	_draw_ellipse(ci, Vector2(ocx, ocy), PORTRAIT_H * 0.30, PORTRAIT_H * 0.07, Color(0, 0, 0, 0.35))
	if tex == null:
		return
	# Portrait: square source, drawn feet-at-(ocx,ocy), bottom-centered; mirror on facing.
	var w := PORTRAIT_H
	ci.draw_set_transform(Vector2(ocx, ocy), 0.0, Vector2(facing, 1.0))
	ci.draw_texture_rect(tex, Rect2(-w / 2.0, -PORTRAIT_H, w, PORTRAIT_H), false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## _draw_ellipse — filled ellipse via a scaled circle (no native draw_ellipse).
static func _draw_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_set_transform(center, 0.0, Vector2(rx, ry))
	ci.draw_circle(Vector2.ZERO, 1.0, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
