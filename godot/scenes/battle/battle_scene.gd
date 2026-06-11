class_name BattleScene
extends Control
## Full-screen battle cutaway (resolve-then-replay): play(record) animates one already-
## resolved battle, then emits finished. Self-contained — it fills the screen and does NOT
## render the map underneath. Portraits (battle_sprites) + effects (battle_fx) wire in at
## Tasks 3-4; this skeleton draws placeholder combatant boxes. Phase durations port the JS
## `B` table (frames @60fps). The phase ORDER is the pure next_phase() (harness-tested).

signal finished

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

func _has_counter() -> bool:
	return _rec.get("counter", {}).get("happened", false)

func _process(delta: float) -> void:
	# Advance in fixed 1/60s frames so the ported durations match the JS timing.
	_acc += delta
	flash *= 0.85
	shake *= 0.85
	while _acc >= 1.0 / 60.0:
		_acc -= 1.0 / 60.0
		_frame += 1
		var budget: int = DUR.get(_phase, 0)
		if _frame >= budget:
			if _phase == "aCharge" or _phase == "cCharge":
				flash = 1.0
				shake = 6.0
			_phase = next_phase(_phase, _has_counter())
			_frame = 0
			if _phase == "done":
				set_process(false)
				visible = false
				finished.emit()
				return
	queue_redraw()

func _draw() -> void:
	if _rec.is_empty():
		return
	var sz := size
	var ox := (randf() - 0.5) * shake
	var oy := (randf() - 0.5) * shake
	# Reveal/letterbox: bars shrink in during intro, grow back during outro.
	var reveal := 1.0
	if _phase == "intro":
		reveal = clampf(float(_frame) / float(DUR["intro"]), 0.0, 1.0)
	elif _phase == "outro":
		reveal = 1.0 - clampf(float(_frame) / float(DUR["outro"]), 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color("#020107"))
	# Placeholder combatants (Task 3 replaces with portraits).
	var ground := sz.y * 0.62
	var ax := sz.x * 0.30 + ox
	var dx := sz.x * 0.70 + ox
	_draw_box(Vector2(ax, ground + oy), _rec["attacker"]["owner"])
	_draw_box(Vector2(dx, ground + oy), _rec["defender"]["owner"])
	# Letterbox bars.
	var bar_h := sz.y * (1.0 - reveal) / 2.0
	draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, bar_h)), Color.BLACK)
	draw_rect(Rect2(Vector2(0, sz.y - bar_h), Vector2(sz.x, bar_h)), Color.BLACK)
	# Hit flash.
	if flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, clampf(flash, 0, 1) * 0.6))

func _draw_box(center: Vector2, owner: int) -> void:
	var col := Color("#5aa8d8") if owner == 0 else Color("#cc6a4a")
	draw_rect(Rect2(center - Vector2(40, 80), Vector2(80, 80)), col)
