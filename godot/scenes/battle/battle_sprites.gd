class_name BattleSprites
extends RefCounted
## Procedural battle portraits — port of game.js drawBattleSprite (sec. 9, ~line 1782).
## Placeholder-quality; real sprites replace these bodies at M10 behind the same signature.
## Pure draw helpers: they only call ci.draw_* and read the combatant view dict.
##
## Player palettes (owner 0 = AZURE, owner 1 = CRIMSON), matching PAL in game.js:
##   AZURE:   color=#5aa8d8  dark=#1f4870  trim=#bce0ff
##   CRIMSON: color=#cc6a4a  dark=#6a2818  trim=#ffc4a0

const Elements = preload("res://data/elements.gd")

## SCALE — JS draws at pixel-art scale 5; we use 5 px per "pixel" just like the source.
const SCALE := 5

## _pal — returns {color, dark, trim} Color dict for the given owner index.
static func _pal(owner: int) -> Dictionary:
	if owner == 0:
		return {"color": Color("#5aa8d8"), "dark": Color("#1f4870"), "trim": Color("#bce0ff")}
	else:
		return {"color": Color("#cc6a4a"), "dark": Color("#6a2818"), "trim": Color("#ffc4a0")}

## _p — draw a scaled pixel rect at (x,y) with size (w,h), offset from (cx,cy).
## Mirrors on facing=-1 by negating x so the sprite faces right by default then flips.
static func _p(ci: CanvasItem, cx: float, cy: float, facing: int, x: int, y: int, w: int, h: int, col: Color) -> void:
	var rx := cx + facing * x * SCALE
	if facing < 0:
		rx -= w * SCALE  # keep rect anchored correctly after flip
	var ry := cy + y * SCALE
	ci.draw_rect(Rect2(rx, ry, w * SCALE, h * SCALE), col)

## draw_unit — render one combatant centered near (cx, cy). `view` is the battle record's
## attacker/defender slice (type_key/element/owner/attack/sprite/is_master). `facing` is +1
## (faces right) or -1 (mirrored). `pose` in {"idle","charge","impact","recover"}; `t` is 0..1
## phase progress.
static func draw_unit(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, pose: String, t: float) -> void:
	# Bob oscillation (uses a simple sine approximation via a counter mapped to 0..1).
	# t is 0..1 phase progress; we scale to a reasonable period. JS used Math.sin(t/14)*1.2
	# with t as frame count. Here t is normalised so we multiply by ~42 to match ~14-frame scale.
	var bob := sin(t * 42.0 / 14.0) * 1.2
	var lunge := 0.0
	if pose == "charge":
		lunge = facing * 6.0 * SCALE
	elif pose == "impact":
		lunge = facing * -8.0 * SCALE
	# Shifted origin for all _p calls.
	var ocx := cx + lunge
	var ocy := cy + bob

	if view.get("is_master", false):
		_draw_archon(ci, view, ocx, ocy, facing, pose, t)
		return
	match view["sprite"]:
		"imp":        _draw_imp(ci, view, ocx, ocy, facing, t)
		"wyrm":       _draw_wyrm(ci, view, ocx, ocy, facing, t)
		"merfolk":    _draw_merfolk(ci, view, ocx, ocy, facing, t)
		"serpent":    _draw_serpent(ci, view, ocx, ocy, facing, t)
		"golem":      _draw_golem(ci, view, ocx, ocy, facing, t)
		"ogre":       _draw_ogre(ci, view, ocx, ocy, facing, t)
		"wisp":       _draw_wisp(ci, view, ocx, ocy, facing, t)
		"raptor":     _draw_raptor(ci, view, ocx, ocy, facing, t)
		# Evolved forms
		"infernite":    _draw_infernite(ci, view, ocx, ocy, facing, t)
		"emberdrake":   _draw_emberdrake(ci, view, ocx, ocy, facing, t)
		"tidelord":     _draw_tidelord(ci, view, ocx, ocy, facing, t)
		"leviathan":    _draw_leviathan(ci, view, ocx, ocy, facing, t)
		"colossus":     _draw_colossus(ci, view, ocx, ocy, facing, t)
		"earthbreaker": _draw_earthbreaker(ci, view, ocx, ocy, facing, t)
		"stormwisp":    _draw_stormwisp(ci, view, ocx, ocy, facing, t)
		"skytyrant":    _draw_skytyrant(ci, view, ocx, ocy, facing, t)
		# New base monsters (arcane + roster depth)
		"hexwisp":   _draw_hexwisp(ci, view, ocx, ocy, facing, t)
		"runeward":  _draw_runeward(ci, view, ocx, ocy, facing, t)
		"frostmaw":  _draw_frostmaw(ci, view, ocx, ocy, facing, t)
		"duneskink": _draw_duneskink(ci, view, ocx, ocy, facing, t)
		_:
			_draw_generic(ci, view, ocx, ocy, facing, t)

