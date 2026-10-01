class_name CameraRig
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Camera rig with modes: OVERVIEW (free orbit), AIM (chase), FOLLOW (projectile), IMPACT,
## FOCUS (fixed orbit target, e.g. placement), REPLAY, ORBIT (menu attract). Spec 6.1 / 18.2.

enum Mode { OVERVIEW, AIM, FOLLOW, IMPACT, FOCUS, ORBIT, CINEMA }

var cam: Camera3D
var mode: int = Mode.OVERVIEW

# smoothed actual state
var _pos: Vector3 = Vector3(0, 60, 60)
var _target: Vector3 = Vector3.ZERO
var _fov: float = 60.0
var _inited: bool = false

# orbit state (OVERVIEW / FOCUS / IMPACT / REPLAY / ORBIT)
var focus: Vector3 = Vector3.ZERO
var yaw: float = 0.6
var pitch: float = deg_to_rad(45.0)
var dist: float = 70.0
var _focus_smooth: Vector3 = Vector3.ZERO
var _dist_smooth: float = 70.0

# aim state
var aim_pos: Vector3 = Vector3.ZERO
var aim_yaw: float = 0.0
var aim_elev: float = 0.3
var aim_off_yaw: float = 0.0            # user orbit offsets (right drag)
var aim_off_pitch: float = 0.0
var aim_dist: float = 11.0
var _aim_yaw_smooth: float = 0.0
var aim_hold: bool = false              # freeze the chase yaw (while the player pulls the slingshot)

# cinema state (scripted shots, e.g. the meteor)
var cin_pos: Vector3 = Vector3.ZERO
var cin_target: Vector3 = Vector3.ZERO
var cin_fov: float = 60.0

# follow state
var follow_pos: Vector3 = Vector3.ZERO
var follow_vel: Vector3 = Vector3.ZERO
var _follow_dir: Vector3 = Vector3(0, 0, -1)

# shake
var shake_amount: float = 0.0
var shake_enabled: bool = true
var _shake_t: float = 0.0
var damping_k: float = 4.0
var _snap: bool = false
var min_height: float = 1.0
var map_limit: float = 200.0
var max_dist: float = 420.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.current = true
	cam.near = 0.15
	cam.far = 1500.0
	cam.fov = 60.0
	add_child(cam)

func snap() -> void:
	_snap = true

func set_mode(m: int) -> void:
	mode = m

# ------------------------------------------------------------ mode helpers
func overview(f: Vector3, d: float = 80.0, p_deg: float = 50.0) -> void:
	mode = Mode.OVERVIEW
	focus = f
	dist = d
	pitch = deg_to_rad(p_deg)

func focus_on(f: Vector3, d: float = 45.0, p_deg: float = 42.0, yaw_rad: float = NAN) -> void:
	mode = Mode.FOCUS
	focus = f
	dist = d
	pitch = deg_to_rad(p_deg)
	if not is_nan(yaw_rad):
		yaw = yaw_rad

func start_orbit(f: Vector3, d: float, p_deg: float) -> void:
	mode = Mode.ORBIT
	focus = f
	dist = d
	pitch = deg_to_rad(p_deg)

func aim_at(p: Vector3, yaw_rad: float, elev_rad: float) -> void:
	if mode != Mode.AIM:
		mode = Mode.AIM
		aim_off_yaw = 0.0
		aim_off_pitch = 0.0
		_aim_yaw_smooth = yaw_rad
	aim_pos = p
	aim_yaw = yaw_rad
	aim_elev = elev_rad

## Scripted shot: the camera goes to `p` and looks at `t` (smoothed)
func cinema(p: Vector3, t: Vector3, fov_deg: float = 60.0) -> void:
	mode = Mode.CINEMA
	cin_pos = p
	cin_target = t
	cin_fov = fov_deg

func follow_projectile(p: Vector3, v: Vector3) -> void:
	if mode != Mode.FOLLOW:
		mode = Mode.FOLLOW
		if v.length() > 0.5:
			_follow_dir = v.normalized()
	follow_pos = p
	follow_vel = v

