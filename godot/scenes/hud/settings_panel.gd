class_name SettingsPanel
extends Control
## M9 settings overlay. Modal panel: MUSIC VOL / SFX VOL (10-segment, persisted,
## inert until M10) + BATTLE SCENE on/off (live: skips the cutaway). Writes back
## to Session.settings via SettingsStore. Mirrors game.js renderSettingsOverlay.

const Pal = preload("res://data/palette.gd")
const SettingsStore = preload("res://core/settings_store.gd")

var session = null
var _panel: Panel
var _built := false
var _bs_on: Button
var _bs_off: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func open(p_session) -> void:
	if p_session == null:
		return
	session = p_session
	if not _built:
		_build()
		_built = true
	_refresh()
	visible = true

func close() -> void:
	visible = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = Panel.new()
	_panel.size = Vector2(360, 240)
	_panel.position = Vector2(640 - 180, 400 - 120)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(20, 18)
	vb.custom_minimum_size = Vector2(320, 0)
	_panel.add_child(vb)
	var title := Label.new(); title.text = "SETTINGS"; vb.add_child(title)
	_add_vol_row(vb, "MUSIC VOL", "music_vol")
	_add_vol_row(vb, "SFX VOL", "sfx_vol")
	# battle scene toggle
	var bs := HBoxContainer.new()
	var bsl := Label.new(); bsl.text = "BATTLE SCENE"; bsl.custom_minimum_size = Vector2(140, 0); bs.add_child(bsl)
	_bs_on = Button.new(); _bs_on.text = "ON"; _bs_on.pressed.connect(func(): _set_bs(true)); bs.add_child(_bs_on)
	_bs_off = Button.new(); _bs_off.text = "OFF"; _bs_off.pressed.connect(func(): _set_bs(false)); bs.add_child(_bs_off)
	vb.add_child(bs)
	var closeb := Button.new(); closeb.text = "CLOSE"; closeb.pressed.connect(close); vb.add_child(closeb)

func _add_vol_row(vb: VBoxContainer, label: String, key: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(140, 0); row.add_child(l)
	for i in range(10):
		var seg := Button.new()
		seg.text = "·"
		seg.custom_minimum_size = Vector2(16, 0)
		var v := (i + 1) / 10.0
		seg.pressed.connect(func(): _set_vol(key, v))
		row.add_child(seg)
	vb.add_child(row)

func _set_vol(key: String, v: float) -> void:
	session.settings[key] = v
	SettingsStore.save_blob(session.settings)
	_refresh()

func _set_bs(on: bool) -> void:
	session.settings["battle_scene"] = on
	SettingsStore.save_blob(session.settings)
	_refresh()

func _refresh() -> void:
	if _bs_on != null and _bs_off != null and session != null:
		var on: bool = session.settings.get("battle_scene", true)
		_bs_on.disabled = on
		_bs_off.disabled = not on
	queue_redraw()   # segment fill is cosmetic; M10 wires real audio + filled bars
