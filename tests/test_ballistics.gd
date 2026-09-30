extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Trajectory prediction and the CPU solver (spec 6.1 / 14 / phase 6): King hits within 3 m without noise,
## Peasant misses > 80% at 60 m.

func _origin(_elev: float, _yaw: float) -> Vector3:
	return Vector3(0, 3.3, 0)

func test_flat_shot_range() -> void:
	# no wind, stone (small drag): 45 degrees at full power travels about v^2/g minus a little
	var vel: Vector3 = Ballistics.launch_velocity(0.0, 45.0, 1.0)
	TestBase.near(vel.length(), Cfg.POWER_MAX_SPEED, 0.001, "full power speed")
	var tr: Dictionary = Ballistics.predict(Vector3(0, 0, 0), vel, "stone", Vector2.ZERO, 12.0)
	var land: Vector3 = tr["landing"] as Vector3
	var d: float = Util.dist_xz(Vector3.ZERO, land)
	var ideal: float = Cfg.POWER_MAX_SPEED * Cfg.POWER_MAX_SPEED / absf(Cfg.GRAVITY)
	TestBase.check(d > ideal * 0.85 and d <= ideal * 1.001, "range %.1f m is close to v^2/g = %.1f m" % [d, ideal])
	TestBase.check(float(tr["flight_time"]) > 4.0 and float(tr["flight_time"]) < 11.0, "flight time is plausible (%.2f s)" % float(tr["flight_time"]))
	# it flies toward -Z for yaw 0
	TestBase.check(land.z < -10.0 and absf(land.x) < 0.5, "yaw 0 flies along -Z")

func test_wind_pushes_the_shot() -> void:
	var vel: Vector3 = Ballistics.launch_velocity(0.0, 45.0, 0.8)
	var calm: Vector3 = Ballistics.predict(Vector3(0, 3, 0), vel, "stone", Vector2.ZERO)["landing"] as Vector3
	var windy: Vector3 = Ballistics.predict(Vector3(0, 3, 0), vel, "stone", Vector2(8.0, 0.0))["landing"] as Vector3
	TestBase.check(windy.x > calm.x + 1.0, "wind along +X pushes the landing to +X (%.1f vs %.1f)" % [windy.x, calm.x])
	# light ammo is affected more than a cow
	var cow: Vector3 = Ballistics.predict(Vector3(0, 3, 0), vel, "cow", Vector2(8.0, 0.0))["landing"] as Vector3
	var cow_calm: Vector3 = Ballistics.predict(Vector3(0, 3, 0), vel, "cow", Vector2.ZERO)["landing"] as Vector3
	var marker: Vector3 = Ballistics.predict(Vector3(0, 3, 0), vel, "meteor", Vector2(8.0, 0.0))["landing"] as Vector3
	var marker_calm: Vector3 = Ballistics.predict(Vector3(0, 3, 0), vel, "meteor", Vector2.ZERO)["landing"] as Vector3
	TestBase.check(absf(marker.x - marker_calm.x) > absf(cow.x - cow_calm.x), "the meteor marker drifts more than the cow")

func test_solver_finds_power() -> void:
	for dist in [20.0, 45.0, 70.0, 95.0]:
		var p: float = Ballistics.solve_power(Vector3(0, 3.3, 0), 0.0, 45.0, dist, "stone", Vector2.ZERO)
		TestBase.check(p > 0.0 and p <= 1.0, "power exists for %.0f m (%.2f)" % [dist, p])
		var land: Vector3 = Ballistics.landing(Vector3(0, 3.3, 0), 0.0, 45.0, p, "stone", Vector2.ZERO)
		TestBase.near(Util.dist_xz(Vector3(0, 3.3, 0), land), dist, 0.6, "solved landing distance %.0f m" % dist)
	TestBase.check(Ballistics.solve_power(Vector3(0, 3.3, 0), 0.0, 45.0, 2500.0, "stone", Vector2.ZERO) < 0.0, "out of range is reported")
	TestBase.check(Ballistics.solve_power(Vector3(0, 3.3, 0), 0.0, 45.0, 9000.0, "stone", Vector2.ZERO) < 0.0, "absurd range is reported")

