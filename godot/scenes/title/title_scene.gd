class_name TitleScene
extends Control
## M9 title screen — port of game.js renderTitle (sec. 14). Synthwave backdrop,
## map + difficulty selectors, CAMPAIGN / CONTINUE buttons. Emits navigation
## signals the router handles. Reads/writes Session prefs on selection.

const Pal = preload("res://data/palette.gd")
const Maps = preload("res://data/maps.gd")
const Campaign = preload("res://data/campaign.gd")
const AiProfiles = preload("res://data/ai_profiles.gd")
const BattleSprites = preload("res://scenes/battle/battle_sprites.gd")

signal begin_skirmish          # click-anywhere / Enter
signal open_campaign           # CAMPAIGN button
signal continue_save           # CONTINUE button

const CW := 1280.0
const CH := 800.0

var session = null
var _frame := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(CW, CH)   # parent is a Node2D, so anchors resolve to a 0-size rect; size the hit-area to the canvas

func _process(_delta: float) -> void:
	_frame += 1
	queue_redraw()

func _diff_rects() -> Array:
	var w := 92.0; var h := 24.0; var gap := 14.0
	var n := AiProfiles.DIFFICULTIES.size()
	var total := n * w + (n - 1) * gap
	var x0 := (CW - total) / 2.0
	var out: Array = []
	for i in range(n):
		out.append({"key": AiProfiles.DIFFICULTIES[i], "r": Rect2(x0 + i * (w + gap), 742, w, h)})
	return out

func _map_rects() -> Array:
	var w := 150.0; var h := 22.0; var gap := 8.0
	var n := Maps.MAPS.size()
	var total := n * w + (n - 1) * gap
	var x0 := (CW - total) / 2.0
	var out: Array = []
	for i in range(n):
		out.append({"index": i, "r": Rect2(x0 + i * (w + gap), 698, w, h)})
	return out

func _campaign_rect() -> Rect2:
	var y := CH * 0.60
	return Rect2(CW / 2 - 188, y, 180, 38) if session.has_save else Rect2(CW / 2 - 90, y, 180, 38)

func _continue_rect() -> Rect2:
	return Rect2(CW / 2 + 8, CH * 0.60, 180, 38)

func _fog_rect() -> Rect2:
	return Rect2(CW / 2 - 70, 668, 140, 22)

