class_name Vision
extends RefCounted
## ROADMAP2 Phase 3 — fog-of-war visibility. Pure: computes the set of visible
## "q,r" keys for one side as the union of its units' sight discs (radius 3 ground,
## 4 flying, +Veilstone) and its owned spires/citadel (radius 2). No LOS blocking —
## plain hex distance, Master-of-Monsters style. Reads GameState; mutates nothing.

const Hex = preload("res://core/hex.gd")
const Relics = preload("res://data/relics.gd")

const GROUND_SIGHT := 3
const FLY_SIGHT := 4
const SPIRE_SIGHT := 2

## unit_sight — a unit's vision radius: 4 if flying else 3, plus a Veilstone bonus.
static func unit_sight(unit: Dictionary) -> int:
	var base: int = FLY_SIGHT if unit["flying"] else GROUND_SIGHT
	return base + int(Relics.unit_bonus(unit, "vision"))

## compute — the set of visible "q,r" keys for `owner` (a Dictionary used as a set).
## Union over every alive unit of `owner` (unit_sight disc) and every tower/castle
## cell owned by `owner` (SPIRE_SIGHT disc). Only in-bounds cells are included.
static func compute(state, owner: int) -> Dictionary:
	var sources: Array = []   # [{pos: Vector2i, r: int}]
	for u in state.alive_units(owner):
		sources.append({"pos": Vector2i(u["q"], u["r"]), "r": unit_sight(u)})
	for k in state.map.get("cells", {}):
		var c: Dictionary = state.map["cells"][k]
		if (c["terrain"] == "tower" or c["terrain"] == "castle") and c.get("owner", -1) == owner:
			sources.append({"pos": Vector2i(c["q"], c["r"]), "r": SPIRE_SIGHT})
	var vis := {}
	for k in state.map.get("cells", {}):
		var c: Dictionary = state.map["cells"][k]
		var p := Vector2i(c["q"], c["r"])
		for s in sources:
			if Hex.distance(p, s["pos"]) <= s["r"]:
				vis[k] = true
				break
	return vis
