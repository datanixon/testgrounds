extends SceneTree
## Headless test harness. Run via tests/run_tests.ps1, which wraps:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Exits 0 if all asserts pass, 1 otherwise. Pure-logic tests only (no display).
const HexLib = preload("res://core/hex.gd")
const Rng = preload("res://core/rng.gd")
const Terrain = preload("res://data/terrain.gd")
const Maps = preload("res://data/maps.gd")
const Campaign = preload("res://data/campaign.gd")
const MapGen = preload("res://core/map_gen.gd")
const BoardLib = preload("res://scenes/board/board.gd")
const UnitTypes = preload("res://data/unit_types.gd")
const Units = preload("res://core/units.gd")
const GameState = preload("res://core/game_state.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const Elements = preload("res://data/elements.gd")
const Statuses = preload("res://data/statuses.gd")
const Status = preload("res://core/status.gd")
const WeatherData = preload("res://data/weather.gd")
const Weather = preload("res://core/weather.gd")
const Combat = preload("res://core/combat.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_harness_smoke()
	_test_hex()
	_test_rng()
	_test_data()
	_test_map_gen()
	_test_board()
	_test_unit_types()
	_test_units_state()
	_test_pathfinding()
	_test_elements()
	_test_status()
	_test_weather()
	_test_leveling()
	_test_combat()
	print("\n== %d passed, %d failed ==" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# ---- assert helpers ----
func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + msg)

func _eq(got: Variant, want: Variant, msg: String) -> void:
	_ok(got == want, "%s  (got %s, want %s)" % [msg, str(got), str(want)])

# ---- tests ----
func _test_harness_smoke() -> void:
	_eq(1 + 1, 2, "harness smoke")

func _test_hex() -> void:
	# distance
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "distance: self")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(1, 0)), 1, "distance: +q neighbor")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(0, 1)), 1, "distance: +r neighbor")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(1, -1)), 1, "distance: diagonal neighbor")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(3, 0)), 3, "distance: straight 3")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(-2, -1)), 3, "distance: -2,-1")
	_eq(HexLib.distance(Vector2i(2, -1), Vector2i(-1, 1)), 3, "distance: arbitrary")
	# neighbors (DIRS order, matching the JS HEX_DIRS)
	_eq(HexLib.neighbors(Vector2i(0, 0)), HexLib.DIRS, "neighbors: origin == DIRS")
	_eq(HexLib.neighbors(Vector2i(2, 3)), [
		Vector2i(3, 3), Vector2i(3, 2), Vector2i(2, 2),
		Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 4),
	], "neighbors: offset")
	# key
	_eq(HexLib.key(Vector2i(3, -2)), "3,-2", "key: format")
	# pixel round-trip: a hex center maps back to its own axial
	for a in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-4, 5), Vector2i(7, 0), Vector2i(0, 6)]:
		_eq(HexLib.pixel_to_axial(HexLib.axial_to_pixel(a)), a, "round-trip %s" % str(a))

func _test_rng() -> void:
	# Bit-exact uint32 sequence for seed 12345, captured from the JS reference.
	var r := Rng.new(12345)
	var want := [4207900869, 1317490944, 2079646450, 3513001552, 2187978186]
	for i in range(want.size()):
		_eq(r.next_u32(), want[i], "rng: u32[%d] seed 12345" % i)
	# next() is the uint32 divided by 2^32 (same arithmetic as JS).
	_eq(Rng.new(12345).next(), 4207900869.0 / 4294967296.0, "rng: next() float")
	# below(n) = floor(next()*n); seed 0 first next()=0.2664... -> below(10)=2
	_eq(Rng.new(0).below(10), 2, "rng: below(10) seed 0")

