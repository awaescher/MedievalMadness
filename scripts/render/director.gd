class_name Director
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Cinema mode (`Settings.cinema`): while somebody else is on turn (CPU or online player) the camera is directed like a film:
## the catapult that is aiming, the flight of the shot from the side and the impact from above the village, from a different
## good angle every turn. Your own turn always uses the normal cameras.

static var _t: float = 0.0
static var _last_phase: int = -1
static var _flight_side: float = 1.0
static var _angle0: float = 0.0
static var _impact_hold: Vector3 = Vector3.INF
static var _flight_fixed: Vector3 = Vector3.INF
static var _orbit_a: float = 0.0
static var _orbit_for: Vector3 = Vector3.INF

## A random event (dragon, geese, fireworks ...) is shown to everybody until the event ends or somebody presses a key
static func event_active() -> bool:
	return RandomEvents.camera_on() and RandomEvents.focus_point() != Vector3.INF

static var _ev_a: float = 0.0
static var _ev_t: float = 0.0

static func event_update(cam: CameraRig, delta: float) -> void:
	var fp: Vector3 = RandomEvents.focus_point()
	if fp == Vector3.INF:
		return
	if _ev_t == 0.0:
		_ev_a = float(Game.turn_number) * 1.7
	_ev_t += delta
	var a: float = _ev_a + _ev_t * 0.08
	var d: float = 44.0
	var pos: Vector3 = fp + Vector3(sin(a) * d, 20.0 + maxf(fp.y - Terrain.h(fp.x, fp.z), 0.0) * 0.3, cos(a) * d)
	cam.cinema(pos, fp, 58.0)

## Is the director in charge of the camera right now?
static func active() -> bool:
	if not Settings.cinema or Game.state != Game.State.BATTLE:
		return false
	var p: PlayerData = Game.cur()
	if p == null:
		return false
	return not (p.is_human() and not p.is_remote())

static func reset() -> void:
	_last_phase = -1
	_land = Vector3.INF
	_orbit_for = Vector3.INF
	_impact_hold = Vector3.INF
	_flight_fixed = Vector3.INF

static func update(cam: CameraRig, delta: float) -> void:
	if event_active() and not Meteor.active():
		event_update(cam, delta)
		return
	_ev_t = 0.0
	if not active() or Meteor.active():
		return
	_t += delta
	var ph: int = Turn.phase
	if ph != _last_phase:
		_last_phase = ph
		_t = 0.0
		var r := Rng.from_string("%d-%d" % [Game.turn_number, ph])
		_flight_side = -1.0 if r.chance(0.5) else 1.0
		_angle0 = r.range_f(0.0, TAU)
		if ph == Turn.Phase.FLIGHT:
			_flight_fixed = Vector3.INF
			_land = Vector3.INF
			_cam_fix = Vector3.INF
		if ph == Turn.Phase.AFTERMATH:
			_impact_hold = Vector3.INF
	var cur: PlayerData = Game.cur()
	var cat: Vector3 = cur.village_center
	if Turn.sel != null and is_instance_valid(Turn.sel):
		cat = Turn.sel.global_pos()
	match ph:
		Turn.Phase.FLIGHT:
			_flight(cam, cat)
		Turn.Phase.AFTERMATH, Turn.Phase.TURN_END:
			_impact(cam, cat)
		_:
			_orbit(cam, cat)

## The catapult on turn, slowly circled from the front-side
static func _orbit(cam: CameraRig, cat: Vector3) -> void:
	if _orbit_for == Vector3.INF or _orbit_for.distance_to(cat) > 1.0:
		_orbit_for = cat
		_orbit_a = _free_angle(cat + Vector3(0, 3.0, 0), _angle0, 14.0)      # a side of the catapult with a clear view
	var a: float = _orbit_a + sin(_t * 0.25) * 0.35
	var pos := cat + Vector3(sin(a) * 13.0, 6.0, cos(a) * 13.0)
	cam.cinema(pos, cat + Vector3(0, 2.0, 0), 55.0)

## The first angle (from `start`, turning round) whose line from `from` outwards is not blocked by a building
static func _free_angle(from: Vector3, start: float, length: float) -> float:
	if not PhysWorld.space.is_valid():
		return start
	for i in 12:
		var a: float = start + float(i) * TAU / 12.0
		var dir := Vector3(sin(a), 0.5, cos(a)).normalized()
		if PhysWorld.raycast(from, dir, length, Cfg.LAYER_STRUCT | Cfg.LAYER_PART).is_empty():
			return a
	return start

