class_name Ballistics
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Pure ballistic helpers (no autoloads, headless-testable): launch velocity, flight prediction with gravity, wind
## and per-ammo drag (terrain only), and the solver used by the CPU bots. `Turn.predict_trajectory` delegates here.

static func launch_velocity(yaw: float, elev_deg: float, power: float) -> Vector3:
	var speed: float = lerpf(Cfg.POWER_MIN_SPEED, Cfg.POWER_MAX_SPEED, clampf(power, 0.0, 1.0))
	var e: float = deg_to_rad(elev_deg)
	var h: Vector3 = Util.yaw_to_dir(yaw)
	return Vector3(h.x * cos(e), sin(e), h.z * cos(e)) * speed

## Simulates the flight at the physics rate. Returns {points: PackedVector3Array, flight_time, landing}
static func predict(start_pos: Vector3, velocity: Vector3, ammo_id: String, wind: Vector2, max_t: float = 12.0) -> Dictionary:
	var a: AmmoDef = AmmoDef.get_def(ammo_id)
	var dt: float = 1.0 / 60.0
	var pos: Vector3 = start_pos
	var v: Vector3 = velocity
	var accel_w := Vector3(wind.x, 0.0, wind.y) * Cfg.WIND_ACCEL_FACTOR * a.wind_factor
	var pts := PackedVector3Array()
	pts.append(pos)
	var t: float = 0.0
	var step: int = 0
	var landing: Vector3 = pos
	var landed: bool = false
	var damp: float = maxf(0.0, 1.0 - a.drag * dt)
	while t < max_t:
		v += (Vector3(0.0, Cfg.GRAVITY, 0.0) + accel_w) * dt
		v *= damp
		var npos: Vector3 = pos + v * dt
		t += dt
		step += 1
		var gh: float = Terrain.h(npos.x, npos.z)
		if npos.y < gh and t > 0.1:
			var f: float = clampf((pos.y - gh) / maxf(pos.y - npos.y, 0.0001), 0.0, 1.0)
			landing = pos.lerp(npos, f)
			pts.append(landing)
			landed = true
			break
		pos = npos
		if step % 3 == 0:
			pts.append(pos)
	if not landed:
		landing = pos
		pts.append(pos)
	return {"points": pts, "flight_time": t, "landing": landing}

static func landing(origin: Vector3, yaw: float, elev: float, power: float, ammo: String, wind: Vector2) -> Vector3:
	var vel: Vector3 = launch_velocity(yaw, elev, power)
	var tr: Dictionary = predict(origin, vel, ammo, wind, 12.0)
	return tr["landing"] as Vector3

## Bisection on power so the flat landing distance matches `dist`. Returns power in (0,1] or -1 if out of range.
static func solve_power(origin: Vector3, yaw: float, elev: float, dist: float, ammo: String, wind: Vector2) -> float:
	var lo: float = 0.04
	var hi: float = 1.0
	var far: Vector3 = landing(origin, yaw, elev, hi, ammo, wind)
	if Util.dist_xz(origin, far) < dist:
		return -1.0
	for i in 16:
		var mid: float = (lo + hi) * 0.5
		var l: Vector3 = landing(origin, yaw, elev, mid, ammo, wind)
		if Util.dist_xz(origin, l) < dist:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

## Signed lateral error (m) of a landing relative to the aim line (positive = landed right of the line)
static func lateral(origin: Vector3, land: Vector3, target: Vector3) -> float:
	var d: Vector3 = Util.flat(target - origin).normalized()
	var e: Vector3 = Util.flat(land - target)
	return d.x * e.z - d.z * e.x

## Full solve for one elevation sample. `origin_fn(elev, yaw) -> Vector3` gives the release point.
## Returns {yaw, elev, power, err} where err = horizontal miss distance of the predicted landing.
static func solve_sample(origin_fn: Callable, shooter_pos: Vector3, target: Vector3, ammo: String, wind: Vector2, elev: float, yaw_jitter: float) -> Dictionary:
	var heading: float = Util.dir_to_yaw(Util.flat(target - shooter_pos))
	var yaw: float = heading + yaw_jitter
	var origin: Vector3 = origin_fn.call(elev, yaw) as Vector3
	var dist: float = Util.dist_xz(origin, target)
	var power: float = solve_power(origin, yaw, elev, dist, ammo, wind)
	if power < 0.0:
		return {"err": 1e9, "yaw": yaw, "elev": elev, "power": 1.0}
	for it in 2:
		origin = origin_fn.call(elev, yaw) as Vector3
		var l0: Vector3 = landing(origin, yaw, elev, power, ammo, wind)
		var e0: float = lateral(origin, l0, target)
		if absf(e0) < 0.15:
			break
		var dy: float = 0.012
		var l1: Vector3 = landing(origin_fn.call(elev, yaw + dy) as Vector3, yaw + dy, elev, power, ammo, wind)
		var e1: float = lateral(origin, l1, target)
		var slope: float = (e1 - e0) / dy
		if absf(slope) > 0.5:
			yaw -= e0 / slope
		origin = origin_fn.call(elev, yaw) as Vector3
		dist = Util.dist_xz(origin, target)
		var p2: float = solve_power(origin, yaw, elev, dist, ammo, wind)
		if p2 > 0.0:
			power = p2
	origin = origin_fn.call(elev, yaw) as Vector3
	var fin: Vector3 = landing(origin, yaw, elev, power, ammo, wind)
	return {"err": Util.dist_xz(fin, target), "yaw": yaw, "elev": elev, "power": power}