func _test_data() -> void:
	# Terrain
	_eq(Terrain.TERRAIN.size(), 7, "terrain: 7 types")
	_eq(Terrain.TERRAIN["plain"]["move_cost"], 1, "terrain: plain move_cost")
	_eq(Terrain.TERRAIN["mountain"]["flyers_only"], true, "terrain: mountain flyers_only")
	_eq(Terrain.TERRAIN["water"]["blocks"], true, "terrain: water blocks")
	_eq(Terrain.TERRAIN["water"]["move_cost"], 99, "terrain: water move_cost")
	_eq(Terrain.TERRAIN["tower"]["capturable"], true, "terrain: tower capturable")
	_eq(Terrain.TERRAIN["castle"]["def"], 4, "terrain: castle def")
	# Maps
	_eq(Maps.MAPS.size(), 4, "maps: 4 skirmish")
	_eq(Maps.MAPS[0]["key"], "frontier", "maps: [0] key")
	_eq(Maps.MAPS[0]["cols"], 14, "maps: [0] cols")
	_eq(Maps.MAPS[2]["key"], "crags", "maps: [2] key")
	_eq(Maps.MAPS[2]["castles"], [Vector2i(0, 5), Vector2i(9, 5)], "maps: crags castles")
	_eq(Maps.MAPS[2]["weather_table"], ["heat", "heat", "clear", "gale"], "maps: crags weather")
	# Campaign
	_eq(Campaign.CAMPAIGN.size(), 4, "campaign: 4 missions")
	_eq(Campaign.CAMPAIGN[0]["map"]["seed"], 7041, "campaign: c1 seed")
	_eq(Campaign.CAMPAIGN[0]["map"]["cols"], 11, "campaign: c1 cols")
	_eq(Campaign.CAMPAIGN[3]["difficulty"], "hard", "campaign: c4 difficulty")
	_eq(Campaign.CAMPAIGN[3]["map"]["seed"], 86011, "campaign: c4 seed")

func _map_sig(m: Dictionary) -> String:
	var cells: Dictionary = m["cells"]
	var keys: Array = cells.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		var c: Dictionary = cells[k]
		parts.append("%s:%s:%d" % [k, c["terrain"], c["owner"]])
	return "|".join(parts)

func _terrain_counts(m: Dictionary) -> Dictionary:
	var counts := {}
	for k in m["cells"]:
		var t: String = m["cells"][k]["terrain"]
		counts[t] = counts.get(t, 0) + 1
	return counts

func _test_map_gen() -> void:
	var c1: Dictionary = Campaign.CAMPAIGN[0]["map"]
	# Determinism: same seed+def -> identical map.
	_eq(_map_sig(MapGen.generate(7041, c1)), _map_sig(MapGen.generate(7041, c1)), "mapgen: deterministic")
	# Cross-engine parity vs the JS reference for seed 7041 / c1.
	var m: Dictionary = MapGen.generate(7041, c1)
	_eq(m["cells"].size(), 99, "mapgen: c1 cell count")
	_eq(_terrain_counts(m), {"plain": 65, "forest": 12, "hill": 8, "water": 5, "mountain": 4, "castle": 2, "tower": 3}, "mapgen: c1 terrain counts")
	_eq(m["castles"], [Vector2i(0, 1), Vector2i(5, 7)], "mapgen: c1 castles")
	_eq(m["cells"]["0,1"]["owner"], 0, "mapgen: c1 castle A owner")
	_eq(m["cells"]["5,7"]["owner"], 1, "mapgen: c1 castle B owner")
	var towers: Array = (m["towers"] as Array).duplicate()
	towers.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	_eq(towers, [Vector2i(-3, 6), Vector2i(-1, 5), Vector2i(10, 1)], "mapgen: c1 towers")
	# Invariants on a skirmish def: 2 owned castles, tower spacing rules.
	var m2: Dictionary = MapGen.generate(123, Maps.MAPS[0])
	_eq(m2["castles"].size(), 2, "mapgen: 2 castles")
	for t in m2["towers"]:
		_ok(HexLib.distance(t, m2["castles"][0]) >= 3 and HexLib.distance(t, m2["castles"][1]) >= 3, "mapgen: tower >=3 from castles")
	for i in range(m2["towers"].size()):
		for j in range(i + 1, m2["towers"].size()):
			_ok(HexLib.distance(m2["towers"][i], m2["towers"][j]) >= 2, "mapgen: towers >=2 apart")