func test_king_accuracy_without_noise() -> void:
	var r := Rng.from_string("king-test")
	var total_err: float = 0.0
	var worst: float = 0.0
	var n: int = 24
	var fn := Callable(self, "_origin")
	for i in n:
		var ang: float = r.range_f(0.0, TAU)
		var dist: float = r.range_f(25.0, 90.0)
		var target := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var res: Dictionary = Ballistics.solve_sample(fn, Vector3.ZERO, target, "stone", Vector2.ZERO, r.range_f(25.0, 65.0), 0.0)
		total_err += float(res["err"])
		worst = maxf(worst, float(res["err"]))
	TestBase.check(total_err / float(n) < 3.0, "King hits within 3 m on average (mean %.2f m)" % (total_err / float(n)))
	TestBase.check(worst < 6.0, "no wild misses (worst %.2f m)" % worst)

func test_king_compensates_wind() -> void:
	var r := Rng.from_string("wind-test")
	var fn := Callable(self, "_origin")
	var wind := Vector2(6.0, -4.0)
	var total: float = 0.0
	for i in 12:
		var ang: float = r.range_f(0.0, TAU)
		var dist: float = r.range_f(30.0, 85.0)
		var target := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var res: Dictionary = Ballistics.solve_sample(fn, Vector3.ZERO, target, "stone", wind, 45.0, 0.0)
		total += float(res["err"])
	TestBase.check(total / 12.0 < 3.0, "wind-aware solve stays accurate (mean %.2f m)" % (total / 12.0))

func test_peasant_misses_at_60m() -> void:
	# Peasant: 14 degrees aim noise, 25% power noise, ignores wind; "hit" = within 3 m
	var r := Rng.from_string("peasant-test")
	var fn := Callable(self, "_origin")
	var hits: int = 0
	var n: int = 300
	var target := Vector3(0, 0, -60.0)
	for i in n:
		var res: Dictionary = Ballistics.solve_sample(fn, Vector3.ZERO, target, "stone", Vector2.ZERO, r.range_f(28.0, 60.0), 0.0)
		var yaw: float = float(res["yaw"]) + deg_to_rad(r.gauss() * 14.0)
		var power: float = clampf(float(res["power"]) * (1.0 + r.gauss() * 0.25), 0.1, 1.0)
		var land: Vector3 = Ballistics.landing(Vector3(0, 3.3, 0), yaw, float(res["elev"]), power, "stone", Vector2.ZERO)
		if Util.dist_xz(land, target) < 3.0:
			hits += 1
	TestBase.check(float(hits) / float(n) < 0.2, "Peasant misses > 80%% at 60 m (hit rate %.1f%%)" % (100.0 * float(hits) / float(n)))

## Spec 6.1 "Guaranteed range": at full power (best elevation, worst ammo, storm head wind) a shot must out-range the
## largest possible catapult-to-building distance on every generated map by 15%.
func test_max_range_covers_every_map() -> void:
	var worst_range: float = INF
	var head_wind := Vector2(0.0, Cfg.WIND_MAX * 1.8)      # shots fly toward -Z, this wind blows toward +Z (head on)
	for id in AmmoDef.all():
		var a: AmmoDef = id as AmmoDef
		var best: float = 0.0
		for elev in [25.0, 30.0, 35.0, 40.0, 45.0, 50.0]:
			var vel: Vector3 = Ballistics.launch_velocity(0.0, elev, 1.0)
			var tr: Dictionary = Ballistics.predict(Vector3(0, 3.3, 0), vel, a.id, head_wind, 12.0)
			best = maxf(best, Util.dist_xz(Vector3(0, 3.3, 0), tr["landing"] as Vector3))
		worst_range = minf(worst_range, best)
	var worst_need: float = 0.0
	for n in [2, 3, 4, 5, 6, 7, 8]:
		for k in 6:
			var m: MapData = MapGen.generate("range-%d-%d" % [n, k], n)
			for i in m.sites.size():
				for j in range(i + 1, m.sites.size()):
					var d: float = Util.dist_xz(m.sites[i], m.sites[j]) + Cfg.ZONE_RADIUS
					worst_need = maxf(worst_need, d)
	TestBase.check(worst_range >= worst_need * 1.15, "worst-case range %.0f m >= 1.15 x largest distance %.0f m" % [worst_range, worst_need])
	# and the map diagonal for good measure (nothing on the map can be out of reach)
	var diag: float = 2.0 * (60.0 + 14.0 * 8.0)
	TestBase.check(worst_range >= diag, "worst-case range %.0f m covers the largest map diameter %.0f m" % [worst_range, diag])
