class_name SettingsPanel
extends Control
## M9 settings overlay — wired for M10 audio. Modal panel: MUSIC VOL / SFX VOL
## (10-segment, live via Audio singleton) + BATTLE SCENE on/off + MUSIC ON/OFF
## + TRACK ◀ name ▶ cycler. Writes back to Session.settings via SettingsStore.
## Mirrors game.js renderSettingsOverlay. Panel grew from 240→320px in M10.

const Pal = preload("res://data/palette.gd")
const SettingsStore = preload("res://core/settings_store.gd")

var session = null
var _panel: Panel
var _built := false
var _bs_on: Button
var _bs_off: Button
var _vol_segs := {}   # key -> Array[Button]
var _music_on_btn: Button
var _music_off_btn: Button
var _track_label: Label

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
	_panel.size = Vector2(360, 320)
	_panel.position = Vector2(640 - 180, 400 - 160)
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
	# music on/off
	var mr := HBoxContainer.new()
	var ml := Label.new(); ml.text = "MUSIC"; ml.custom_minimum_size = Vector2(140, 0); mr.add_child(ml)
	_music_on_btn = Button.new(); _music_on_btn.text = "ON"; _music_on_btn.pressed.connect(func(): _set_music_on(true)); mr.add_child(_music_on_btn)
	_music_off_btn = Button.new(); _music_off_btn.text = "OFF"; _music_off_btn.pressed.connect(func(): _set_music_on(false)); mr.add_child(_music_off_btn)
	vb.add_child(mr)
	# track cycler
	var tr := HBoxContainer.new()
	var tl := Label.new(); tl.text = "TRACK"; tl.custom_minimum_size = Vector2(140, 0); tr.add_child(tl)
	var prevb := Button.new(); prevb.text = "◀"; prevb.pressed.connect(_cycle_track); tr.add_child(prevb)
	_track_label = Label.new(); _track_label.custom_minimum_size = Vector2(130, 0); tr.add_child(_track_label)
	var nextb := Button.new(); nextb.text = "▶"; nextb.pressed.connect(_cycle_track); tr.add_child(nextb)
	vb.add_child(tr)
	var closeb := Button.new(); closeb.text = "CLOSE"; closeb.pressed.connect(close); vb.add_child(closeb)

func _add_vol_row(vb: VBoxContainer, label: String, key: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(140, 0); row.add_child(l)
	var segs: Array[Button] = []
	for i in range(10):
		var seg := Button.new()
		seg.custom_minimum_size = Vector2(16, 0)
		var v := (i + 1) / 10.0
		seg.pressed.connect(func(): _set_vol(key, v))
		row.add_child(seg)
		segs.append(seg)
	_vol_segs[key] = segs
	vb.add_child(row)

func _set_vol(key: String, v: float) -> void:
	session.settings[key] = v
	SettingsStore.save_blob(session.settings)
	if key == "music_vol":
		Audio.set_music_vol(v)
	elif key == "sfx_vol":
		Audio.set_sfx_vol(v)
	_refresh()

func _set_bs(on: bool) -> void:
	session.settings["battle_scene"] = on
	SettingsStore.save_blob(session.settings)
	_refresh()

func _set_music_on(on: bool) -> void:
	session.settings["music_on"] = on
	SettingsStore.save_blob(session.settings)
	if on:
		Audio.start_music()
	else:
		Audio.stop_music()
	_refresh()

func _cycle_track() -> void:
	Audio.cycle_track()
	session.settings["track_index"] = Audio.track_index
	SettingsStore.save_blob(session.settings)
	_refresh()

func _refresh() -> void:
	if _bs_on != null and _bs_off != null and session != null:
		var on: bool = session.settings.get("battle_scene", true)
		_bs_on.disabled = on
		_bs_off.disabled = not on
	if session != null:
		for key in _vol_segs:
			var val: float = session.settings.get(key, 0.6)
			var lit := int(round(val * 10.0))
			var segs: Array = _vol_segs[key]
			for i in range(segs.size()):
				segs[i].text = "█" if i < lit else "·"
	if _music_on_btn != null and _music_off_btn != null:
		var on: bool = session.settings.get("music_on", true)
		_music_on_btn.disabled = on
		_music_off_btn.disabled = not on
	if _track_label != null:
		_track_label.text = Audio.current_track_name()
	queue_redraw()
