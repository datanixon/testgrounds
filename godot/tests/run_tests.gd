extends SceneTree
## Headless test harness. Run via tests/run_tests.ps1, which wraps:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Exits 0 if all asserts pass, 1 otherwise. Pure-logic tests only (no display).
const HexLib = preload("res://core/hex.gd")
const Hex = preload("res://core/hex.gd")
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
const Abilities = preload("res://data/abilities.gd")
const AbilityResolve = preload("res://core/ability_resolve.gd")
const AiProfiles = preload("res://data/ai_profiles.gd")
const AI = preload("res://core/ai.gd")
const UiQueries = preload("res://core/ui_queries.gd")
const SaveGame = preload("res://core/save_game.gd")
const SettingsStore = preload("res://core/settings_store.gd")
const Session = preload("res://core/session.gd")
const Tracks = preload("res://data/tracks.gd")
const MusicSeq = preload("res://core/music_seq.gd")
const Sprites = preload("res://core/sprites.gd")
const Relics = preload("res://data/relics.gd")
const Vision = preload("res://core/vision.gd")
const Objectives = preload("res://core/objectives.gd")
const RosterStore = preload("res://core/roster_store.gd")

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
	_test_new_evolutions()
	_test_bosses()
	_test_combat()
	_test_resolve()
	_test_turn()
	_test_abilities_data()
	_test_attack_status()
	_test_instant_abilities()
	_test_blink()
	_test_ai_profiles()
	_test_ai_helpers()
	_test_ai_attack()
	_test_ai_decision()
	_test_ai_summons()
	_test_ai_turn()
	_test_ui_queries()
	_test_battle_record()
	_test_battle_phases()
	_test_stats()
	_test_new_campaign()
	_test_save()
	_test_settings()
	_test_session()
	_test_tracks()
	_test_music_seq()
	_test_gen_wave()
	_test_sprites()
	_test_relics_data()
	_test_relic_effects()
	_test_relic_spawn()
	_test_relic_pickup()
	_test_relic_consumables()
	_test_ai_relic_nudge()
	_test_vision()
	_test_veilstone()
	_test_fog_state()
	_test_ai_fog()
	_test_ai_fog_approach()
	_test_objectives()
	_test_objective_win()
	_test_objective_save()
	_test_objective_ai_weights()
	_test_objective_campaign()
	_test_fog_settings()
	_test_roster_basic()
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

func _approx(got: float, want: float, msg: String) -> void:
	_ok(absf(got - want) < 0.01, "%s  (got %f, want %f)" % [msg, got, want])

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
	_eq(Maps.MAPS.size(), 6, "maps: 6 skirmish")
	_eq(Maps.MAPS[0]["key"], "frontier", "maps: [0] key")
	_eq(Maps.MAPS[0]["cols"], 14, "maps: [0] cols")
	_eq(Maps.MAPS[2]["key"], "crags", "maps: [2] key")
	_eq(Maps.MAPS[2]["castles"], [Vector2i(0, 5), Vector2i(9, 5)], "maps: crags castles")
	_eq(Maps.MAPS[2]["weather_table"], ["heat", "heat", "clear", "gale"], "maps: crags weather")
	_eq(Maps.MAPS[4]["key"], "mistveil", "maps: [4] key")
	_eq(Maps.MAPS[4]["fog"], true, "maps: mistveil fog-default")
	_eq(Maps.MAPS[5]["key"], "ashfall", "maps: [5] key")
	_eq(Maps.MAPS[5]["weather_table"], ["heat", "heat", "gale", "clear"], "maps: ashfall weather")
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
	# 8 original base + 8 evolved + 4 new base + 4 evolved + 2 bosses = 26.
	_eq(UnitTypes.UNIT_TYPES.size(), 26, "unit_types: 26 entries")
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

func _test_resolve() -> void:
	# Attacker kills a low-HP defender; no counter; attacker gains dmg+kill xp.
	var gs := _combat_state()
	gs.rng = Rng.new(7)
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)   # pyro power 5
	var dfn := gs.spawn_unit("galewisp", 1, 3, 3)      # zephyr hp 10
	dfn["hp"] = 4
	Combat.resolve_attack(gs, atk, dfn)
	_ok(dfn["hp"] <= 0, "resolve: lethal hit kills defender")
	_ok(atk["xp"] > 0, "resolve: attacker gained xp")
	_eq(atk["hp"], atk["max_hp"], "resolve: no counter from a dead defender (attacker at full hp)")
	# Two healthy units trade: defender survives and counters (galewisp range 2).
	var gs2 := _combat_state()
	gs2.rng = Rng.new(7)
	var a2 := gs2.spawn_unit("stoneward", 0, 2, 3)   # terra hp 22
	var d2 := gs2.spawn_unit("galewisp", 1, 3, 3)     # zephyr hp 10, range 2
	var a_hp0: int = a2["hp"]
	var d_hp0: int = d2["hp"]
	Combat.resolve_attack(gs2, a2, d2)
	_ok(d2["hp"] < d_hp0, "resolve: defender took the primary hit")
	_ok(a2["hp"] < a_hp0, "resolve: attacker took a counter")
	# Ward absorbs the primary hit (no damage, ward consumed).
	var gs3 := _combat_state()
	gs3.rng = Rng.new(1)
	var a3 := gs3.spawn_unit("cinderling", 0, 2, 3)
	var d3 := gs3.spawn_unit("stoneward", 1, 3, 3)
	var d3_hp0: int = d3["hp"]
	Status.add_status(d3, "ward", 1)
	Combat.resolve_attack(gs3, a3, d3)
	_eq(d3["hp"], d3_hp0, "resolve: ward absorbs the hit")
	_ok(not Status.has_status(d3, "ward"), "resolve: ward consumed")
	_ok(a3["hp"] < a3["max_hp"], "resolve: ward absorbs primary but in-range defender still counters")
	# Out-of-range counter: a melee defender can't counter a range-2 attacker at dist 2.
	var gs4 := _combat_state()
	gs4.rng = Rng.new(3)
	var a4 := gs4.spawn_unit("pyrowyrm", 0, 1, 3)    # range 2
	var d4 := gs4.spawn_unit("stoneward", 1, 3, 3)    # range 1, distance 2 away
	var a4_hp0: int = a4["hp"]
	Combat.resolve_attack(gs4, a4, d4)
	_ok(d4["hp"] < d4["max_hp"], "resolve: ranged attacker hits")
	_eq(a4["hp"], a4_hp0, "resolve: melee defender out of range cannot counter")

func _test_turn() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	var m0: Variant = gs.master_of(0)
	var m1: Variant = gs.master_of(1)
	# Capture player 1's master MP BEFORE it is brought in (starts at 14).
	var m1_mp0: int = m1["mp"]
	# end_turn flips the player, locks the outgoing side, regens the incoming master.
	gs.end_turn()
	_eq(gs.current_player, 1, "turn: switched to player 1")
	_ok(m0["acted"], "turn: outgoing units locked (acted)")
	# Incoming master regenerates MP (base mp_regen 4, +2/owned-tower = 0 at start).
	_eq(m1["mp"], mini(m1["max_mp"], m1_mp0 + 4), "turn: incoming master regained base MP")
	gs.end_turn()   # back to player 0
	_eq(gs.current_player, 0, "turn: back to player 0")
	_eq(gs.turn, 2, "turn: counter advances on player-0 round")
	# Incoming units are unlocked for the new turn.
	_ok(not m0["acted"], "turn: incoming units unlocked")
	# Heal on owned castle: wound master, end a full round, it heals +4 (castle).
	m0["hp"] = m0["max_hp"] - 10
	var hp_before: int = m0["hp"]
	gs.end_turn(); gs.end_turn()   # back to player 0, on its castle
	_ok(m0["hp"] > hp_before, "turn: unit on owned castle heals")
	# Win condition: kill a master, end_turn detects it.
	var gs2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	gs2.master_of(1)["hp"] = 0
	gs2.check_win_condition()
	_eq(gs2.winner, 0, "win: surviving owner wins")
	# capture_tower flips ownership.
	var gs3 := GameState.new_skirmish(Maps.MAPS[0], 42)
	var tower_pos: Vector2i = gs3.map["towers"][0]
	var tcell: Dictionary = gs3.cell_at(tower_pos.x, tower_pos.y)
	var u := gs3.spawn_unit("cinderling", 0, tower_pos.x, tower_pos.y)
	gs3.capture_tower(u, tcell)
	_eq(tcell["owner"], 0, "capture: tower owner flipped")
	# effective_move now honours slow / skitter / weather fly bonus.
	var gw := _flat_state(5, 5)
	gw.weather = {"key": "clear", "turns_left": 5}
	var s := gw.spawn_unit("cinderling", 0, 2, 2)   # move 4
	_eq(Pathfinding.effective_move(s, gw), 4, "move: base move")
	Status.add_status(s, "slow", 2)
	_eq(Pathfinding.effective_move(s, gw), 2, "move: slow -2")
	s["status"].erase("slow")
	Status.add_status(s, "skitterBoost", 2)
	_eq(Pathfinding.effective_move(s, gw), 6, "move: skitter +2")
	s["status"].erase("skitterBoost")
	var fl := gw.spawn_unit("galewisp", 0, 1, 1)     # flying, move 5
	gw.weather = {"key": "gale", "turns_left": 5}    # gale fly_bonus 1
	_eq(Pathfinding.effective_move(fl, gw), 6, "move: gale +1 for flyers")
	# weather counter expires during a full round -> end_turn re-rolls it.
	var gsw := GameState.new_skirmish(Maps.MAPS[0], 42)
	gsw.weather = {"key": "clear", "turns_left": 1}
	gsw.end_turn()   # -> player 1; no countdown (only ticks on the player-0 boundary)
	gsw.end_turn()   # -> player 0; turns_left 1 -> 0 -> re-roll
	_ok(gsw.weather["turns_left"] >= 4, "turn: weather re-rolled when counter expired")

func _test_abilities_data() -> void:
	_eq(Abilities.ABILITIES.size(), 12, "abilities: 12 entries")
	_eq(Abilities.ABILITIES["ignite"]["target"], "enemy", "abilities: ignite is enemy-target")
	_eq(Abilities.ABILITIES["ignite"]["status"], "burn", "abilities: ignite burns")
	_eq(Abilities.ABILITIES["ignite"]["status_turns"], 2, "abilities: ignite 2 turns")
	_eq(Abilities.ABILITIES["healPulse"]["target"], "none", "abilities: heal is instant")
	_eq(Abilities.ABILITIES["blink"]["target"], "tile", "abilities: blink is tile-target")
	_eq(Abilities.ABILITIES["quake"]["cd"], 4, "abilities: quake cd 4")
	# ability_for: reads the unit's type ability; evolved shaves cd by 1 (min 1).
	var cinder := Units.make_unit(1, "cinderling", 0, 0, 0)   # ability ignite (cd 3), not evolved
	var ab: Variant = Abilities.ability_for(cinder)
	_eq(ab["key"], "ignite", "ability_for: cinderling -> ignite")
	_eq(ab["cd"], 3, "ability_for: base cd")
	var infern := Units.make_unit(2, "infernite", 0, 0, 0)    # evolved form, ability ignite
	_eq(Abilities.ability_for(infern)["cd"], 2, "ability_for: evolved cd-1")
	# master has no ability (type_key "master" not in UNIT_TYPES).
	var m := Units.make_master(3, 0, 0, 0)
	_eq(Abilities.ability_for(m), null, "ability_for: master has none")

