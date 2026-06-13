class_name DeployScene
extends Control
## Phase 5.2 pre-mission veteran picker. Lists the campaign roster, lets the player
## select up to the mission's deploy-slot cap, then emits the chosen entry dicts to
## begin. Mirrors campaign_scene's procedural row-list. ESC -> back to campaign list.

const Pal = preload("res://data/palette.gd")
const RosterStore = preload("res://core/roster_store.gd")
const Deploy = preload("res://core/deploy.gd")

signal begin_mission(picked_entries: Array)
signal back

const CW := 1280.0
const CH := 800.0
const ROW_BG := Color(0.09, 0.08, 0.14)
const MAX_VISIBLE := 7      # rows shown at once; wheel-scroll for more

var session = null
var scenario: Dictionary = {}
var roster: Array = []
var picked := {}            # roster_id -> true
var _reset_armed := false
var _scroll_top := 0        # index of the first visible roster row

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(CW, CH)
	if session != null:
		roster = RosterStore.load_or_init(session.campaign_progress).get("roster", [])

func _cap() -> int:
	return Deploy.slots_for(scenario)

func _max_scroll() -> int:
	return maxi(0, roster.size() - MAX_VISIBLE)

func _row_rects() -> Array:
	var w := 720.0; var h := 56.0; var gap := 10.0
	var x := (CW - w) / 2.0
	var out: Array = []
	var last := mini(roster.size(), _scroll_top + MAX_VISIBLE)
	for i in range(_scroll_top, last):
		var slot := i - _scroll_top
		out.append({"index": i, "r": Rect2(x, 190 + slot * (h + gap), w, h)})
	return out

func _begin_rect() -> Rect2:
	return Rect2(CW / 2.0 - 110, CH - 70, 220, 40)

func _reset_rect() -> Rect2:
	return Rect2(CW - 240, 150, 200, 26)

func _draw() -> void:
	var fnt := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	var title: String = scenario.get("name", "Mission")
	draw_string(fnt, Vector2(CW / 2.0 - 300, 90), "DEPLOY — %s" % title, HORIZONTAL_ALIGNMENT_CENTER, 600, 26, Pal.GOLD)
	draw_string(fnt, Vector2(CW / 2.0 - 300, 124), "choose up to %d veteran(s)  ·  %d / %d selected" % [_cap(), picked.size(), _cap()], HORIZONTAL_ALIGNMENT_CENTER, 600, 12, Pal.INK_DIM)
	if roster.is_empty():
		draw_string(fnt, Vector2(CW / 2.0 - 250, 240), "no veterans yet — summon fresh in battle", HORIZONTAL_ALIGNMENT_CENTER, 500, 14, Pal.INK_DIM)
	else:
		for row in _row_rects():
			var e: Dictionary = roster[row["index"]]
			var r: Rect2 = row["r"]
			var sel: bool = picked.has(int(e["roster_id"]))
			draw_rect(r, Pal.PANEL_LIGHT if sel else ROW_BG)
			draw_rect(r, Pal.GOLD if sel else Pal.INK_FAINT, false, 1.0)
			draw_string(fnt, Vector2(r.position.x + 16, r.position.y + 24), "%s    L%d    %s" % [e.get("name", "?"), int(e.get("level", 1)), String(e.get("element", "")).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.GOLD if sel else Pal.INK)
			var relic: String = String(e.get("relic", ""))
			var line2: String = "HP %d   PWR %d   DEF %d%s" % [int(e.get("max_hp", 0)), int(e.get("power", 0)), int(e.get("def", 0)), ("    ·  relic: " + relic) if relic != "" else ""]
			draw_string(fnt, Vector2(r.position.x + 16, r.position.y + 44), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Pal.INK_DIM)
	if not roster.is_empty():
		if _scroll_top > 0:
			draw_string(fnt, Vector2(CW / 2.0 - 60, 178), "▲ more above", HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Pal.INK_DIM)
		if _scroll_top < _max_scroll():
			draw_string(fnt, Vector2(CW / 2.0 - 60, CH - 92), "▼ more below", HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Pal.INK_DIM)
	var br := _begin_rect()
	draw_rect(br, Pal.PANEL_LIGHT)
	draw_rect(br, Pal.GOLD, false, 1.0)
	draw_string(fnt, Vector2(br.position.x, br.position.y + 26), "BEGIN MISSION", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 15, Pal.GOLD)
	var rr := _reset_rect()
	draw_string(fnt, Vector2(rr.position.x, rr.position.y + 18), "click again to confirm reset" if _reset_armed else "↻ reset roster", HORIZONTAL_ALIGNMENT_LEFT, rr.size.x, 11, Pal.RED if _reset_armed else Pal.INK_FAINT)
	draw_string(fnt, Vector2(CW / 2.0 - 250, CH - 18), "click a veteran to toggle  ·  ESC to go back", HORIZONTAL_ALIGNMENT_CENTER, 500, 11, Pal.INK_DIM)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		back.emit()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_top = clampi(_scroll_top + 1, 0, _max_scroll())
		queue_redraw()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_top = clampi(_scroll_top - 1, 0, _max_scroll())
		queue_redraw()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos: Vector2 = event.position
	if _begin_rect().has_point(pos):
		var out: Array = []
		for e in roster:
			if picked.has(int(e["roster_id"])):
				out.append(e)
		begin_mission.emit(out)
		return
	if _reset_rect().has_point(pos):
		if _reset_armed:
			RosterStore.reset()
			roster = RosterStore.load_or_init(session.campaign_progress).get("roster", [])
			picked.clear()
			_reset_armed = false
		else:
			_reset_armed = true
		queue_redraw()
		return
	if _reset_armed:
		_reset_armed = false
		queue_redraw()
	for row in _row_rects():
		if (row["r"] as Rect2).has_point(pos):
			var rid: int = int(roster[row["index"]]["roster_id"])
			if picked.has(rid):
				picked.erase(rid)
			elif picked.size() < _cap():
				picked[rid] = true
			queue_redraw()
			return
