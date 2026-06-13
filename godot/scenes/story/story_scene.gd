class_name StoryScene
extends Control
## M9 mission intro — port of game.js renderStoryScreen (sec. 14b). Intro lines
## fade in sequentially; click begins the match.

const Pal = preload("res://data/palette.gd")
const Campaign = preload("res://data/campaign.gd")

signal begin_mission

const CW := 1280.0
const CH := 800.0

var session = null
var _frame := 0
var _shown_at := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(CW, CH)   # Node2D parent -> anchors give a 0-size rect; size the click area to the canvas

func _process(_delta: float) -> void:
	_frame += 1
	queue_redraw()

func _draw() -> void:
	if session == null:
		return
	var fnt := ThemeDB.fallback_font
	var sc: Dictionary = Campaign.CAMPAIGN[session.story_index]
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	draw_string(fnt, Vector2(CW / 2 - 200, CH * 0.3), "MISSION %d OF %d" % [session.story_index + 1, Campaign.CAMPAIGN.size()], HORIZONTAL_ALIGNMENT_CENTER, 400, 10, Pal.INK_FAINT)
	draw_string(fnt, Vector2(CW / 2 - 300, CH * 0.3 + 34), String(sc["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 600, 24, Pal.GOLD)
	var lines: Array = sc["intro"]
	for i in range(lines.size()):
		var a := clampf((_frame - _shown_at - i * 26) / 26.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		draw_string(fnt, Vector2(CW / 2 - 300, CH * 0.46 + i * 24), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 600, 14, Color(Pal.INK, a))
	if int(_frame / 30.0) % 2 == 0:
		draw_string(fnt, Vector2(CW / 2 - 200, CH * 0.78), "CLICK TO BEGIN", HORIZONTAL_ALIGNMENT_CENTER, 400, 14, Pal.GOLD)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		begin_mission.emit()