func _test_attack_status() -> void:
	# ignite: a surviving defender gets burn(2).
	var gs := _combat_state()
	gs.rng = Rng.new(5)
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)
	var dfn := gs.spawn_unit("stoneward", 1, 3, 3)   # 22 hp, survives a cinderling hit
	Combat.resolve_attack(gs, atk, dfn, "burn", 2)
	_ok(Status.has_status(dfn, "burn"), "attack-status: surviving defender burns")
	_eq(dfn["status"]["burn"], 2, "attack-status: 2 turns")
	# a dead defender gets no status (it's gone).
	var gs2 := _combat_state()
	gs2.rng = Rng.new(5)
	var a2 := gs2.spawn_unit("cinderling", 0, 2, 3)
	var d2 := gs2.spawn_unit("galewisp", 1, 3, 3)
	d2["hp"] = 2
	Combat.resolve_attack(gs2, a2, d2, "burn", 2)
	_ok(d2["hp"] <= 0, "attack-status: lethal kills")
	_ok(not Status.has_status(d2, "burn"), "attack-status: no status on a dead target")
	# the counter does NOT inflict the attacker's status on the attacker.
	var gs3 := _combat_state()
	gs3.rng = Rng.new(5)
	var a3 := gs3.spawn_unit("stoneward", 0, 2, 3)   # terra, weak vs nothing; survives
	var d3 := gs3.spawn_unit("galewisp", 1, 3, 3)     # range 2, counters
	Combat.resolve_attack(gs3, a3, d3, "burn", 2)
	_ok(not Status.has_status(a3, "burn"), "attack-status: counter inflicts no status on attacker")
	# a basic attack (no payload) inflicts nothing.
	var gs4 := _combat_state()
	gs4.rng = Rng.new(5)
	var a4 := gs4.spawn_unit("cinderling", 0, 2, 3)
	var d4 := gs4.spawn_unit("stoneward", 1, 3, 3)
	Combat.resolve_attack(gs4, a4, d4)
	_ok(not Status.has_status(d4, "burn"), "attack-status: plain attack inflicts nothing")
	# a warded defender absorbs the hit AND takes no status.
	var gs5 := _combat_state()
	gs5.rng = Rng.new(5)
	var a5 := gs5.spawn_unit("cinderling", 0, 2, 3)
	var d5 := gs5.spawn_unit("stoneward", 1, 3, 3)
	Status.add_status(d5, "ward", 1)
	Combat.resolve_attack(gs5, a5, d5, "burn", 2)
	_ok(not Status.has_status(d5, "burn"), "attack-status: warded hit applies no status")

func _test_blink() -> void:
	var gs := _flat_state(11, 11)
	var hexwisp := gs.spawn_unit("hexwisp", 0, 5, 5)   # flying blinker
	var tg := AbilityResolve.blink_targets(gs, hexwisp)
	# in range (<=4): a tile 3 away is a target; 5 away is not; the own tile is not.
	_ok(tg.has("8,5"), "blink: tile 3 away is a target")          # distance 3
	_ok(not tg.has("10,5"), "blink: tile 5 away out of range")    # distance 5
	_ok(not tg.has("5,5"), "blink: own tile excluded")
	# occupied tiles are excluded.
	gs.spawn_unit("cinderling", 1, 7, 5)
	_ok(not AbilityResolve.blink_targets(gs, hexwisp).has("7,5"), "blink: occupied tile excluded")
	# water blocks landing for everyone (even flyers); mountain only for non-flyers.
	var gw := _flat_state(11, 11)
	gw.cell_at(6, 5)["terrain"] = "water"
	gw.cell_at(6, 6)["terrain"] = "mountain"
	var flyer := gw.spawn_unit("hexwisp", 0, 5, 5)        # flying
	var tg2 := AbilityResolve.blink_targets(gw, flyer)
	_ok(not tg2.has("6,5"), "blink: water never landable")
	_ok(tg2.has("6,6"), "blink: flyer may land on mountain")
	var gg := _flat_state(11, 11)
	gg.cell_at(6, 6)["terrain"] = "mountain"
	var ground := gg.spawn_unit("runeward", 0, 5, 5)      # non-flyer (would be ward, but fine for blink targeting)
	_ok(not AbilityResolve.blink_targets(gg, ground).has("6,6"), "blink: non-flyer cannot land on mountain")
	# do_blink teleports.
	AbilityResolve.do_blink(hexwisp, 8, 5)
	_eq(Vector2i(hexwisp["q"], hexwisp["r"]), Vector2i(8, 5), "blink: teleported")

func _instant(key: String) -> Dictionary:
	return {"key": key}   # resolve_instant only reads ab["key"]

func _test_instant_abilities() -> void:
	# healPulse: +5 to a wounded adjacent ally, capped at max_hp; full allies untouched.
	var gs := _flat_state(5, 5)
	var caster := gs.spawn_unit("tidekin", 0, 2, 2)      # healPulse line
	var hurt := gs.spawn_unit("stoneward", 0, 3, 2)      # adjacent ally, hp 22
	hurt["hp"] = 10
	var full := gs.spawn_unit("cinderling", 0, 2, 3)     # adjacent ally at full
	_ok(AbilityResolve.resolve_instant(gs, caster, _instant("healPulse")), "instant: heal fired")
	_eq(hurt["hp"], 15, "heal: +5 to wounded ally")
	_eq(full["hp"], full["max_hp"], "heal: full ally untouched")
	# quake: 4 dmg to every adjacent enemy, no counter; caster gains xp; a kill counts.
	var gq := _flat_state(5, 5)
	var ogre := gq.spawn_unit("geomaul", 0, 2, 2)        # quake line
	var e1 := gq.spawn_unit("cinderling", 1, 3, 2)       # adjacent enemy, hp 12
	var e2 := gq.spawn_unit("galewisp", 1, 2, 3)         # adjacent enemy, hp 10
	e2["hp"] = 3                                          # will die to the 4 dmg
	_ok(AbilityResolve.resolve_instant(gq, ogre, _instant("quake")), "instant: quake fired")
	_eq(e1["hp"], 8, "quake: -4 to survivor")
	_ok(e2["hp"] <= 0, "quake: kills the soft target")
	_ok(ogre["xp"] > 0 or ogre["level"] > 1, "quake: caster gained xp")
	# skitter: adds skitterBoost(1) and flags a second move.
	var gsk := _flat_state(5, 5)
	var skink := gsk.spawn_unit("duneskink", 0, 2, 2)
	_ok(AbilityResolve.resolve_instant(gsk, skink, _instant("skitter")), "instant: skitter fired")
	_ok(Status.has_status(skink, "skitterBoost"), "skitter: boost applied")
	_ok(skink["second_move"], "skitter: second move flagged")
	# galeRush: second move, but NO skitterBoost.
	var ggr := _flat_state(5, 5)
	var wisp := ggr.spawn_unit("galewisp", 0, 2, 2)
	_ok(AbilityResolve.resolve_instant(ggr, wisp, _instant("galeRush")), "instant: galeRush fired")
	_ok(wisp["second_move"], "galeRush: second move flagged")
	_ok(not Status.has_status(wisp, "skitterBoost"), "galeRush: no skitter boost")
	# bulwark: self + adjacent allies get bulwark(1); enemies don't.
	var gb := _flat_state(5, 5)
	var ward_u := gb.spawn_unit("stoneward", 0, 2, 2)    # bulwark line
	var ally := gb.spawn_unit("cinderling", 0, 3, 2)
	var enemy := gb.spawn_unit("cinderling", 1, 2, 3)
	_ok(AbilityResolve.resolve_instant(gb, ward_u, _instant("bulwark")), "instant: bulwark fired")
	_ok(Status.has_status(ward_u, "bulwark"), "bulwark: self shielded")
	_ok(Status.has_status(ally, "bulwark"), "bulwark: adjacent ally shielded")
	_ok(not Status.has_status(enemy, "bulwark"), "bulwark: enemy not shielded")

func _test_ai_profiles() -> void:
	_eq(AiProfiles.AI_PROFILES.size(), 3, "ai_profiles: 3 difficulties")
	_eq(AiProfiles.DIFFICULTIES, ["easy", "normal", "hard"], "ai_profiles: difficulty order")
	_eq(AiProfiles.AI_PROFILES["normal"]["kill_bonus"], 30, "ai_profiles: normal kill_bonus")
	_eq(AiProfiles.AI_PROFILES["hard"]["master_bonus"], 26, "ai_profiles: hard master_bonus")
	_eq(AiProfiles.AI_PROFILES["easy"]["random_summons"], true, "ai_profiles: easy random summons")
	_eq(AiProfiles.AI_PROFILES["normal"]["random_summons"], false, "ai_profiles: normal not random")
	# GameState defaults to normal; weights() reads it.
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(gs.difficulty, "normal", "ai_profiles: state defaults normal")
	_eq(AI.weights(gs)["kill_bonus"], 30, "ai_profiles: weights() picks the state profile")
	gs.difficulty = "hard"
	_eq(AI.weights(gs)["kill_bonus"], 40, "ai_profiles: weights() follows difficulty")

func _test_ai_helpers() -> void:
	# threat map: a lone enemy contributes its power to every tile it could attack.
	var gs := _flat_state(9, 9)
	var foe := gs.spawn_unit("cinderling", 1, 4, 4)   # power 5, move 4, range 1
	var threat := AI.build_threat_map(gs, 0)           # threat to player 0 from player 1
	# the foe's own tile is reachable; a tile adjacent to it is threatened (>=5).
	_ok(threat.get("5,4", 0) >= 5, "threat: adjacent tile threatened by foe power")
	# a far tile (distance > move+range) is unthreatened.
	_eq(threat.get("0,0", 0), 0, "threat: far tile not threatened")
	# two enemies stack on a shared tile.
	gs.spawn_unit("cinderling", 1, 6, 4)
	var threat2 := AI.build_threat_map(gs, 0)
	_ok(threat2.get("5,4", 0) >= 10, "threat: two foes stack")
	# find_summon_slot: first free non-blocking neighbor of the master.
	var gs2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	var m: Variant = gs2.master_of(0)
	var slot: Variant = AI.find_summon_slot(gs2, m)
	_ok(slot != null, "summon-slot: found a free neighbor")
	_eq(Hex.distance(slot, Vector2i(m["q"], m["r"])), 1, "summon-slot: adjacent to master")
	_ok(gs2.unit_at(slot.x, slot.y) == null, "summon-slot: empty")
	# score_instant_ability: a quaker with two adjacent enemies wants to quake.
	var gq := _flat_state(7, 7)
	var ogre := gq.spawn_unit("geomaul", 0, 3, 3)       # quake (target none)
	gq.spawn_unit("cinderling", 1, 4, 3)
	gq.spawn_unit("galewisp", 1, 3, 4)
	var inst: Variant = AI.score_instant_ability(gq, ogre)
	_ok(inst != null and inst["score"] > 0, "instant-score: quake scored with 2 adjacent enemies")
	# a quaker with no adjacent enemy scores nothing.
	var gq2 := _flat_state(7, 7)
	var lone := gq2.spawn_unit("geomaul", 0, 3, 3)
	_eq(AI.score_instant_ability(gq2, lone), null, "instant-score: no targets -> null")
	# an enemy-target ability (cinderling/ignite) is NOT an instant -> null.
	_eq(AI.score_instant_ability(gq2, gq2.spawn_unit("cinderling", 0, 1, 1)), null, "instant-score: enemy-target ability not instant")
	# _retreat_node: a wounded unit prefers the reachable tile nearest an owned heal cell.
	var gr := _flat_state(9, 9)
	gr.cell_at(4, 4)["terrain"] = "castle"
	gr.cell_at(4, 4)["owner"] = 0
	var retreater := gr.spawn_unit("cinderling", 0, 2, 4)   # move 4
	retreater["hp"] = 3
	var rr := Pathfinding.compute_reachable(gr, retreater)
	var rthreat := AI.build_threat_map(gr, 0)
	var rnode: Variant = AI._retreat_node(gr, retreater, rr, rthreat)
	_ok(rnode != null, "retreat: found a node")
	_ok(Hex.distance(Vector2i(rnode["q"], rnode["r"]), Vector2i(4, 4)) <= Hex.distance(Vector2i(2, 4), Vector2i(4, 4)), "retreat: node is no farther from the owned castle than the start")