func _test_board() -> void:
	_eq(BoardLib.terrain_color("plain"), Color("#3a5a3e"), "board: plain color")
	_eq(BoardLib.terrain_color("water"), Color("#264a78"), "board: water color")
	_eq(BoardLib.terrain_color("castle"), Color("#9a8a52"), "board: castle color")
	_eq(BoardLib.hex_corners(Vector2.ZERO).size(), 6, "board: 6 corners")

func _test_unit_types() -> void:
	# 8 original base + 8 evolved + 4 new base = 20.
	_eq(UnitTypes.UNIT_TYPES.size(), 20, "unit_types: 20 entries")
	_eq(UnitTypes.SUMMON_LIST.size(), 12, "unit_types: 12 summonable")
	_eq(UnitTypes.SUMMON_LIST[0], "cinderling", "unit_types: summon[0]")
	# Representative balance-locked values.
	_eq(UnitTypes.UNIT_TYPES["cinderling"]["max_hp"], 12, "unit_types: cinderling max_hp")
	_eq(UnitTypes.UNIT_TYPES["cinderling"]["move"], 4, "unit_types: cinderling move")
	_eq(UnitTypes.UNIT_TYPES["cinderling"]["evolves_to"], "infernite", "unit_types: cinderling evolves_to")
	_eq(UnitTypes.UNIT_TYPES["geomaul"]["power"], 9, "unit_types: geomaul power")
	_eq(UnitTypes.UNIT_TYPES["skyharrow"]["flying"], true, "unit_types: skyharrow flying")
	_eq(UnitTypes.UNIT_TYPES["infernite"]["evolved"], true, "unit_types: infernite evolved")
	_eq(UnitTypes.UNIT_TYPES["hexwisp"]["element"], "arcane", "unit_types: hexwisp element")
	_eq(UnitTypes.UNIT_TYPES["duneskink"]["ability"], "skitter", "unit_types: duneskink ability")
	# Master template.
	_eq(UnitTypes.MASTER_TEMPLATE["max_hp"], 40, "unit_types: master max_hp")
	_eq(UnitTypes.MASTER_TEMPLATE["max_mp"], 30, "unit_types: master max_mp")
	_eq(UnitTypes.MASTER_TEMPLATE["mp_regen"], 4, "unit_types: master mp_regen")
	_eq(UnitTypes.MASTER_TEMPLATE["move"], 3, "unit_types: master move")

