class_name CampaignScene
extends Control
## M9 campaign mission list — port of game.js renderCampaignScreen (sec. 14b).
## Rows unlock by Session.campaign_progress. Click unlocked -> story; ESC -> title.

const Pal = preload("res://data/palette.gd")
const Campaign = preload("res://data/campaign.gd")

signal pick_mission(index: int)
signal back_to_title

const CW := 1280.0
const CH := 800.0

var session = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)   # equal anchors -> explicit size sticks (no FULL_RECT override warning)
	size = Vector2(CW, CH)   # Node2D parent -> anchors give no rect; size the click area to the canvas

func _row_rects() -> Array:
	var w := 720.0; var h := 70.0; var gap := 16.0
	var x := (CW - w) / 2.0
	var out: Array = []
	for i in range(Campaign.CAMPAIGN.size()):
		out.append({"index": i, "r": Rect2(x, 170 + i * (h + gap), w, h)})
	return out

func _draw() -> void:
	if session == null:
		return
	var fnt := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	draw_string(fnt, Vector2(CW / 2 - 200, 90), "CAMPAIGN", HORIZONTAL_ALIGNMENT_CENTER, 400, 28, Pal.GOLD)
	draw_string(fnt, Vector2(CW / 2 - 300, 116), "— the fall of the crimson archon, in four battles —", HORIZONTAL_ALIGNMENT_CENTER, 600, 11, Pal.INK_DIM)
	for row in _row_rects():
		var i: int = row["index"]
		var r: Rect2 = row["r"]
		var sc: Dictionary = Campaign.CAMPAIGN[i]
		var unlocked: bool = i <= session.campaign_progress
		var cleared: bool = i < session.campaign_progress
		draw_rect(r, Pal.PANEL_LIGHT if unlocked else Color(0.075, 0.067, 0.12, 0.7))
		draw_rect(r, Pal.GOLD if unlocked else Pal.INK_FAINT, false, 1.0)
		draw_string(fnt, Vector2(r.position.x + 18, r.position.y + 28), "%d.  %s" % [i + 1, sc["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.GOLD if unlocked else Pal.INK_FAINT)
		var teaser: String = (sc["intro"][0] + " ...") if unlocked else "locked — clear the previous mission"
		draw_string(fnt, Vector2(r.position.x + 18, r.position.y + 48), teaser, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Pal.INK_DIM if unlocked else Pal.INK_FAINT)
		var badge: String = "CLEARED" if cleared else ("READY" if unlocked else "LOCKED")
		var bcol: Color = Pal.GREEN if cleared else (Pal.GOLD if unlocked else Pal.INK_FAINT)
		draw_string(fnt, Vector2(r.position.x + r.size.x - 120, r.position.y + 28), badge, HORIZONTAL_ALIGNMENT_RIGHT, 104, 11, bcol)
		draw_string(fnt, Vector2(r.position.x + r.size.x - 120, r.position.y + 48), String(sc["difficulty"]).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 104, 10, Pal.INK_DIM if unlocked else Pal.INK_FAINT)
	draw_string(fnt, Vector2(CW / 2 - 250, CH - 40), "click a mission to begin  ·  ESC to return", HORIZONTAL_ALIGNMENT_CENTER, 500, 11, Pal.INK_DIM)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		back_to_title.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for row in _row_rects():
			if (row["r"] as Rect2).has_point(event.position) and row["index"] <= session.campaign_progress:
				pick_mission.emit(row["index"]); return
