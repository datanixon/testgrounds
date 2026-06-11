class_name WeatherData
extends RefCounted
## Port of game.js WEATHERS + DEFAULT_WEATHER_TABLE (sec. 19). One global modifier,
## re-rolled ~every 5 turns from the map's table. Read inside combat (atk_mul,
## ranged_mul) and movement (fly_bonus) so forecast and AI inherit it for free.

const WEATHERS := {
	"clear": {"name": "Clear",    "color": "#8a85a2"},
	"rain":  {"name": "Rain",     "color": "#5aa8d8", "atk_mul": {"hydro": 1.15, "pyro": 0.85}},
	"heat":  {"name": "Heatwave", "color": "#e07050", "atk_mul": {"pyro": 1.15, "hydro": 0.85}},
	"gale":  {"name": "Gale",     "color": "#c8c8d8", "ranged_mul": 0.8, "fly_bonus": 1},
}

const DEFAULT_WEATHER_TABLE := ["clear", "clear", "rain", "heat", "gale"]
