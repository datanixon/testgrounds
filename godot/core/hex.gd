class_name Hex
extends RefCounted
## Pointy-top axial hex math. Ported from the JS reference (game.js, section 2).
## Axial coords are Vector2i where x = q, y = r. Pure: no node/render deps.

const SIZE := 36.0  ## hex "radius" (HEX_SIZE in the JS reference)

## Six axial neighbor directions, in the JS reference order (HEX_DIRS).
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Axial -> pixel, grid-relative (hex {0,0} center is the origin). The board node
## applies its own screen offset; this lib stays layout-free, so the JS canvas
## margins (+6 / HEX_W/2) are intentionally not ported here.
static func axial_to_pixel(a: Vector2i) -> Vector2:
	var q := float(a.x)
	var r := float(a.y)
	return Vector2(SIZE * sqrt(3.0) * (q + r / 2.0), SIZE * 1.5 * r)

## Pixel (grid-relative) -> nearest axial.
static func pixel_to_axial(p: Vector2) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / SIZE
	var r := (2.0 / 3.0 * p.y) / SIZE
	return round_axial(q, r)

## Cube-rounding of fractional axial coords to the nearest hex.
static func round_axial(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var rq := roundi(qf)
	var rr := roundi(rf)
	var rs := roundi(sf)
	var dq := absf(rq - qf)
	var dr := absf(rr - rf)
	var ds := absf(rs - sf)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(rq, rr)

## The six neighbors of an axial coord, in DIRS order.
static func neighbors(a: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(a + d)
	return out

## Axial distance (number of steps between two hexes).
static func distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.x + a.y - b.x - b.y) + absi(a.y - b.y)) / 2

## Storage key "q,r" (matches the JS hexKey).
static func key(a: Vector2i) -> String:
	return "%d,%d" % [a.x, a.y]