func _test_ai_attack() -> void:
	var gs := _combat_state()                          # 7x7 plain, clear weather, rng default
	var atk := gs.spawn_unit("cinderling", 1, 2, 3)    # AI unit (player 1), pyro
	var foe := gs.spawn_unit("galewisp", 0, 4, 3)       # human unit, zephyr (pyro>zephyr), 2 tiles away
	var reach := Pathfinding.compute_reachable(gs, atk)
	var threat := {}                                    # ignore threat for this scoring test
	var W: Dictionary = AI.weights(gs)
	var best: Variant = AI.score_attacks(gs, atk, reach, threat, W)
	_ok(best != null, "ai-attack: found an attack")
	_eq(best["target_id"], foe["id"], "ai-attack: targets the reachable foe")
	# the chosen end tile is adjacent to the foe (cinderling range 1) and reachable.
	_eq(Hex.distance(best["dest"], Vector2i(foe["q"], foe["r"])), 1, "ai-attack: ends in range")
	# a confirmed kill is flagged and scores above a non-kill.
	var gk := _combat_state()
	var killer := gk.spawn_unit("geomaul", 1, 2, 3)     # power 9
	var prey := gk.spawn_unit("galewisp", 0, 3, 3)       # adjacent, low hp
	prey["hp"] = 2
	var bk: Variant = AI.score_attacks(gk, killer, Pathfinding.compute_reachable(gk, killer), {}, AI.weights(gk))
	_ok(bk != null and bk["kills"], "ai-attack: lethal hit flagged as kill")
	# no enemy in reach -> null.
	var gn := _combat_state()
	var lonely := gn.spawn_unit("cinderling", 1, 2, 3)
	_eq(AI.score_attacks(gn, lonely, Pathfinding.compute_reachable(gn, lonely), {}, AI.weights(gn)), null, "ai-attack: no targets -> null")
	# scoring did NOT mutate the attacker's position.
	_eq(Vector2i(atk["q"], atk["r"]), Vector2i(2, 3), "ai-attack: attacker position unchanged by scoring")
	# kill-drops-ability: an enemy-target-ability unit (cinderling/ignite) that scores a
	# guaranteed kill takes the PLAIN swing (ab nulled — no status on a corpse).
	var gd := _combat_state()
	var burner := gd.spawn_unit("cinderling", 1, 2, 3)   # ignite (target enemy), cd 0
	var dying := gd.spawn_unit("galewisp", 0, 3, 3)        # adjacent
	dying["hp"] = 1
	var bk2: Variant = AI.score_attacks(gd, burner, Pathfinding.compute_reachable(gd, burner), {}, AI.weights(gd))
	_ok(bk2 != null and bk2["kills"], "ai-attack: cinderling lethal swing flagged kill")
	_eq(bk2["ab"], null, "ai-attack: kill drops the enemy-target ability")
	# non-kill: the same unit vs a healthy foe KEEPS its ability armed.
	var ge := _combat_state()
	var burner2 := ge.spawn_unit("cinderling", 1, 2, 3)
	ge.spawn_unit("stoneward", 0, 3, 3)                    # tanky, won't die in one hit
	var bk3: Variant = AI.score_attacks(ge, burner2, Pathfinding.compute_reachable(ge, burner2), {}, AI.weights(ge))
	_ok(bk3 != null and not bk3["kills"], "ai-attack: non-lethal swing not a kill")
	_ok(bk3["ab"] != null and bk3["ab"]["key"] == "ignite", "ai-attack: non-kill keeps the ignite ability")

func _test_ai_decision() -> void:
	# Confirmed kill is taken (kind "attack", flagged kill via ab==null + lethal).
	var gk := _combat_state()
	var killer := gk.spawn_unit("geomaul", 1, 2, 3)
	var prey := gk.spawn_unit("galewisp", 0, 3, 3)
	prey["hp"] = 2
	var enemy_master := gk.spawn_master(0, 6, 6)
	var threat := AI.build_threat_map(gk, 1)
	var act := AI.decide_unit_action(gk, killer, threat, enemy_master)
	_eq(act["kind"], "attack", "decide: takes the confirmed kill")
	_eq(act["target_id"], prey["id"], "decide: kill targets the prey")
	# A lone unit with nothing in reach moves toward the enemy master (move-only).
	var gm := _flat_state(13, 13)
	var em2 := gm.spawn_master(0, 11, 11)
	var grunt := gm.spawn_unit("cinderling", 1, 2, 2)
	var t2 := AI.build_threat_map(gm, 1)
	var act2 := AI.decide_unit_action(gm, grunt, t2, em2)
	_eq(act2["kind"], "move", "decide: lone grunt moves")
	# the move steps CLOSER to the enemy master.
	_ok(Hex.distance(act2["dest"], Vector2i(11, 11)) < Hex.distance(Vector2i(2, 2), Vector2i(11, 11)), "decide: move approaches the master")
	# A quaker surrounded by enemies prefers its instant ability over a weak attack.
	var gi := _flat_state(7, 7)
	var emi := gi.spawn_master(0, 0, 0)
	var ogre := gi.spawn_unit("geomaul", 1, 3, 3)
	gi.spawn_unit("stoneward", 0, 4, 3)    # tanky adjacent enemies — attack is weak, quake hits both
	gi.spawn_unit("stoneward", 0, 3, 4)
	var ti := AI.build_threat_map(gi, 1)
	var acti := AI.decide_unit_action(gi, ogre, ti, emi)
	_ok(acti["kind"] == "instant" or acti["kind"] == "attack", "decide: quaker acts (instant or attack)")
	# A unit adjacent to an unowned tower it can reach, with no better attack, captures.
	var gc := _flat_state(7, 7)
	gc.cell_at(3, 4)["terrain"] = "tower"   # neutral tower next to the unit
	gc.map["towers"].append(Vector2i(3, 4))  # register so capture branch can find it
	var emc := gc.spawn_master(0, 0, 0)
	var grabber := gc.spawn_unit("cinderling", 1, 3, 3)
	var tc := AI.build_threat_map(gc, 1)
	var actc := AI.decide_unit_action(gc, grabber, tc, emc)
	_eq(actc["kind"], "capture", "decide: captures a reachable neutral tower")
	_eq(actc["dest"], Vector2i(3, 4), "decide: capture dest is the tower")

func _test_ai_summons() -> void:
	# A master with plenty of MP and an enemy army summons at least one unit, adjacent.
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	var m1: Variant = gs.master_of(1)
	m1["mp"] = 30
	gs.spawn_unit("cinderling", 0, 3, 3)   # an enemy to score matchups against
	var before := gs.alive_units(1).size()
	AI.run_summons(gs, m1)
	_ok(gs.alive_units(1).size() > before, "summons: AI summoned at least one unit")
	_ok(m1["mp"] < 30, "summons: MP was spent")
	# summoned units belong to the master's owner, are adjacent, and are flagged acted.
	for u in gs.alive_units(1):
		if not u["is_master"]:
			_ok(Hex.distance(Vector2i(u["q"], u["r"]), Vector2i(m1["q"], m1["r"])) == 1, "summons: spawned adjacent to master")
			_ok(u["acted"], "summons: summoned unit is acted")
	# Deterministic on normal: same seed + same setup -> same summoned roster.
	var ga := GameState.new_skirmish(Maps.MAPS[0], 77)
	var gb := GameState.new_skirmish(Maps.MAPS[0], 77)
	ga.master_of(1)["mp"] = 24
	gb.master_of(1)["mp"] = 24
	ga.spawn_unit("galewisp", 0, 3, 3); gb.spawn_unit("galewisp", 0, 3, 3)
	AI.run_summons(ga, ga.master_of(1))
	AI.run_summons(gb, gb.master_of(1))
	var types_a := PackedStringArray()
	for u in ga.alive_units(1): if not u["is_master"]: types_a.append(u["type_key"])
	var types_b := PackedStringArray()
	for u in gb.alive_units(1): if not u["is_master"]: types_b.append(u["type_key"])
	_eq(types_a, types_b, "summons: deterministic roster on normal")
	# Too little MP (<6) summons nothing.
	var gp := GameState.new_skirmish(Maps.MAPS[0], 42)
	gp.master_of(1)["mp"] = 5
	var n0 := gp.alive_units(1).size()
	AI.run_summons(gp, gp.master_of(1))
	_eq(gp.alive_units(1).size(), n0, "summons: <6 MP summons nothing")

func _test_ai_turn() -> void:
	# A full AI turn: every AI unit ends up acted; a guaranteed kill is executed.
	var gs := _combat_state()
	gs.current_player = 1                      # AI's turn
	var killer := gs.spawn_unit("geomaul", 1, 2, 3)
	var prey := gs.spawn_unit("galewisp", 0, 3, 3)
	prey["hp"] = 2
	gs.spawn_master(0, 6, 6)                    # enemy master (so take_turn has a target)
	gs.spawn_master(1, 0, 0)                    # AI master
	AI.take_turn(gs)
	_ok(prey["hp"] <= 0, "ai-turn: AI executed the guaranteed kill")
	for u in gs.alive_units(1):
		_ok(u["acted"], "ai-turn: every AI unit acted")
	# No enemy master -> take_turn is a no-op (and does not crash).
	var gn := _combat_state()
	gn.current_player = 1
	gn.spawn_unit("cinderling", 1, 2, 3)
	AI.take_turn(gn)
	_ok(true, "ai-turn: no enemy master -> safe no-op")
	# A move-toward-master turn for a lone grunt actually moves it.
	var gm := _flat_state(13, 13)
	gm.current_player = 1
	gm.spawn_master(0, 11, 11)
	gm.spawn_master(1, 0, 0)
	var grunt := gm.spawn_unit("cinderling", 1, 2, 2)
	AI.take_turn(gm)
	_ok(Hex.distance(Vector2i(grunt["q"], grunt["r"]), Vector2i(11, 11)) < Hex.distance(Vector2i(2, 2), Vector2i(11, 11)), "ai-turn: grunt advanced on the master")

