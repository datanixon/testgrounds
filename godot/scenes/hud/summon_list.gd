class_name SummonList
extends Control
## Anchored summon picker: a Button per UiQueries.summon_options() entry (unaffordable
## ones disabled) plus a Back button. Emits summon_chosen(key) or back.

signal summon_chosen(key: String)
signal back

var _vbox: VBoxContainer
var _panel: PanelContainer

func _ready() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_panel.add_child(_vbox)
	visible = false

func open(options: Array, screen_pos: Vector2) -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()
	var first_enabled: Button = null
	for o in options:
		var b := Button.new()
		b.text = o["label"]
		b.disabled = o["disabled"]
		var key: String = o["key"]
		b.pressed.connect(func(): summon_chosen.emit(key))
		_vbox.add_child(b)
		if not o["disabled"] and first_enabled == null:
			first_enabled = b
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func(): back.emit())
	_vbox.add_child(back_btn)
	_panel.position = _clamp_on_screen(screen_pos)
	visible = true
	if first_enabled != null:
		first_enabled.call_deferred("grab_focus")
	else:
		back_btn.call_deferred("grab_focus")

func close() -> void:
	visible = false

func _clamp_on_screen(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var sz := Vector2(180, 28 * maxi(1, _vbox.get_child_count()))
	return Vector2(clampf(p.x, 0, vp.x - sz.x), clampf(p.y, 36, vp.y - sz.y))
