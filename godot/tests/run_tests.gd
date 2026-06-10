extends SceneTree
## Headless test harness. Run via tests/run_tests.ps1, which wraps:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Exits 0 if all asserts pass, 1 otherwise. Pure-logic tests only (no display).

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_harness_smoke()
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
