class_name Statuses
extends RefCounted
## Port of game.js STATUS_META (sec. 16). Presentation metadata for the 7 statuses;
## the engine (core/status.gd) reads only the keys. Writers are the M5 abilities.

const STATUS_META := {
	"burn":         {"color": "#e07050", "label": "burning"},
	"slow":         {"color": "#5aa8d8", "label": "slowed"},
	"regen":        {"color": "#7ac075", "label": "regenerating"},
	"bulwark":      {"color": "#f0c674", "label": "bulwark +2 DEF"},
	"ward":         {"color": "#b078c8", "label": "warded"},
	"mark":         {"color": "#ff8888", "label": "marked +20% dmg taken"},
	"skitterBoost": {"color": "#c8c8d8", "label": "skittering"},
}
