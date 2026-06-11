class_name Elements
extends RefCounted
## Faithful port of game.js ELEMENT / ELEM_MATRIX / AFFINITY (sec. 4). Balance-
## locked. ELEM_MATRIX[attacker][defender] is the damage multiplier; arcane is the
## flat 1.1 "anti-everything" row. Affinity: attacking FROM an empowering terrain
## adds AFFINITY_MULT (+20%).

const ELEMENT := {
	"pyro":   {"name": "Pyro",   "color": "#e07050", "short": "PYR"},
	"hydro":  {"name": "Hydro",  "color": "#5aa8d8", "short": "HYD"},
	"terra":  {"name": "Terra",  "color": "#9a7a4a", "short": "TER"},
	"zephyr": {"name": "Zephyr", "color": "#c8c8d8", "short": "ZEP"},
	"arcane": {"name": "Arcane", "color": "#b078c8", "short": "ARC"},
}

const ELEM_MATRIX := {
	"pyro":   {"pyro": 1.0, "hydro": 0.7, "terra": 1.0, "zephyr": 1.3, "arcane": 1.0},
	"hydro":  {"pyro": 1.3, "hydro": 1.0, "terra": 0.7, "zephyr": 1.0, "arcane": 1.0},
	"terra":  {"pyro": 1.0, "hydro": 1.3, "terra": 1.0, "zephyr": 0.7, "arcane": 1.0},
	"zephyr": {"pyro": 0.7, "hydro": 1.0, "terra": 1.3, "zephyr": 1.0, "arcane": 1.0},
	"arcane": {"pyro": 1.1, "hydro": 1.1, "terra": 1.1, "zephyr": 1.1, "arcane": 1.0},
}

const AFFINITY_MULT := 1.2

const ELEM_AFFINITY := {
	"pyro":   {"terrains": ["hill", "mountain"], "label": "scorching heights"},
	"hydro":  {"terrains": ["water", "forest"],  "label": "drenched ground"},
	"terra":  {"terrains": ["mountain", "hill"], "label": "raw bedrock"},
	"zephyr": {"terrains": ["plain", "mountain"], "label": "open skies"},
	"arcane": {"terrains": ["tower", "castle"],  "label": "ley nexus"},
}

## Returns the affinity record if `element` is empowered on `terrain`, else null.
static func affinity_for(element: String, terrain: String) -> Variant:
	var a: Dictionary = ELEM_AFFINITY.get(element, {})
	if a.is_empty():
		return null
	return a if a.get("terrains", []).has(terrain) else null