func _test_ui_queries() -> void:
	# can_capture: tower-only (the capturable flag), and only when not already owned.
	var gs := _flat_state(7, 7)
	var u := gs.spawn_unit("cinderling", 0, 3, 3)
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), false, "ui: plain tile not capturable")
	gs.cell_at(3, 3)["terrain"] = "tower"
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), true, "ui: neutral tower capturable")
	gs.cell_at(3, 3)["owner"] = 0
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), false, "ui: own tower not capturable")
	gs.cell_at(3, 3)["owner"] = 1
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), true, "ui: enemy tower capturable")
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(2, 2)), false, "ui: plain neighbor not capturable")
	gs.cell_at(2, 2)["terrain"] = "castle"
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(2, 2)), false, "ui: castle tile not capturable")

	# available_actions on an empty plain board: a lone grunt has just Wait.
	var ga := _flat_state(7, 7)
	var lone := ga.spawn_unit("cinderling", 0, 3, 3)
	var acts := UiQueries.available_actions(ga, lone, false)
	_eq(acts.size(), 2, "ui: lone grunt has ability + wait only")
	_eq(acts[0]["kind"], "ability", "ui: lone grunt first action is its ability")
	_eq(acts[acts.size() - 1]["kind"], "wait", "ui: lone grunt ends in wait")

	# with an adjacent enemy, Attack appears (before Wait).
	ga.spawn_unit("galewisp", 1, 4, 3)
	var acts2 := UiQueries.available_actions(ga, lone, false)
	_eq(acts2[0]["kind"], "attack", "ui: attack present with adjacent enemy")
	_eq(acts2[acts2.size() - 1]["kind"], "wait", "ui: wait is always last")

	# has_undo inserts Undo immediately before Wait.
	var acts3 := UiQueries.available_actions(ga, lone, true)
	_eq(acts3[acts3.size() - 2]["kind"], "undo", "ui: undo sits before wait")
	_eq(acts3[acts3.size() - 1]["kind"], "wait", "ui: wait still last with undo")

	# master with MP >= 6 gets Summon; ability gated by cooldown shows disabled + label.
	var gm := _flat_state(7, 7)
	var m := gm.spawn_master(0, 3, 3)
	m["mp"] = 6
	var ma := UiQueries.available_actions(gm, m, false)
	var has_summon := false
	for a in ma:
		if a["kind"] == "summon":
			has_summon = true
	_ok(has_summon, "ui: master with 6 MP can summon")
	m["mp"] = 5
	var ma2 := UiQueries.available_actions(gm, m, false)
	for a in ma2:
		_ok(a["kind"] != "summon", "ui: master under 6 MP cannot summon")

	# ability cooldown: a unit with an ability on cd shows it disabled with the count.
	var gb := _flat_state(7, 7)
	var ogre := gb.spawn_unit("geomaul", 0, 3, 3)   # quake ability
	ogre["cd"] = 2
	var ba := UiQueries.available_actions(gb, ogre, false)
	var ab_item: Variant = null
	for a in ba:
		if a["kind"] == "ability":
			ab_item = a
	_ok(ab_item != null and ab_item["disabled"], "ui: ability on cd is disabled")
	_ok(String(ab_item["label"]).ends_with("(2)"), "ui: disabled ability label carries the cd count")

	# second-move leg: only Capture (if applicable) + Wait — no Attack/Summon/Ability.
	var gs2 := _flat_state(7, 7)
	var sk := gs2.spawn_unit("galewisp", 0, 3, 3)
	gs2.spawn_unit("cinderling", 1, 4, 3)           # adjacent enemy would normally give Attack
	sk["second_move"] = true
	var sa := UiQueries.available_actions(gs2, sk, false)
	for a in sa:
		_ok(a["kind"] == "capture" or a["kind"] == "wait", "ui: second-move leg is capture/wait only")
	_eq(sa[sa.size() - 1]["kind"], "wait", "ui: second-move ends in wait")

	# summon_options: full SUMMON_LIST, costs correct, disabled flips at the MP boundary.
	var gso := _flat_state(7, 7)
	var sm := gso.spawn_master(1, 3, 3)
	sm["mp"] = 8
	var opts := UiQueries.summon_options(gso, sm)
	_eq(opts.size(), UnitTypes.SUMMON_LIST.size(), "ui: one summon option per SUMMON_LIST entry")
	for o in opts:
		_eq(o["disabled"], o["cost"] > 8, "ui: summon option disabled iff cost exceeds MP")
		_ok(String(o["label"]).ends_with("MP"), "ui: summon label ends in MP")

func _test_battle_record() -> void:
	# A plain attack records one snapshot with the right dmg/kill/terrain and counter.
	var gs := _combat_state()
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)   # pyro, power 5
	var foe := gs.spawn_unit("galewisp", 1, 3, 3)       # zephyr, adjacent (pyro>zephyr)
	Combat.resolve_attack(gs, atk, foe)
	_eq(gs.battle_log.size(), 1, "record: one battle logged")
	var rec: Dictionary = gs.battle_log[0]
	_eq(rec["attacker_pos"], Vector2i(2, 3), "record: attacker position captured")
	_eq(rec["attacker"]["type_key"], "cinderling", "record: attacker type")
	_eq(rec["defender"]["type_key"], "galewisp", "record: defender type")
	_ok(rec["primary"]["dmg"] >= 1, "record: primary dealt damage")
	_eq(rec["def_hp_before"], 10, "record: defender pre-HP captured")  # galewisp max_hp 10
	_eq(rec["terrain"], "plain", "record: defender terrain")
	_ok(rec["counter"].has("happened"), "record: counter block present")
	# A lethal primary records killed + no counter.
	var gk := _combat_state()
	var killer := gk.spawn_unit("geomaul", 0, 2, 3)     # power 9
	var prey := gk.spawn_unit("galewisp", 1, 3, 3)
	prey["hp"] = 2
	Combat.resolve_attack(gk, killer, prey)
	var rk: Dictionary = gk.battle_log[0]
	_ok(rk["primary"]["killed"], "record: lethal primary flagged killed")
	_eq(rk["counter"]["happened"], false, "record: dead defender does not counter")
	# A warded defender records absorbed + no status, and survives.
	var gw := _combat_state()
	var hitter := gw.spawn_unit("cinderling", 0, 2, 3)
	var warded := gw.spawn_unit("stoneward", 1, 3, 3)
	Status.add_status(warded, "ward", 2)
	Combat.resolve_attack(gw, hitter, warded, "burn", 2)
	var rw: Dictionary = gw.battle_log[0]
	_ok(rw["primary"]["absorbed"], "record: ward absorbs primary")
	_eq(rw["status"], null, "record: absorbed swing applies no status")
	# An enemy-ability hit on a surviving defender records the applied status.
	var gstat := _combat_state()
	var burner := gstat.spawn_unit("cinderling", 0, 2, 3)
	var victim := gstat.spawn_unit("stoneward", 1, 3, 3)   # tanky, survives
	Combat.resolve_attack(gstat, burner, victim, "burn", 2)
	var rs: Dictionary = gstat.battle_log[0]
	_ok(rs["status"] != null and rs["status"]["key"] == "burn", "record: surviving defender takes the status")
	# atk_hp_before is the attacker's PRE-swing HP (validated via a counter that wounds it).
	var gc := _combat_state()
	var sw := gc.spawn_unit("stoneward", 0, 2, 3)     # range 1
	var gw2 := gc.spawn_unit("galewisp", 1, 3, 3)      # range 2 → counters at distance 1
	var sw_hp0: int = sw["hp"]
	Combat.resolve_attack(gc, sw, gw2)
	var rc: Dictionary = gc.battle_log[0]
	_ok(rc["counter"]["happened"], "record: ranged defender counters the adjacent attacker")
	_eq(rc["atk_hp_before"], sw_hp0, "record: atk_hp_before is pre-swing HP (not post-counter)")
	_ok(sw["hp"] < sw_hp0, "record: attacker actually took counter damage (so the field is meaningful)")

func _test_battle_phases() -> void:
	const BS = preload("res://scenes/battle/battle_scene.gd")
	# With a counter, the full a-then-c sequence runs to done.
	var seq: Array[String] = []
	var p := "intro"
	for i in range(20):
		seq.append(p)
		if p == "done":
			break
		p = BS.next_phase(p, true)
	_eq(seq[0], "intro", "phases: starts at intro")
	_ok(seq.has("cImpact"), "phases: counter runs the c-side")
	_eq(seq[seq.size() - 1], "done", "phases: reaches done")
	# Without a counter, aRecover jumps straight to outro (no c-side).
	var seq2: Array[String] = []
	var p2 := "intro"
	for i in range(20):
		seq2.append(p2)
		if p2 == "done":
			break
		p2 = BS.next_phase(p2, false)
	_ok(not seq2.has("cCharge"), "phases: no counter skips the c-side")
	_eq(BS.next_phase("aRecover", false), "outro", "phases: aRecover->outro without counter")
	_eq(BS.next_phase("aRecover", true), "cPause", "phases: aRecover->cPause with counter")
	_eq(BS.next_phase("outro", true), "done", "phases: outro->done")

func _test_stats() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	# fresh stats
	_eq(gs.stats["summoned"], [0, 0], "stats: fresh summoned")
	_eq(gs.stats["lost"], [0, 0], "stats: fresh lost")
	_eq(gs.stats["battles"], 0, "stats: fresh battles")
	# spawning a non-master unit tallies summoned for its owner; masters do not
	gs.spawn_unit("cinderling", 0, 1, 1)
	_eq(gs.stats["summoned"], [1, 0], "stats: spawn_unit tallies summoned")
	# a resolved battle bumps battles, and a kill bumps the dead unit's owner's lost
	var atk := gs.spawn_unit("colossus", 0, 2, 2)   # heavy hitter
	var foe := gs.spawn_unit("cinderling", 1, 3, 2)  # adjacent, frail
	foe["hp"] = 1                                    # ensure lethal hit (plan used "imp" sprite key, type key is "cinderling")
	atk["acted"] = false
	Combat.resolve_attack(gs, atk, foe)
	_eq(gs.stats["battles"], 1, "stats: resolve bumps battles")
	_ok(gs.stats["lost"][1] >= 1, "stats: enemy loss tallied on kill")

func _test_new_campaign() -> void:
	var sc: Dictionary = Campaign.CAMPAIGN[1]   # Drowned Marches: ai_mp_bonus 0, ai_summons ["tidekin"]
	var gs := GameState.new_campaign(sc, 1)
	_eq(gs.campaign_index, 1, "campaign: index set")
	_eq(gs.match_difficulty, "normal", "campaign: match_difficulty from scenario")
	_eq(gs.difficulty, "normal", "campaign: AI weight profile follows match difficulty")
	# ai_summons pre-placed for player 1
	var ai_extra := 0
	for u in gs.units:
		if u["owner"] == 1 and not u.get("is_master", false):
			ai_extra += 1
	_eq(ai_extra, 1, "campaign: one ai_summon pre-placed")
	# ai_mp_bonus applied & clamped (mission 1 bonus 0 -> master mp unchanged but >= 4)
	var m1 = gs.master_of(1)
	_ok(m1["mp"] >= 4, "campaign: ai master mp clamped >= 4")

