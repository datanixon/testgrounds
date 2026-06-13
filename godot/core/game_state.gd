class_name GameState
extends RefCounted
## Single source of truth for a match — the logic-only slice of the JS STATE.
## Holds the generated map + the unit list + turn bookkeeping, owns the unit id
## counter, and exposes the query helpers pathfinding reads. Pure: no nodes,
## instantiable in isolation for headless tests.

const Units = preload("res://core/units.gd")
const MapGen = preload("res://core/map_gen.gd")
const Rng = preload("res://core/rng.gd")
const Weather = preload("res://core/weather.gd")
const Status = preload("res://core/status.gd")
const AILib = preload("res://core/ai.gd")  # M9: new_campaign AI opener; ai.gd does NOT preload game_state.gd — no cycle
const Relics = preload("res://data/relics.gd")
const Vision = preload("res://core/vision.gd")

var map: Dictionary = {}              # the generate() result: cols, rows, cells, castles, towers
var units: Array[Dictionary] = []
var current_player: int = 0
var turn: int = 1
var _next_id: int = 1
var rng: Mulberry32 = Rng.new(0)   # placeholder seed; new_skirmish reseeds. Avoids null on bare GameState.new()
var weather: Dictionary = {}  # {key, turns_left}
var map_def: Dictionary = {}  # the active map def (for its weather_table)
var winner: int = -1          # -1 none; else the winning owner
var difficulty := "normal"    # AI weight profile (easy/normal/hard); difficulty-select UI is M9
var battle_log: Array = []   # M8: per-battle snapshots appended by Combat.resolve_attack, drained by the presentation cutaway
var fog: bool = false              # P3: this match uses fog of war (saved)
var visibility: Dictionary = {}    # P3: cached visible "q,r" set for the viewer (NOT saved)
var revealed: Dictionary = {}      # P3: extra reveals this turn (ambush cutaways); NOT saved
var is_ai: Array[bool] = [false, true]   # M9: per-player AI flag (replaces the current_player==1 hardcode)
var campaign_index: int = -1             # M9: -1 skirmish; else CAMPAIGN index
var match_difficulty: String = "normal"  # M9: difficulty in force THIS match (campaign sets its own w/o touching prefs)
var stats: Dictionary = {"summoned": [0, 0], "lost": [0, 0], "battles": 0}  # M9: gameover summary

func _new_id() -> int:
	var n := _next_id
	_next_id += 1
	return n

## cellAt — the terrain cell at (q,r), or null off-board. Returns the live dict
## (reference), so callers may mutate the stored map.
func cell_at(q: int, r: int) -> Variant:
	return map.get("cells", {}).get("%d,%d" % [q, r])

## inBounds — whether (q,r) is a real cell on this map.
func in_bounds(q: int, r: int) -> bool:
	return map.get("cells", {}).has("%d,%d" % [q, r])

## unitAt — first living unit on (q,r), or null.
func unit_at(q: int, r: int) -> Variant:
	for u in units:
		if u["q"] == q and u["r"] == r and u["hp"] > 0:
			return u
	return null