## The shot: the camera stands near the place of impact, off to the side and a bit back towards the shooter, so the target area
## is in view before the shot lands and the projectile is seen coming in. Its position is chosen once per shot.
static var _land: Vector3 = Vector3.INF
static var _cam_fix: Vector3 = Vector3.INF

static func _flight(cam: CameraRig, cat: Vector3) -> void:
	var pp: Vector3 = Vector3.INF
	if Projectile.primary != null and Projectile.primary.alive:
		pp = Projectile.primary.position()
	elif Projectile.last_pos != Vector3.INF:
		pp = Projectile.last_pos
	if _land == Vector3.INF and Projectile.primary != null and Projectile.primary.alive:
		var tr: Dictionary = Ballistics.predict(Projectile.primary.position(), Projectile.primary.velocity(), Turn.shot_ammo, Game.wind, 14.0)
		_land = tr["landing"] as Vector3
		if _land == Vector3.INF or _land.distance_to(cat) < 5.0:
			_land = cat + Turn._launch_dir * 40.0
		_cam_fix = _pick_flight_cam(cat)
	if _land == Vector3.INF:
		cam.cinema(cat + Vector3(sin(_angle0) * 14.0, 7.0, cos(_angle0) * 14.0), cat + Vector3(0, 3.0, 0), 58.0)
		return
	var look: Vector3 = _land
	if pp != Vector3.INF:
		look = pp.lerp(_land, clampf(1.0 - pp.distance_to(_land) / maxf(cat.distance_to(_land), 1.0), 0.0, 1.0) * 0.8 + 0.1)
		look.y = maxf(look.y, _land.y)
	cam.cinema(_cam_fix, look + Vector3(0, 1.0, 0), 56.0)

## A good spot: ~38 m from the landing place, off to the side of the path / slightly back towards the shooter, high enough, with a clear line of sight
static func _pick_flight_cam(cat: Vector3) -> Vector3:
	var d: Vector3 = Vector3(_land.x - cat.x, 0.0, _land.z - cat.z)
	if d.length() < 0.01:
		d = Vector3(0, 0, -1)
	d = d.normalized()
	var base: float = atan2(-d.x, -d.z)            # the direction from the landing place back towards the shooter
	var tries: Array = [PI * 0.5, -PI * 0.5, PI * 0.33, -PI * 0.33, PI * 0.75, -PI * 0.75, PI * 0.15, -PI * 0.15]
	var best: Vector3 = Vector3.INF
	for off in tries:
		var a: float = base + float(off) - PI
		var cand: Vector3 = _land + Vector3(sin(a) * 38.0, 0.0, cos(a) * 38.0)
		cand.y = maxf(Terrain.h(cand.x, cand.z), _land.y) + 17.0
		if best == Vector3.INF:
			best = cand
		var clear: bool = true
		if PhysWorld.space.is_valid():
			var from: Vector3 = _land + Vector3(0, 3.0, 0)
			clear = PhysWorld.raycast(from, (cand - from).normalized(), from.distance_to(cand), Cfg.LAYER_STRUCT | Cfg.LAYER_PART).is_empty()
		if clear:
			return cand
	return best

## The impact, from above the village at a changing angle
static func _impact(cam: CameraRig, cat: Vector3) -> void:
	if _impact_hold == Vector3.INF:
		var ip: Vector3 = Vector3.INF
		if not Turn.impact_points.is_empty():
			ip = Turn.impact_points[Turn.impact_points.size() - 1]
		elif Projectile.last_impact_pos != Vector3.INF:
			ip = Projectile.last_impact_pos
		if ip == Vector3.INF:
			ip = cat + Turn._launch_dir * 40.0
		_impact_hold = Turn._impact_focus(ip)
	if _orbit_for != _impact_hold:
		_orbit_for = _impact_hold
		if _cam_fix != Vector3.INF:
			_orbit_a = atan2(_cam_fix.x - _impact_hold.x, _cam_fix.z - _impact_hold.z)          # carry on from the angle of the flight shot
		else:
			_orbit_a = _free_angle(_impact_hold + Vector3(0, 2.0, 0), _angle0, 36.0)
	var a: float = _orbit_a + _t * 0.10
	var dist_i: float = 38.0
	var pos: Vector3 = _impact_hold + Vector3(sin(a) * dist_i, 20.0, cos(a) * dist_i)
	cam.cinema(pos, _impact_hold + Vector3(0, 1.5, 0), 55.0)
