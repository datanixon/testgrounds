class_name Session
extends RefCounted
## M9 app/session state — the slice of the JS STATE that outlives any single
## match: the active screen, persisted prefs (difficulty/map_index/campaign_progress),
## the settings blob, and the live GameState (or null on menu screens). Owned by
## the router (scenes/main.gd). Match-start helpers mirror JS startNewGame.

const GameStateLib = preload("res://core/game_state.gd")
const Maps = preload("res://data/maps.gd")
const Campaign = preload("res://data/campaign.gd")
const SettingsStore = preload("res://core/settings_store.gd")
const SaveGame = preload("res://core/save_game.gd")

var screen: String = "title"          # title | campaign | story | play | gameover
var settings: Dictionary = SettingsStore.defaults()
var difficulty: String = "normal"     # persisted skirmish difficulty
var map_index: int = 0                 # persisted skirmish map
var campaign_progress: int = 0         # highest unlocked mission index
var story_index: int = 0               # mission selected on the campaign screen
var has_save: bool = false
var state = null                       # the live GameState, or null

## load_prefs — pull persisted settings into the session at boot.
func load_prefs() -> void:
	settings = SettingsStore.load_blob()
	difficulty = settings["difficulty"]
	map_index = settings["map_index"]
	campaign_progress = settings["campaign_progress"]
	has_save = SaveGame.probe()

## persist_prefs — write current prefs back to the settings file.
func persist_prefs() -> void:
	settings["difficulty"] = difficulty
	settings["map_index"] = map_index
	settings["campaign_progress"] = campaign_progress
	SettingsStore.save_blob(settings)

func start_skirmish() -> void:
	var def: Dictionary = Maps.MAPS[map_index] if map_index < Maps.MAPS.size() else Maps.MAPS[0]
	var seed: int = def["seed"] if int(def.get("seed", -1)) >= 0 else randi()
	state = GameStateLib.new_skirmish(def, seed)
	state.difficulty = difficulty
	state.match_difficulty = difficulty
	state.campaign_index = -1
	state.fog = bool(settings.get("fog", false)) or bool(def.get("fog", false))
	screen = "play"

func start_campaign(index: int) -> void:
	state = GameStateLib.new_campaign(Campaign.CAMPAIGN[index], index)
	state.fog = bool(Campaign.CAMPAIGN[index]["map"].get("fog", false))
	screen = "deploy"

## on_match_won — called by MatchScene when a winner is decided. Advances campaign
## progress on a player-0 mission win (capped, never regressing) and persists it.
func on_match_won(winner: int) -> void:
	if state != null and state.campaign_index >= 0 and winner == 0:
		campaign_progress = mini(Campaign.CAMPAIGN.size() - 1, maxi(campaign_progress, state.campaign_index + 1))
		persist_prefs()
	SaveGame.delete()
	has_save = false

func return_to_title() -> void:
	screen = "title"
	state = null
