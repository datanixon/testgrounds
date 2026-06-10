class_name Mulberry32
extends RefCounted
## Bit-exact port of the JS reference PRNG (game.js mulberry32). Fixed seeds
## reproduce the JS map layouts exactly. All state/arithmetic is masked to 32
## bits so GDScript's 64-bit ints match JS int32/uint32 bit patterns. (A 32-bit
## product overflows int64, but the low 32 bits after &U32 are still exact.)

const U32 := 0xFFFFFFFF

var _a: int

func _init(seed: int) -> void:
	_a = seed & U32

## Next raw uint32 — matches JS `(t ^ t >>> 14) >>> 0`.
func next_u32() -> int:
	_a = (_a + 0x6D2B79F5) & U32
	var t := _a
	t = _imul(t ^ (t >> 15), t | 1) & U32
	t = (t ^ (t + _imul(t ^ (t >> 7), t | 61))) & U32
	return (t ^ (t >> 14)) & U32

## Next float in [0, 1) — matches JS `... / 4294967296`.
func next() -> float:
	return float(next_u32()) / 4294967296.0

## Integer in [0, n) — matches JS `Math.floor(rng() * n)`.
func below(n: int) -> int:
	return int(floor(next() * n))

# 32-bit low-word multiply, matching JS Math.imul.
static func _imul(x: int, y: int) -> int:
	return (x * y) & U32