func _test_save() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	gs.spawn_unit("cinderling", 0, 1, 1)
	gs.spawn_unit("colossus", 1, 5, 5)
	gs.turn = 4
	gs.current_player = 1
	gs.campaign_index = 2
	gs.match_difficulty = "hard"
	gs.stats["battles"] = 3
	# round-trip through the pure dict
	var blob := SaveGame.to_dict(gs)
	_eq(blob["v"], 1, "save: version")
	var gs2 = SaveGame.from_dict(blob)
	_ok(gs2 != null, "save: from_dict returns a state")
	_eq(gs2.turn, 4, "save: turn restored")
	_eq(gs2.current_player, 1, "save: current_player restored")
	_eq(gs2.campaign_index, 2, "save: campaign_index restored")
	_eq(gs2.match_difficulty, "hard", "save: match_difficulty restored")
	_eq(gs2.stats["battles"], 3, "save: stats restored")
	# units (living only) restored with full fields
	_eq(gs2.units.size(), gs.units.size(), "save: unit count")
	var cinderling_unit = gs2.unit_at(1, 1)
	_ok(cinderling_unit != null and cinderling_unit["type_key"] == "cinderling", "save: unit identity restored")
	_ok(typeof(cinderling_unit["cd"]) == TYPE_INT or typeof(cinderling_unit["cd"]) == TYPE_FLOAT, "save: unit cd present")
	# weather + map_def carried (closes the JS resumed-campaign-weather gap)
	_eq(gs2.weather.get("key"), gs.weather.get("key"), "save: weather restored")
	_eq(gs2.map_def.get("key"), gs.map_def.get("key"), "save: map_def restored")
	# map cells + rebuilt tower/castle lists
	_eq(gs2.map["cells"].size(), gs.map["cells"].size(), "save: cell count")
	_eq(gs2.map["castles"].size(), gs.map["castles"].size(), "save: castle list rebuilt")
	# version guard
	var bad := blob.duplicate(true)
	bad["v"] = 99
	_eq(SaveGame.from_dict(bad), null, "save: version guard rejects v!=1")
	# old-blob cd normalization
	var nocd := blob.duplicate(true)
	for u in nocd["units"]:
		u.erase("cd")
	var gs3 = SaveGame.from_dict(nocd)
	_ok(gs3 != null and gs3.units[0].get("cd", -1) == 0, "save: missing cd normalized to 0")
	# JSON-path round-trip (the real file path): ints must survive as ints, not floats
	var json_blob = JSON.parse_string(JSON.stringify(SaveGame.to_dict(gs)))
	var gs4 = SaveGame.from_dict(json_blob)
	_ok(gs4 != null, "save: json-path from_dict")
	var ju = gs4.unit_at(1, 1)
	_eq(typeof(ju["owner"]), TYPE_INT, "save: json-path unit owner is int")
	_eq(typeof(ju["hp"]), TYPE_INT, "save: json-path unit hp is int")
	_eq(typeof(gs4.stats["lost"][0]), TYPE_INT, "save: json-path stats int")
	# the actual crash scenario: a float subscript would panic here
	gs4.stats["lost"][ju["owner"]] += 1
	_ok(true, "save: json-path stats subscript by unit owner does not crash")
	# relics: map.relics + unit.relic round-trip
	var rgs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	rgs.map["relics"] = [{"q": 2, "r": 2, "relic": "swift"}]
	var ru := rgs.spawn_unit("cinderling", 0, 1, 1)
	ru["relic"] = "atk_charm"
	var rblob = SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(rgs))))
	_eq(rblob.map["relics"], [{"q": 2, "r": 2, "relic": "swift"}], "save: map.relics round-trips")
	var ru2 = rblob.unit_at(1, 1)
	_eq(ru2["relic"], "atk_charm", "save: unit.relic round-trips")
	# old blob (no relics key) defaults to []
	var noblob := SaveGame.to_dict(rgs)
	noblob.erase("relics")
	_eq(SaveGame.from_dict(noblob).map["relics"], [], "save: missing relics -> []")

func _test_settings() -> void:
	# default blob shape
	var d := SettingsStore.defaults()
	_eq(d["music_vol"], 0.6, "settings: default music_vol")
	_eq(d["battle_scene"], true, "settings: default battle_scene")
	_eq(d["difficulty"], "normal", "settings: default difficulty")
	# merge sanitizes: good values applied, bad ones defaulted
	var merged := SettingsStore.merge(d, {"music_vol": 0.3, "difficulty": "hard", "map_index": 2, "campaign_progress": 1, "battle_scene": false})
	_eq(merged["music_vol"], 0.3, "settings: merge applies valid music_vol")
	_eq(merged["difficulty"], "hard", "settings: merge applies valid difficulty")
	_eq(merged["map_index"], 2, "settings: merge applies valid map_index")
	_eq(merged["battle_scene"], false, "settings: merge applies battle_scene")
	var bad := SettingsStore.merge(d, {"difficulty": "lunatic", "map_index": 99, "music_vol": "loud"})
	_eq(bad["difficulty"], "normal", "settings: merge rejects bad difficulty")
	_eq(bad["map_index"], 0, "settings: merge rejects out-of-range map_index")
	_eq(bad["music_vol"], 0.6, "settings: merge rejects non-number music_vol")
	var over := SettingsStore.merge(d, {"campaign_progress": 999})
	_eq(over["campaign_progress"], Campaign.CAMPAIGN.size() - 1, "settings: campaign_progress clamped to last mission")
	# M10: music_on default true, track_index default 0, clamped to track range
	var dd := SettingsStore.defaults()
	_eq(dd.get("music_on"), true, "settings: default music_on")
	_eq(dd.get("track_index"), 0, "settings: default track_index")
	var m2 := SettingsStore.merge(dd, {"music_on": false, "track_index": 3})
	_eq(m2["music_on"], false, "settings: merge music_on")
	_eq(m2["track_index"], 3, "settings: merge track_index")
	var m3 := SettingsStore.merge(dd, {"track_index": 99})
	_eq(m3["track_index"], Tracks.TRACKS.size() - 1, "settings: track_index clamped to last")
	var m4 := SettingsStore.merge(dd, {"music_on": "yes"})
	_eq(m4["music_on"], true, "settings: bad music_on keeps default")

func _test_session() -> void:
	var s := Session.new()
	# defaults
	_eq(s.screen, "title", "session: starts on title")
	_eq(s.difficulty, "normal", "session: default difficulty")
	# start a skirmish: builds a live state on the selected map/difficulty
	s.map_index = 1
	s.difficulty = "hard"
	s.start_skirmish()
	_eq(s.screen, "play", "session: skirmish -> play")
	_ok(s.state != null, "session: skirmish builds a state")
	_eq(s.state.difficulty, "hard", "session: skirmish AI difficulty from pref")
	_eq(s.state.campaign_index, -1, "session: skirmish is not a campaign")
	_eq(s.state.is_ai, [false, true], "session: is_ai table")
	# start a campaign mission
	s.start_campaign(0)
	_eq(s.screen, "play", "session: campaign -> play")
	_eq(s.state.campaign_index, 0, "session: campaign index tagged")
	_eq(s.difficulty, "hard", "session: campaign did NOT overwrite skirmish pref")
	# progression rule: P0 wins mission 0 -> progress advances to 1
	s.campaign_progress = 0
	s.on_match_won(0)   # state.campaign_index is 0, winner 0
	_eq(s.campaign_progress, 1, "session: win advances campaign_progress")
	# a loss does not advance; progress never regresses
	s.start_campaign(0)
	s.campaign_progress = 2
	s.on_match_won(1)   # AI won
	_eq(s.campaign_progress, 2, "session: AI win leaves progress unchanged")
	# cap at last mission
	var last: int = Campaign.CAMPAIGN.size() - 1
	s.start_campaign(last)
	s.campaign_progress = last
	s.on_match_won(0)
	_eq(s.campaign_progress, last, "session: progress capped at last mission")
	# return_to_title clears the campaign tag
	s.return_to_title()
	_eq(s.screen, "title", "session: return_to_title")

func _test_tracks() -> void:
	_eq(Tracks.TRACKS.size(), 6, "tracks: 6 tracks")
	var t0: Dictionary = Tracks.TRACKS[0]
	_eq(t0["name"], "WRAITHSPIRE FRONTIER", "tracks: t0 name")
	_eq(t0["chords"].size(), 4, "tracks: t0 has 4 chords")
	_eq(t0["chords"][0], {"root": 110.00, "third": 130.81, "fifth": 164.81}, "tracks: t0 Am chord")
	_eq(t0["arp"], [0, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1, 0, 2, 1, 2], "tracks: t0 arp")
	_eq(t0["arp"].size(), 16, "tracks: arp is 16 steps")
	_eq(t0["lead"][0][0], {"s": 4, "hz": 440.0}, "tracks: t0 lead bar0 note0")
	_eq(Tracks.TRACKS[5]["name"], "HEX STORM", "tracks: t5 name")
	# every track: 4 chords, 16-step arp, 4 lead bars
	for t in Tracks.TRACKS:
		_eq(t["chords"].size(), 4, "tracks: 4 chords each")
		_eq(t["arp"].size(), 16, "tracks: 16-step arp each")
		_eq(t["lead"].size(), 4, "tracks: 4 lead bars each")

func _test_music_seq() -> void:
	# step 0, track 0 (bar 0 = Am root 110): kick + hat(accent? beat0%4==0 -> 0.06) + bass + arp + pad(6) ; lead bar0 has no s==0
	var e0 := MusicSeq.events_for_step(0, 0)
	var kinds0 := {}
	for e in e0:
		kinds0[e["kind"]] = kinds0.get(e["kind"], 0) + 1
	_eq(kinds0.get("kick", 0), 1, "seq: step0 has a kick")
	_eq(kinds0.get("hat", 0), 1, "seq: step0 has a hat")
	_eq(kinds0.get("bass", 0), 1, "seq: step0 has a bass")
	_eq(kinds0.get("synth", 0), 1 + 6, "seq: step0 arp(1) + pad(6) synths")  # arp + 3 saw + 3 sine
	# bass freq on the downbeat == chord root
	for e in e0:
		if e["kind"] == "bass":
			_approx(e["freq"], 110.0, "seq: step0 bass = root 110")
	# step 4: snare + hat(beat4%4==0 ->0.06) + bass-walk(fifth*0.5) + arp; lead bar0 s==4 -> 440
	var e4 := MusicSeq.events_for_step(4, 0)
	var kinds4 := {}
	for e in e4:
		kinds4[e["kind"]] = kinds4.get(e["kind"], 0) + 1
	_eq(kinds4.get("snare", 0), 1, "seq: step4 snare")
	_ok(kinds4.get("kick", 0) == 0, "seq: step4 no kick")
	var has_lead := false
	for e in e4:
		if e["kind"] == "synth" and absf(e["freq"] - 440.0) < 0.01:
			has_lead = true
	_ok(has_lead, "seq: step4 lead note 440")
	# step 2: hat accent (beat2%4==2 -> 0.10), arp only among drums; no kick/snare/bass
	var e2 := MusicSeq.events_for_step(2, 0)
	var hat_gain := -1.0
	var has_bass2 := false
	for e in e2:
		if e["kind"] == "hat":
			hat_gain = e["gain"]
		if e["kind"] == "bass":
			has_bass2 = true
	_approx(hat_gain, 0.10, "seq: step2 hat accent gain 0.10")
	_ok(not has_bass2, "seq: step2 no bass")
	# odd step 1: no drums, just arp (beat%2==1 -> no hat)
	var e1 := MusicSeq.events_for_step(1, 0)
	var only := {}
	for e in e1:
		only[e["kind"]] = only.get(e["kind"], 0) + 1
	_eq(only.get("hat", 0), 0, "seq: step1 no hat (odd beat)")
	_eq(only.get("synth", 0), 1, "seq: step1 arp only")
	# bar rollover: step 16 is bar 1 (chord index 1). track0 bar1 root = 87.31
	var e16 := MusicSeq.events_for_step(16, 0)
	for e in e16:
		if e["kind"] == "bass":
			_approx(e["freq"], 87.31, "seq: step16 bass = bar1 root 87.31")

func _test_gen_wave() -> void:
	var sq := MusicSeq.gen_wave("square", 200)
	_eq(sq.size(), 200, "gen_wave: length 200")
	_approx(sq[10], 1.0, "gen_wave: square first half +1")
	_approx(sq[120], -1.0, "gen_wave: square second half -1")
	var sine := MusicSeq.gen_wave("sine", 200)
	_approx(sine[0], 0.0, "gen_wave: sine starts at 0")
	_approx(sine[50], 1.0, "gen_wave: sine quarter +1")
	var saw := MusicSeq.gen_wave("sawtooth", 200)
	_ok(saw[0] < saw[100] and saw[100] < saw[199], "gen_wave: saw rises")
	var tri := MusicSeq.gen_wave("triangle", 200)
	_approx(tri[50], 1.0, "gen_wave: triangle peak at quarter")
	# all bounded to ±1
	for w in ["square", "triangle", "sawtooth", "sine"]:
		for s in MusicSeq.gen_wave(w, 64):
			_ok(s >= -1.0001 and s <= 1.0001, "gen_wave: %s bounded" % w)

