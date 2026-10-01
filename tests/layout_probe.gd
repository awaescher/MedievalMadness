extends SceneTree
## Dev tool: how "line-like" are 3-village layouts? (height of the triangle / longest side; < 0.15 = nearly a straight line)
func _init() -> void:
	var lines: int = 0
	var total: int = 60
	var dmin: float = 1e9
	var dmax: float = 0.0
	for k in total:
		var m: MapData = MapGen.generate("layout-%d" % k, 3, 2)
		var a := Vector2(m.sites[0].x, m.sites[0].z)
		var b := Vector2(m.sites[1].x, m.sites[1].z)
		var c := Vector2(m.sites[2].x, m.sites[2].z)
		var sides: Array[float] = [a.distance_to(b), b.distance_to(c), a.distance_to(c)]
		var longest: float = maxf(sides[0], maxf(sides[1], sides[2]))
		var area2: float = absf((b - a).cross(c - a))
		var height: float = area2 / maxf(longest, 0.1)
		if height / longest < 0.15:
			lines += 1
		dmin = minf(dmin, minf(sides[0], minf(sides[1], sides[2])))
		dmax = maxf(dmax, longest)
	print("3 villages over %d seeds: %d nearly straight lines (%.0f%%), shortest pair %.0f m, longest pair %.0f m" % [total, lines, 100.0 * float(lines) / float(total), dmin, dmax])
	# same seed, different layout nonce: terrain far from the villages must be identical, the villages must differ
	var ok_terrain: int = 0
	var differ: int = 0
	for k2 in 20:
		var m1: MapData = MapGen.generate("nonce", 3, 2, "a%d" % k2)
		var m2: MapData = MapGen.generate("nonce", 3, 2, "b%d" % k2)
		var same_far: bool = true
		for q in 120:
			var px: float = float((q * 37) % 200 - 100) * m1.map_radius / 120.0
			var pz: float = float((q * 91) % 200 - 100) * m1.map_radius / 120.0
			var near: bool = false
			for s in m1.sites:
				if Vector2(s.x - px, s.z - pz).length() < 60.0:
					near = true
			for s2 in m2.sites:
				if Vector2(s2.x - px, s2.z - pz).length() < 60.0:
					near = true
			if not near and absf(m1.height_at(px, pz) - m2.height_at(px, pz)) > 0.001:
				same_far = false
		if same_far:
			ok_terrain += 1
		if not m1.sites[0].is_equal_approx(m2.sites[0]):
			differ += 1
	print("same seed + different layout nonce: terrain identical away from the villages in %d/20, villages differ in %d/20" % [ok_terrain, differ])
	quit()
