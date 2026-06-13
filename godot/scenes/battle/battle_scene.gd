class_name BattleScene
extends Control
## Full-screen battle cutaway (resolve-then-replay): play(record) animates one already-
## resolved battle, then emits finished. Self-contained — it fills the screen and does NOT
## render the map underneath. Phase durations port the JS `B` table (frames @60fps).
## The phase ORDER is the pure next_phase() (harness-tested).

signal finished

const BattleSprites = preload("res://scenes/battle/battle_sprites.gd")
const BattleFx      = preload("res://scenes/battle/battle_fx.gd")

## Phase frame budgets (JS B table; charge/impact/recover/pause shared by both sides).
const DUR := {
	"intro": 36, "standoff": 26, "aCharge": 22, "aImpact": 34, "aRecover": 18,
	"cPause": 22, "cCharge": 22, "cImpact": 34, "cRecover": 18, "outro": 32,
}

## next_phase — the pure phase transition. `has_counter` is record.counter.happened.
static func next_phase(phase: String, has_counter: bool) -> String:
	match phase:
		"intro": return "standoff"
		"standoff": return "aCharge"
		"aCharge": return "aImpact"
		"aImpact": return "aRecover"
		"aRecover": return "cPause" if has_counter else "outro"
		"cPause": return "cCharge"
		"cCharge": return "cImpact"
		"cImpact": return "cRecover"
		"cRecover": return "outro"
		"outro": return "done"
	return "done"

var _rec: Dictionary = {}
var _phase := "done"
var _frame := 0
var _acc := 0.0
var shake := 0.0
var flash := 0.0
var _ox := 0.0
var _oy := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)

## play — start the cutaway for one battle record. Emits finished when it reaches done.
func play(record: Dictionary) -> void:
	_rec = record
	_phase = "intro"
	_frame = 0
	_acc = 0.0
	shake = 0.0
	flash = 0.0
	visible = true
	set_process(true)
	queue_redraw()
	var _audio := get_node_or_null("/root/Audio")
	if _audio != null:
		_audio.duck(0.35)
		_audio.beep(150.0, 0.08, "square", 0.18)

func _has_counter() -> bool:
	return _rec.get("counter", {}).get("happened", false)

func _process(delta: float) -> void:
	# Advance in fixed 1/60s frames so the ported durations match the JS timing.
	_acc += delta
	while _acc >= 1.0 / 60.0:
		_acc -= 1.0 / 60.0
		flash *= 0.85
		shake *= 0.85
		_ox = (randf() - 0.5) * shake
		_oy = (randf() - 0.5) * shake
		_frame += 1
		var budget: int = DUR.get(_phase, 0)
		if _frame >= budget:
			if _phase == "aCharge" or _phase == "cCharge":
				flash = 1.0
				shake = 6.0
				var _audio2 := get_node_or_null("/root/Audio")
				if _audio2 != null:
					_audio2.beep(170.0, 0.08, "square", 0.18)
			_phase = next_phase(_phase, _has_counter())
			_frame = 0
			if _phase == "done":
				set_process(false)
				visible = false
				var _audio := get_node_or_null("/root/Audio")
				if _audio != null:
					_audio.duck(1.0)
				finished.emit()
				return
	queue_redraw()