func _test_sprites() -> void:
	# every distinct sprite id in UNIT_TYPES resolves a non-null token + battle texture,
	# EXCEPT art-pending stems (P4.1 evolved forms whose PNGs are not generated yet).
	var pending_art := ["hexlord", "sigilwarden", "glaciamaw", "dunestalker", "pyre_colossus", "storm_tyrant"]
	for key in UnitTypes.UNIT_TYPES:
		var sid: String = UnitTypes.UNIT_TYPES[key]["sprite"]
		if sid in pending_art:
			continue
		_ok(Sprites.token(sid, 0) is Texture2D, "sprites: token %s loads" % sid)
		_ok(Sprites.battle(sid, 0) is Texture2D, "sprites: battle %s loads" % sid)
	# archon resolves for both factions, token + battle
	_ok(Sprites.token("archon", 0) is Texture2D, "sprites: archon azure token")
	_ok(Sprites.token("archon", 1) is Texture2D, "sprites: archon crimson token")
	_ok(Sprites.battle("archon", 0) is Texture2D, "sprites: archon azure battle")
	_ok(Sprites.battle("archon", 1) is Texture2D, "sprites: archon crimson battle")
	# archon art differs per faction; neutral monster art does NOT depend on owner
	_ok(Sprites.battle("archon", 0) != Sprites.battle("archon", 1), "sprites: archon faction split")
	_ok(Sprites.token("imp", 0) == Sprites.token("imp", 1), "sprites: neutral monster owner-independent")

func _test_relic_effects() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	# atk_charm: +2 power raises base damage vs the same defender
	var atk := gs.spawn_unit("colossus", 0, 2, 2)
	var foe := gs.spawn_unit("cinderling", 1, 3, 2)
	var base_no: int = Combat.compute_damage(gs, atk, foe)["base"]
	atk["relic"] = "atk_charm"
	var base_atk: int = Combat.compute_damage(gs, atk, foe)["base"]
	_ok(base_atk > base_no, "relic effect: atk_charm raises base damage")
	atk["relic"] = ""
	# effective_move: swift +1 (stacks with the base move)
	var u := gs.spawn_unit("cinderling", 0, 5, 5)
	var mv_no := Pathfinding.effective_move(u, gs)
	u["relic"] = "swift"
	_eq(Pathfinding.effective_move(u, gs), mv_no + 1, "relic effect: swift +1 move")
	# effective_max_hp + regenring heal in end_turn
	var v := gs.spawn_unit("cinderling", 0, 6, 6)
	v["relic"] = "vital"
	_eq(gs.effective_max_hp(v), v["max_hp"] + 4, "relic effect: vital +4 max hp")
	v["relic"] = "regenring"
	v["hp"] = 3
	v["acted"] = true
	# end_turn heals the INCOMING player's units; make player 0 incoming
	gs.current_player = 1
	gs.end_turn()   # -> player 0 incoming, regenring heals +2
	_eq(v["hp"], 5, "relic effect: regenring heals +2 on turn start")
	# thorncharm: defender's counter does +2 (compare counter dmg via resolve)
	var d := gs.spawn_unit("stoneward", 0, 8, 8)   # tanky, survives to counter
	var atkr := gs.spawn_unit("cinderling", 1, 9, 8)  # adjacent attacker
	d["relic"] = "thorncharm"
	var hp_before: int = atkr["hp"]
	Combat.resolve_attack(gs, atkr, d)   # d counters; thorncharm adds +2
	# attacker took counter damage; exact value varies by jitter, but with thorncharm
	# the counter is at least base_counter+2 -> attacker lost > 0 hp (sanity)
	_ok(atkr["hp"] < hp_before, "relic effect: thorncharm defender counters")
	# farsight extends counter range: a range-1 defender with farsight counters at dist 2
	var fdef := gs.spawn_unit("stoneward", 0, 1, 1)   # range 1, tanky
	fdef["relic"] = "farsight"                          # -> effective range 2
	var fatk := gs.spawn_unit("pyrowyrm", 1, 3, 1)      # range 2, attacks from dist 2
	var fatk_hp: int = fatk["hp"]
	Combat.resolve_attack(gs, fatk, fdef)               # fdef should counter (eff range 2)
	_ok(fatk["hp"] < fatk_hp, "relic effect: farsight extends counter range to 2")

func _test_relics_data() -> void:
	_eq(Relics.RELICS.size(), 10, "relics: 10 defined")
	_eq(Relics.bonus("atk_charm", "atk"), 2, "relics: atk_charm +2 atk")
	_eq(Relics.bonus("vital", "max_hp"), 4, "relics: vital +4 hp")
	_eq(Relics.bonus("swift", "move"), 1, "relics: swift +1 move")
	_eq(Relics.bonus("farsight", "range"), 1, "relics: farsight +1 range")
	_eq(Relics.bonus("regenring", "regen"), 2, "relics: regenring +2")
	_eq(Relics.bonus("thorncharm", "counter"), 2, "relics: thorncharm +2 counter")
	_eq(Relics.bonus("nonsense", "atk"), 0, "relics: unknown id -> 0")
	_eq(Relics.bonus("atk_charm", "move"), 0, "relics: missing key -> 0")
	_ok(Relics.is_passive("atk_charm") and not Relics.is_consumable("atk_charm"), "relics: atk_charm passive")
	_ok(Relics.is_consumable("phoenix") and not Relics.is_passive("phoenix"), "relics: phoenix consumable")
	_ok(Relics.RELICS["ley_crystal"].get("master_only", false), "relics: ley_crystal master_only")
	# unit_bonus reads unit.relic
	_eq(Relics.unit_bonus({"relic": "atk_charm"}, "atk"), 2, "relics: unit_bonus reads relic")
	_eq(Relics.unit_bonus({"relic": ""}, "atk"), 0, "relics: no relic -> 0")
	_eq(Relics.unit_bonus({}, "atk"), 0, "relics: missing relic key -> 0")
	# max_hp + effective_range helpers
	_eq(Relics.max_hp({"max_hp": 12, "relic": "vital"}), 16, "relics: max_hp adds vital")
	_eq(Relics.max_hp({"max_hp": 12, "relic": ""}), 12, "relics: max_hp base")
	_eq(Relics.effective_range({"range": 1, "relic": "farsight"}), 2, "relics: farsight 1->2")
	_eq(Relics.effective_range({"range": 2, "relic": "farsight"}), 2, "relics: range capped at 2")
	_eq(Relics.effective_range({"range": 1, "relic": ""}), 1, "relics: base range")
	# every POOL id is a real relic
	for id in Relics.POOL:
		_ok(Relics.RELICS.has(id), "relics: POOL id %s defined" % id)

func _test_relic_spawn() -> void:
	var def := {"key": "t", "name": "T", "cols": 12, "rows": 10, "seed": 7041,
		"mountains": 2, "lakes": 1, "forests": 8, "hills": 6, "towers": 3, "relics": 3}
	var m := MapGen.generate(7041, def)
	_ok(m.has("relics"), "spawn: map has relics list")
	_eq(m["relics"].size(), 3, "spawn: placed def.relics count")
	for r in m["relics"]:
		var cell = m["cells"]["%d,%d" % [r["q"], r["r"]]]
		_eq(cell["terrain"], "plain", "spawn: relic on plain tile")
		_ok(Relics.RELICS.has(r["relic"]), "spawn: valid relic id")
	# determinism: same seed+def -> identical relic layout
	var m2 := MapGen.generate(7041, def)
	_eq(m2["relics"], m["relics"], "spawn: deterministic for fixed seed")
	# zero relics when unspecified
	var def0 := {"key": "z", "name": "Z", "cols": 10, "rows": 8, "seed": 5,
		"mountains": 1, "lakes": 1, "forests": 4, "hills": 4, "towers": 2}
	_eq(MapGen.generate(5, def0)["relics"].size(), 0, "spawn: no relics key -> 0")

func _test_relic_pickup() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	gs.map["relics"] = [{"q": 3, "r": 3, "relic": "atk_charm"}]
	var u := gs.spawn_unit("cinderling", 0, 3, 3)
	# equip into empty slot
	_eq(gs.pick_up_relic(u), "atk_charm", "pickup: returns equipped id")
	_eq(u["relic"], "atk_charm", "pickup: unit equips")
	_eq(gs.map["relics"].size(), 0, "pickup: tile cleared on empty-slot equip")
	# swap: dropping old back onto the tile
	gs.map["relics"] = [{"q": 3, "r": 3, "relic": "swift"}]
	_eq(gs.pick_up_relic(u), "swift", "pickup: swap returns new id")
	_eq(u["relic"], "swift", "pickup: unit now holds new")
	_eq(gs.map["relics"].size(), 1, "pickup: old relic dropped on tile")
	_eq(gs.map["relics"][0]["relic"], "atk_charm", "pickup: dropped relic is the old one")
	# vital tops up hp on equip
	gs.map["relics"] = [{"q": 4, "r": 4, "relic": "vital"}]
	var w := gs.spawn_unit("cinderling", 0, 4, 4)
	var hp0: int = w["hp"]
	gs.pick_up_relic(w)
	_eq(w["hp"], hp0 + 4, "pickup: vital tops up hp by 4")
	# ley_crystal: master applies MP + tile cleared; non-master leaves it
	gs.map["relics"] = [{"q": 5, "r": 5, "relic": "ley_crystal"}]
	var grunt := gs.spawn_unit("cinderling", 0, 5, 5)
	_eq(gs.pick_up_relic(grunt), "", "pickup: non-master leaves ley_crystal")
	_eq(gs.map["relics"].size(), 1, "pickup: ley tile remains for non-master")
	var master = gs.master_of(0)
	master["q"] = 5; master["r"] = 5
	var mp0: int = master["mp"]
	_eq(gs.pick_up_relic(master), "ley_crystal", "pickup: master takes ley")
	_eq(master["mp"], mini(master["max_mp"], mp0 + 6), "pickup: ley grants +6 mp (capped)")
	_eq(master["relic"], "", "pickup: ley never equips")
	_eq(gs.map["relics"].size(), 0, "pickup: ley tile cleared")
	# no relic on tile -> ""
	_eq(gs.pick_up_relic(u), "", "pickup: empty tile -> ''")

func _test_relic_consumables() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	# warhorn: boosts compute_damage base ~1.5x, then clears after the swing
	var atk := gs.spawn_unit("colossus", 0, 2, 2)
	var foe := gs.spawn_unit("stoneward", 1, 3, 2)
	var base_no: int = Combat.compute_damage(gs, atk, foe)["base"]
	atk["relic"] = "warhorn"
	var base_wh: int = Combat.compute_damage(gs, atk, foe)["base"]
	_ok(base_wh > base_no, "consumable: warhorn boosts base damage")
	Combat.resolve_attack(gs, atk, foe)
	_eq(atk["relic"], "", "consumable: warhorn consumed after attack")
	# phoenix: a lethal hit leaves the bearer at 1 hp, relic cleared, alive
	var killer := gs.spawn_unit("colossus", 0, 6, 6)
	var victim := gs.spawn_unit("cinderling", 1, 7, 6)
	victim["relic"] = "phoenix"
	victim["hp"] = 1   # ensure the swing is lethal
	Combat.resolve_attack(gs, killer, victim)
	_eq(victim["hp"], 1, "consumable: phoenix revives at 1 hp")
	_eq(victim["relic"], "", "consumable: phoenix consumed")
	_ok(gs.unit_at(7, 6) != null, "consumable: phoenix-saved unit still alive")
	# a second lethal hit (no phoenix now) kills
	victim["hp"] = 1
	Combat.resolve_attack(gs, killer, victim)
	_ok(victim["hp"] <= 0, "consumable: no phoenix second time -> dead")

