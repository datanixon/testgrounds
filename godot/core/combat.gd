class_name Combat
extends RefCounted
## Combat math — port of game.js computeDamage/forecastBattle (sec. 7). compute_damage
## is PURE and DETERMINISTIC (returns `base`, no jitter), so forecast and AI reuse it.
## The ±1 jitter lives in resolve_attack (next task), drawn from state.rng. Reads terrain
## defense, the element matrix, affinity, mark/bulwark statuses, and weather.

const Elements = preload("res://data/elements.gd")
const Terrain = preload("res://data/terrain.gd")
const Status = preload("res://core/status.gd")
const Weather = preload("res://core/weather.gd")
const Hex = preload("res://core/hex.gd")
const Units = preload("res://core/units.gd")

## computeDamage — the deterministic `base` swing of `attacker` vs `defender`, plus
## the multiplier breakdown the forecast/UI need. No RNG.
static func compute_damage(state, attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var a_cell: Dictionary = state.cell_at(attacker["q"], attacker["r"])
	var d_cell: Dictionary = state.cell_at(defender["q"], defender["r"])
	var d_terrain_def: int = Terrain.TERRAIN[d_cell["terrain"]]["def"]
	var elem_mul: float = Elements.ELEM_MATRIX[attacker["element"]][defender["element"]]
	var aff: Variant = Elements.affinity_for(attacker["element"], a_cell["terrain"])
	var aff_mul: float = Elements.AFFINITY_MULT if aff != null else 1.0
	var mark_mul: float = 1.2 if Status.has_status(defender, "mark") else 1.0
	var bulwark_def: int = 2 if Status.has_status(defender, "bulwark") else 0
	var w: Dictionary = Weather.weather_now(state)
	var w_atk: float = w.get("atk_mul", {}).get(attacker["element"], 1.0)
	var w_ranged: float = w["ranged_mul"] if (w.has("ranged_mul") and attacker["range"] >= 2) else 1.0
	var w_mul: float = w_atk * w_ranged
	var raw: float = attacker["power"] * (float(attacker["hp"]) / float(attacker["max_hp"]) * 0.5 + 0.5)
	var mit: float = defender["def"] + bulwark_def + d_terrain_def * 0.5
	var base: int = maxi(1, roundi(raw * elem_mul * aff_mul * mark_mul * w_mul - mit * 0.6))
	return {"base": base, "elem_mul": elem_mul, "aff_mul": aff_mul, "has_affinity": aff != null, "d_terrain_def": d_terrain_def}

## forecastBattle — two-way pre-jitter forecast for the UI/AI. Mirrors resolve_attack's
## counter rule (defender in range -> 0.8x swing) and reports a stable lo..hi range.
static func forecast_battle(state, attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var a: Dictionary = compute_damage(state, attacker, defender)
	var dist: int = state_distance(attacker, defender)
	var can_counter: bool = dist >= 1 and dist <= defender["range"]
	var c_base: int = 0
	if can_counter:
		c_base = maxi(1, roundi(compute_damage(state, defender, attacker)["base"] * 0.8))
	return {
		"lo": maxi(1, a["base"] - 1), "hi": a["base"] + 1,
		"elem_mul": a["elem_mul"], "has_affinity": a["has_affinity"],
		"can_counter": can_counter,
		"c_lo": maxi(1, c_base - 1) if can_counter else 0,
		"c_hi": c_base + 1 if can_counter else 0,
		"sure_kill": defender["hp"] <= maxi(1, a["base"] - 1),
	}

## Hex distance between two unit records. Kept local so callers don't unpack
## q/r twice inline; Hex.distance is the canonical implementation.
static func state_distance(a: Dictionary, b: Dictionary) -> int:
	return Hex.distance(Vector2i(a["q"], a["r"]), Vector2i(b["q"], b["r"]))

## resolve_attack — INLINE battle (no cutaway). Primary swing, then a counter if the
## defender survives and the attacker is within the defender's range. Jitter and the
## counter 0.8x are drawn from state.rng. Mirrors beginBattle + applySwing, minus the
## animation/float/log side effects (those return with the M8 battle scene + M7 HUD).
static func resolve_attack(state, attacker: Dictionary, defender: Dictionary) -> void:
	var a1: Dictionary = compute_damage(state, attacker, defender)
	_apply_hit(state, attacker, defender, _jitter(state, a1["base"]))
	if defender["hp"] > 0:
		var d: int = state_distance(attacker, defender)
		if d >= 1 and d <= defender["range"]:
			var a2: Dictionary = compute_damage(state, defender, attacker)
			var counter_dmg: int = maxi(1, roundi(_jitter(state, a2["base"]) * 0.8))
			_apply_hit(state, defender, attacker, counter_dmg)
	state.check_win_condition()

## _jitter — apply the JS ±1 spread (base-1 / base / base+1), floored at 1, via state.rng.
static func _jitter(state, base: int) -> int:
	return maxi(1, base + state.rng.below(3) - 1)

## _apply_hit — one swing: ward absorbs (consumed, no damage/xp); else deal `dmg`,
## award `dmg` (+kill bonus) XP to `src`, leave death detection to hp <= 0.
## `_state` is unused now; reserved for M8 float/log emission without a signature change.
static func _apply_hit(_state, src: Dictionary, dst: Dictionary, dmg: int) -> void:
	if Status.has_status(dst, "ward"):
		dst["status"].erase("ward")
		return
	dst["hp"] -= dmg
	var killed: bool = dst["hp"] <= 0
	var xp_amt: int = dmg + (Units.KILL_XP_BONUS if killed else 0)
	Units.gain_xp(src, xp_amt)