# ---------------------------------------------------------------------------
# Archon (isMaster branch) — AZURE=0 round hood, CRIMSON=1 spiked hood
# ---------------------------------------------------------------------------
static func _draw_archon(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _pose: String, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]
	var dark: Color  = p["dark"]
	var trim: Color  = p["trim"]
	# robe + body (shared)
	_p(ci, cx, cy, facing, -7, -2, 14, 16, dark)
	_p(ci, cx, cy, facing, -6,  0, 12, 12, color)
	_p(ci, cx, cy, facing, -8,  4, 16,  4, dark)
	_p(ci, cx, cy, facing, -3,  6,  6,  2, trim)
	_p(ci, cx, cy, facing, -9, -3, 18,  5, dark)
	_p(ci, cx, cy, facing, -7, -2, 14,  3, color)
	_p(ci, cx, cy, facing, -9, -1,  2,  6, color)
	_p(ci, cx, cy, facing,  7, -1,  2,  6, color)
	if view["owner"] == 0:
		# AZURE: round hood, crescent staff
		_p(ci, cx, cy, facing, -6, -10, 12,  4, dark)
		_p(ci, cx, cy, facing, -5, -12, 10,  3, color)
		_p(ci, cx, cy, facing, -4, -13,  8,  2, color)
		_p(ci, cx, cy, facing, -1, -11,  2,  2, trim)
		_p(ci, cx, cy, facing, -3,  -7,  6,  3, Color("#13111f"))
		_p(ci, cx, cy, facing, -2,  -6,  1,  1, Color("#bce0ff"))
		_p(ci, cx, cy, facing,  1,  -6,  1,  1, Color("#bce0ff"))
		# staff (left side, so -12 in local space)
		_p(ci, cx, cy, facing, -12, -12,  1, 22, Color("#bbbbbb"))
		_p(ci, cx, cy, facing, -13, -14,  3,  3, trim)
		_p(ci, cx, cy, facing, -13, -14,  1,  3, dark)
	else:
		# CRIMSON: spiked hood, flaming staff
		_p(ci, cx, cy, facing, -6, -10, 12,  4, dark)
		_p(ci, cx, cy, facing, -5, -13, 10,  4, color)
		_p(ci, cx, cy, facing, -3, -15,  2,  3, color)
		_p(ci, cx, cy, facing,  1, -15,  2,  3, color)
		_p(ci, cx, cy, facing, -1, -17,  2,  2, trim)
		_p(ci, cx, cy, facing, -3,  -7,  6,  3, Color("#13111f"))
		_p(ci, cx, cy, facing, -2,  -6,  1,  1, Color("#ffd6b0"))
		_p(ci, cx, cy, facing,  1,  -6,  1,  1, Color("#ffd6b0"))
		# flaming staff (right side, +11 in local space)
		_p(ci, cx, cy, facing, 11, -12,  1, 22, Color("#bbbbbb"))
		_p(ci, cx, cy, facing, 10, -15,  3,  3, trim)
		_p(ci, cx, cy, facing, 11, -17,  1,  2, Color("#ffe0a0"))
		_p(ci, cx, cy, facing, 10, -13,  1,  1, dark)
	# shoes (shared)
	_p(ci, cx, cy, facing, -5, 14,  4,  2, dark)
	_p(ci, cx, cy, facing,  1, 14,  4,  2, dark)

# ---------------------------------------------------------------------------
# Base monsters
# ---------------------------------------------------------------------------

## imp — big head + small body
static func _draw_imp(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -6, -8, 12,  8, color)
	_p(ci, cx, cy, facing, -8, -10,  3,  3, color)
	_p(ci, cx, cy, facing,  5, -10,  3,  3, color)
	_p(ci, cx, cy, facing, -9,  -7,  1,  2, color)
	_p(ci, cx, cy, facing,  8,  -7,  1,  2, color)
	_p(ci, cx, cy, facing, -3,  -5,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing,  1,  -5,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing, -1,  -2,  2,  1, trim)
	_p(ci, cx, cy, facing, -6,   0, 12,  8, dark)
	_p(ci, cx, cy, facing, -4,   1,  8,  4, color)
	_p(ci, cx, cy, facing, -3,   8,  2,  4, dark)
	_p(ci, cx, cy, facing,  1,   8,  2,  4, dark)
	_p(ci, cx, cy, facing, -10,  0,  3,  5, color)
	_p(ci, cx, cy, facing,  7,   0,  3,  5, color)
	_p(ci, cx, cy, facing, -12, -3,  2,  4, dark)
	_p(ci, cx, cy, facing, 10,  -3,  2,  4, dark)
	# tail
	_p(ci, cx, cy, facing,  7,  7,  2,  2, color)
	_p(ci, cx, cy, facing,  9,  9,  2,  2, color)
	_p(ci, cx, cy, facing, 11, 10,  2,  1, trim)