func _test_units_state() -> void:
	# --- factories ---
	var m := Units.make_master(1, 0, 3, 4)
	_eq(m["id"], 1, "units: master id")
	_eq(m["type_key"], "master", "units: master type_key")
	_eq(m["hp"], 40, "units: master hp")
	_eq(m["max_mp"], 30, "units: master max_mp")
	_eq(m["mp"], 14, "units: master starting mp")
	_eq(m["move"], 3, "units: master move")
	_eq(m["is_master"], true, "units: master is_master")
	_eq(m["q"], 3, "units: master q")
	var u := Units.make_unit(2, "cinderling", 1, 5, 6)
	_eq(u["type_key"], "cinderling", "units: unit type_key")
	_eq(u["max_hp"], 12, "units: unit max_hp")
	_eq(u["hp"], 12, "units: unit hp == max_hp")
	_eq(u["move"], 4, "units: unit move")
	_eq(u["owner"], 1, "units: unit owner")
	_eq(u["is_master"], false, "units: unit is_master")
	_eq(u["level"], 1, "units: unit level")
	_eq(u["acted"], false, "units: unit acted")
	# --- GameState queries ---
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(gs.units.size(), 2, "state: two archons placed")
	_eq(gs.current_player, 0, "state: starts player 0")
	var m0: Variant = gs.master_of(0)
	var m1: Variant = gs.master_of(1)
	_ok(m0 != null and m1 != null, "state: both masters found")
	_eq(m0["owner"], 0, "state: master_of(0) owner")
	_eq(m1["owner"], 1, "state: master_of(1) owner")
	_ok(m0["id"] != m1["id"], "state: distinct ids")
	# masters sit on the two castles
	var castles: Array = gs.map["castles"]
	_eq(Vector2i(m0["q"], m0["r"]), castles[0], "state: master 0 on castle 0")
	_eq(Vector2i(m1["q"], m1["r"]), castles[1], "state: master 1 on castle 1")
	# unit_at / alive_units / bounds / cell_at
	_eq(gs.unit_at(m0["q"], m0["r"])["id"], m0["id"], "state: unit_at finds master")
	_eq(gs.unit_at(9999, 9999), null, "state: unit_at empty -> null")
	_eq(gs.alive_units(0).size(), 1, "state: alive_units(0)")
	_ok(gs.in_bounds(castles[0].x, castles[0].y), "state: castle in bounds")
	_ok(not gs.in_bounds(9999, 9999), "state: off-board not in bounds")
	_eq(gs.cell_at(castles[0].x, castles[0].y)["terrain"], "castle", "state: cell_at castle terrain")
	_eq(gs.cell_at(9999, 9999), null, "state: cell_at off-board -> null")

# A rectangular all-`terrain` board (axial q,r in [0,cols)x[0,rows)). in_bounds is
# a plain dict lookup, so the un-offset rectangle is fine for movement asserts.
func _flat_state(cols: int, rows: int, terrain := "plain") -> GameState:
	var gs := GameState.new()
	var cells := {}
	for r in range(rows):
		for q in range(cols):
			cells["%d,%d" % [q, r]] = {"q": q, "r": r, "terrain": terrain, "owner": -1}
	gs.map = {"cols": cols, "rows": rows, "cells": cells, "castles": [], "towers": []}
	return gs