## Impact camera. With `shot_dir` it is set up once: behind the shot looking along it, high enough to see the whole
## village around the impact; without it only the focus point moves (rolling barrels) and the angle stays put.
func impact_cam(p: Vector3, shot_dir: Vector3 = Vector3.ZERO) -> void:
	var fresh: bool = shot_dir.length() > 0.01
	mode = Mode.IMPACT
	focus = p
	if fresh:
		var fd := Vector3(shot_dir.x, 0.0, shot_dir.z)
		if fd.length() > 0.01:
			yaw = atan2(-fd.x, -fd.z)
		dist = 34.0
		pitch = deg_to_rad(44.0)

# ------------------------------------------------------------ input
func orbit_drag(dx: float, dy: float) -> void:
	match mode:
		Mode.AIM:
			aim_off_yaw = clampf(aim_off_yaw - dx * 0.006, deg_to_rad(-60.0), deg_to_rad(60.0))
			aim_off_pitch = clampf(aim_off_pitch + dy * 0.005, deg_to_rad(-25.0), deg_to_rad(25.0))
		_:
			yaw -= dx * 0.006
			pitch = clampf(pitch + dy * 0.005, deg_to_rad(8.0), deg_to_rad(88.0))

func zoom(steps: float) -> void:
	match mode:
		Mode.AIM:
			aim_dist = clampf(aim_dist * pow(0.86, steps), 4.0, 260.0)
		_:
			dist = clampf(dist * pow(0.9, steps), 12.0, max_dist)

func pan(dx: float, dz: float) -> void:
	# camera-relative pan on the ground plane
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var pan_scale: float = dist * 0.0022
	focus += (-right * dx + fwd * dz) * pan_scale
	focus.x = clampf(focus.x, -map_limit, map_limit)
	focus.z = clampf(focus.z, -map_limit, map_limit)

func pan_world(v: Vector3) -> void:
	focus += v
	focus.x = clampf(focus.x, -map_limit, map_limit)
	focus.z = clampf(focus.z, -map_limit, map_limit)

func recenter(f: Vector3) -> void:
	focus = f

func shake(amount: float) -> void:
	if not shake_enabled:
		return
	shake_amount = maxf(shake_amount, minf(amount, 1.5))

# ------------------------------------------------------------ update
func _orbit_pos(f: Vector3, d: float, yaw_r: float, pitch_r: float) -> Vector3:
	var horiz: float = cos(pitch_r) * d
	return f + Vector3(sin(yaw_r) * horiz, sin(pitch_r) * d, cos(yaw_r) * horiz)

