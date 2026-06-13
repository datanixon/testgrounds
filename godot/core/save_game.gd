class_name SaveGame
extends RefCounted
## M9 save/load. Pure to_dict/from_dict (harness-tested round-trip) + thin
## user:// file I/O. Versioned blob (v:1); loader defaults missing fields and
## normalizes pre-ability units (cd). Mirrors JS saveGame/loadGame (sec. 6.1),
## additionally serializing map_def to fix the resumed-campaign weather gap.

const GameStateLib = preload("res://core/game_state.gd")
const Rng = preload("res://core/rng.gd")

const SAVE_PATH := "user://wraithspire_save.json"

## to_dict — pure snapshot of a live match. Serializes living units whole, the
## terrain cells (owners mutate, so a seed isn't enough), weather, and map_def.
static func to_dict(state) -> Dictionary:
	var cells: Array = []
	for c in state.map.get("cells", {}).values():
		cells.append({"q": c["q"], "r": c["r"], "terrain": c["terrain"], "owner": c.get("owner", -1)})
	var living: Array = []
	for u in state.units:
		if u["hp"] > 0:
			living.append(u.duplicate(true))
	return {
		"v": 1,
		"fog": state.fog,
		"turn": state.turn,
		"current_player": state.current_player,
		"next_id": state._next_id,
		"cols": state.map.get("cols", 0),
		"rows": state.map.get("rows", 0),
		"cells": cells,
		"units": living,
		"stats": state.stats.duplicate(true),
		"campaign_index": state.campaign_index,
		"match_difficulty": state.match_difficulty,
		"difficulty": state.difficulty,
		"is_ai": state.is_ai.duplicate(),
		"weather": state.weather.duplicate(true),
		"map_def": state.map_def.duplicate(true),
		"relics": (state.map.get("relics", []) as Array).duplicate(true),
	}

## from_dict — rebuild a GameState from a blob, or null if invalid. Rebuilds the
## map cell dictionary + tower/castle reference lists, restores units (normalizing
## missing cd), and defaults missing weather/stats/is_ai for old blobs.
static func from_dict(blob) -> GameState:
	if blob == null or typeof(blob) != TYPE_DICTIONARY:
		return null
	if blob.get("v", 0) != 1:
		return null
	if typeof(blob.get("cells")) != TYPE_ARRAY or typeof(blob.get("units")) != TYPE_ARRAY:
		return null
	var gs = GameStateLib.new()
	var cells := {}
	var towers: Array[Vector2i] = []
	var castles: Array[Vector2i] = []
	for c in blob["cells"]:
		var cell := {"q": int(c["q"]), "r": int(c["r"]), "terrain": c["terrain"], "owner": int(c.get("owner", -1))}
		cells["%d,%d" % [cell["q"], cell["r"]]] = cell
		if cell["terrain"] == "tower":
			towers.append(Vector2i(cell["q"], cell["r"]))
		elif cell["terrain"] == "castle":
			castles.append(Vector2i(cell["q"], cell["r"]))
	gs.map = {
		"cols": int(blob.get("cols", 0)), "rows": int(blob.get("rows", 0)),
		"cells": cells, "towers": towers, "castles": castles,
	}
	var relics: Array = []
	for r in blob.get("relics", []):
		relics.append({"q": int(r["q"]), "r": int(r["r"]), "relic": String(r["relic"])})
	gs.map["relics"] = relics
	var units: Array[Dictionary] = []
	for u in blob["units"]:
		var ud: Dictionary = (u as Dictionary).duplicate(true)
		if typeof(ud.get("cd")) != TYPE_INT and typeof(ud.get("cd")) != TYPE_FLOAT:
			ud["cd"] = 0
		units.append(ud)
	# JSON round-trip turns ints into floats in GDScript 4; re-coerce all numeric unit fields.
	for ud in units:
		for k in ["id", "owner", "q", "r", "hp", "max_hp", "move", "range", "power", "def", "level", "xp", "cd", "mp", "max_mp", "mp_regen"]:
			if ud.has(k):
				ud[k] = int(ud[k])
	gs.units = units
	gs.turn = int(blob.get("turn", 1))
	gs.current_player = int(blob.get("current_player", 0))
	gs._next_id = int(blob.get("next_id", 1000))
	gs.stats = blob.get("stats", {"summoned": [0, 0], "lost": [0, 0], "battles": 0})
	var stx: Dictionary = gs.stats
	if typeof(stx.get("summoned")) == TYPE_ARRAY:
		stx["summoned"] = [int(stx["summoned"][0]), int(stx["summoned"][1])]
	if typeof(stx.get("lost")) == TYPE_ARRAY:
		stx["lost"] = [int(stx["lost"][0]), int(stx["lost"][1])]
	if stx.has("battles"):
		stx["battles"] = int(stx["battles"])
	gs.stats = stx
	gs.campaign_index = int(blob.get("campaign_index", -1))
	gs.match_difficulty = blob.get("match_difficulty", "normal")
	gs.difficulty = blob.get("difficulty", "normal")
	var ai = blob.get("is_ai", [false, true])
	var ai_arr: Array[bool] = [false, true]
	if typeof(ai) == TYPE_ARRAY and (ai as Array).size() >= 2:
		ai_arr[0] = bool(ai[0])
		ai_arr[1] = bool(ai[1])
	gs.is_ai = ai_arr
	gs.weather = blob.get("weather", {"key": "clear", "turns_left": 5})
	gs.map_def = blob.get("map_def", {})
	gs.rng = Rng.new(0)   # resumed match: fresh RNG stream (determinism is per-session, not cross-save)
	gs.fog = bool(blob.get("fog", false))
	return gs

# ---- file I/O (thin; not unit-tested — the pure round-trip above is) ----

static func save(state) -> void:
	if state == null:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(to_dict(state)))
	f.close()

static func load_game() -> GameState:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return from_dict(parsed)

static func delete() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

static func probe() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