func _test_pathfinding() -> void:
	# --- move_cost_for: terrain + flying matrix ---
	var ground := {"flying": false}
	var flyer := {"flying": true}
	_eq(Pathfinding.move_cost_for(ground, {"terrain": "plain"}), 1.0, "cost: plain ground")
	_eq(Pathfinding.move_cost_for(ground, {"terrain": "forest"}), 2.0, "cost: forest ground")
	_ok(not is_finite(Pathfinding.move_cost_for(ground, {"terrain": "water"})), "cost: water ground INF")
	_eq(Pathfinding.move_cost_for(flyer, {"terrain": "water"}), 1.0, "cost: water flyer")
	_ok(not is_finite(Pathfinding.move_cost_for(ground, {"terrain": "mountain"})), "cost: mountain ground INF")
	_eq(Pathfinding.move_cost_for(flyer, {"terrain": "mountain"}), 1.0, "cost: mountain flyer")
	_ok(not is_finite(Pathfinding.move_cost_for(ground, null)), "cost: off-board INF")

	# --- reachable on an open plain field ---
	var gs := _flat_state(9, 9)
	var mover := gs.spawn_unit("stoneward", 0, 4, 4)   # move 2... use a 3-mover instead:
	mover["move"] = 3
	var reach := Pathfinding.compute_reachable(gs, mover)
	_ok(reach.has("4,4"), "reach: start present")
	_ok(reach.has("7,4"), "reach: distance-3 reachable")        # hex_distance((4,4),(7,4)) == 3
	_ok(not reach.has("8,4"), "reach: distance-4 unreachable")  # cost 4 > move 3
	# On uniform plain, every reachable tile's cost equals its hex distance and is <= move.
	var all_ok := true
	for k in reach:
		var v: Dictionary = reach[k]
		var d := HexLib.distance(Vector2i(4, 4), Vector2i(v["q"], v["r"]))
		if v["cost"] != d or v["cost"] > 3:
			all_ok = false
	_ok(all_ok, "reach: cost == hex distance, <= move")

	# --- enemy blocks, friendly is passable ---
	var gs2 := _flat_state(9, 9)
	var u2 := gs2.spawn_unit("cinderling", 0, 4, 4)   # move 4
	gs2.spawn_unit("cinderling", 1, 5, 4)             # ENEMY directly east (4,4)->(5,4)
	var reach2 := Pathfinding.compute_reachable(gs2, u2)
	_ok(not reach2.has("5,4"), "reach: enemy tile excluded")
	_ok(reach2.has("6,4"), "reach: tile past enemy still reachable around")
	var gs3 := _flat_state(9, 9)
	var u3 := gs3.spawn_unit("cinderling", 0, 4, 4)   # move 4
	gs3.spawn_unit("cinderling", 0, 5, 4)             # FRIENDLY east — passable, but a dead end
	var reach3 := Pathfinding.compute_reachable(gs3, u3)
	_ok(not reach3.has("5,4"), "reach: friendly-occupied tile dropped as a destination")
	_eq(reach3["6,4"]["cost"], 2, "reach: path passes THROUGH friendly (cost 2)")

	# --- flyer crosses water; grounded unit is stuck ---
	var gw := _flat_state(9, 9, "water")
	var fly := gw.spawn_unit("galewisp", 0, 4, 4)     # flying, move 5
	var reach_fly := Pathfinding.compute_reachable(gw, fly)
	_ok(reach_fly.size() > 1, "reach: flyer moves over water")
	var gg := _flat_state(9, 9, "water")
	var grd := gg.spawn_unit("cinderling", 0, 4, 4)   # grounded
	var reach_grd := Pathfinding.compute_reachable(gg, grd)
	_eq(reach_grd.size(), 1, "reach: grounded unit landlocked (start only)")

	# --- attack targets by range ---
	var ga := _flat_state(9, 9)
	var melee := ga.spawn_unit("cinderling", 0, 4, 4) # range 1
	var foe := ga.spawn_unit("cinderling", 1, 5, 4)   # distance 1
	var ally := ga.spawn_unit("cinderling", 0, 3, 4)  # friendly, never a target
	var t1 := Pathfinding.compute_attack_targets(ga, melee, melee["q"], melee["r"])
	_eq(t1.size(), 1, "attack: melee hits adjacent foe")
	_ok(t1.has("5,4"), "attack: foe key present")
	foe["q"] = 6   # move foe to distance 2
	var t2 := Pathfinding.compute_attack_targets(ga, melee, melee["q"], melee["r"])
	_eq(t2.size(), 0, "attack: melee can't reach distance 2")
	var ranged := ga.spawn_unit("pyrowyrm", 0, 4, 4)  # range 2, same tile as melee for the query
	var t3 := Pathfinding.compute_attack_targets(ga, ranged, 4, 4)
	_ok(t3.has("6,4"), "attack: range-2 reaches distance-2 foe")
	_ok(not t3.has("3,4"), "attack: friendly excluded")

	# --- reconstruct_path: contiguous, start-first ---
	var gp := _flat_state(9, 9)
	var pm := gp.spawn_unit("cinderling", 0, 4, 4)
	var rp := Pathfinding.compute_reachable(gp, pm)
	var path := Pathfinding.reconstruct_path(rp, 7, 4)
	_eq(path[0], Vector2i(4, 4), "path: starts at the unit")
	_eq(path[path.size() - 1], Vector2i(7, 4), "path: ends at the destination")
	var contiguous := true
	for i in range(1, path.size()):
		if HexLib.distance(path[i - 1], path[i]) != 1:
			contiguous = false
	_ok(contiguous, "path: each step is one hex")

