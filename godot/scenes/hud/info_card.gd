class_name InfoCard
extends Control
## Bottom-left unit info card: stats for the selected/hovered unit. show_unit(unit)
## fills it and makes it visible; clear() hides it. Built in code (no .tscn).

const Relics = preload("res://data/relics.gd")

var _label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = Vector2(12, -150)
	custom_minimum_size = Vector2(240, 138)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label = Label.new()
	_label.position = Vector2(10, 8)
	add_child(_label)
	visible = false

func show_unit(unit) -> void:
	if unit == null:
		clear()
		return
	var statuses := ""
	if unit.has("status") and not unit["status"].is_empty():
		statuses = "  [" + ", ".join(PackedStringArray(unit["status"].keys())) + "]"
	var cd_txt: String = ("  CD %d" % unit["cd"]) if unit.get("cd", 0) > 0 else ""
	var relic_id: String = unit.get("relic", "")
	var relic_txt: String = ""
	if relic_id != "" and Relics.RELICS.has(relic_id):
		relic_txt = "\nRelic: " + Relics.RELICS[relic_id]["name"]
	_label.text = "%s  (%s)\nHP %d/%d   ATK %d   DEF %d\nMOV %d   RNG %d   LV %d%s%s%s" % [
		unit["name"], unit["element"],
		unit["hp"], Relics.max_hp(unit), unit["power"], unit["def"],
		unit["move"] + int(Relics.unit_bonus(unit, "move")), Relics.effective_range(unit), unit["level"], cd_txt, statuses, relic_txt,
	]
	visible = true

func clear() -> void:
	visible = false