func alive_units(owner: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in units:
		if u["hp"] > 0 and u["owner"] == owner:
			out.append(u)
	return out

func master_of(owner: int) -> Variant:
	for u in units:
		if u["is_master"] and u["owner"] == owner and u["hp"] > 0:
			return u
	return null

func spawn_unit(type_key: String, owner: int, q: int, r: int) -> Dictionary:
	var u := Units.make_unit(_new_id(), type_key, owner, q, r)
	units.append(u)
	if owner >= 0 and owner < 2:
		stats["summoned"][owner] += 1
	return u

func spawn_master(owner: int, q: int, r: int) -> Dictionary:
	var u := Units.make_master(_new_id(), owner, q, r)
	units.append(u)
	return u

## checkWinCondition — if a player's master is dead, the other player wins.
func check_win_condition() -> void:
	if winner != -1:
		return   # already decided
	for owner in [0, 1]:
		if master_of(owner) == null:
			winner = 1 - owner
			return

## captureTower — flip a tower's ownership to the capturing unit's side.
func capture_tower(unit: Dictionary, cell: Dictionary) -> void:
	cell["owner"] = unit["owner"]

## effective_max_hp — base max HP plus a vital relic. Single source for heal clamps.
func effective_max_hp(unit: Dictionary) -> int:
	return Relics.max_hp(unit)

## recompute_visibility — refresh the cached visible-key set for `owner` (the viewer),
## unioning in any per-turn revealed tiles. Presentation calls this on match start and
## after each move/summon/death/turn. Pure read of unit positions + owned spires.
func recompute_visibility(owner: int) -> void:
	visibility = Vision.compute(self, owner)
	for k in revealed:
		visibility[k] = true

## pick_up_relic — if a relic sits on `unit`'s tile, resolve pickup and return the
## relic id taken (or "" if none / left). Ley Crystal: master-only, applies MP and
## clears the tile. Others: equip; a full slot drops the old relic back onto the tile.
func pick_up_relic(unit: Dictionary) -> String:
	var relics: Array = map.get("relics", [])
	var idx := -1
	for i in relics.size():
		if relics[i]["q"] == unit["q"] and relics[i]["r"] == unit["r"]:
			idx = i
			break
	if idx < 0:
		return ""
	var rid: String = relics[idx]["relic"]
	if not Relics.RELICS.has(rid):
		return ""
	if Relics.RELICS[rid].get("master_only", false):
		if not unit.get("is_master", false):
			return ""   # non-master leaves it
		unit["mp"] = mini(unit["max_mp"], unit["mp"] + int(Relics.bonus(rid, "mp")))
		relics.remove_at(idx)
		return rid
	var old: String = unit.get("relic", "")
	unit["relic"] = rid
	if int(Relics.bonus(rid, "max_hp")) > 0:
		unit["hp"] = mini(effective_max_hp(unit), unit["hp"] + int(Relics.bonus(rid, "max_hp")))
	if old != "":
		relics[idx] = {"q": unit["q"], "r": unit["r"], "relic": old}   # swap: drop old
	else:
		relics.remove_at(idx)
	return rid

## endTurn — advance one player's turn: lock the outgoing side, switch player, bump
## the round counter, regen the incoming master's MP (base + 2/owned-tower), tick
## statuses, unlock + heal + evolve the incoming units, and roll weather per round.
## Logic only — AI handoff, autosave, camera, banners/logs return at the HUD/AI layers.
func end_turn() -> void:
	for u in alive_units(current_player):
		u["acted"] = true
	current_player = 1 - current_player
	if current_player == 0:
		turn += 1
	var m: Variant = master_of(current_player)
	if m != null:
		var tower_bonus: int = _owned_tower_count(current_player) * 2
		m["mp"] = mini(m["max_mp"], m["mp"] + m["mp_regen"] + tower_bonus)
	Status.tick_statuses(self, current_player)
	if winner != -1:
		return   # a burn-kill may have ended the match
	for u in alive_units(current_player):
		u["acted"] = false
		u["second_move"] = false
		if u["cd"] > 0:
			u["cd"] -= 1
		var c: Variant = cell_at(u["q"], u["r"])
		if c != null and c["terrain"] == "tower" and c.get("owner", -1) == u["owner"]:
			u["hp"] = mini(effective_max_hp(u), u["hp"] + 2)
		if c != null and c["terrain"] == "castle" and c.get("owner", -1) == u["owner"]:
			u["hp"] = mini(effective_max_hp(u), u["hp"] + 4)
		var rg: int = int(Relics.unit_bonus(u, "regen"))
		if rg > 0:
			u["hp"] = mini(effective_max_hp(u), u["hp"] + rg)
		Units.try_evolve(u, c)
	if current_player == 0 and not weather.is_empty():
		weather["turns_left"] -= 1
		if weather["turns_left"] <= 0:
			Weather.roll_weather(self, false)
	check_win_condition()

## _owned_tower_count — towers (by board cell ownership) held by `owner`.
func _owned_tower_count(owner: int) -> int:
	var n := 0
	for t in map.get("towers", []):
		var c: Variant = cell_at(t.x, t.y)
		if c != null and c.get("owner", -1) == owner:
			n += 1
	return n

## new_skirmish — port of startNewGame's match setup (sec. 13): generate the map,
## place both archons on their castles, start at turn 1 / player 0. Campaign AI
## summons + weather init land in their owning milestones.
static func new_skirmish(def: Dictionary, seed: int) -> GameState:
	var gs := new()
	gs.map = MapGen.generate(seed, def)
	gs.map_def = def
	gs.rng = Rng.new(seed)
	Weather.roll_weather(gs, true)
	var castles: Array = gs.map["castles"]
	gs.spawn_master(0, castles[0].x, castles[0].y)
	gs.spawn_master(1, castles[1].x, castles[1].y)
	gs.current_player = 0
	gs.turn = 1
	gs.stats = {"summoned": [0, 0], "lost": [0, 0], "battles": 0}
	return gs

## new_campaign — like new_skirmish but for a CAMPAIGN scenario: generates the
## scenario map, sets match_difficulty/difficulty from the scenario (without
## touching the persisted skirmish pref, which lives on Session), applies the
## AI opening modifiers (ai_mp_bonus clamped to [4, max_mp]; ai_summons pre-placed
## near the AI master), and tags campaign_index. Mirrors JS startNewGame(scenario).
## Uses the global `AI` class (ai.gd has class_name AI, does not preload GameState,
## so no preload const here — avoids a circular preload).
static func new_campaign(scenario: Dictionary, index: int) -> GameState:
	var def: Dictionary = scenario["map"]
	var gs := new_skirmish(def, def.get("seed", 0))
	gs.campaign_index = index
	gs.match_difficulty = scenario["difficulty"]
	gs.difficulty = scenario["difficulty"]
	var m1 = gs.master_of(1)
	if m1 != null:
		var bonus: int = scenario.get("ai_mp_bonus", 0)
		m1["mp"] = clampi(m1["mp"] + bonus, mini(4, m1["max_mp"]), m1["max_mp"])
		for k in scenario.get("ai_summons", []):
			var slot = AILib.find_summon_slot(gs, m1)
			if slot == null:
				break
			gs.spawn_unit(k, 1, slot.x, slot.y)
	return gs
