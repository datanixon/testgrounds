class_name SettingsStore
extends RefCounted
## M9 settings persistence. Pure defaults()/merge() (harness-tested) + thin
## user:// JSON I/O. Holds music_vol, sfx_vol, battle_scene, plus the persisted
## skirmish prefs (difficulty, map_index, campaign_progress). Mirrors JS
## loadSettings/saveSettings (sec. 3.3). Music/sfx are inert until M10 audio.

const Maps = preload("res://data/maps.gd")
const AiProfiles = preload("res://data/ai_profiles.gd")
const Campaign = preload("res://data/campaign.gd")
const Tracks = preload("res://data/tracks.gd")

const SETTINGS_PATH := "user://wraithspire_settings.json"

static func defaults() -> Dictionary:
	return {
		"music_vol": 0.6, "sfx_vol": 0.6, "battle_scene": true,
		"difficulty": "normal", "map_index": 0, "campaign_progress": 0,
		"music_on": true, "track_index": 0, "fog": false,
	}

## merge — fold a (possibly untrusted) saved blob onto defaults, accepting only
## values of the right type / range; bad fields keep the default.
static func merge(base: Dictionary, saved: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in ["music_vol", "sfx_vol"]:
		if typeof(saved.get(key)) == TYPE_FLOAT or typeof(saved.get(key)) == TYPE_INT:
			out[key] = clampf(float(saved[key]), 0.0, 1.0)
	if typeof(saved.get("battle_scene")) == TYPE_BOOL:
		out["battle_scene"] = saved["battle_scene"]
	if typeof(saved.get("fog")) == TYPE_BOOL:
		out["fog"] = saved["fog"]
	if AiProfiles.DIFFICULTIES.has(saved.get("difficulty")):
		out["difficulty"] = saved["difficulty"]
	if typeof(saved.get("map_index")) == TYPE_FLOAT or typeof(saved.get("map_index")) == TYPE_INT:
		var mi := int(saved["map_index"])
		if mi >= 0 and mi < Maps.MAPS.size():
			out["map_index"] = mi
	if typeof(saved.get("campaign_progress")) == TYPE_FLOAT or typeof(saved.get("campaign_progress")) == TYPE_INT:
		out["campaign_progress"] = clampi(int(saved["campaign_progress"]), 0, Campaign.CAMPAIGN.size() - 1)
	if typeof(saved.get("music_on")) == TYPE_BOOL:
		out["music_on"] = saved["music_on"]
	if typeof(saved.get("track_index")) == TYPE_FLOAT or typeof(saved.get("track_index")) == TYPE_INT:
		out["track_index"] = clampi(int(saved["track_index"]), 0, Tracks.TRACKS.size() - 1)
	return out

# ---- file I/O ----

static func load_blob() -> Dictionary:
	var base := defaults()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return base
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return base
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return base
	return merge(base, parsed)

static func save_blob(blob: Dictionary) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(blob))
	f.close()
