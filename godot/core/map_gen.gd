class_name MapGen
extends RefCounted
## Deterministic map generation — faithful port of generateMap (game.js sec. 3),
## same algorithm AND same Mulberry32 RNG, so fixed seeds reproduce JS layouts
## exactly. Pure: returns a map dict; no globals, no nodes.
## Returned dict:
##   cols, rows: int
##   cells: { "q,r": {q, r, terrain: String, owner: int(-1 none / 0 / 1)} }
##   castles: Array[Vector2i]   (owner is on the cell)
##   towers:  Array[Vector2i]

const Hex = preload("res://core/hex.gd")
const Rng = preload("res://core/rng.gd")
const Relics = preload("res://data/relics.gd")

static func generate(seed: int, def: Dictionary) -> Dictionary:
	var rng := Rng.new(seed)
	var cols: int = def["cols"]
	var rows: int = def["rows"]
	var cells := {}
	var order: Array[Vector2i] = []   # JS [...MAP.cells.values()] insertion order
	for r in range(rows):
		var offset := -(r >> 1)        # -floor(r/2)
		for q in range(offset, offset + cols):
			var v := Vector2i(q, r)
			cells[Hex.key(v)] = {"q": q, "r": r, "terrain": "plain", "owner": -1}
			order.append(v)

	# Mountains: random-walk ridges.
	for i in range(def["mountains"]):
		var c: Variant = _pick(cells, order, rng)
		var length := 2 + rng.below(3)
		for j in range(length):
			if c == null:
				break
			c["terrain"] = "mountain"
			var nbrs: Array[Vector2i] = []
			for n in Hex.neighbors(Vector2i(c["q"], c["r"])):
				if cells.has(Hex.key(n)):
					nbrs.append(n)
			c = cells.get(Hex.key(nbrs[rng.below(nbrs.size())])) if nbrs.size() > 0 else null

	# Lakes: plain-neighbor accretion.
	for i in range(def["lakes"]):
		var c: Variant = _pick(cells, order, rng)
		if c == null:
			continue
		var lake: Array = [c]
		while lake.size() < 4 + rng.below(3):
			var base: Dictionary = lake[rng.below(lake.size())]
			var nbrs: Array = []
			for n in Hex.neighbors(Vector2i(base["q"], base["r"])):
				var nc: Variant = cells.get(Hex.key(n))
				if nc != null and nc["terrain"] == "plain" and not lake.has(nc):
					nbrs.append(nc)
			if nbrs.is_empty():
				break
			lake.append(nbrs[rng.below(nbrs.size())])
		for c2 in lake:
			c2["terrain"] = "water"

	_scatter(cells, order, rng, "forest", def["forests"])
	_scatter(cells, order, rng, "hill", def["hills"])

	# Castles: handcrafted override or default opposite corners.
	var castles: Array[Vector2i] = []
	var start_a := Vector2i(0, 1)
	var start_b := Vector2i(cols - 3 - ((rows - 2) >> 1), rows - 2)
	if def.has("castles"):
		start_a = def["castles"][0]
		start_b = def["castles"][1]
	var castle_a: Variant = cells.get(Hex.key(start_a))
	if castle_a == null:
		castle_a = cells.get(Hex.key(Vector2i(1, 1)))
	var castle_b: Variant = cells.get(Hex.key(start_b))
	if castle_a != null:
		_clear_around(cells, castle_a)
		castle_a["terrain"] = "castle"
		castle_a["owner"] = 0
		castles.append(Vector2i(castle_a["q"], castle_a["r"]))
	if castle_b != null:
		_clear_around(cells, castle_b)
		castle_b["terrain"] = "castle"
		castle_b["owner"] = 1
		castles.append(Vector2i(castle_b["q"], castle_b["r"]))

	# Towers: plain cells, >=3 from each castle, >=2 from other towers.
	var towers: Array[Vector2i] = []
	var pa := Vector2i(castle_a["q"], castle_a["r"]) if castle_a != null else Vector2i.ZERO
	var pb := Vector2i(castle_b["q"], castle_b["r"]) if castle_b != null else Vector2i.ZERO
	var placed := 0
	var guard := 0
	while placed < def["towers"] and guard < 500:
		guard += 1
		var c: Variant = _pick(cells, order, rng)
		if c == null or c["terrain"] != "plain":
			continue
		var cp := Vector2i(c["q"], c["r"])
		if Hex.distance(cp, pa) < 3 or Hex.distance(cp, pb) < 3:
			continue
		var too_close := false
		for t in towers:
			if Hex.distance(t, cp) < 2:
				too_close = true
				break
		if too_close:
			continue
		c["terrain"] = "tower"
		c["owner"] = -1
		towers.append(cp)
		placed += 1

	# Relics: plain cells, >=3 from castles, >=2 from towers and other relics. Each
	# tile rolls a relic id from the pool. Deterministic via the seeded rng.
	var relics: Array = []
	var rcount: int = int(def.get("relics", 0))
	var rguard := 0
	while relics.size() < rcount and rguard < 800:
		rguard += 1
		var rc: Variant = _pick(cells, order, rng)
		if rc == null or rc["terrain"] != "plain":
			continue
		var rp := Vector2i(rc["q"], rc["r"])
		if Hex.distance(rp, pa) < 3 or Hex.distance(rp, pb) < 3:
			continue
		var clash := false
		for t in towers:
			if Hex.distance(t, rp) < 2:
				clash = true
				break
		for er in relics:
			if Hex.distance(Vector2i(er["q"], er["r"]), rp) < 2:
				clash = true
				break
		if clash:
			continue
		relics.append({"q": rc["q"], "r": rc["r"], "relic": Relics.POOL[rng.below(Relics.POOL.size())]})
	return {"cols": cols, "rows": rows, "cells": cells, "castles": castles, "towers": towers, "relics": relics}

static func _pick(cells: Dictionary, order: Array, rng: Rng) -> Variant:
	return cells.get(Hex.key(order[rng.below(order.size())]))

static func _scatter(cells: Dictionary, order: Array, rng: Rng, kind: String, count: int) -> void:
	var guard := 0
	var i := 0
	while i < count and guard < 1000:
		guard += 1
		var c: Dictionary = _pick(cells, order, rng)
		if c["terrain"] != "plain":
			continue
		c["terrain"] = kind
		i += 1

static func _clear_around(cells: Dictionary, c: Dictionary) -> void:
	c["terrain"] = "plain"
	for n in Hex.neighbors(Vector2i(c["q"], c["r"])):
		var nc: Variant = cells.get(Hex.key(n))
		if nc != null and (nc["terrain"] == "mountain" or nc["terrain"] == "water"):
			nc["terrain"] = "plain"
