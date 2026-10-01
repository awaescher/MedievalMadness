class_name Util
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Static helpers: easing, color parsing, spatial hash, misc.

static func hex(c: String) -> Color:
	return Color.html(c)

static func smooth01(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func ease_out_cubic(t: float) -> float:
	var x: float = 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - x * x * x

static func ease_out_back(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

static func ease_in_out(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func ease_out_elastic(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	if x <= 0.0 or x >= 1.0:
		return x
	return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * (TAU / 3.0)) + 1.0

## Frame-rate independent damping factor for lerp
static func damp(k: float, dt: float) -> float:
	return 1.0 - exp(-k * dt)

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

static func xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func dist_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func yaw_to_dir(yaw: float) -> Vector3:
	## yaw 0 = facing -Z; positive yaw rotates counter-clockwise seen from above
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

static func dir_to_yaw(d: Vector3) -> float:
	return atan2(-d.x, -d.z)

static func wrap_angle(a: float) -> float:
	return fposmod(a + PI, TAU) - PI

static func angle_diff(a: float, b: float) -> float:
	return wrap_angle(a - b)

static func is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

static func vec3_hash(v: Vector3) -> int:
	return Rng.fnv1a("%.3f,%.3f,%.3f" % [v.x, v.y, v.z])

static func color_jitter(c: Color, rng: Rng, amount: float = 0.05) -> Color:
	return Color(
		clampf(c.r + rng.range_f(-amount, amount), 0.0, 1.0),
		clampf(c.g + rng.range_f(-amount, amount), 0.0, 1.0),
		clampf(c.b + rng.range_f(-amount, amount), 0.0, 1.0),
		c.a)

static func format_int(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var cnt: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if n < 0 else "") + out

static func remove_swap(arr: Array, idx: int) -> void:
	var last: int = arr.size() - 1
	if idx != last:
		arr[idx] = arr[last]
	arr.pop_back()

## Simple 3D spatial hash grid storing integer ids in cells (rebuilt per use).
class SpatialHash extends RefCounted:
	var cell: float = 3.0
	var cells: Dictionary = {}

	func _init(cell_size: float = 3.0) -> void:
		cell = cell_size

	func clear() -> void:
		cells.clear()

	func _key(cx: int, cy: int, cz: int) -> int:
		return (cx & 0x1FFFFF) | ((cy & 0x3FF) << 21) | ((cz & 0x1FFFFF) << 31)

	func insert(id: int, p: Vector3) -> void:
		var k: int = _key(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		if cells.has(k):
			(cells[k] as PackedInt32Array).append(id)
		else:
			var a := PackedInt32Array()
			a.append(id)
			cells[k] = a

	## Fills `out` with candidate ids within radius (cell granularity)
	func query(p: Vector3, radius: float, out: PackedInt32Array) -> void:
		out.clear()
		var x0: int = floori((p.x - radius) / cell)
		var x1: int = floori((p.x + radius) / cell)
		var y0: int = floori((p.y - radius) / cell)
		var y1: int = floori((p.y + radius) / cell)
		var z0: int = floori((p.z - radius) / cell)
		var z1: int = floori((p.z + radius) / cell)
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				for z in range(z0, z1 + 1):
					var k: int = _key(x, y, z)
					if cells.has(k):
						out.append_array(cells[k] as PackedInt32Array)