func _test_status() -> void:
	_eq(Statuses.STATUS_META.size(), 7, "status: 7 meta entries")
	_eq(Statuses.STATUS_META["burn"]["label"], "burning", "status: burn label")
	# add/has
	var u := {"hp": 20, "max_hp": 20, "owner": 0, "q": 0, "r": 0}
	_ok(not Status.has_status(u, "slow"), "status: none initially")
	Status.add_status(u, "slow", 2)
	_ok(Status.has_status(u, "slow"), "status: slow added")
	# add_status keeps the MAX of existing vs new turns (never shortens)
	Status.add_status(u, "slow", 1)
	_eq(u["status"]["slow"], 2, "status: add keeps max turns")
	# tick: burn deals 3, regen heals 2, all statuses decrement, expired drop
	var gs := _flat_state(5, 5)
	var b := gs.spawn_unit("stoneward", 0, 1, 1)   # hp 22
	Status.add_status(b, "burn", 2)
	Status.add_status(b, "regen", 1)
	Status.tick_statuses(gs, 0)
	_eq(b["hp"], 22 - 3 + 2, "status: burn -3 then regen +2")   # 21
	_eq(b["status"]["burn"], 1, "status: burn decremented")
	_ok(not Status.has_status(b, "regen"), "status: regen expired (1->0 dropped)")
	# burn can kill (hp floored at 0)
	var c := gs.spawn_unit("galewisp", 0, 2, 2)   # hp 10
	c["hp"] = 2
	Status.add_status(c, "burn", 1)
	Status.tick_statuses(gs, 0)
	_eq(c["hp"], 0, "status: burn floors at 0 (kill)")

func _test_elements() -> void:
	_eq(Elements.ELEMENT.size(), 5, "elements: 5 elements")
	_eq(Elements.ELEMENT["pyro"]["short"], "PYR", "elements: pyro short")
	# Matrix: pyro strong vs zephyr (1.3), weak vs hydro (0.7), neutral vs self (1.0).
	_eq(Elements.ELEM_MATRIX["pyro"]["zephyr"], 1.3, "elements: pyro>zephyr")
	_eq(Elements.ELEM_MATRIX["pyro"]["hydro"], 0.7, "elements: pyro<hydro")
	_eq(Elements.ELEM_MATRIX["pyro"]["pyro"], 1.0, "elements: pyro=pyro")
	_eq(Elements.ELEM_MATRIX["arcane"]["pyro"], 1.1, "elements: arcane>all 1.1")
	_eq(Elements.ELEM_MATRIX["arcane"]["arcane"], 1.0, "elements: arcane=arcane")
	# Every element has a row and column against every element.
	for a in Elements.ELEMENT:
		_eq(Elements.ELEM_MATRIX[a].size(), 5, "elements: %s full row" % a)
	# Affinity
	_eq(Elements.AFFINITY_MULT, 1.2, "elements: affinity mult")
	_ok(Elements.affinity_for("pyro", "hill") != null, "elements: pyro empowered on hill")
	_eq(Elements.affinity_for("pyro", "water"), null, "elements: pyro not on water")
	_ok(Elements.affinity_for("arcane", "tower") != null, "elements: arcane on tower")

func _test_weather() -> void:
	_eq(WeatherData.WEATHERS.size(), 4, "weather: 4 types")
	_eq(WeatherData.WEATHERS["rain"]["atk_mul"]["hydro"], 1.15, "weather: rain boosts hydro")
	_eq(WeatherData.WEATHERS["gale"]["ranged_mul"], 0.8, "weather: gale dampens ranged")
	_eq(WeatherData.WEATHERS["gale"]["fly_bonus"], 1, "weather: gale fly bonus")
	# weather_now defaults to clear when unset.
	var bare := GameState.new()
	_eq(Weather.weather_now(bare)["name"], "Clear", "weather: defaults to clear")
	# new_skirmish initialises weather to clear (initial roll).
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(gs.weather["key"], "clear", "weather: match starts clear")
	_ok(gs.weather["turns_left"] >= 4 and gs.weather["turns_left"] <= 6, "weather: turns_left 4..6")
	# roll_weather determinism: same seed -> same roll. crags has a custom table.
	var crags: Dictionary = Maps.MAPS[2]
	var a := GameState.new_skirmish(crags, 99)
	var b := GameState.new_skirmish(crags, 99)
	Weather.roll_weather(a, false)
	Weather.roll_weather(b, false)
	_eq(a.weather["key"], b.weather["key"], "weather: roll deterministic (key)")
	_eq(a.weather["turns_left"], b.weather["turns_left"], "weather: roll deterministic (turns)")
	_ok(crags["weather_table"].has(a.weather["key"]), "weather: rolled key from map table")

