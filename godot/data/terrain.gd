class_name Terrain
extends RefCounted

const TERRAIN := {
	"plain":    {"name": "Plain",    "move_cost": 1,  "def": 0, "blocks": false, "color": "#3a5a3e"},
	"forest":   {"name": "Forest",   "move_cost": 2,  "def": 2, "blocks": false, "color": "#1f3e25"},
	"hill":     {"name": "Hill",     "move_cost": 2,  "def": 2, "blocks": false, "color": "#6a5a3a"},
	"mountain": {"name": "Mountain", "move_cost": 4,  "def": 4, "blocks": false, "flyers_only": true, "color": "#4a4452"},
	"water":    {"name": "Tide",     "move_cost": 99, "def": 0, "blocks": true,  "flyers_only": true, "color": "#264a78"},
	"tower":    {"name": "Spire",    "move_cost": 1,  "def": 3, "blocks": false, "capturable": true, "color": "#6a5a72"},
	"castle":   {"name": "Citadel",  "move_cost": 1,  "def": 4, "blocks": false, "color": "#9a8a52"},
}
