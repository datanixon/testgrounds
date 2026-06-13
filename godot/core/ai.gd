class_name AI
extends RefCounted
## Enemy AI — threat map + scored decision tree + summon economy (port of game.js
## sec. 8). The designated C#-swap seam: every function reads a GameState plus the
## pure query/combat modules and returns intended actions; take_turn() is the thin
## runner that applies them. Scoring is side-effect-free (candidate tiles are scored
## via a duplicated probe unit, never by mutating the real unit).

const AiProfiles = preload("res://data/ai_profiles.gd")
const Hex = preload("res://core/hex.gd")
const Terrain = preload("res://data/terrain.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const Abilities = preload("res://data/abilities.gd")
const AbilityResolve = preload("res://core/ability_resolve.gd")
const Status = preload("res://core/status.gd")
const Combat = preload("res://core/combat.gd")
const Elements = preload("res://data/elements.gd")
const UnitTypes = preload("res://data/unit_types.gd")
const Vision = preload("res://core/vision.gd")

## weights — the active difficulty's weight profile (defaults to normal).
static func weights(state) -> Dictionary:
	return AiProfiles.AI_PROFILES.get(state.difficulty, AiProfiles.AI_PROFILES["normal"])

## build_threat_map — total potential enemy damage onto every tile: each enemy of the
## OTHER player expands its reachable tiles by its attack range; one enemy contributes
## its power at most once per tile, separate enemies stack. Returns { "q,r": int }.
static func build_threat_map(state, owner: int) -> Dictionary:
	var threat := {}
	var vis: Dictionary = Vision.compute(state, owner) if state.fog else {}
	for e in state.alive_units(1 - owner):
		if state.fog and not vis.has(Hex.key(Vector2i(e["q"], e["r"]))):
			continue
		var seen := {}
		var reach := Pathfinding.compute_reachable(state, e)
		for k in reach:
			var node: Dictionary = reach[k]
			for n1 in Hex.neighbors(Vector2i(node["q"], node["r"])):
				_threat_mark(threat, seen, n1, e["power"])
				if e["range"] >= 2:
					for n2 in Hex.neighbors(n1):
						_threat_mark(threat, seen, n2, e["power"])
	return threat

static func _threat_mark(threat: Dictionary, seen: Dictionary, p: Vector2i, power: int) -> void:
	var k := Hex.key(p)
	if seen.has(k):
		return
	seen[k] = true
	threat[k] = threat.get(k, 0) + power

static func threat_at(threat: Dictionary, q: int, r: int) -> int:
	return threat.get(Hex.key(Vector2i(q, r)), 0)

## find_summon_slot — first free, non-blocking, non-mountain neighbor of the master.
static func find_summon_slot(state, master: Dictionary) -> Variant:
	for n in Hex.neighbors(Vector2i(master["q"], master["r"])):
		if not state.in_bounds(n.x, n.y):
			continue
		var cell: Variant = state.cell_at(n.x, n.y)
		if cell == null:
			continue
		if Terrain.TERRAIN[cell["terrain"]].get("blocks", false):
			continue
		if cell["terrain"] == "mountain":
			continue
		if state.unit_at(n.x, n.y) != null:
			continue
		return n
	return null

## _retreat_node — best reachable tile for a wounded unit: near an owned heal tile
## (tower/castle), low threat, decent cover. Returns the reach node dict, or null.
static func _retreat_node(state, unit: Dictionary, reach: Dictionary, threat: Dictionary) -> Variant:
	var heals: Array[Vector2i] = []
	for k in state.map["cells"]:
		var c: Dictionary = state.map["cells"][k]
		if (c["terrain"] == "tower" or c["terrain"] == "castle") and c.get("owner", -1) == unit["owner"]:
			heals.append(Vector2i(c["q"], c["r"]))
	var best: Variant = null
	var best_score := INF
	for k in reach:
		var node: Dictionary = reach[k]
		var np := Vector2i(node["q"], node["r"])
		var d_heal := 0
		if not heals.is_empty():
			d_heal = 9999
			for h in heals:
				d_heal = mini(d_heal, Hex.distance(np, h))
		var tdef: int = Terrain.TERRAIN[state.cell_at(np.x, np.y)["terrain"]]["def"]
		var s: float = d_heal * 2 + threat_at(threat, np.x, np.y) * 1.5 - tdef * 1.5
		if s < best_score:
			best_score = s
			best = node
	return best

## score_instant_ability — score firing the unit's instant (target:"none") ability from
## where it stands. Returns {score} or null. Tuned vs attack scores (kill ~30+, decent
## attack ~8-15). heal/quake/bulwark/ward only; skitter/galeRush are movement value
## (out of scope for AI v1, as in the JS).
static func score_instant_ability(state, unit: Dictionary) -> Variant:
	var ab: Variant = Abilities.ability_for(unit)
	if ab == null or unit["cd"] > 0 or ab["target"] != "none":
		return null
	var s := 0.0
	match ab["key"]:
		"healPulse":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"] and a["hp"] < a["max_hp"] * 0.6:
					s += 12
		"quake":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var e: Variant = state.unit_at(n.x, n.y)
				if e != null and e["owner"] != unit["owner"]:
					s += 20 if e["hp"] <= 4 else 9
			if s < 18:
				s = 0.0
		"bulwark", "ward":
			if Status.has_status(unit, ab["key"]):
				return null
			var allies := 0
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"]:
					allies += 1
			s = allies * 5 + 4
			if s < 12:
				s = 0.0
	return {"score": s} if s > 0 else null

## score_attacks — best (end tile, target) attack for `unit` over its reachable tiles,
## scored with forecast_battle. PURE: a candidate end tile is evaluated on a duplicated
## probe unit moved to that tile (so attacker terrain/affinity are correct) — the real
## unit is never moved. Returns {score, dest:Vector2i, target_id:int, kills:bool, ab:Variant}
## or null. `ab` is the enemy-target ability to use (null on a plain attack / a kill, which
## takes the plain swing to keep the cooldown ready). Mirrors game.js 1224–1258.
static func score_attacks(state, unit: Dictionary, reach: Dictionary, threat: Dictionary, W: Dictionary) -> Variant:
	var atk_ab: Variant = null
	var ability: Variant = Abilities.ability_for(unit)
	if ability != null and ability["target"] == "enemy" and unit["cd"] <= 0:
		atk_ab = ability
	var low_hp: bool = unit["hp"] < unit["max_hp"] * W["retreat_hp_frac"]
	var best: Variant = null
	for k in reach:
		var node: Dictionary = reach[k]
		var targets := Pathfinding.compute_attack_targets(state, unit, node["q"], node["r"])
		if targets.is_empty():
			continue
		var probe := unit.duplicate()
		probe["q"] = node["q"]
		probe["r"] = node["r"]
		var tdef: int = Terrain.TERRAIN[state.cell_at(node["q"], node["r"])["terrain"]]["def"]
		for tk in targets:
			var enemy: Variant = _unit_at_key(state, tk)
			if enemy == null:
				continue
			var f: Dictionary = Combat.forecast_battle(state, probe, enemy)
			var kills: bool = enemy["hp"] <= f["lo"]   # worst roll still lethal -> no counter
			var score: float = (f["lo"] + f["hi"]) / 2.0
			if kills:
				score += W["kill_bonus"]
			if enemy["is_master"]:
				score += W["master_bonus"]
			score += W["focus_fire"] * (1.0 - float(enemy["hp"]) / float(enemy["max_hp"]))
			if not kills and f["can_counter"]:
				score -= f["c_hi"] * W["counter_risk"]
				if unit["hp"] <= f["c_hi"]:
					score -= W["counter_death"]
			score += tdef * W["terrain_def"] * 0.5
			score -= threat_at(threat, node["q"], node["r"]) * (W["threat_hurt"] if low_hp else W["threat_safe"]) * 0.5
			if W["score_jitter"] != 0:
				score += (state.rng.next() * 2.0 - 1.0) * W["score_jitter"]
			if atk_ab != null:
				score += 6
			if best == null or score > best["score"]:
				best = {"score": score, "dest": Vector2i(node["q"], node["r"]), "target_id": enemy["id"], "kills": kills, "ab": atk_ab}
	# On a predicted kill, take the plain swing (no status on a corpse) — drop the ability.
	if best != null and best["kills"]:
		best["ab"] = null
	return best

static func _unit_at_key(state, key: String):
	for u in state.units:
		if u["hp"] > 0 and Hex.key(Vector2i(u["q"], u["r"])) == key:
			return u
	return null

## decide_unit_action — the scored decision tree for one unit. Returns an action dict
## (see the plan header for shapes). Pure: reads state + helpers, mutates nothing.
## Order: confirmed kill -> wounded retreat -> instant ability -> capture -> plain
## attack -> move-only. Mirrors game.js aiActUnit 1217–1349.
static func decide_unit_action(state, unit: Dictionary, threat: Dictionary, enemy_master: Dictionary) -> Dictionary:
	var W: Dictionary = weights(state)
	var reach := Pathfinding.compute_reachable(state, unit)
	var low_hp: bool = unit["hp"] < unit["max_hp"] * W["retreat_hp_frac"]
	var best_atk: Variant = score_attacks(state, unit, reach, threat, W)

	# 1. Confirmed kills are always worth taking (no counter comes back). The master
	#    still refuses if the end tile is hot enough to kill it next turn.
	if best_atk != null and best_atk["kills"] and not (unit["is_master"] and threat_at(threat, best_atk["dest"].x, best_atk["dest"].y) >= unit["hp"]):
		return {"kind": "attack", "dest": best_atk["dest"], "target_id": best_atk["target_id"], "ab": best_atk["ab"]}

	# 2. Wounded units fall back toward owned heal tiles.
	if low_hp:
		var node: Variant = _retreat_node(state, unit, reach, threat)
		if node != null:
			return {"kind": "move", "dest": Vector2i(node["q"], node["r"])}

	# 3. Instant ability when its heuristic beats the best attack on offer.
	var best_inst: Variant = score_instant_ability(state, unit)
	if best_inst != null and (best_atk == null or best_inst["score"] > best_atk["score"]):
		return {"kind": "instant", "ab": Abilities.ability_for(unit)}

	# 4. Capture: any unit can flip a spire; scored against the best attack.
	var best_cap: Variant = null
	for t in state.map["towers"]:
		var cell: Variant = state.cell_at(t.x, t.y)
		if cell == null or cell.get("owner", -1) == unit["owner"]:
			continue
		var node: Variant = reach.get(Hex.key(t))
		if node == null:
			continue
		var heat := threat_at(threat, t.x, t.y)
		if heat >= unit["hp"]:
			continue   # don't capture into certain death
		var cap_score: float = W["capture_bonus"] - heat * 0.5 - node["cost"]
		if best_cap == null or cap_score > best_cap["score"]:
			best_cap = {"score": cap_score, "dest": t}
	if best_cap != null and (best_atk == null or best_cap["score"] > best_atk["score"]):
		return {"kind": "capture", "dest": best_cap["dest"]}

	# 5. Plain attack: clear the floor; the master is choosier (never trades into a
	#    tile where the standing threat outweighs it).
	if best_atk != null and best_atk["score"] > W["atk_floor"] \
			and not (unit["is_master"] and (best_atk["score"] < 8 or threat_at(threat, best_atk["dest"].x, best_atk["dest"].y) > unit["hp"] * 0.6)):
		return {"kind": "attack", "dest": best_atk["dest"], "target_id": best_atk["target_id"], "ab": best_atk["ab"]}

	# 6. Move-only. Non-masters advance on the enemy master (shaped by cover/threat);
	#    the master drifts toward the nearest unowned spire, else holds safe ground.
	var best_step: Variant = null
	var best_score := -INF
	var unowned: Array[Vector2i] = []
	for t in state.map["towers"]:
		var c: Variant = state.cell_at(t.x, t.y)
		if c == null or c.get("owner", -1) != unit["owner"]:
			unowned.append(t)
	for k in reach:
		var node: Dictionary = reach[k]
		var np := Vector2i(node["q"], node["r"])
		var tdef: int = Terrain.TERRAIN[state.cell_at(np.x, np.y)["terrain"]]["def"]
		var s: float = tdef * W["terrain_def"] - threat_at(threat, np.x, np.y) * (W["threat_hurt"] if unit["is_master"] else W["threat_safe"])
		if unit["is_master"]:
			if not unowned.is_empty():
				var d_tower := 9999
				for t in unowned:
					d_tower = mini(d_tower, Hex.distance(np, t))
				s -= d_tower * 0.8
		else:
			s -= Hex.distance(np, Vector2i(enemy_master["q"], enemy_master["r"])) * W["approach"]
		s += relic_tile_bonus(state, np.x, np.y)
		if s > best_score:
			best_score = s
			best_step = np
	if best_step != null:
		return {"kind": "move", "dest": best_step}
	return {"kind": "wait"}

## run_summons — the AI summon economy (MUTATES state: spawns units, spends master MP).
## Scores types by element matchup vs the enemy army, terrain resonance, stat-value-per-MP,
## and a variety nudge; banks MP when clearly ahead, floods cheap bodies when the master is
## threatened. `normal`/`hard` are deterministic; `easy` picks randomly via state.rng.
static func run_summons(state, master: Dictionary) -> void:
	var owner: int = master["owner"]
	var W := weights(state)
	var enemies: Array = []
	var vis_s: Dictionary = Vision.compute(state, owner) if state.fog else {}
	for e in state.alive_units(1 - owner):
		if state.fog and not vis_s.has(Hex.key(Vector2i(e["q"], e["r"]))):
			continue
		enemies.append(e)
	var my_army: Array[Dictionary] = []
	for u in state.alive_units(owner):
		if not u["is_master"]:
			my_army.append(u)

	# Fraction of the map that empowers each element (+20% terrain).
	var terr_frac := {}
	for el in Elements.ELEMENT:
		var n := 0
		var tot := 0
		for k in state.map["cells"]:
			tot += 1
			if Elements.affinity_for(el, state.map["cells"][k]["terrain"]) != null:
				n += 1
		terr_frac[el] = float(n) / float(tot) if tot > 0 else 0.0

	var ahead: bool = _army_value(my_army) > _army_value(_non_masters(enemies)) * 1.25
	var emergency := false
	for e in enemies:
		if Hex.distance(Vector2i(e["q"], e["r"]), Vector2i(master["q"], master["r"])) <= e["move"] + e["range"]:
			emergency = true
			break

	var attempts := 4
	while attempts > 0 and master["mp"] >= 6:
		attempts -= 1
		var pool: Array = []
		for k in UnitTypes.SUMMON_LIST:
			if UnitTypes.UNIT_TYPES[k]["cost"] <= master["mp"]:
				pool.append(k)
		if pool.is_empty():
			break
		if W["random_summons"]:
			pool = [pool[state.rng.below(pool.size())]]
		elif emergency:
			pool.sort_custom(func(a, b): return UnitTypes.UNIT_TYPES[a]["cost"] < UnitTypes.UNIT_TYPES[b]["cost"])
			pool = pool.slice(0, maxi(1, int(ceil(pool.size() / 2.0))))
		elif ahead:
			var bigs: Array = []
			for k in pool:
				if UnitTypes.UNIT_TYPES[k]["cost"] >= 12:
					bigs.append(k)
			var regen: int = master["mp_regen"] + _owned_tower_count(state, owner) * 2
			if bigs.is_empty() and master["mp"] + regen <= master["max_mp"]:
				break
			if not bigs.is_empty():
				pool = bigs
		pool.sort_custom(func(a, b): return _score_type(b, enemies, terr_frac, my_army) > _score_type(a, enemies, terr_frac, my_army))
		var choice: String = pool[0]
		var slot: Variant = find_summon_slot(state, master)
		if slot == null:
			break
		master["mp"] -= UnitTypes.UNIT_TYPES[choice]["cost"]
		var u: Dictionary = state.spawn_unit(choice, owner, slot.x, slot.y)
		u["acted"] = true
		my_army.append(u)   # keep the variety penalty honest across the loop

static func _army_value(list: Array) -> float:
	var v := 0.0
	for u in list:
		v += u["power"] + u["max_hp"] * 0.25
	return v

static func _non_masters(list: Array) -> Array:
	var out: Array = []
	for u in list:
		if not u["is_master"]:
			out.append(u)
	return out

static func _owned_tower_count(state, owner: int) -> int:
	var n := 0
	for t in state.map.get("towers", []):
		var c: Variant = state.cell_at(t.x, t.y)
		if c != null and c.get("owner", -1) == owner:
			n += 1
	return n

## _score_type — summon desirability: element edge vs the enemy army (offense minus how
## hard they counter-hit), terrain resonance, stat value per MP, minus a variety penalty.
static func _score_type(k: String, enemies: Array, terr_frac: Dictionary, my_army: Array) -> float:
	var t: Dictionary = UnitTypes.UNIT_TYPES[k]
	var s := 0.0
	if not enemies.is_empty():
		var off := 0.0
		var deff := 0.0
		for e in enemies:
			off += Elements.ELEM_MATRIX[t["element"]][e["element"]] - 1.0
			deff += Elements.ELEM_MATRIX[e["element"]][t["element"]] - 1.0
		s += off / enemies.size() * 20.0
		s -= deff / enemies.size() * 10.0
	s += terr_frac.get(t["element"], 0.0) * 12.0
	s += (t["max_hp"] * 0.25 + t["power"]) / float(t["cost"]) * 6.0
	var same := 0
	for m in my_army:
		if m["type_key"] == k:
			same += 1
	s -= same * 4.0
	return s

## relic_tile_bonus — a small move-scoring nudge for ending on a relic tile.
static func relic_tile_bonus(state, q: int, r: int) -> float:
	for rl in state.map.get("relics", []):
		if rl["q"] == q and rl["r"] == r:
			return 3.0
	return 0.0

## take_turn — run the current player's entire AI turn synchronously (combat is inline
## in M6; the battle-scene awaiting returns at M8 as a coroutine). For each non-acted unit
## (masters last), decide and apply an action; then run the summon economy. Does NOT call
## end_turn — the caller does. MUTATES state.
static func take_turn(state) -> void:
	var owner: int = state.current_player
	var enemy_master: Variant = state.master_of(1 - owner)
	if enemy_master == null:
		return
	var queue: Array[Dictionary] = []
	for u in state.alive_units(owner):
		if not u["acted"]:
			queue.append(u)
	queue.sort_custom(func(a, b): return (0 if a["is_master"] else -1) < (0 if b["is_master"] else -1))  # masters last
	var threat := build_threat_map(state, owner)
	for u in queue:
		if u["hp"] <= 0:
			continue
		_apply_action(state, u, decide_unit_action(state, u, threat, enemy_master))
		u["acted"] = true
		if state.winner != -1:
			return
	var master: Variant = state.master_of(owner)
	if master != null and master["mp"] >= 6:
		run_summons(state, master)

## _apply_action — execute one decided action (MUTATES state). Move/attack/capture/instant.
static func _apply_action(state, unit: Dictionary, action: Dictionary) -> void:
	match action["kind"]:
		"attack":
			unit["q"] = action["dest"].x
			unit["r"] = action["dest"].y
			state.pick_up_relic(unit)
			var target: Variant = _unit_by_id(state, action["target_id"])
			if target == null:
				return
			if action["ab"] != null:
				unit["cd"] = action["ab"]["cd"]
				Combat.resolve_attack(state, unit, target, action["ab"]["status"], action["ab"]["status_turns"])
			else:
				Combat.resolve_attack(state, unit, target)
		"instant":
			AbilityResolve.resolve_instant(state, unit, action["ab"])
			unit["cd"] = action["ab"]["cd"]
		"capture":
			unit["q"] = action["dest"].x
			unit["r"] = action["dest"].y
			state.pick_up_relic(unit)
			var cell: Variant = state.cell_at(action["dest"].x, action["dest"].y)
			if cell != null and cell["terrain"] == "tower" and cell.get("owner", -1) != unit["owner"]:
				state.capture_tower(unit, cell)
		"move":
			unit["q"] = action["dest"].x
			unit["r"] = action["dest"].y
			state.pick_up_relic(unit)
		"wait":
			pass

static func _unit_by_id(state, id: int):
	for u in state.units:
		if u["id"] == id and u["hp"] > 0:
			return u
	return null
