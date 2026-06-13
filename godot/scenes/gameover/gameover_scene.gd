class_name GameoverScene
extends Control
## M9 victory screen — port of game.js renderGameOver (sec. 14). Winning archon
## silhouette, faction banner, stats summary, campaign verdict. Click/Enter ->
## title. Built from a finished GameState handed in via set_result().

const Pal = preload("res://data/palette.gd")
const Campaign = preload("res://data/campaign.gd")
const BattleSprites = preload("res://scenes/battle/battle_sprites.gd")

signal to_title

const CW := 1280.0
const CH := 800.0

var _state = null
var _frame := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(CW, CH)   # Node2D parent -> anchors give a 0-size rect; size the click area to the canvas

func set_result(state) -> void:
	_state = state

func _process(_delta: float) -> void:
	_frame += 1
	queue_redraw()

func _draw() -> void:
	if _state == null:
		return
	var fnt := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	var won_p0: bool = _state.winner == 0
	var text: String = ("AZURE" if won_p0 else "CRIMSON") + " TRIUMPHS"
	var col: Color = Pal.P0 if won_p0 else Pal.P1
	BattleSprites.draw_unit(self, {"owner": _state.winner, "is_master": true, "sprite": "archon"}, CW / 2, CH / 2 - 40, 1, "idle", float(_frame))
	draw_string(fnt, Vector2(CW / 2 - 350, CH / 2 + 80), text, HORIZONTAL_ALIGNMENT_CENTER, 700, 56, col)
	var st: Dictionary = _state.stats
	# towers/castles are stored as Array[Vector2i] coords; ownership lives on the
	# CELL (cell.owner), not the tower entry — so look up each tower's cell.
	var towers := [0, 0]
	for t in _state.map.get("towers", []):
		var tcell = _state.cell_at(t.x, t.y)
		if tcell != null:
			var o: int = tcell.get("owner", -1)
			if o == 0 or o == 1:
				towers[o] += 1
	draw_string(fnt, Vector2(CW / 2 - 300, CH / 2 + 116), "Turns elapsed: %d     Battles fought: %d" % [_state.turn, st["battles"]], HORIZONTAL_ALIGNMENT_CENTER, 600, 14, Pal.INK_DIM)
	# two-column stat table
	var cx0 := CW / 2; var colL := cx0 - 90; var colR := cx0 + 90; var top := CH / 2 + 140
	draw_string(fnt, Vector2(colL - 50, top), "AZURE", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Pal.P0)
	draw_string(fnt, Vector2(colR - 50, top), "CRIMSON", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Pal.P1)
	var rows := [
		["Summoned", st["summoned"][0], st["summoned"][1]],
		["Lost", st["lost"][0], st["lost"][1]],
		["Spires", towers[0], towers[1]],
	]
	for i in range(rows.size()):
		var ry := top + 20 + i * 17
		draw_string(fnt, Vector2(cx0 - 50, ry), String(rows[i][0]), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Pal.INK_DIM)
		draw_string(fnt, Vector2(colL - 50, ry), str(rows[i][1]), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Pal.INK)
		draw_string(fnt, Vector2(colR - 50, ry), str(rows[i][2]), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Pal.INK)
	# campaign verdict
	if _state.campaign_index >= 0:
		var msg: String; var vcol: Color
		if won_p0:
			var last: bool = _state.campaign_index >= Campaign.CAMPAIGN.size() - 1
			msg = "CAMPAIGN COMPLETE — THE REALM IS YOURS" if last else "MISSION COMPLETE — THE NEXT BATTLE AWAITS"
			vcol = Pal.GREEN
		else:
			msg = "MISSION FAILED — THE FRONTIER REMEMBERS"
			vcol = Pal.RED
		draw_string(fnt, Vector2(CW / 2 - 350, CH / 2 + 196), msg, HORIZONTAL_ALIGNMENT_CENTER, 700, 13, vcol)
	if int(_frame / 30.0) % 2 == 0:
		draw_string(fnt, Vector2(CW / 2 - 300, CH - 60), "CLICK OR PRESS ENTER TO RETURN TO TITLE", HORIZONTAL_ALIGNMENT_CENTER, 600, 14, Pal.GOLD)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		to_title.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		to_title.emit()
