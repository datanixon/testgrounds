class_name AiProfiles
extends RefCounted
## Port of game.js AI_PROFILES (sec. 8). Difficulty swaps the weight profile without
## touching the AI logic. easy = threat-blind, no retreat, jittered, random summons (v1
## feel); normal = the tuned brain; hard = accepts trades, hunts kills/archon, retreats
## earlier. JS camelCase keys -> snake_case.

const AI_PROFILES := {
	"easy": {
		"kill_bonus": 18, "master_bonus": 10, "focus_fire": 3,
		"counter_risk": 0.3, "counter_death": 5, "terrain_def": 0.5,
		"threat_safe": 0.0, "threat_hurt": 0.0, "approach": 1.0,
		"capture_bonus": 18, "retreat_hp_frac": 0.0, "atk_floor": 0,
		"score_jitter": 6, "random_summons": true,
	},
	"normal": {
		"kill_bonus": 30, "master_bonus": 18, "focus_fire": 10,
		"counter_risk": 0.8, "counter_death": 25, "terrain_def": 2.0,
		"threat_safe": 0.35, "threat_hurt": 1.1, "approach": 1.2,
		"capture_bonus": 26, "retreat_hp_frac": 0.35, "atk_floor": 0,
		"score_jitter": 0, "random_summons": false,
	},
	"hard": {
		"kill_bonus": 40, "master_bonus": 26, "focus_fire": 16,
		"counter_risk": 0.45, "counter_death": 12, "terrain_def": 2.0,
		"threat_safe": 0.3, "threat_hurt": 0.9, "approach": 1.7,
		"capture_bonus": 26, "retreat_hp_frac": 0.28, "atk_floor": -3,
		"score_jitter": 0, "random_summons": false,
	},
}

const DIFFICULTIES := ["easy", "normal", "hard"]
