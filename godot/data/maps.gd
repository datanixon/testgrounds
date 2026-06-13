class_name Maps
extends RefCounted

const MAPS := [
	{"key": "frontier", "name": "Wraithspire Frontier", "desc": "The classic borderland.",
	 "cols": 14, "rows": 12, "seed": -1, "mountains": 4, "lakes": 3, "forests": 22, "hills": 14, "towers": 5, "relics": 2},
	{"key": "tides", "name": "Shattered Tides", "desc": "Drowned field — flyers rule.",
	 "cols": 14, "rows": 12, "seed": -1, "mountains": 1, "lakes": 8, "forests": 12, "hills": 6, "towers": 5,
	 "weather_table": ["rain", "rain", "clear", "gale"], "relics": 2},
	{"key": "crags", "name": "Emberfall Crags", "desc": "Walls of stone, tight passes.",
	 "cols": 15, "rows": 11, "seed": -1, "mountains": 9, "lakes": 1, "forests": 8, "hills": 22, "towers": 4,
	 "castles": [Vector2i(0, 5), Vector2i(9, 5)],
	 "weather_table": ["heat", "heat", "clear", "gale"], "relics": 2},
	{"key": "verdant", "name": "Verdant Expanse", "desc": "Wide greens, six spires.",
	 "cols": 16, "rows": 13, "seed": -1, "mountains": 2, "lakes": 2, "forests": 30, "hills": 10, "towers": 6, "relics": 3},
	{"key": "mistveil", "name": "Mistveil Hollow", "desc": "Fog-shrouded woods.",
	 "cols": 15, "rows": 12, "seed": -1, "mountains": 2, "lakes": 3, "forests": 34, "hills": 10,
	 "towers": 5, "relics": 2, "fog": true},
	{"key": "ashfall", "name": "Ashfall Basin", "desc": "Volcanic crags, ash winds.",
	 "cols": 15, "rows": 11, "seed": -1, "mountains": 8, "lakes": 1, "forests": 6, "hills": 22,
	 "towers": 4, "weather_table": ["heat", "heat", "gale", "clear"], "relics": 2},
]
