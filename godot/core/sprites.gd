class_name Sprites
extends RefCounted
## M10 art resolver: sprite-id (+ owner for the archon) + kind -> Texture2D, cached.
## The single seam both renderers (board token, battle portrait) use to load art.
## Faction-neutral monsters ignore owner; only "archon" splits per faction.
## Files: res://assets/sprites/<stem>_<token|battle>.png (manifest naming).

const DIR := "res://assets/sprites/"

static var _cache := {}

## _stem -- filename stem for a sprite id. Archon is bespoke per faction; all other
## monsters are faction-neutral (owner ignored).
static func _stem(sprite_id: String, owner: int) -> String:
	if sprite_id == "archon":
		return "archon_azure" if owner == 0 else "archon_crimson"
	return sprite_id

static func _tex(stem: String, kind: String) -> Texture2D:
	var path := "%s%s_%s.png" % [DIR, stem, kind]
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	if t != null:
		_cache[path] = t   # don't cache a miss — a later import shouldn't be poisoned
	return t

static func token(sprite_id: String, owner: int) -> Texture2D:
	return _tex(_stem(sprite_id, owner), "token")

static func battle(sprite_id: String, owner: int) -> Texture2D:
	return _tex(_stem(sprite_id, owner), "battle")