func _draw() -> void:
	if _rec.is_empty():
		return
	var sz := get_viewport_rect().size   # parent is a CanvasLayer, so `size` stays (0,0); use the real viewport
	var ox := _ox
	var oy := _oy
	# Reveal/letterbox: bars shrink in during intro, grow back during outro.
	var reveal := 1.0
	if _phase == "intro":
		reveal = clampf(float(_frame) / float(DUR["intro"]), 0.0, 1.0)
	elif _phase == "outro":
		reveal = 1.0 - clampf(float(_frame) / float(DUR["outro"]), 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color("#020107"))
	BattleFx.draw_arena(self, _rec.get("terrain", "plain"), sz)
	var ground := sz.y * 0.62
	var ax := sz.x * 0.30 + ox
	var dx := sz.x * 0.70 + ox
	BattleSprites.draw_unit(self, _rec["attacker"], ax, ground + oy, 1, _pose_for("a"), _phase_t())
	BattleSprites.draw_unit(self, _rec["defender"], dx, ground + oy, -1, _pose_for("c"), _phase_t())
	var a_flavor: String = "bolt" if _rec["attacker"].get("is_master", false) else _rec["attacker"]["attack"]
	var d_flavor: String = "bolt" if _rec["defender"].get("is_master", false) else _rec["defender"]["attack"]
	BattleFx.draw_attack_effect(self, _phase, a_flavor, d_flavor, _rec["attacker"]["element"], _rec["defender"]["element"], ax, dx, ground + oy, _phase_t())
	_draw_hp_bars(Vector2(ax, ground + oy), Vector2(dx, ground + oy))
	_draw_damage_popups(Vector2(ax, ground + oy), Vector2(dx, ground + oy))
	# Letterbox bars.
	var bar_h := sz.y * (1.0 - reveal) / 2.0
	draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, bar_h)), Color.BLACK)
	draw_rect(Rect2(Vector2(0, sz.y - bar_h), Vector2(sz.x, bar_h)), Color.BLACK)
	# Hit flash.
	if flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, clampf(flash, 0, 1) * 0.6))

func _phase_t() -> float:
	var budget: int = DUR.get(_phase, 1)
	return clampf(float(_frame) / float(maxi(1, budget)), 0.0, 1.0)

## _pose_for — map the current phase to a combatant pose for side "a" (attacker) or "c" (defender).
func _pose_for(side: String) -> String:
	var p := _phase
	if side == "a":
		if p == "aCharge": return "charge"
		if p == "aImpact": return "impact"
		if p == "aRecover": return "recover"
	else:
		if p == "cCharge": return "charge"
		if p == "cImpact": return "impact"
		if p == "cRecover": return "recover"
	return "idle"

func _draw_hp_bars(atk_c: Vector2, def_c: Vector2) -> void:
	var def_now: int = _rec["def_hp_before"]
	if _phase in ["aImpact", "aRecover", "cPause", "cCharge", "cImpact", "cRecover", "outro"] and not _rec["primary"]["absorbed"]:
		def_now = maxi(0, _rec["def_hp_before"] - _rec["primary"]["dmg"])
	var atk_now: int = _rec["atk_hp_before"]
	if _rec["counter"]["happened"] and _phase in ["cImpact", "cRecover", "outro"] and not _rec["counter"]["absorbed"]:
		atk_now = maxi(0, _rec["atk_hp_before"] - _rec["counter"]["dmg"])
	_hp_bar(atk_c + Vector2(-40, -96), float(atk_now) / float(maxi(1, _rec["atk_max_hp"])))
	_hp_bar(def_c + Vector2(-40, -96), float(def_now) / float(maxi(1, _rec["def_max_hp"])))

func _hp_bar(top_left: Vector2, frac: float) -> void:
	draw_rect(Rect2(top_left, Vector2(80, 7)), Color(0, 0, 0, 0.7))
	var c := Color("#5ad06a") if frac > 0.5 else (Color("#e0d050") if frac > 0.25 else Color("#e05050"))
	draw_rect(Rect2(top_left, Vector2(80.0 * clampf(frac, 0, 1), 7)), c)

func _draw_damage_popups(atk_c: Vector2, def_c: Vector2) -> void:
	var font := ThemeDB.fallback_font
	if _phase == "aImpact":
		var txt := "WARDED" if _rec["primary"]["absorbed"] else "-%d" % _rec["primary"]["dmg"]
		draw_string(font, def_c + Vector2(-20, -110), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color("#e85858"))
	if _phase == "cImpact" and _rec["counter"]["happened"]:
		var txt2 := "WARDED" if _rec["counter"]["absorbed"] else "-%d" % _rec["counter"]["dmg"]
		draw_string(font, atk_c + Vector2(-20, -110), txt2, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color("#e85858"))
