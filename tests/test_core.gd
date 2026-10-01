extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Rng / noise / util / materials / ammo tables.

func test_fnv1a_known_vectors() -> void:
	TestBase.eq(Rng.fnv1a(""), 0x811c9dc5, "fnv1a of empty string")
	TestBase.eq(Rng.fnv1a("a"), 0xe40c292c, "fnv1a of 'a'")
	TestBase.eq(Rng.fnv1a("foobar"), 0xbf9cf968, "fnv1a of 'foobar'")

func test_rng_deterministic() -> void:
	var a := Rng.new(12345)
	var b := Rng.new(12345)
	var same: bool = true
	for i in 200:
		if a.next_f() != b.next_f():
			same = false
	TestBase.check(same, "same seed gives the same sequence")
	var c := Rng.new(12346)
	var differs: bool = false
	var d := Rng.new(12345)
	for i in 20:
		if c.next_f() != d.next_f():
			differs = true
	TestBase.check(differs, "different seed gives a different sequence")

func test_rng_range_and_distribution() -> void:
	var r := Rng.from_string("distribution")
	var sum: float = 0.0
	var n: int = 5000
	var ok: bool = true
	for i in n:
		var v: float = r.next_f()
		if v < 0.0 or v >= 1.0:
			ok = false
		sum += v
	TestBase.check(ok, "values are in [0,1)")
	TestBase.near(sum / float(n), 0.5, 0.03, "mean is about 0.5")
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for i in 5000:
		counts[r.range_i(0, 4)] += 1
	var bal: bool = true
	for c in counts:
		if c < 800 or c > 1200:
			bal = false
	TestBase.check(bal, "range_i(0,4) is roughly uniform: %s" % str(counts))
	TestBase.eq(r.range_i(7, 7), 7, "degenerate range")

func test_rng_shuffle_and_pick() -> void:
	var r := Rng.new(9)
	var arr: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	r.shuffle(arr)
	var sorted: Array = arr.duplicate()
	sorted.sort()
	TestBase.eq(sorted, [1, 2, 3, 4, 5, 6, 7, 8], "shuffle keeps all elements")
	TestBase.check(arr.has(int(r.pick(arr))), "pick returns an element")

func test_noise_is_deterministic_and_bounded() -> void:
	var lo: float = 1.0
	var hi: float = 0.0
	for i in 400:
		var x: float = float(i) * 3.7
		var v: float = VNoise.fbm(x, x * 0.5, 77, 4, 1.0 / 70.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
		TestBase.check(v == VNoise.fbm(x, x * 0.5, 77, 4, 1.0 / 70.0), "noise is a pure function")
		if i > 3:
			break
	for i in 400:
		var v2: float = VNoise.fbm(float(i) * 3.7, float(i) * 1.3, 5)
		lo = minf(lo, v2)
		hi = maxf(hi, v2)
	TestBase.check(lo >= 0.0 and hi <= 1.0, "fbm stays within [0,1] (got %.3f..%.3f)" % [lo, hi])
	TestBase.check(hi - lo > 0.3, "fbm actually varies")

func test_material_table() -> void:
	var wood: Materials.MaterialDef = Materials.get_def("wood")
	TestBase.eq(wood.density, 600.0, "wood density")
	TestBase.eq(wood.break_force, 260.0, "wood break force")
	TestBase.near(wood.flammability, 0.7, 0.001, "wood flammability")
	var stone: Materials.MaterialDef = Materials.get_def("stone")
	TestBase.eq(stone.density, 2300.0, "stone density")
	TestBase.eq(stone.flammability, 0.0, "stone is not flammable")
	TestBase.eq(Materials.get_def("thatch").break_force, 60.0, "thatch break force")
	TestBase.eq(Materials.get_def("metal").break_force, 2500.0, "metal break force")
	TestBase.eq(Materials.get_def("glass").hp_per_m3, 20.0, "glass hp per m3")
	for id in ["wood", "plank", "stone", "brick", "thatch", "cloth", "metal", "hay", "barrel_wood", "glass", "flesh"]:
		TestBase.check(Materials.has(id), "material %s exists" % id)

func test_ammo_table() -> void:
	var all: Array[AmmoDef] = AmmoDef.all()
	TestBase.eq(all.size(), 11, "eleven ammo types")
	TestBase.eq(AmmoDef.get_def("stone").start_count, -1, "stone is unlimited")
	TestBase.eq(AmmoDef.get_def("firebarrel").start_count, 2, "only two fire barrels at the start")
	for id in ["boulder", "powderkeg", "scatter", "cow", "quad", "chain", "log", "meteor", "powdertrail"]:
		TestBase.eq(AmmoDef.get_def(id).start_count, 0, "%s has to be earned" % id)
	TestBase.eq(AmmoDef.earnable_ids().size(), 10, "ten earnable weapons (everything but the stone)")
	TestBase.check(not AmmoDef.ids().has("waterbomb") and not AmmoDef.ids().has("cheese"), "water balloon and cheese are gone")
	TestBase.eq(AmmoDef.get_def("cow").mass, 250.0, "cow mass")
	TestBase.near(AmmoDef.get_def("cow").wind_factor, 0.15, 0.001, "cow wind factor")
	TestBase.near(AmmoDef.get_def("chain").radius, 0.4, 0.001, "chain ball radius")
	TestBase.eq(AmmoDef.get_def("quad").base, "stone", "the stone hail behaves like stones")

func test_constants() -> void:
	TestBase.eq(Cfg.ZONE_RADIUS, 22.0, "zone radius")
	TestBase.eq(Cfg.POWER_MAX_SPEED, 140.0, "max launch speed")
	TestBase.eq(Cfg.CATAPULTS_PER_PLAYER, 5, "catapults per player")
	TestBase.near(Cfg.GRAVITY, -19.62, 0.0001, "gravity")
	TestBase.eq(Cfg.SETTLE_MAX, 8.0, "settle max")
	TestBase.eq(Cfg.SETTLE_TIME, 0.8, "settle time")

func test_util_helpers() -> void:
	TestBase.near(absf(Util.wrap_angle(3.0 * PI)), PI, 0.0001, "wrap_angle")
	TestBase.near(Util.wrap_angle(0.5 + TAU), 0.5, 0.0001, "wrap_angle small")
	var d: Vector3 = Util.yaw_to_dir(0.0)
	TestBase.near(d.z, -1.0, 0.0001, "yaw 0 faces -Z")
	TestBase.near(Util.dir_to_yaw(Util.yaw_to_dir(1.234)), 1.234, 0.0001, "yaw round trip")
	TestBase.eq(Util.format_int(1234567), "1.234.567", "format_int")
	var sh := Util.SpatialHash.new(3.0)
	sh.insert(5, Vector3(1, 1, 1))
	sh.insert(6, Vector3(40, 1, 40))
	var out := PackedInt32Array()
	sh.query(Vector3(0, 0, 0), 4.0, out)
	TestBase.check(out.has(5) and not out.has(6), "spatial hash query")