func _test_leveling() -> void:
	# XP curve: 12, 20, 28, 36 to advance FROM levels 1..4; huge at max.
	_eq(Units.xp_to_next(1), 12, "level: xp_to_next(1)")
	_eq(Units.xp_to_next(2), 20, "level: xp_to_next(2)")
	_eq(Units.xp_to_next(4), 36, "level: xp_to_next(4)")
	_ok(Units.xp_to_next(5) > 100000, "level: max level no advance")
	# gain_xp: a single level-up bumps stats and full-heals.
	var u := Units.make_unit(1, "cinderling", 0, 0, 0)  # hp 12, power 5, def 1
	u["hp"] = 3
	var gained := Units.gain_xp(u, 12)
	_eq(gained, 1, "level: gained one level")
	_eq(u["level"], 2, "level: now level 2")
	_eq(u["max_hp"], 16, "level: +4 max_hp")        # 12 + 4
	_eq(u["power"], 6, "level: +1 power")
	_eq(u["def"], 2, "level: +1 def")
	_eq(u["hp"], 16, "level: full heal on level up")
	# multi-level in one award; xp carries the remainder.
	var v := Units.make_unit(2, "cinderling", 0, 0, 0)
	var g2 := Units.gain_xp(v, 12 + 20 + 5)   # level 1->3, 5 xp into level 3
	_eq(g2, 2, "level: two levels at once")
	_eq(v["level"], 3, "level: reached level 3")
	_eq(v["xp"], 5, "level: remainder xp carried")
	# master grows +6 max_hp per level.
	var m := Units.make_master(3, 0, 0, 0)   # max_hp 40
	Units.gain_xp(m, 12)
	_eq(m["max_hp"], 46, "level: master +6 max_hp")
	# evolution: a level-4 cinderling on an owned tower -> infernite, absorbing growth.
	var e := Units.make_unit(4, "cinderling", 0, 0, 0)
	Units.gain_xp(e, 12 + 20 + 28)   # level 1->4 (lvlBonus 3)
	_eq(e["level"], 4, "level: at evolve level")
	var tower_cell := {"terrain": "tower", "owner": 0}
	_ok(Units.try_evolve(e, tower_cell), "evolve: fires on owned tower at L4")
	_eq(e["type_key"], "infernite", "evolve: became infernite")
	_eq(e["evolved"], true, "evolve: evolved flag")
	# infernite base max_hp 22 + lvlBonus(3)*4 = 34; power 9 + 3 = 12; def 3 + 3 = 6.
	_eq(e["max_hp"], 22 + 3 * 4, "evolve: absorbs level max_hp")
	_eq(e["power"], 9 + 3, "evolve: absorbs level power")
	_eq(e["hp"], e["max_hp"], "evolve: full restore")
	# gating: not at level, not owned, wrong terrain, already evolved.
	var low := Units.make_unit(5, "cinderling", 0, 0, 0)  # level 1
	_ok(not Units.try_evolve(low, tower_cell), "evolve: blocked below level 4")
	_ok(not Units.try_evolve(e, tower_cell), "evolve: blocked when already evolved")
	# remaining gates: enemy-owned tower (false), non-tower/castle terrain (false),
	# then the castle branch (true). e2 is a fresh, un-evolved level-4 cinderling.
	var e2 := Units.make_unit(6, "cinderling", 0, 0, 0)
	Units.gain_xp(e2, 12 + 20 + 28)
	_ok(not Units.try_evolve(e2, {"terrain": "tower", "owner": 1}), "evolve: blocked on enemy tower")
	_ok(not Units.try_evolve(e2, {"terrain": "plain", "owner": 0}), "evolve: blocked on non-tower/castle")
	_ok(Units.try_evolve(e2, {"terrain": "castle", "owner": 0}), "evolve: also fires on owned castle")