func update(delta: float) -> void:
	var dt: float = minf(delta, 1.0 / 20.0)
	var want_pos: Vector3
	var want_target: Vector3
	var want_fov: float = 60.0
	var k: float = damping_k
	match mode:
		Mode.AIM:
			if not aim_hold:
				_aim_yaw_smooth = lerp_angle(_aim_yaw_smooth, aim_yaw, Util.damp(5.0, dt))
			var back_yaw: float = _aim_yaw_smooth + aim_off_yaw
			var fwd: Vector3 = Util.yaw_to_dir(back_yaw)
			# zoomed far out the camera climbs steeply and looks further ahead: a map view with the catapult in it
			var far_k: float = maxf(aim_dist - 16.0, 0.0)
			var up_h: float = 6.0 + aim_dist * 0.1 + far_k * 0.8 + aim_off_pitch * 10.0
			want_pos = aim_pos - fwd * aim_dist + Vector3.UP * up_h
			want_target = aim_pos + fwd * (8.0 + far_k * 0.45) + Vector3.UP * (0.5 + aim_elev * 1.5)
			want_fov = 65.0
			k = 7.0
		Mode.FOLLOW:
			if follow_vel.length() > 1.0:
				_follow_dir = _follow_dir.lerp(follow_vel.normalized(), Util.damp(3.0, dt)).normalized()
			want_pos = follow_pos - _follow_dir * 9.0 + Vector3.UP * 4.2
			want_target = follow_pos + _follow_dir * 6.0
			want_fov = 68.0
			k = 6.0
		Mode.IMPACT:
			want_pos = _orbit_pos(focus, dist, yaw, pitch)
			want_target = focus + Vector3.UP * 1.5
			k = 4.0
		Mode.CINEMA:
			want_pos = cin_pos
			want_target = cin_target
			want_fov = cin_fov
			k = 5.0
		Mode.ORBIT:
			yaw += dt * 0.05
			want_pos = _orbit_pos(focus, dist, yaw, pitch)
			want_target = focus
			k = 3.0
		_:
			# OVERVIEW / FOCUS
			want_pos = _orbit_pos(focus, dist, yaw, pitch)
			want_target = focus
			k = 5.0
	# keep the camera out of buildings: shorten the arm when something solid is in the way
	var arm_origin: Vector3 = want_target
	if mode == Mode.AIM:
		arm_origin = aim_pos + Vector3(0, 2.2, 0)
	elif mode == Mode.FOLLOW:
		arm_origin = follow_pos
	if PhysWorld.space.is_valid() and (mode == Mode.AIM or mode == Mode.FOLLOW):
		var arm: Vector3 = want_pos - arm_origin
		var alen: float = arm.length()
		if alen > 2.0:
			var hit: Dictionary = PhysWorld.raycast(arm_origin, arm / alen, alen, Cfg.LAYER_STRUCT | Cfg.LAYER_PART)
			if not hit.is_empty():
				var hd: float = arm_origin.distance_to(hit["point"] as Vector3)
				want_pos = arm_origin + arm / alen * maxf(hd - 0.9, alen * 0.6)
	if not _inited or _snap:
		_pos = want_pos
		_target = want_target
		_fov = want_fov
		_inited = true
		_snap = false
	else:
		var f: float = Util.damp(k, dt)
		_pos = _pos.lerp(want_pos, f)
		_target = _target.lerp(want_target, f)
		_fov = lerpf(_fov, want_fov, Util.damp(4.0, dt))
	var p: Vector3 = _pos
	# never enter terrain / go below terrain + 1
	if Terrain.current != null:
		var gh: float = Terrain.h(p.x, p.z)
		p.y = maxf(p.y, maxf(gh, Cfg.WATER_LEVEL) + min_height)
	var fwd: Vector3 = (_target - p)
	var cam_up: Vector3 = Vector3.UP if fwd.length() < 0.001 or absf(fwd.normalized().y) < 0.995 else Vector3.FORWARD
	var xf := Transform3D(Basis(), p).looking_at(_target if fwd.length() > 0.001 else p + Vector3.FORWARD, cam_up)
	# shake
	if shake_amount > 0.001:
		_shake_t += dt * 45.0
		var s: float = shake_amount
		var off := Vector3(sin(_shake_t * 1.3) + sin(_shake_t * 2.9) * 0.5, sin(_shake_t * 1.7 + 1.0) + sin(_shake_t * 3.3) * 0.5, sin(_shake_t * 2.1 + 2.0)) * s * 0.35
		xf.origin += xf.basis * off
		xf.basis = xf.basis * Basis.from_euler(Vector3(off.y * 0.01, off.x * 0.01, off.z * 0.02))
		shake_amount = move_toward(shake_amount, 0.0, dt * 1.6 * (0.5 + shake_amount))
	cam.global_transform = xf
	cam.fov = _fov

func camera_position() -> Vector3:
	return cam.global_position

func project(p: Vector3) -> Vector2:
	return cam.unproject_position(p)

func is_behind(p: Vector3) -> bool:
	return cam.is_position_behind(p)

func ray_from_screen(pos: Vector2) -> Dictionary:
	return {"origin": cam.project_ray_origin(pos), "dir": cam.project_ray_normal(pos)}
