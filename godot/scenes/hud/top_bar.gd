class_name TopBar
extends Control
## Top HUD strip: turn #, active player, weather, active master MP, End-Turn button.
## Built in code (no .tscn). Emits end_turn_pressed; main.gd refreshes via refresh(state).

signal end_turn_pressed
signal settings_pressed

const PLAYER_NAMES := ["AZURE", "CRIMSON"]
const Objectives = preload("res://core/objectives.gd")

var _label: Label
var _button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 36)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	add_child(_label)
	_button = Button.new()
	_button.text = "End Turn"
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -110
	_button.offset_top = 4
	_button.offset_right = -10
	_button.offset_bottom = 32
	_button.pressed.connect(func(): end_turn_pressed.emit())
	add_child(_button)
	var gear := Button.new()
	gear.text = "⚙"
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -150
	gear.offset_top = 4
	gear.offset_right = -118
	gear.offset_bottom = 32
	gear.pressed.connect(func(): settings_pressed.emit())
	add_child(gear)

func refresh(state) -> void:
	if state == null or _label == null:
		return
	var who: String = PLAYER_NAMES[state.current_player] if state.current_player < PLAYER_NAMES.size() else str(state.current_player)
	var weather_key: String = state.weather.get("key", "clear") if state.weather != null else "clear"
	var m = state.master_of(state.current_player)
	var mp: int = m["mp"] if m != null else 0
	var base := "Turn %d   %s   Weather: %s   MP: %d" % [state.turn, who, weather_key, mp]
	var obj := Objectives.label(state)
	_label.text = base if obj == "" else base + "   |   " + obj