func _combat_state() -> GameState:
	var gs := _flat_state(7, 7)
	gs.map_def = {}            # default weather table; weather stays clear
	gs.weather = {"key": "clear", "turns_left": 5}
	return gs

func _test_combat() -> void:
	# cinderling (pyro, power 5, hp 12/12) vs galewisp (zephyr, def 1). pyro>zephyr 1.3.
	# raw = 5 * (12/12*0.5+0.5) = 5; mit = def1 + 0 + plainDef0*0.5 = 1.
	# base = max(1, round(5 * 1.3 * 1.0(aff) * 1.0(mark) * 1.0(weather) - 1*0.6))
	#      = round(6.5 - 0.6) = round(5.9) = 6.
	var gs := _combat_state()
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)   # pyro
	var dfn := gs.spawn_unit("galewisp", 1, 3, 3)      # zephyr, def 1
	var r := Combat.compute_damage(gs, atk, dfn)
	_eq(r["elem_mul"], 1.3, "combat: pyro>zephyr mult")
	_eq(r["base"], 6, "combat: base damage on plain")
	# wounded attacker scales down: hp 6/12 -> raw = 5*(0.25+0.5)=3.75.
	atk["hp"] = 6
	# base = max(1, round(3.75 * 1.3 - 0.6)) = round(4.875 - 0.6) = round(4.275) = 4.
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 4, "combat: wounded scales damage")
	atk["hp"] = 12
	# mark on defender -> *1.2 ; bulwark -> +2 mitigation.
	Status.add_status(dfn, "mark", 2)
	# base = round(5*1.3*1.2 - 0.6) = round(7.8 - 0.6) = round(7.2) = 7.
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 7, "combat: mark amplifies")
	dfn["status"].erase("mark")
	Status.add_status(dfn, "bulwark", 2)
	# mit = 1 + 2 = 3; base = round(6.5 - 3*0.6) = round(6.5 - 1.8) = round(4.7) = 5.
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 5, "combat: bulwark mitigates")
	dfn["status"].erase("bulwark")
	# weather: heat boosts pyro 1.15. base = round(5*1.3*1.15 - 0.6) = round(7.475-0.6)=round(6.875)=7.
	gs.weather = {"key": "heat", "turns_left": 5}
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 7, "combat: heat boosts pyro")
	gs.weather = {"key": "clear", "turns_left": 5}
	# affinity: pyro attacking FROM a hill -> +20%. Put attacker on a hill tile.
	gs.cell_at(2, 3)["terrain"] = "hill"
	var rh := Combat.compute_damage(gs, atk, dfn)
	_ok(rh["has_affinity"], "combat: pyro has hill affinity")
	# mit = def1 + plainDef0*0.5 = 1 (defender stays on plain; the hill is the attacker's tile, affinity only).
	# base = round(5*1.3*1.2(aff) - 1*0.6) = round(7.8 - 0.6) = round(7.2) = 7.
	_eq(rh["base"], 7, "combat: affinity + terrain def")
	gs.cell_at(2, 3)["terrain"] = "plain"
	# forecast: lo/hi straddle base, counter detected when defender in range.
	var f := Combat.forecast_battle(gs, atk, dfn)
	_eq(f["lo"], 5, "forecast: lo = base-1")
	_eq(f["hi"], 7, "forecast: hi = base+1")
	_ok(f["can_counter"], "forecast: adjacent ranged defender counters")  # galewisp range 2, dist 1
	# sure_kill when defender hp <= base-1.
	dfn["hp"] = 3
	_ok(Combat.forecast_battle(gs, atk, dfn)["sure_kill"], "forecast: sure kill flagged")
