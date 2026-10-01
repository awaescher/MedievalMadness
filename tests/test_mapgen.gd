extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Seeded map generation (spec 7): determinism, sizes, village sites.

func test_same_seed_same_heightmap_hash() -> void:
	var a: MapData = MapGen.generate("hash-test", 4)
	var b: MapData = MapGen.generate("hash-test", 4)
	TestBase.eq(a.heights_hash(), b.heights_hash(), "same seed -> identical heightmap hash")
	TestBase.eq(a.sites.size(), b.sites.size(), "same number of villages")
	for i in a.sites.size():
		TestBase.check(a.sites[i].is_equal_approx(b.sites[i]), "village site %d identical" % i)

func test_different_seed_differs() -> void:
	var a: MapData = MapGen.generate("seed-one", 3)
	var b: MapData = MapGen.generate("seed-two", 3)
	TestBase.check(a.heights_hash() != b.heights_hash(), "different seeds give different maps")

func test_map_size_formula() -> void:
	for n in [2, 4, 8]:
		var m: MapData = MapGen.generate("size-%d" % n, n)
		var base_r: float = 60.0 + 14.0 * float(n)
		TestBase.check(m.map_radius >= base_r * 1.3 - 0.01 and m.map_radius <= minf(base_r * 3.0, 300.0) + 0.01, "map radius for %d players is 1.3-3.0x the base (%.0f m)" % [n, m.map_radius])
		TestBase.check(m.n <= Cfg.TERRAIN_MAX_VERTS, "at most 256 vertices per side (%d)" % m.n)
		TestBase.eq(m.heights.size(), m.n * m.n, "heightfield size")
		TestBase.eq(m.sites.size(), n, "one village per player")

func test_village_sites_are_valid() -> void:
	for seed_text in ["alpha", "beta", "gamma", "delta"]:
		var m: MapData = MapGen.generate(seed_text, 6)
		for i in m.sites.size():
			var s: Vector3 = m.sites[i]
			TestBase.check(s.y >= Cfg.WATER_LEVEL + 0.8, "%s: village %d is on dry land (h=%.2f)" % [seed_text, i, s.y])
			for j in range(i + 1, m.sites.size()):
				var o: Vector3 = m.sites[j]
				var d: float = Vector2(s.x - o.x, s.z - o.z).length()
				TestBase.check(d >= 2.6 * Cfg.ZONE_RADIUS - 6.0, "%s: villages %d/%d far enough apart (%.1f m)" % [seed_text, i, j, d])
			# zone must be flat: slope <= 10 degrees everywhere inside the zone
			var worst: float = 0.0
			var gx: float = -Cfg.ZONE_RADIUS
			while gx <= Cfg.ZONE_RADIUS:
				var gz: float = -Cfg.ZONE_RADIUS
				while gz <= Cfg.ZONE_RADIUS:
					if gx * gx + gz * gz <= Cfg.ZONE_RADIUS * Cfg.ZONE_RADIUS:
						worst = maxf(worst, m.slope_deg_at(s.x + gx, s.z + gz))
					gz += 4.0
				gx += 4.0
			TestBase.check(worst <= 10.0, "%s: village %d zone slope <= 10 deg (worst %.1f)" % [seed_text, i, worst])

func test_island_edges_are_sea() -> void:
	var m: MapData = MapGen.generate("island", 4)
	var edge: float = m.height_at(m.map_radius + 10.0, 0.0)
	TestBase.check(edge < Cfg.WATER_LEVEL, "far outside the island is below sea level")
	TestBase.check(m.height_at(m.sites[0].x, m.sites[0].z) > Cfg.WATER_LEVEL, "village is above sea level")