func _draw() -> void:
	if session == null:
		return
	var fnt := ThemeDB.fallback_font
	# backdrop gradient (approx via two rects + blend; flat fill is acceptable parity)
	draw_rect(Rect2(0, 0, CW, CH), Color("#1a1130"))
	draw_rect(Rect2(0, CH * 0.5, CW, CH * 0.5), Color("#05030c"))
	# synthwave grid floor
	var horizon := CH * 0.62
	for i in range(-8, 9):
		draw_line(Vector2(CW / 2, horizon), Vector2(CW / 2 + i * 200, CH), Color(0.78, 0.31, 0.78, 0.4), 1.0)
	for i in range(1, 12):
		var yy := horizon + pow(float(i) / 12.0, 2.2) * (CH - horizon)
		var wln := (float(i) / 12.0) * CW * 0.9
		draw_line(Vector2(CW / 2 - wln, yy), Vector2(CW / 2 + wln, yy), Color(0.78, 0.31, 0.78, maxf(0.0, 0.6 - i * 0.04)), 1.0)
	# stars
	for i in range(120):
		var x := float((i * 73 + int(_frame / 4.0)) % int(CW))
		var y := float((i * 31) % int(CH * 0.55))
		var tw := (sin(_frame / 20.0 + i) + 1.0) / 2.0
		draw_rect(Rect2(x, y, 2, 2), Color(0.86, 0.82, 1.0, 0.3 + tw * 0.5))
	# sun + bars
	draw_circle(Vector2(CW / 2, CH * 0.36), 130, Color("#c8418a"))
	for i in range(5):
		draw_rect(Rect2(CW / 2 - 130, CH * 0.36 + 60 + i * 14, 260, 4), Color("#1a1130"))
	# title text
	draw_string(fnt, Vector2(CW / 2 - 250, CH * 0.38), "WRAITHSPIRE", HORIZONTAL_ALIGNMENT_CENTER, 500, 80, Pal.GOLD)
	draw_string(fnt, Vector2(CW / 2 - 250, CH * 0.46), "— SUMMONER'S WAR —", HORIZONTAL_ALIGNMENT_CENTER, 500, 20, Pal.INK)
	# archon previews
	BattleSprites.draw_unit(self, {"owner": 0, "is_master": true, "sprite": "archon"}, CW / 2 - 180, CH * 0.66, 1, "idle", float(_frame))
	BattleSprites.draw_unit(self, {"owner": 1, "is_master": true, "sprite": "archon"}, CW / 2 + 180, CH * 0.66, -1, "idle", float(_frame))
	# CAMPAIGN / CONTINUE buttons
	var prog := maxi(0, session.campaign_progress)
	var next_idx := -1 if prog >= Campaign.CAMPAIGN.size() - 1 else prog
	var next_name: String = "all missions open" if next_idx < 0 else "next: " + Campaign.CAMPAIGN[next_idx]["name"]
	_draw_btn(_campaign_rect(), "CAMPAIGN", next_name, Pal.GOLD, fnt)
	if session.has_save:
		_draw_btn(_continue_rect(), "CONTINUE", "resume the saved battle", Pal.GREEN, fnt)
	# fog toggle (skirmish)
	var fr := _fog_rect()
	var fog_on: bool = session.settings.get("fog", false)
	draw_rect(fr, Pal.PURPLE if fog_on else Color(0.12, 0.11, 0.19, 0.85))
	draw_rect(fr, Pal.PURPLE if fog_on else Pal.INK_FAINT, false, 1.0)
	draw_string(fnt, Vector2(fr.position.x, fr.position.y + 15), "FOG: ON" if fog_on else "FOG: OFF", HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 12, Pal.BG if fog_on else Pal.INK_DIM)
	# map selector
	for m in _map_rects():
		var sel: bool = m["index"] == session.map_index
		draw_rect(m["r"], Pal.PURPLE if sel else Color(0.12, 0.11, 0.19, 0.85))
		draw_rect(m["r"], Pal.PURPLE if sel else Pal.INK_FAINT, false, 1.0)
		draw_string(fnt, Vector2(m["r"].position.x, m["r"].position.y + 15), String(Maps.MAPS[m["index"]]["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, m["r"].size.x, 11, Pal.BG if sel else Pal.INK_DIM)
	# difficulty selector
	for d in _diff_rects():
		var sel2: bool = d["key"] == session.difficulty
		draw_rect(d["r"], Pal.GOLD if sel2 else Color(0.12, 0.11, 0.19, 0.85))
		draw_rect(d["r"], Pal.GOLD if sel2 else Pal.INK_FAINT, false, 1.0)
		draw_string(fnt, Vector2(d["r"].position.x, d["r"].position.y + 16), String(d["key"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, d["r"].size.x, 12, Pal.BG if sel2 else Pal.INK_DIM)
	# blinking prompt
	if int(_frame / 30.0) % 2 == 0:
		draw_string(fnt, Vector2(CW / 2 - 250, CH * 0.973), "CLICK OR PRESS ENTER TO BEGIN", HORIZONTAL_ALIGNMENT_CENTER, 500, 15, Pal.GOLD)

func _draw_btn(r: Rect2, label: String, sub: String, accent: Color, fnt: Font) -> void:
	draw_rect(r, Color(0.12, 0.11, 0.19, 0.9))
	draw_rect(r, accent, false, 1.0)
	draw_string(fnt, Vector2(r.position.x, r.position.y + 17), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, accent)
	draw_string(fnt, Vector2(r.position.x, r.position.y + 30), sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Pal.INK_DIM)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		begin_skirmish.emit()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	Audio.beep(620.0, 0.06, "triangle", 0.15)
	var p: Vector2 = event.position
	for m in _map_rects():
		if (m["r"] as Rect2).has_point(p):
			session.map_index = m["index"]; session.persist_prefs(); return
	for d in _diff_rects():
		if (d["r"] as Rect2).has_point(p):
			session.difficulty = d["key"]; session.persist_prefs(); return
	if _campaign_rect().has_point(p):
		open_campaign.emit(); return
	if session.has_save and _continue_rect().has_point(p):
		continue_save.emit(); return
	if _fog_rect().has_point(p):
		session.settings["fog"] = not session.settings.get("fog", false)
		session.persist_prefs(); return
	begin_skirmish.emit()
