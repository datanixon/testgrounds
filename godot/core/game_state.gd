class_name GameState
extends RefCounted
## Single source of truth for a match — the logic-only slice of the JS STATE.
## Holds the generated map + the unit list + turn bookkeeping, owns the unit id
## counter, and exposes the query helpers pathfinding reads. Pure: no nodes,
## instantiable in isolation for headless tests.

const Units = preload("res://core/units.gd")
const MapGen = preload("res://core/map_gen.gd")

var map: Dictionary = {}              # the generate() result: cols, rows, cells, castles, towers
var units: Array[Dictionary] = []
var current_player: int = 0
var turn: int = 1
var _next_id: int = 1

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
	return u

func spawn_master(owner: int, q: int, r: int) -> Dictionary:
	var u := Units.make_master(_new_id(), owner, q, r)
	units.append(u)
	return u

## check_win_condition — set winner if a master is dead. Full body in Task 7.
func check_win_condition() -> void:
	pass

## new_skirmish — port of startNewGame's match setup (sec. 13): generate the map,
## place both archons on their castles, start at turn 1 / player 0. Campaign AI
## summons + weather init land in their owning milestones.
static func new_skirmish(def: Dictionary, seed: int) -> GameState:
	var gs := new()
	gs.map = MapGen.generate(seed, def)
	var castles: Array = gs.map["castles"]
	gs.spawn_master(0, castles[0].x, castles[0].y)
	gs.spawn_master(1, castles[1].x, castles[1].y)
	gs.current_player = 0
	gs.turn = 1
	return gs
