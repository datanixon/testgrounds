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
			u["hp"] = mini(u["max_hp"], u["hp"] + 2)
		if c != null and c["terrain"] == "castle" and c.get("owner", -1) == u["owner"]:
			u["hp"] = mini(u["max_hp"], u["hp"] + 4)
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
	return gs
