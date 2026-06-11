class_name ActionMenu
extends Control
## Anchored post-move action menu: a vertical stack of Buttons built from a
## UiQueries.available_actions() list. open(actions, screen_pos) shows it at a screen
## position (clamped on-screen); a click (or focus+Enter) emits action_chosen(kind).
## Disabled items render as disabled buttons and cannot be chosen.

signal action_chosen(kind: String)

var _vbox: VBoxContainer
var _panel: PanelContainer

func _ready() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_panel.add_child(_vbox)
	visible = false

func open(actions: Array, screen_pos: Vector2) -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()
	var first_enabled: Button = null
	for a in actions:
		var b := Button.new()
		b.text = a["label"]
		b.disabled = a["disabled"]
		var kind: String = a["kind"]
		b.pressed.connect(func(): action_chosen.emit(kind))
		_vbox.add_child(b)
		if not a["disabled"] and first_enabled == null:
			first_enabled = b
	_panel.position = _clamp_on_screen(screen_pos)
	visible = true
	if first_enabled != null:
		first_enabled.call_deferred("grab_focus")

func close() -> void:
	visible = false

func _clamp_on_screen(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var sz := _panel.size if _panel.size.x > 0 else Vector2(160, 28 * maxi(1, _vbox.get_child_count()))
	return Vector2(clampf(p.x, 0, vp.x - sz.x), clampf(p.y, 36, vp.y - sz.y))
