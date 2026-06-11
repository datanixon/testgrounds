class_name BattleFx
extends RefCounted
## Battle arena + attack effects — port of game.js drawArenaBackground / drawAttackEffect
## (drawAttackTrail + drawImpactBurst). Pure draw helpers. Placeholder-quality (M10 replaces).

const Elements = preload("res://data/elements.gd")
const Terrain  = preload("res://data/terrain.gd")

## draw_arena — full-screen background tinted by the defender's terrain (port of
## drawArenaBackground). Sky gradient → approximate with a few stacked draw_rect bands;
## add a ground line + sparse parallax detail. `screen` is the Control size.
static func draw_arena(ci: CanvasItem, terrain: String, screen: Vector2) -> void:
	var w := screen.x
	var h := screen.y

	# Sky gradient — 5 horizontal bands lerping between two stop colours.
	var sky_top: Color
	var sky_bot: Color
	if terrain == "water":
		sky_top = Color("#0a2238")
		sky_bot = Color("#1a4a7a")
	elif terrain == "mountain":
		sky_top = Color("#1a1432")
		sky_bot = Color("#3a324a")
	elif terrain == "forest":
		sky_top = Color("#0a1820")
		sky_bot = Color("#1a3a2a")
	elif terrain == "tower" or terrain == "castle":
		sky_top = Color("#1a1024")
		sky_bot = Color("#3a2a44")
	else:
		sky_top = Color("#1a1430")
		sky_bot = Color("#3a2840")

	var bands := 6
	for i in range(bands):
		var frac := float(i) / float(bands)
		var frac2 := float(i + 1) / float(bands)
		var c: Color = sky_top.lerp(sky_bot, (frac + frac2) * 0.5)
		ci.draw_rect(Rect2(0.0, h * frac, w, h * (frac2 - frac) + 1.0), c)

	# Stars — 60 dots in the upper half, brightness seeded by position index.
	for i in range(60):
		var sx := fmod(float(i) * 127.3 + 41.7, w)
		var sy := fmod(float(i) * 53.1 + 19.3, h * 0.5)
		var bright := 0.2 + (sin(float(i) * 0.7) * 0.5 + 0.5) * 0.4
		ci.draw_rect(Rect2(sx, sy, 2.0, 2.0), Color(0.86, 0.82, 1.0, bright))

	# Distant mountain silhouette.
	var sil_y := h * 0.55
	var prev_x := 0.0
	var prev_y := sil_y - 30.0 - fmod(17.3, 60.0)
	var step := 0
	while prev_x < w:
		var nx := prev_x + 40.0 + fmod(float(step) * 53.7 + 11.1, 50.0)
		var ny := sil_y - 30.0 - fmod(float(step + 1) * 37.1 + 7.7, 60.0)
		ci.draw_line(Vector2(prev_x, prev_y), Vector2(nx, ny), Color("#0e0a18"), 1.0)
		prev_x = nx
		prev_y = ny
		step += 1
	# Fill below silhouette as a solid rect.
	ci.draw_rect(Rect2(0.0, sil_y, w, h - sil_y), Color("#0e0a18"))

	# Ground gradient — 5 bands from terrain alt colour to dark.
	var ground_y := h * 0.62
	var tdata: Dictionary = Terrain.TERRAIN.get(terrain, Terrain.TERRAIN["plain"])
	var t_col: Color = Color(tdata["color"])
	# Approximate alt — slightly lighter variant of the terrain colour.
	var t_alt: Color = t_col.lightened(0.15)
	var g_bands := 5
	for i in range(g_bands):
		var frac := float(i) / float(g_bands)
		var frac2 := float(i + 1) / float(g_bands)
		var c: Color = t_alt.lerp(Color("#06040a"), (frac + frac2) * 0.5)
		ci.draw_rect(Rect2(0.0, ground_y + (h - ground_y) * frac, w, (h - ground_y) * (frac2 - frac) + 1.0), c)

	# Ground hex line-pattern (subtle white lines).
	for i in range(12):
		var yy := ground_y + 30.0 + float(i) * 18.0
		var off := float(i % 2) * 30.0
		for j in range(30):
			var xx := float(j) * 60.0 + off
			ci.draw_line(Vector2(xx, yy), Vector2(xx + 20.0, yy), Color(1, 1, 1, 0.05), 1.0)

	# Ground splotches per terrain.
	for i in range(20):
		var sx := fmod(float(i) * 83.7 + 11.3, w)
		var sy := ground_y + 20.0 + fmod(float(i) * 61.3 + 7.1, (h - ground_y - 40.0))
		ci.draw_rect(Rect2(sx, sy, 8.0, 3.0), t_col)

	# Foreground terrain details.
	if terrain == "forest":
		for i in range(6):
			var xx := fmod(float(i) * 139.7 + 23.3, w)
			ci.draw_rect(Rect2(xx, h - 30.0, 12.0, 20.0), Color("#0a1810"))
			ci.draw_rect(Rect2(xx + 2.0, h - 30.0, 8.0, 16.0), Color("#1a3220"))
	elif terrain == "mountain":
		for i in range(5):
			var xx := fmod(float(i) * 157.3 + 31.1, w)
			var mw := 30.0 + fmod(float(i) * 47.3 + 9.1, 30.0)
			var mh := 30.0 + fmod(float(i) * 37.7 + 5.3, 20.0)
			# Triangle rock: draw as two lines meeting at a peak.
			ci.draw_line(Vector2(xx, h), Vector2(xx + mw * 0.5, h - mh), Color("#0a0814"), 8.0)
			ci.draw_line(Vector2(xx + mw * 0.5, h - mh), Vector2(xx + mw, h), Color("#0a0814"), 8.0)


