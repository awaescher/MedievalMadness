class_name TestBase
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Minimal assertion helpers for the headless test runner (tests/run_tests.gd).

static var passed: int = 0
static var failed: int = 0
static var current: String = ""
static var messages: PackedStringArray = []

static func reset() -> void:
	passed = 0
	failed = 0
	messages = PackedStringArray()

static func check(cond: bool, msg: String) -> bool:
	if cond:
		passed += 1
	else:
		failed += 1
		var line: String = "  FAIL [%s] %s" % [current, msg]
		messages.append(line)
		print(line)
	return cond

static func eq(a: Variant, b: Variant, msg: String) -> bool:
	return check(a == b, "%s (got %s, expected %s)" % [msg, str(a), str(b)])

static func near(a: float, b: float, tol: float, msg: String) -> bool:
	return check(absf(a - b) <= tol, "%s (got %.4f, expected %.4f +- %.4f)" % [msg, a, b, tol])