func _test_ai_relic_nudge() -> void:
	# relic_tile_bonus is a small pure helper: >0 when the tile holds an un-owned relic
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	gs.map["relics"] = [{"q": 4, "r": 4, "relic": "atk_charm"}]
	_ok(AI.relic_tile_bonus(gs, 4, 4) > 0.0, "ai: relic tile scored positively")
	_eq(AI.relic_tile_bonus(gs, 0, 0), 0.0, "ai: non-relic tile no bonus")
	# _apply_action "attack" case: unit relocates to dest and picks up the relic there
	var ga := _flat_state(7, 7)
	ga.weather = {"key": "clear", "turns_left": 5}
	ga.map["relics"] = [{"q": 3, "r": 3, "relic": "swift"}]
	var attacker := ga.spawn_unit("cinderling", 1, 1, 3)   # player 1, starts at (1,3)
	var prey := ga.spawn_unit("galewisp", 0, 4, 3)          # player 0, at (4,3) — adjacent to (3,3)
	var atk_action := {"kind": "attack", "dest": Vector2i(3, 3), "target_id": prey["id"], "ab": null}
	AI._apply_action(ga, attacker, atk_action)
	_eq(attacker["relic"], "swift", "ai: attack relocation picks up relic on dest tile")
	_eq(ga.map["relics"].size(), 0, "ai: attack relocation clears relic tile")
	# _apply_action "capture" case: unit relocates to tower and picks up the relic there
	var gc := _flat_state(7, 7)
	gc.map["towers"] = [Vector2i(3, 3)]
	gc.cell_at(3, 3)["terrain"] = "tower"
	gc.map["relics"] = [{"q": 3, "r": 3, "relic": "vital"}]
	var grabber := gc.spawn_unit("cinderling", 1, 2, 3)   # player 1
	var cap_action := {"kind": "capture", "dest": Vector2i(3, 3)}
	AI._apply_action(gc, grabber, cap_action)
	_eq(grabber["relic"], "vital", "ai: capture relocation picks up relic on dest tile")
	_eq(gc.map["relics"].size(), 0, "ai: capture relocation clears relic tile")

func _test_vision() -> void:
	# Ground unit sees radius 3, not 4.
	var gs := _flat_state(11, 11)
	var g := gs.spawn_unit("cinderling", 0, 5, 5)   # grounded, move 4
	_eq(Vision.unit_sight(g), 3, "vision: ground sight 3")
	var vg := Vision.compute(gs, 0)
	_ok(vg.has("5,5"), "vision: own tile visible")
	_ok(vg.has("8,5"), "vision: ground sees distance 3")          # dist 3
	_ok(not vg.has("9,5"), "vision: ground blind at distance 4")  # dist 4
	# Flyer sees radius 4.
	var gf := _flat_state(11, 11)
	var f := gf.spawn_unit("galewisp", 0, 5, 5)      # flying, move 5
	_eq(Vision.unit_sight(f), 4, "vision: flyer sight 4")
	var vf := Vision.compute(gf, 0)
	_ok(vf.has("9,5"), "vision: flyer sees distance 4")
	_ok(not vf.has("10,5"), "vision: flyer blind at distance 5")
	# Veilstone adds +1.
	var gv := _flat_state(11, 11)
	var v := gv.spawn_unit("cinderling", 0, 5, 5)
	v["relic"] = "veilstone"
	_eq(Vision.unit_sight(v), 4, "vision: veilstone +1 sight")
	_ok(Vision.compute(gv, 0).has("9,5"), "vision: veilstone ground sees distance 4")
	# Owned spire contributes radius 2; an unowned one contributes nothing.
	var gt := _flat_state(11, 11)
	gt.spawn_unit("cinderling", 0, 0, 0)             # far unit; its disc never reaches (8,8)
	gt.cell_at(8, 8)["terrain"] = "tower"
	gt.cell_at(8, 8)["owner"] = 0
	var vt := Vision.compute(gt, 0)
	_ok(vt.has("8,8"), "vision: owned tower visible")
	_ok(vt.has("8,6"), "vision: owned tower radius 2")             # dist 2
	_ok(not vt.has("8,5"), "vision: owned tower not radius 3")     # dist 3
	gt.cell_at(8, 8)["owner"] = 1
	_ok(not Vision.compute(gt, 0).has("8,8"), "vision: enemy tower grants no vision")

func _test_veilstone() -> void:
	_ok(Relics.RELICS.has("veilstone"), "veilstone: defined")
	_eq(Relics.RELICS["veilstone"]["kind"], "passive", "veilstone: passive")
	_eq(Relics.bonus("veilstone", "vision"), 1, "veilstone: +1 vision")
	_ok("veilstone" in Relics.POOL, "veilstone: in spawn pool")
	var u := Units.make_unit(1, "cinderling", 0, 0, 0)
	_eq(Relics.unit_bonus(u, "vision"), 0, "veilstone: no relic -> 0 vision bonus")
	u["relic"] = "veilstone"
	_eq(Relics.unit_bonus(u, "vision"), 1, "veilstone: equipped -> +1")

func _test_fog_state() -> void:
	# recompute_visibility fills the cache for the viewer; revealed tiles union in.
	var gs := _flat_state(9, 9)
	gs.spawn_unit("cinderling", 0, 4, 4)   # owner-0 vision source
	gs.recompute_visibility(0)
	_ok(gs.visibility.has("4,4"), "fog state: recompute fills viewer vision")
	_ok(not gs.visibility.has("0,0"), "fog state: far tile not visible")
	gs.revealed["0,0"] = true
	gs.recompute_visibility(0)
	_ok(gs.visibility.has("0,0"), "fog state: revealed tiles union into visibility")
	# fog flag round-trips through save; visibility/revealed are NOT saved.
	var g2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	g2.fog = true
	var blob := SaveGame.to_dict(g2)
	_eq(blob["fog"], true, "fog state: to_dict serializes fog")
	_eq(blob.has("visibility"), false, "fog state: visibility not serialized")
	var restored := SaveGame.from_dict(blob)
	_eq(restored.fog, true, "fog state: from_dict restores fog")
	# old blob without fog defaults to false.
	blob.erase("fog")
	_eq(SaveGame.from_dict(blob).fog, false, "fog state: missing fog defaults false")

func _test_ai_fog() -> void:
	# With fog on, build_threat_map ignores enemies the owner cannot see.
	var gs := _flat_state(9, 9)
	gs.spawn_unit("cinderling", 0, 4, 4)        # owner-0 vision source (sight 3)
	gs.spawn_unit("cinderling", 1, 6, 4)        # visible enemy (dist 2 from the source)
	gs.spawn_unit("cinderling", 1, 0, 0)        # hidden enemy (dist 8 — out of vision)
	gs.fog = true
	var tf := AI.build_threat_map(gs, 0)
	_ok(tf.get("6,5", 0) > 0, "ai fog: visible enemy still threatens")
	_eq(tf.get("0,1", 0), 0, "ai fog: hidden enemy contributes no threat")
	# With fog off, the same hidden enemy IS counted (regression / determinism).
	gs.fog = false
	var tn := AI.build_threat_map(gs, 0)
	_ok(tn.get("0,1", 0) > 0, "ai fog off: all enemies threaten (baseline)")

func _test_ai_fog_approach() -> void:
	# Under fog, a non-master must not beeline to a hidden enemy master — it falls back to
	# the enemy's always-visible home castle. With fog off (or master visible) it targets
	# the master's live tile.
	var gs := _flat_state(11, 11)
	gs.map["castles"] = [Vector2i(0, 5), Vector2i(10, 5)]   # [owner0 castle, owner1 castle]
	var ai_unit := gs.spawn_unit("cinderling", 1, 8, 8)     # AI (owner 1) grunt, sight 3
	var enemy_master := gs.spawn_master(0, 1, 1)            # enemy master, far from (8,8)
	gs.fog = false
	_eq(AI.approach_target(gs, ai_unit, enemy_master), Vector2i(1, 1), "ai approach: fog off -> master tile")
	gs.fog = true
	_eq(AI.approach_target(gs, ai_unit, enemy_master), Vector2i(0, 5), "ai approach: hidden master -> enemy castle")
	# Move the grunt adjacent to the master so it is visible again -> target the master.
	ai_unit["q"] = 2
	ai_unit["r"] = 1
	_eq(AI.approach_target(gs, ai_unit, enemy_master), Vector2i(1, 1), "ai approach: visible master -> master tile")

func _test_fog_settings() -> void:
	_eq(SettingsStore.defaults()["fog"], false, "settings: fog defaults off")
	var merged := SettingsStore.merge(SettingsStore.defaults(), {"fog": true})
	_eq(merged["fog"], true, "settings: fog merges from a valid blob")
	var bad := SettingsStore.merge(SettingsStore.defaults(), {"fog": "yes"})
	_eq(bad["fog"], false, "settings: non-bool fog rejected")

func _test_objectives() -> void:
	# empty objective -> no verdict.
	var gs := _flat_state(9, 9)
	_eq(Objectives.evaluate(gs), -1, "obj: empty -> -1")
	# survive: met only at/after start + turns.
	gs.objective = {"kind": "survive", "turns": 3}
	gs.objective_progress = {"start_turn": 1}
	gs.turn = 3
	_eq(Objectives.evaluate(gs), -1, "obj: survive not yet (turn 3, need start+3=4)")
	gs.turn = 4
	_eq(Objectives.evaluate(gs), 0, "obj: survive met")
	# seize: a player-0 unit on the target hex wins.
	var gz := _flat_state(9, 9)
	gz.objective = {"kind": "seize", "q": 5, "r": 5}
	_eq(Objectives.evaluate(gz), -1, "obj: seize empty hex -> -1")
	gz.spawn_unit("cinderling", 1, 5, 5)
	_eq(Objectives.evaluate(gz), -1, "obj: seize enemy-occupied -> -1")
	gz.units.clear()
	gz.spawn_unit("cinderling", 0, 5, 5)
	_eq(Objectives.evaluate(gz), 0, "obj: seize player-occupied -> 0")
	# protect: lose when the unit id is gone.
	var gp := _flat_state(9, 9)
	var ally := gp.spawn_unit("cinderling", 0, 2, 2)
	gp.objective = {"kind": "protect", "unit_id": ally["id"]}
	_eq(Objectives.evaluate(gp), -1, "obj: protect alive -> -1")
	ally["hp"] = 0
	_eq(Objectives.evaluate(gp), 1, "obj: protect dead -> 1 (player loses)")
	# rout: turn-2 guard, then win when enemy non-masters are cleared.
	var gr := _flat_state(9, 9)
	gr.objective = {"kind": "rout"}
	gr.spawn_master(1, 0, 0)
	var foe := gr.spawn_unit("cinderling", 1, 3, 3)
	gr.turn = 1
	_eq(Objectives.evaluate(gr), -1, "obj: rout turn-1 guard")
	gr.turn = 2
	_eq(Objectives.evaluate(gr), -1, "obj: rout with a live enemy -> -1")
	foe["hp"] = 0
	_eq(Objectives.evaluate(gr), 0, "obj: rout cleared -> 0")
	# label.
	var gl := _flat_state(9, 9)
	gl.objective = {"kind": "survive", "turns": 8}
	gl.objective_progress = {"start_turn": 1}
	gl.turn = 4
	_eq(Objectives.label(gl), "Survive: 3/8", "obj: survive label")
	_eq(Objectives.label(_flat_state(3, 3)), "", "obj: no objective -> empty label")