## draw_attack_effect — per-flavor effect during a charge/impact phase (port of
## drawAttackEffect → drawAttackTrail/drawImpactBurst). `phase` is the BattleScene phase;
## `t` is phase progress 0..1; flavors are the acting unit's `attack` ("bolt" for a master).
## aImpact→burst at defender; aCharge→trail from attacker; cImpact→burst at attacker;
## cCharge→trail from defender. atk_x/def_x/ground_y are pixel anchors.
static func draw_attack_effect(ci: CanvasItem, phase: String, attacker_flavor: String,
		defender_flavor: String, attacker_el: String, defender_el: String,
		atk_x: float, def_x: float, ground_y: float, t: float) -> void:
	var ay := ground_y - 40.0
	var dy := ground_y - 40.0
	match phase:
		"aImpact":
			_draw_burst(ci, def_x - 20.0, dy, attacker_el)
		"aCharge":
			_draw_trail(ci, attacker_flavor, atk_x + 60.0, ay, +1.0, t, def_x)
		"cImpact":
			_draw_burst(ci, atk_x + 20.0, ay, defender_el)
		"cCharge":
			_draw_trail(ci, defender_flavor, def_x - 60.0, dy, -1.0, t, atk_x)


## _draw_trail — port of drawAttackTrail. `facing` is +1 (left→right) or −1 (right→left).
## `t` is charge progress 0..1. `target_x` is the destination anchor for range calc.
static func _draw_trail(ci: CanvasItem, kind: String, x: float, y: float,
		facing: float, t: float, target_x: float) -> void:
	# Range heuristic: if target is far (>180px gap) treat as ranged.
	var ranged := absf(target_x - x) > 180.0
	var tx := x + (facing * t * (260.0 if ranged else 30.0))

	match kind:
		"melee":
			# Arc swoosh.
			var rad := 36.0
			var a0 := -PI / 3.0 if facing > 0.0 else PI + PI / 3.0
			var a1 :=  PI / 3.0 if facing > 0.0 else PI - PI / 3.0
			ci.draw_arc(Vector2(x, y), rad, a0, a1, 24, Color(1.0, 0.94, 0.71, 0.85), 3.0)
		"breath":
			# Cone of fire — 8 dots advancing outward.
			for i in range(8):
				var dx := facing * (float(i) * 16.0 + fmod(float(i) * 7.3, 6.0))
				var ddy := (fmod(float(i) * 13.7, 1.0) - 0.5) * 26.0
				var r := 6.0 - float(i) * 0.4
				var alpha := 0.7 - float(i) * 0.06
				var col := Color(1.0, (120.0 + float(i) * 10.0) / 255.0, 40.0 / 255.0, alpha)
				ci.draw_circle(Vector2(x + dx, y + ddy), r, col)
		"spray":
			# Water spray — 14 dots in a wave.
			for i in range(14):
				var dx := facing * (float(i) * 14.0 + fmod(float(i) * 11.3, 4.0))
				var ddy := sin(float(i)) * 18.0
				var alpha := 0.7 - float(i) * 0.04
				ci.draw_rect(Rect2(x + dx - 2.0, y + ddy - 2.0, 4.0, 4.0),
					Color(0.47, 0.78, 0.94, alpha))
		"spark":
			# Wisp sparks — 12 scattered dots + a streak to tx.
			for i in range(12):
				var ang := fmod(float(i) * 137.5 * PI / 180.0, TAU)
				var r := 10.0 + fmod(float(i) * 53.3, 26.0)
				var a := fmod(float(i) * 61.7, 1.0)
				ci.draw_rect(Rect2(x + cos(ang) * r, y + sin(ang) * r, 2.0, 2.0),
					Color(1.0, 0.94, 0.67, a))
			ci.draw_line(Vector2(x, y), Vector2(tx, y), Color(1.0, 0.94, 0.67, 0.9), 2.0)
		"dive":
			# Swooping diagonal line.
			ci.draw_line(Vector2(x - facing * 80.0, y - 60.0),
				Vector2(tx + facing * 30.0, y + 6.0),
				Color(0.86, 0.86, 0.94, 0.8), 4.0)
		"bolt":
			# Arcane orb at tx, approximate radial gradient with stacked circles.
			ci.draw_circle(Vector2(tx, y), 20.0, Color(0.47, 0.31, 0.78, 0.0))  # outer (transparent rim)
			ci.draw_circle(Vector2(tx, y), 14.0, Color(0.78, 0.63, 1.0, 0.6))   # mid purple
			ci.draw_circle(Vector2(tx, y), 7.0,  Color(1.0, 1.0, 1.0, 0.9))     # bright centre
			# Jagged trail.
			var cx2 := x
			while (facing > 0.0 and cx2 < tx) or (facing < 0.0 and cx2 > tx):
				var nx := cx2 + facing * 8.0
				var jitter := (fmod(cx2 * 17.3, 1.0) - 0.5) * 14.0
				ci.draw_line(Vector2(cx2, y), Vector2(nx, y + jitter),
					Color(0.78, 0.63, 1.0, 0.85), 2.0)
				cx2 = nx


## _draw_burst — port of drawImpactBurst.
static func _draw_burst(ci: CanvasItem, x: float, y: float, element: String) -> void:
	var edata: Dictionary = Elements.ELEMENT.get(element, {})
	var col: Color = Color(edata.get("color", "#ffffff") if not edata.is_empty() else "#ffffff")

	# Expanding rings — 3 concentric arcs.
	for i in range(3):
		var ring_col := Color(1.0, 0.94, 0.78, 0.6 - float(i) * 0.15)
		ci.draw_arc(Vector2(x, y), 20.0 + float(i) * 14.0, 0.0, TAU, 24, ring_col, float(3 - i))

	# Shards — 14 dots radiating outward.
	for i in range(14):
		var a := float(i) * (PI / 7.0) + fmod(float(i) * 53.3, 0.3)
		var r := 18.0 + fmod(float(i) * 47.7, 24.0)
		ci.draw_rect(Rect2(x + cos(a) * r, y + sin(a) * r, 3.0, 3.0), col)

	# Centre flash.
	ci.draw_circle(Vector2(x, y), 12.0, Color(1.0, 0.96, 0.82, 0.9))