## wyrm — low dragon body
static func _draw_wyrm(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]
	_p(ci, cx, cy, facing, -12, -3, 22,  9, color)
	_p(ci, cx, cy, facing, -10,  0, 18,  5, dark)
	_p(ci, cx, cy, facing,   8, -6,  7, 10, color)
	_p(ci, cx, cy, facing,  11, -4,  3,  3, Color("#ffcd5a"))
	_p(ci, cx, cy, facing,  12, -3,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing,  14, -2,  2,  2, color)
	_p(ci, cx, cy, facing, -14,  0,  6,  3, color)
	_p(ci, cx, cy, facing, -16,  1,  3,  2, color)
	_p(ci, cx, cy, facing,  -6,  6,  3,  5, dark)
	_p(ci, cx, cy, facing,   3,  6,  3,  5, dark)
	_p(ci, cx, cy, facing, -10, -8,  4,  3, dark)
	_p(ci, cx, cy, facing,  -2, -8,  4,  3, dark)
	_p(ci, cx, cy, facing,   6, -9,  3,  3, dark)
	_p(ci, cx, cy, facing,  -3,-11,  5,  3, dark)
	_p(ci, cx, cy, facing,  -3,-11,  5,  1, color)

## merfolk — humanoid with fin tail
static func _draw_merfolk(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -4, -11,  8,  8, color)
	_p(ci, cx, cy, facing, -2,  -8,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing,  1,  -8,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing, -3,  -5,  6,  2, trim)
	_p(ci, cx, cy, facing, -7,  -4, 14,  8, dark)
	_p(ci, cx, cy, facing, -6,  -2, 12,  4, color)
	_p(ci, cx, cy, facing, -9,  -3,  3,  6, color)
	_p(ci, cx, cy, facing,  6,  -3,  3,  6, color)
	_p(ci, cx, cy, facing, -4,   4,  8,  6, color)
	_p(ci, cx, cy, facing,-10,  10,  7,  5, color)
	_p(ci, cx, cy, facing,  3,  10,  7,  5, color)
	_p(ci, cx, cy, facing, -8,  13,  4,  2, dark)
	_p(ci, cx, cy, facing,  4,  13,  4,  2, dark)
	# crown spike
	_p(ci, cx, cy, facing, -1, -14,  2,  3, trim)

## serpent — long coiled serpent
static func _draw_serpent(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -15,  4,  7,  4, color)
	_p(ci, cx, cy, facing, -10,  1,  7,  4, color)
	_p(ci, cx, cy, facing,  -5,  4,  7,  4, color)
	_p(ci, cx, cy, facing,   0,  1,  7,  4, color)
	_p(ci, cx, cy, facing,   5,  4,  7,  4, color)
	_p(ci, cx, cy, facing,  10, -2,  5,  6, color)
	_p(ci, cx, cy, facing,  13, -1,  1,  1, Color("#ffffff"))
	_p(ci, cx, cy, facing,  13,  1,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing,  15,  1,  2,  2, color)
	_p(ci, cx, cy, facing,  11, -5,  4,  3, dark)
	_p(ci, cx, cy, facing,  12, -6,  2,  1, trim)
	_p(ci, cx, cy, facing, -17,  5,  3,  2, dark)

## golem — stone construct
static func _draw_golem(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing,  -9, -10, 18, 20, dark)
	_p(ci, cx, cy, facing,  -7,  -8, 14,  6, color)
	_p(ci, cx, cy, facing,  -3, -15,  6,  5, dark)
	_p(ci, cx, cy, facing,  -2, -13,  1,  1, Color("#ffcd5a"))
	_p(ci, cx, cy, facing,   1, -13,  1,  1, Color("#ffcd5a"))
	_p(ci, cx, cy, facing,  -1, -11,  2,  1, Color("#ffffff"))
	_p(ci, cx, cy, facing, -12,  -5,  3, 14, color)
	_p(ci, cx, cy, facing,   9,  -5,  3, 14, color)
	_p(ci, cx, cy, facing, -13,   8,  5,  4, dark)
	_p(ci, cx, cy, facing,   8,   8,  5,  4, dark)
	_p(ci, cx, cy, facing,  -7,   0, 14,  2, trim)
	_p(ci, cx, cy, facing,  -3,   2,  6,  2, trim)
	_p(ci, cx, cy, facing,  -5,  10,  4,  4, dark)
	_p(ci, cx, cy, facing,   1,  10,  4,  4, dark)

