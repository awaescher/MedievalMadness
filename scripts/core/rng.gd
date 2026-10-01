class_name Rng
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Seeded PRNG (mulberry32) + helpers, and FNV-1a string hash.
## Generation code must ONLY use this (never randf()/String.hash()).

var _state: int = 0

func _init(seed_value: int = 1) -> void:
	_state = seed_value & 0xFFFFFFFF

static func fnv1a(text: String) -> int:
	var h: int = 0x811c9dc5
	var bytes: PackedByteArray = text.to_utf8_buffer()
	for b in bytes:
		h = h ^ int(b)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h

static func from_string(text: String) -> Rng:
	return Rng.new(fnv1a(text))

static func imul(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF

## Next float in [0, 1)
func next_f() -> float:
	_state = (_state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = _state
	t = imul(t ^ (t >> 15), t | 1)
	t = t ^ ((t + imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

func next_u32() -> int:
	return int(next_f() * 4294967296.0)

func range_f(a: float, b: float) -> float:
	return a + (b - a) * next_f()

## Inclusive integer range.
func range_i(a: int, b: int) -> int:
	if b <= a:
		return a
	return a + int(next_f() * float(b - a + 1))

func chance(p: float) -> bool:
	return next_f() < p

func sign_f() -> float:
	return 1.0 if next_f() < 0.5 else -1.0

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[int(next_f() * arr.size()) % arr.size()]

func pick_str(arr: Array) -> String:
	if arr.is_empty():
		return ""
	return str(arr[int(next_f() * arr.size()) % arr.size()])

func shuffle(arr: Array) -> void:
	var i: int = arr.size() - 1
	while i > 0:
		var j: int = int(next_f() * float(i + 1))
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
		i -= 1

## Standard normal (Box-Muller)
func gauss() -> float:
	var u: float = maxf(next_f(), 1e-9)
	var v: float = next_f()
	return sqrt(-2.0 * log(u)) * cos(TAU * v)

func in_circle(radius: float) -> Vector2:
	var a: float = next_f() * TAU
	var r: float = sqrt(next_f()) * radius
	return Vector2(cos(a) * r, sin(a) * r)

func unit_vec3() -> Vector3:
	var z: float = range_f(-1.0, 1.0)
	var a: float = next_f() * TAU
	var r: float = sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(a), z, r * sin(a))

func pick_weighted(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return 0
	var r: float = next_f() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1
