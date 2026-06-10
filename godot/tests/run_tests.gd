extends SceneTree
## Headless test harness. Run via tests/run_tests.ps1, which wraps:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Exits 0 if all asserts pass, 1 otherwise. Pure-logic tests only (no display).
const HexLib = preload("res://core/hex.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_harness_smoke()
	_test_hex()
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