## ogre — hulking brute with weapon
static func _draw_ogre(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]
	_p(ci, cx, cy, facing, -8, -14, 16,  9, color)
	_p(ci, cx, cy, facing, -2, -11,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing,  0, -11,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing, -3,  -7,  8,  2, dark)
	_p(ci, cx, cy, facing, -2,  -6,  1,  1, Color("#ffffff"))
	_p(ci, cx, cy, facing,  2,  -6,  1,  1, dark)
	_p(ci, cx, cy, facing,-10,  -5, 20, 14, dark)
	_p(ci, cx, cy, facing, -8,  -3, 16,  8, color)
	_p(ci, cx, cy, facing,-13,   0,  4,  8, color)
	_p(ci, cx, cy, facing,  9,   0,  4,  8, color)
	_p(ci, cx, cy, facing, 11, -10,  4, 12, Color("#aaaaaa"))
	_p(ci, cx, cy, facing,  8, -14,  9,  6, Color("#dddddd"))
	_p(ci, cx, cy, facing,  9, -16,  2,  2, Color("#ffffff"))
	_p(ci, cx, cy, facing, -5,   9,  4,  4, dark)
	_p(ci, cx, cy, facing,  1,   9,  4,  4, dark)

## wisp — floating glow ball with orbiting motes
static func _draw_wisp(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var trim: Color = p["trim"]
	# Glow corona (concentric circles from outer to inner)
	for r in range(7, 0, -1):
		var alpha := float(8 - r) / 8.0 * 0.4
		ci.draw_circle(Vector2(cx, cy), r * SCALE * 0.9, Color(1.0, 0.902, 0.627, alpha))
	_p(ci, cx, cy, facing, -4, -4, 8, 8, color)
	_p(ci, cx, cy, facing, -3, -3, 6, 6, Color("#fff5b6"))
	_p(ci, cx, cy, facing, -2, -2, 4, 4, Color("#ffffff"))
	# floating motes (5-fold orbit)
	for i in range(5):
		var ang := t * 42.0 / 30.0 + i * 1.2
		var rd := (9.0 + sin(t * 42.0 / 18.0 + i) * 2.0)
		var mx := cx + facing * cos(ang) * rd * SCALE
		var my := cy + sin(ang) * rd * SCALE
		ci.draw_rect(Rect2(mx - 1, my - 1, SCALE, SCALE), trim)

## raptor — outstretched wings
static func _draw_raptor(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	var flap := sin(t * 42.0 / 6.0) * 2.0
	_p(ci, cx, cy, facing, -14, int(-2 - flap), 10, 4, dark)
	_p(ci, cx, cy, facing,   4, int(-2 - flap), 10, 4, dark)
	_p(ci, cx, cy, facing, -13, int( 0 - flap),  8, 3, color)
	_p(ci, cx, cy, facing,   5, int( 0 - flap),  8, 3, color)
	_p(ci, cx, cy, facing, -4, -4, 8, 9, color)
	_p(ci, cx, cy, facing, -1, -9, 4, 5, color)
	_p(ci, cx, cy, facing,  2, -7, 1, 1, Color("#ffcd5a"))
	_p(ci, cx, cy, facing,  2, -5, 1, 1, Color("#110000"))
	_p(ci, cx, cy, facing,  3, -8, 2, 1, trim)
	_p(ci, cx, cy, facing, -3,  5, 6, 4, dark)
	_p(ci, cx, cy, facing, -4,  9, 3, 3, dark)
	_p(ci, cx, cy, facing,  1,  9, 3, 3, dark)

# ---------------------------------------------------------------------------
# Evolved forms
# ---------------------------------------------------------------------------

## infernite — ascended imp: broader frame, crown of horns, armor chest, dual tails
static func _draw_infernite(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -7,  -9, 14,  9, color)
	_p(ci, cx, cy, facing,-10, -12,  4,  4, color)
	_p(ci, cx, cy, facing,  6, -12,  4,  4, color)
	_p(ci, cx, cy, facing, -5, -13,  3,  4, dark)
	_p(ci, cx, cy, facing,  2, -13,  3,  4, dark)
	_p(ci, cx, cy, facing, -3,  -5,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing,  1,  -5,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing, -1,  -2,  2,  1, Color("#ff4040"))
	_p(ci, cx, cy, facing, -7,   0, 14,  9, dark)
	_p(ci, cx, cy, facing, -5,   1, 10,  5, color)
	_p(ci, cx, cy, facing, -5,   3, 10,  2, trim)
	_p(ci, cx, cy, facing, -3,   9,  2,  5, dark)
	_p(ci, cx, cy, facing,  1,   9,  2,  5, dark)
	_p(ci, cx, cy, facing,-12,   0,  4,  6, color)
	_p(ci, cx, cy, facing,  8,   0,  4,  6, color)
	_p(ci, cx, cy, facing,-14,  -4,  2,  5, dark)
	_p(ci, cx, cy, facing, 12,  -4,  2,  5, dark)
	# dual tails
	_p(ci, cx, cy, facing,  7,   8,  2,  2, color)
	_p(ci, cx, cy, facing,  9,  10,  2,  2, color)
	_p(ci, cx, cy, facing, 11,  11,  2,  1, trim)
	_p(ci, cx, cy, facing,  5,  10,  2,  2, color)
	_p(ci, cx, cy, facing,  7,  12,  2,  2, color)
	_p(ci, cx, cy, facing,  9,  13,  1,  1, trim)

## emberdrake — ascended wyrm: thicker body, head frill, back armor, larger tail
static func _draw_emberdrake(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -13, -3, 26, 10, color)
	_p(ci, cx, cy, facing, -11,  0, 22,  5, dark)
	_p(ci, cx, cy, facing,  10, -7,  8, 12, color)
	_p(ci, cx, cy, facing,  14, -5,  3,  3, Color("#ff9020"))
	_p(ci, cx, cy, facing,  15, -4,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing,  17, -3,  3,  3, color)
	_p(ci, cx, cy, facing, -15,  1,  8,  3, color)
	_p(ci, cx, cy, facing, -18,  2,  4,  2, color)
	_p(ci, cx, cy, facing,  -7,  7,  3,  6, dark)
	_p(ci, cx, cy, facing,   3,  7,  3,  6, dark)
	_p(ci, cx, cy, facing,  -9, -9,  4,  5, dark)
	_p(ci, cx, cy, facing,  -2,-10,  4,  5, dark)
	_p(ci, cx, cy, facing,   5,-11,  4,  5, dark)
	_p(ci, cx, cy, facing,   9,-11,  5,  4, trim)
	_p(ci, cx, cy, facing,  12,-13,  3,  3, color)
	_p(ci, cx, cy, facing,  -3,-12,  6,  4, dark)
	_p(ci, cx, cy, facing,  -3,-12,  6,  1, color)

## tidelord — ascended merfolk: taller frame, triple crown, wide tail fins
static func _draw_tidelord(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -5, -12, 10,  9, color)
	_p(ci, cx, cy, facing, -2,  -9,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing,  1,  -9,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing, -3,  -6,  6,  2, trim)
	# triple crown
	_p(ci, cx, cy, facing, -1, -15,  2,  4, trim)
	_p(ci, cx, cy, facing, -3, -14,  1,  3, color)
	_p(ci, cx, cy, facing,  2, -14,  1,  3, color)
	_p(ci, cx, cy, facing, -8,  -4, 16,  9, dark)
	_p(ci, cx, cy, facing, -6,  -2, 12,  5, color)
	_p(ci, cx, cy, facing,-10,  -3,  3,  7, color)
	_p(ci, cx, cy, facing,  7,  -3,  3,  7, color)
	_p(ci, cx, cy, facing, -5,   5, 10,  7, color)
	_p(ci, cx, cy, facing,-12,  12,  8,  6, color)
	_p(ci, cx, cy, facing,  4,  12,  8,  6, color)
	_p(ci, cx, cy, facing,-10,  15,  5,  2, dark)
	_p(ci, cx, cy, facing,  5,  15,  5,  2, dark)
	# scale row on torso
	_p(ci, cx, cy, facing, -4,  0,  1,  1, trim)
	_p(ci, cx, cy, facing, -1,  0,  1,  1, trim)
	_p(ci, cx, cy, facing,  2,  0,  1,  1, trim)

## leviathan — ascended serpent: thicker coils, armored head, double crest
static func _draw_leviathan(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -16,  5,  8,  5, color)
	_p(ci, cx, cy, facing, -10,  1,  8,  5, color)
	_p(ci, cx, cy, facing,  -4,  5,  8,  5, color)
	_p(ci, cx, cy, facing,   2,  1,  8,  5, color)
	_p(ci, cx, cy, facing,   8,  5,  7,  5, color)
	_p(ci, cx, cy, facing,  12, -3,  6,  7, color)
	_p(ci, cx, cy, facing,  15, -2,  1,  1, Color("#ffffff"))
	_p(ci, cx, cy, facing,  15,  1,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing,  17,  1,  2,  2, color)
	_p(ci, cx, cy, facing, -15,  6, 28,  3, dark)
	# double crest
	_p(ci, cx, cy, facing,  13, -7,  5,  3, dark)
	_p(ci, cx, cy, facing,  14, -9,  3,  2, trim)
	_p(ci, cx, cy, facing,  11, -5,  4,  2, dark)
	_p(ci, cx, cy, facing,  12, -7,  2,  2, trim)
	# tail fin
	_p(ci, cx, cy, facing, -18,  6,  3,  4, dark)
	_p(ci, cx, cy, facing, -18,  9,  4,  2, trim)

## colossus — ascended golem: massive frame, shoulder spires, gem array
static func _draw_colossus(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -10, -11, 20, 22, dark)
	_p(ci, cx, cy, facing,  -8,  -9, 16,  7, color)
	_p(ci, cx, cy, facing,  -4, -16,  8,  5, dark)
	_p(ci, cx, cy, facing,  -2, -14,  1,  1, Color("#ffcd5a"))
	_p(ci, cx, cy, facing,   1, -14,  1,  1, Color("#ffcd5a"))
	_p(ci, cx, cy, facing,  -1, -12,  2,  1, Color("#ffffff"))
	_p(ci, cx, cy, facing, -13,  -6,  3, 16, color)
	_p(ci, cx, cy, facing,  10,  -6,  3, 16, color)
	_p(ci, cx, cy, facing, -14,  10,  6,  5, dark)
	_p(ci, cx, cy, facing,   8,  10,  6,  5, dark)
	# shoulder spires
	_p(ci, cx, cy, facing, -16, -11,  3,  7, dark)
	_p(ci, cx, cy, facing, -14, -14,  2,  4, trim)
	_p(ci, cx, cy, facing,  13, -11,  3,  7, dark)
	_p(ci, cx, cy, facing,  14, -14,  2,  4, trim)
	# gem array
	_p(ci, cx, cy, facing,  -7,   1, 14,  3, trim)
	_p(ci, cx, cy, facing,  -4,   5,  8,  3, trim)
	_p(ci, cx, cy, facing,  -2,   8,  4,  2, Color("#ffe080"))
	_p(ci, cx, cy, facing,  -5,  11,  4,  5, dark)
	_p(ci, cx, cy, facing,   1,  11,  4,  5, dark)

## earthbreaker — ascended ogre: hulking, stone armor, stone crown, massive war-maul
static func _draw_earthbreaker(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]
	_p(ci, cx, cy, facing, -9, -15, 18, 10, color)
	_p(ci, cx, cy, facing, -2, -12,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing,  0, -12,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing, -3,  -7,  8,  2, dark)
	_p(ci, cx, cy, facing, -2,  -6,  1,  1, Color("#ffffff"))
	_p(ci, cx, cy, facing,  2,  -6,  2,  2, dark)
	# stone crown (5 battlements)
	_p(ci, cx, cy, facing, -9, -20,  3,  6, dark)
	_p(ci, cx, cy, facing, -5, -21,  3,  6, dark)
	_p(ci, cx, cy, facing, -1, -21,  3,  6, dark)
	_p(ci, cx, cy, facing,  3, -21,  3,  6, dark)
	_p(ci, cx, cy, facing,  6, -20,  3,  6, dark)
	_p(ci, cx, cy, facing,-11,  -6, 22, 15, dark)
	_p(ci, cx, cy, facing, -9,  -4, 18,  9, color)
	_p(ci, cx, cy, facing,-15,   1,  5, 10, color)
	_p(ci, cx, cy, facing, 10,   1,  5, 10, color)
	# shoulder armor plates
	_p(ci, cx, cy, facing,-16,  -5,  5,  6, dark)
	_p(ci, cx, cy, facing, 11,  -5,  5,  6, dark)
	# massive war-maul
	_p(ci, cx, cy, facing, 13, -12,  4, 14, Color("#888888"))
	_p(ci, cx, cy, facing, 10, -16, 10,  6, Color("#cccccc"))
	_p(ci, cx, cy, facing, 11, -18,  3,  3, Color("#ffffff"))
	_p(ci, cx, cy, facing, 16, -18,  2,  2, dark)
	_p(ci, cx, cy, facing, -6,  10,  5,  5, dark)
	_p(ci, cx, cy, facing,  1,  10,  5,  5, dark)

## stormwisp — ascended wisp: larger glow corona, blue-white, crackling lightning
static func _draw_stormwisp(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var trim: Color = p["trim"]
	# Larger glow corona
	for r in range(9, 0, -1):
		var alpha := float(10 - r) / 10.0 * 0.35
		ci.draw_circle(Vector2(cx, cy), r * SCALE * 0.9, Color(0.706, 0.863, 1.0, alpha))
	_p(ci, cx, cy, facing, -5, -5, 10, 10, color)
	_p(ci, cx, cy, facing, -4, -4,  8,  8, Color("#d8f0ff"))
	_p(ci, cx, cy, facing, -3, -3,  6,  6, Color("#ffffff"))
	# floating lightning motes (6-fold orbit)
	for i in range(6):
		var ang := t * 42.0 / 22.0 + i * 1.05
		var rd := 11.0 + sin(t * 42.0 / 14.0 + i) * 2.0
		var mx := cx + facing * cos(ang) * rd * SCALE
		var my := cy + sin(ang) * rd * SCALE
		ci.draw_rect(Rect2(mx - 1, my - 1, SCALE, SCALE), Color("#d0f0ff"))
	# lightning arcs
	_p(ci, cx, cy, facing, -8,  0,  2,  1, trim)
	_p(ci, cx, cy, facing,  6,  0,  2,  1, trim)
	_p(ci, cx, cy, facing,  0, -8,  1,  2, trim)
	_p(ci, cx, cy, facing,  0,  6,  1,  2, trim)

## skytyrant — ascended raptor: armored wings, spiked crest, talons, twin tail fans
static func _draw_skytyrant(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	var flap2 := sin(t * 42.0 / 5.0) * 2.0
	_p(ci, cx, cy, facing, -16, int(-3 - flap2), 12,  5, dark)
	_p(ci, cx, cy, facing,   4, int(-3 - flap2), 12,  5, dark)
	_p(ci, cx, cy, facing, -15, int(-1 - flap2), 10,  3, color)
	_p(ci, cx, cy, facing,   5, int(-1 - flap2), 10,  3, color)
	# wing armor edge
	_p(ci, cx, cy, facing, -17, -2,  2,  6, trim)
	_p(ci, cx, cy, facing,  15, -2,  2,  6, trim)
	_p(ci, cx, cy, facing,  -5, -5, 10, 10, color)
	_p(ci, cx, cy, facing,  -2,-10,  5,  6, color)
	_p(ci, cx, cy, facing,   2, -8,  1,  1, Color("#ffcd5a"))
	_p(ci, cx, cy, facing,   2, -6,  1,  1, Color("#110000"))
	# spiked head crest
	_p(ci, cx, cy, facing,  3,-11,  3,  2, trim)
	_p(ci, cx, cy, facing,  4,-13,  2,  3, color)
	_p(ci, cx, cy, facing,  5,-15,  1,  2, trim)
	_p(ci, cx, cy, facing, -4,  5,  7,  5, dark)
	# twin tail fans
	_p(ci, cx, cy, facing, -5, 10,  3,  4, dark)
	_p(ci, cx, cy, facing, -3, 13,  2,  2, trim)
	_p(ci, cx, cy, facing,  2, 10,  3,  4, dark)
	_p(ci, cx, cy, facing,  3, 13,  2,  2, trim)

# ---------------------------------------------------------------------------
# New base monsters (arcane + roster depth)
# ---------------------------------------------------------------------------

## hexwisp — floating arcane rune-eye wisp, purple/violet glow (hardcoded arcane colors, no owner tint)
static func _draw_hexwisp(ci: CanvasItem, _view: Dictionary, cx: float, cy: float, facing: int, t: float) -> void:
	# glow corona (purple tint)
	for r in range(7, 0, -1):
		var alpha := float(8 - r) / 8.0 * 0.38
		ci.draw_circle(Vector2(cx, cy), r * SCALE * 0.9, Color(0.627, 0.314, 0.941, alpha))
	_p(ci, cx, cy, facing, -4, -4,  8,  8, Color("#7040c0"))
	_p(ci, cx, cy, facing, -3, -3,  6,  6, Color("#c0a0ff"))
	_p(ci, cx, cy, facing, -2, -2,  4,  4, Color("#ffffff"))
	# rune pupils
	_p(ci, cx, cy, facing, -1, -1,  1,  1, Color("#300060"))
	_p(ci, cx, cy, facing,  0,  0,  1,  1, Color("#300060"))
	# orbital rune motes (6-fold, different from wisp's 5-fold)
	for i in range(6):
		var ang := t * 42.0 / 25.0 + i * (PI / 3.0)
		var rd := 8.0 + sin(t * 42.0 / 16.0 + i) * 1.5
		var mx := cx + facing * cos(ang) * rd * SCALE
		var my := cy + sin(ang) * rd * SCALE
		ci.draw_rect(Rect2(mx - 1, my - 1, SCALE, SCALE), Color("#9060d0"))

## runeward — squat obsidian guardian with glowing glyphs
static func _draw_runeward(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -10,  -9, 20, 21, dark)
	_p(ci, cx, cy, facing,  -8,  -7, 16,  6, color)
	_p(ci, cx, cy, facing,  -5, -16, 10,  7, dark)
	_p(ci, cx, cy, facing,  -3, -13,  1,  1, trim)
	_p(ci, cx, cy, facing,   2, -13,  1,  1, trim)
	_p(ci, cx, cy, facing,  -1, -11,  2,  1, Color("#ffffff"))
	# glyph inscriptions on chest
	_p(ci, cx, cy, facing, -7,   1,  3,  3, trim)
	_p(ci, cx, cy, facing, -2,   1,  2,  3, trim)
	_p(ci, cx, cy, facing,  3,   1,  3,  3, trim)
	_p(ci, cx, cy, facing, -6,   6,  2,  2, trim)
	_p(ci, cx, cy, facing, -1,   5,  4,  2, Color("#ffe080"))
	_p(ci, cx, cy, facing,  4,   6,  2,  2, trim)
	_p(ci, cx, cy, facing, -4,   9,  8,  2, trim)
	# arms
	_p(ci, cx, cy, facing, -14,  -5,  3, 16, color)
	_p(ci, cx, cy, facing,  11,  -5,  3, 16, color)
	_p(ci, cx, cy, facing, -15,  10,  6,  5, dark)
	_p(ci, cx, cy, facing,   9,  10,  6,  5, dark)
	_p(ci, cx, cy, facing,  -5,  12,  4,  5, dark)
	_p(ci, cx, cy, facing,   1,  12,  4,  5, dark)

## frostmaw — hulking ice-jawed beast
static func _draw_frostmaw(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]
	_p(ci, cx, cy, facing, -11,  -9, 22, 14, color)
	_p(ci, cx, cy, facing,  -9,  -5, 18,  7, Color("#d0eeff"))
	_p(ci, cx, cy, facing,  -9, -17, 18,  9, color)
	_p(ci, cx, cy, facing,  -3, -13,  2,  2, Color("#110000"))
	_p(ci, cx, cy, facing,   1, -13,  2,  2, Color("#110000"))
	# massive ice jaw
	_p(ci, cx, cy, facing, -10,  -9, 20,  5, Color("#c0e8ff"))
	_p(ci, cx, cy, facing,  -8,  -8,  3,  3, Color("#ffffff"))
	_p(ci, cx, cy, facing,  -3,  -8,  3,  3, Color("#ffffff"))
	_p(ci, cx, cy, facing,   1,  -8,  3,  3, Color("#ffffff"))
	_p(ci, cx, cy, facing,   5,  -8,  3,  3, Color("#ffffff"))
	# frost plating on shoulders
	_p(ci, cx, cy, facing, -14,  -5,  4,  9, Color("#d0eeff"))
	_p(ci, cx, cy, facing,  10,  -5,  4,  9, Color("#d0eeff"))
	_p(ci, cx, cy, facing, -13,  -7,  2,  2, Color("#ffffff"))
	_p(ci, cx, cy, facing,  11,  -7,  2,  2, Color("#ffffff"))
	_p(ci, cx, cy, facing,  -5,   5, 10,  8, dark)
	_p(ci, cx, cy, facing,  -7,   9,  4,  6, dark)
	_p(ci, cx, cy, facing,   3,   9,  4,  6, dark)
	_p(ci, cx, cy, facing,  -5,  15,  4,  3, dark)
	_p(ci, cx, cy, facing,   1,  15,  4,  3, dark)

## duneskink — low fast sand lizard
static func _draw_duneskink(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var p := _pal(view["owner"])
	var color: Color = p["color"]; var dark: Color = p["dark"]; var trim: Color = p["trim"]
	_p(ci, cx, cy, facing, -13, -2, 25,  7, color)
	_p(ci, cx, cy, facing, -11,  0, 21,  3, Color("#d0a050"))
	_p(ci, cx, cy, facing, -15,  1,  5,  3, color)
	_p(ci, cx, cy, facing, -17,  2,  3,  2, dark)
	_p(ci, cx, cy, facing, -18,  3,  2,  1, dark)
	_p(ci, cx, cy, facing,  10, -7,  7,  7, color)
	_p(ci, cx, cy, facing,  13, -5,  1,  1, Color("#110000"))
	_p(ci, cx, cy, facing,  13, -3,  1,  1, Color("#ffffff"))
	_p(ci, cx, cy, facing,  16, -4,  3,  2, dark)
	_p(ci, cx, cy, facing,  17, -3,  2,  1, trim)
	# dorsal stripe
	_p(ci, cx, cy, facing, -11, -3, 20,  1, dark)
	# four legs, splayed wide
	_p(ci, cx, cy, facing, -8,  5,  2,  5, dark)
	_p(ci, cx, cy, facing, -3,  5,  2,  5, dark)
	_p(ci, cx, cy, facing,  3,  5,  2,  5, dark)
	_p(ci, cx, cy, facing,  7,  5,  2,  5, dark)
	# toe details
	_p(ci, cx, cy, facing, -9,  9,  2,  1, dark)
	_p(ci, cx, cy, facing, -7,  9,  2,  1, dark)
	_p(ci, cx, cy, facing,  2,  9,  2,  1, dark)
	_p(ci, cx, cy, facing,  8,  9,  2,  1, dark)

# ---------------------------------------------------------------------------
# Fallback
# ---------------------------------------------------------------------------

## _draw_generic — safety-net for any sprite id that slips through the match.
static func _draw_generic(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, _t: float) -> void:
	var el_col := Color(Elements.ELEMENT.get(view.get("element", "arcane"), {}).get("color", "#cccccc"))
	ci.draw_circle(Vector2(cx, cy - 36), 30.0, el_col)
	ci.draw_circle(Vector2(cx + facing * 10, cy - 44), 6.0, Color.BLACK)
