class_name AI
extends RefCounted
## Enemy AI — threat map + scored decision tree + summon economy (port of game.js
## sec. 8). The designated C#-swap seam: every function reads a GameState plus the
## pure query/combat modules and returns intended actions; take_turn() is the thin
## runner that applies them. Scoring is side-effect-free (candidate tiles are scored
## via a duplicated probe unit, never by mutating the real unit).

const AiProfiles = preload("res://data/ai_profiles.gd")

## weights — the active difficulty's weight profile (defaults to normal).
static func weights(state) -> Dictionary:
	return AiProfiles.AI_PROFILES.get(state.difficulty, AiProfiles.AI_PROFILES["normal"])
