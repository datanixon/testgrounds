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