func _test_objective_win() -> void:
	# An objective win sets winner=0 with both masters alive.
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	gs.objective = {"kind": "rout"}
	gs.turn = 2   # enemy has no non-masters yet -> rout met (past the turn-1 guard)
	gs.check_win_condition()
	_eq(gs.winner, 0, "obj-win: rout sets winner 0")
	# Archon-kill still takes precedence and still works with no objective.
	var g2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	g2.master_of(1)["hp"] = 0
	g2.check_win_condition()
	_eq(g2.winner, 0, "obj-win: archon-kill still wins")
	# protect-fail sets winner=1.
	var g3 := GameState.new_skirmish(Maps.MAPS[0], 42)
	var ally := g3.spawn_unit("cinderling", 0, 3, 3)
	g3.objective = {"kind": "protect", "unit_id": ally["id"]}
	g3.check_win_condition()
	_eq(g3.winner, -1, "obj-win: protect alive -> no winner")
	ally["hp"] = 0
	g3.check_win_condition()
	_eq(g3.winner, 1, "obj-win: protect dead -> player loses")
	# new_skirmish copies the def objective + stamps start_turn.
	var def := (Maps.MAPS[0] as Dictionary).duplicate(true)
	def["objective"] = {"kind": "survive", "turns": 5}
	var g4 := GameState.new_skirmish(def, 42)
	_eq(g4.objective.get("kind"), "survive", "obj-win: new_skirmish copies objective")
	_eq(int(g4.objective_progress.get("start_turn", -1)), 1, "obj-win: start_turn stamped")
	# A def with no objective -> empty (skirmish stays archon-kill).
	var g5 := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(g5.objective, {}, "obj-win: no def objective -> empty")

func _test_objective_save() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	gs.objective = {"kind": "seize", "q": 3, "r": 4}
	gs.objective_progress = {"start_turn": 2}
	var blob := SaveGame.to_dict(gs)
	_eq(blob["objective"].get("kind"), "seize", "obj-save: objective serialized")
	var r := SaveGame.from_dict(blob)
	_eq(r.objective.get("kind"), "seize", "obj-save: objective restored")
	_eq(int(r.objective_progress.get("start_turn", -1)), 2, "obj-save: progress restored")
	# old blob without objective -> {}.
	blob.erase("objective")
	blob.erase("objective_progress")
	var r2 := SaveGame.from_dict(blob)
	_eq(r2.objective, {}, "obj-save: missing objective -> empty")

func _test_objective_ai_weights() -> void:
	var gs := _flat_state(9, 9)
	gs.difficulty = "normal"
	# No objective -> identical to the profile.
	_eq(AI.weights(gs), AiProfiles.AI_PROFILES["normal"], "obj-ai: no objective -> profile unchanged")
	# survive -> approach * 1.5, atk_floor 0.
	var base_approach: float = float(AiProfiles.AI_PROFILES["normal"]["approach"])
	gs.objective = {"kind": "survive", "turns": 5}
	var w := AI.weights(gs)
	_approx(float(w["approach"]), base_approach * 1.5, "obj-ai: survive raises approach")
	_eq(int(w["atk_floor"]), 0, "obj-ai: survive zeroes atk_floor")
	# The const profile must NOT be mutated.
	_approx(float(AiProfiles.AI_PROFILES["normal"]["approach"]), base_approach, "obj-ai: profile not mutated")

func _test_objective_campaign() -> void:
	var gs := GameState.new_campaign(Campaign.CAMPAIGN[1], 1)
	_eq(gs.objective.get("kind"), "survive", "obj-campaign: mission 2 has a survive objective")
	_eq(int(gs.objective["turns"]), 8, "obj-campaign: survive 8 turns")
	_eq(int(gs.objective_progress.get("start_turn", -1)), 1, "obj-campaign: start_turn stamped")

func _test_new_evolutions() -> void:
	# evolves_to wired on the four newest bases.
	_eq(UnitTypes.UNIT_TYPES["hexwisp"]["evolves_to"], "hexlord", "evo: hexwisp -> hexlord")
	_eq(UnitTypes.UNIT_TYPES["runeward"]["evolves_to"], "sigilwarden", "evo: runeward -> sigilwarden")
	_eq(UnitTypes.UNIT_TYPES["frostmaw"]["evolves_to"], "glaciamaw", "evo: frostmaw -> glaciamaw")
	_eq(UnitTypes.UNIT_TYPES["duneskink"]["evolves_to"], "dunestalker", "evo: duneskink -> dunestalker")
	# evolved entries exist with the evolved flag, lineage element, and the base's ability.
	for id in ["hexlord", "sigilwarden", "glaciamaw", "dunestalker"]:
		_ok(UnitTypes.UNIT_TYPES.has(id), "evo: %s defined" % id)
		_eq(UnitTypes.UNIT_TYPES[id]["evolved"], true, "evo: %s evolved flag" % id)
	_eq(UnitTypes.UNIT_TYPES["hexlord"]["element"], "arcane", "evo: hexlord arcane")
	_eq(UnitTypes.UNIT_TYPES["hexlord"]["flying"], true, "evo: hexlord flying")
	_eq(UnitTypes.UNIT_TYPES["hexlord"]["ability"], "blink", "evo: hexlord keeps blink")
	_eq(UnitTypes.UNIT_TYPES["glaciamaw"]["power"], 14, "evo: glaciamaw power")
	# evolved forms are NOT summonable.
	_eq(UnitTypes.SUMMON_LIST.size(), 12, "evo: summon list unchanged (12)")
	for id in ["hexlord", "sigilwarden", "glaciamaw", "dunestalker"]:
		_ok(not (id in UnitTypes.SUMMON_LIST), "evo: %s not summonable" % id)
	# behavior: a level-4 hexwisp on an owned tower evolves to hexlord, absorbing growth.
	var h := Units.make_unit(101, "hexwisp", 0, 0, 0)
	Units.gain_xp(h, 12 + 20 + 28)   # level 1 -> 4
	_eq(h["level"], 4, "evo: hexwisp at level 4")
	_ok(Units.try_evolve(h, {"terrain": "tower", "owner": 0}), "evo: hexwisp evolves on owned tower")
	_eq(h["type_key"], "hexlord", "evo: became hexlord")
	_eq(h["evolved"], true, "evo: hexlord evolved flag set")
	_eq(h["hp"], h["max_hp"], "evo: full restore on evolve")
	# spot-check a second line on an owned castle.
	var d := Units.make_unit(102, "duneskink", 0, 0, 0)
	Units.gain_xp(d, 12 + 20 + 28)
	_ok(Units.try_evolve(d, {"terrain": "castle", "owner": 0}), "evo: duneskink evolves on owned castle")
	_eq(d["type_key"], "dunestalker", "evo: became dunestalker")

func _test_bosses() -> void:
	_eq(UnitTypes.UNIT_TYPES.size(), 26, "bosses: 26 unit types")
	for id in ["pyre_colossus", "storm_tyrant"]:
		_ok(UnitTypes.UNIT_TYPES.has(id), "bosses: %s defined" % id)
		_eq(UnitTypes.UNIT_TYPES[id]["boss"], true, "bosses: %s boss flag" % id)
		_ok(not (id in UnitTypes.SUMMON_LIST), "bosses: %s not summonable" % id)
		_ok(Abilities.ABILITIES.has(UnitTypes.UNIT_TYPES[id]["ability"]), "bosses: %s ability exists" % id)
	_eq(UnitTypes.UNIT_TYPES["pyre_colossus"]["power"], 16, "bosses: pyre_colossus power")
	_eq(UnitTypes.UNIT_TYPES["pyre_colossus"]["ability"], "quake", "bosses: pyre_colossus quake")
	_eq(UnitTypes.UNIT_TYPES["storm_tyrant"]["flying"], true, "bosses: storm_tyrant flying")
	_eq(UnitTypes.UNIT_TYPES["storm_tyrant"]["ability"], "diveMark", "bosses: storm_tyrant diveMark")
	_eq(UnitTypes.SUMMON_LIST.size(), 12, "bosses: summon list still 12")
	_ok("pyre_colossus" in Campaign.CAMPAIGN[3]["ai_summons"], "bosses: mission 4 ai_summons has the boss")
	var gs := GameState.new_campaign(Campaign.CAMPAIGN[3], 3)
	var found := false
	for u in gs.units:
		if u["type_key"] == "pyre_colossus" and u["owner"] == 1:
			found = true
	_ok(found, "bosses: new_campaign spawns the boss for the AI")

func _test_roster_basic() -> void:
	var b := RosterStore.new_roster()
	_eq(b["v"], 2, "roster: new version 2")
	_eq((b["roster"] as Array).size(), 0, "roster: new empty")
	_eq(b["next_roster_id"], 1, "roster: new next id 1")
	# entry_from_unit snapshots carry fields, strips transient, doesn't mutate.
	var u := {
		"id": 42, "owner": 0, "q": 3, "r": 5, "is_master": false,
		"type_key": "stoneward", "name": "Stoneward", "element": "terra",
		"sprite": "golem", "attack": "melee", "flying": false,
		"hp": 10, "max_hp": 26, "power": 6, "def": 5, "move": 2, "range": 1,
		"level": 2, "xp": 4, "relic": "vital", "acted": true, "cd": 1, "second_move": true,
	}
	var e := RosterStore.entry_from_unit(u, 7)
	_eq(e["roster_id"], 7, "entry: roster_id stamped")
	_eq(e["type_key"], "stoneward", "entry: type_key kept")
	_eq(e["level"], 2, "entry: level kept")
	_eq(e["xp"], 4, "entry: xp kept")
	_eq(e["max_hp"], 26, "entry: grown max_hp kept")
	_eq(e["power"], 6, "entry: grown power kept")
	_eq(e["relic"], "vital", "entry: relic kept")
	_eq(e["flying"], false, "entry: flying kept")
	_eq(e.has("q"), false, "entry: q stripped")
	_eq(e.has("hp"), false, "entry: hp stripped")
	_eq(e.has("id"), false, "entry: id stripped")
	_eq(e.has("acted"), false, "entry: acted stripped")
	_eq(u["id"], 42, "entry: source unit not mutated")
	# add / remove / clear.
	var id1 := RosterStore.add_entry(b, u)
	var id2 := RosterStore.add_entry(b, u)
	_eq(id1, 1, "add: first id 1")
	_eq(id2, 2, "add: second id 2")
	_eq(b["next_roster_id"], 3, "add: next id bumped")
	_eq((b["roster"] as Array).size(), 2, "add: roster size 2")
	_eq(RosterStore.remove_entry(b, 1), true, "remove: existing returns true")
	_eq(RosterStore.remove_entry(b, 99), false, "remove: missing returns false")
	_eq((b["roster"] as Array).size(), 1, "remove: roster size 1")
	RosterStore.clear(b)
	_eq((b["roster"] as Array).size(), 0, "clear: empty")
	_eq(b["next_roster_id"], 3, "clear: next id preserved")
