class_name Weather
extends RefCounted
## Weather engine — port of game.js rollWeather/weatherNow (sec. 19). Stateless;
## reads/writes state.weather, draws from state.rng. The JS banner/log are dropped
## (presentation, added at the HUD layer in M7).

const WeatherData = preload("res://data/weather.gd")

## weatherNow — the active weather record, defaulting to Clear when unset.
static func weather_now(state) -> Dictionary:
	var key: String = state.weather.get("key", "clear")
	return WeatherData.WEATHERS.get(key, WeatherData.WEATHERS["clear"])

## rollWeather — pick the next weather. `initial` forces "clear" (no table draw);
## turns_left always draws once. Draw ORDER matches the JS reference exactly.
static func roll_weather(state, initial: bool) -> void:
	var table: Array = state.map_def.get("weather_table", WeatherData.DEFAULT_WEATHER_TABLE)
	var key: String = "clear" if initial else table[state.rng.below(table.size())]
	state.weather = {"key": key, "turns_left": 4 + state.rng.below(3)}
