class_name BRuin
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Ruined Castle decoration for the map center (spec 7.4): broken stone walls and a stump of a tower.

const DEF := {"id": "ruin", "footprint_radius": 8.0, "prop_hints": [], "name_key": "building.ruin"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 9.0
	# broken tower stump (8-sided)
	var th: float = rng.range_f(3.0, 5.0)
	Kit.ring(r, "stone", Vector2(-4.0, 0.0), 2.4, 0.0, th, 0.5, 8, 1.0, rng, true, [Vector2(0.0, 0.7)], Color("#8a9096"), "ruin")
	# wall pieces with broken tops
	var segs: Array = [[Vector2(0.0, -4.5), Vector2(6.0, -4.5)], [Vector2(6.0, -4.5), Vector2(6.0, 2.5)], [Vector2(-1.5, 5.0), Vector2(4.5, 5.0)]]
	for sgm in segs:
		var a: Vector2 = (sgm as Array)[0] as Vector2
		var b: Vector2 = (sgm as Array)[1] as Vector2
		var length: float = a.distance_to(b)
		var n: int = int(length / 1.0)
		var dir2: Vector2 = (b - a) / length
		var yaw: float = atan2(-dir2.y, dir2.x)
		for i in n:
			var hgt: float = rng.range_f(1.0, 3.5)
			var rows: int = maxi(1, roundi(hgt / 0.9))
			var c2: Vector2 = a + dir2 * (float(i) + 0.5)
			for k in rows:
				Kit.box(r, "stone", Vector3(1.0, 0.9, 0.8), Vector3(c2.x, 0.45 + float(k) * 0.9, c2.y), rng, Color("#8a9096"), k == 0, "ruin", Vector3(0, yaw, 0))
	r.height = 4.0
	return r
