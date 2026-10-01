class_name Meteor
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Orbital strike (spec 6.4 "meteor"). The fired marker (a small green glowing ball) calls `start()` where it lands:
## a thin green beam shoots into the sky for WARN_TIME seconds, then a burning meteor falls onto exactly that point
## and blows a huge crater. The cinematic camera (no bullet time) is driven from `camera()`.

const WARN_TIME := 3.6
const FALL_SPEED := 105.0
const START_DIST := 330.0
const RADIUS := 64.0                 # twice the former red barrel (32)
const DAMAGE := 18000.0              # twice the former red barrel (9000)
const BOOM_HOLD := 4.5               # seconds the camera stays on the crater after the blast

static var strikes: Array[Meteor] = []
static var _clock: float = 0.0
static var last_boom: float = -100.0
static var boom_pos: Vector3 = Vector3.INF
static var _last_yaw: float = 0.0

var target: Vector3
var source: Dictionary = {}
var shot_dir: Vector3 = Vector3(0, 0, -1)
var t: float = 0.0
var state: int = 0                   # 0 beam, 1 falling, 2 done
var root: Node3D                     # marker orb + beam + ground disc
var beam: Node3D
var beam_mat: StandardMaterial3D
var core_mat: StandardMaterial3D
var disc: MeshInstance3D
var rock: Node3D
var light: OmniLight3D
var trail: Trail
var dir_in: Vector3
var dist: float = START_DIST
var _fx_acc: float = 0.0
var _snd_acc: float = 0.0
var _cam_pos: Vector3
var _cam_yaw: float = 0.0

static func reset() -> void:
	for m in strikes:
		m._free_nodes()
	strikes.clear()
	_clock = 0.0
	last_boom = -100.0
	boom_pos = Vector3.INF

## A strike is running (marker down, meteor still to come) or has just landed (camera still on the crater)
static func active() -> bool:
	for m in strikes:
		if m.state < 2:
			return true
	return _clock - last_boom < BOOM_HOLD

static func pending() -> bool:
	for m in strikes:
		if m.state < 2:
			return true
	return false

static func start(pos: Vector3, src: Dictionary, dir: Vector3) -> void:
	var m := Meteor.new()
	m.target = pos
	m.source = src
	var fd := Vector3(dir.x, 0.0, dir.z)
	m.shot_dir = fd.normalized() if fd.length() > 0.01 else Vector3(0, 0, -1)
	# the meteor comes in from beyond the target, heading back towards the shooter
	m.dir_in = (-m.shot_dir * 0.5 + Vector3.DOWN).normalized()
	m._cam_yaw = atan2(-m.shot_dir.x, -m.shot_dir.z) + 0.55
	m._build_marker()
	strikes.append(m)
	Events.banner.emit(I18n.t("banner.meteor"), "fire")
	Sfx.play("stinger_event", pos, 0.7, 5)

func _build_marker() -> void:
	if Game.world == null or not is_instance_valid(Game.world.fx_root):
		return
	root = Node3D.new()
	Game.world.fx_root.add_child(root)
	root.global_position = target
	# the marker orb
	var orb := MeshInstance3D.new()
	orb.mesh = MeshGen.sphere_mesh(0.32, 8, 12)
	orb.material_override = Toon.emissive(Color("#35ff86"), 2.5, false)
	orb.position = Vector3(0, 0.35, 0)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(orb)
	var halo := MeshInstance3D.new()
	halo.mesh = MeshGen.sphere_mesh(0.8, 8, 12)
	halo.material_override = Toon.unlit(Color(0.2, 1.0, 0.5, 0.22), true)
	halo.position = Vector3(0, 0.35, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	# the beam (pivot at the ground so it can grow upwards) with a thin bright core
	beam = Node3D.new()
	root.add_child(beam)
	beam.scale = Vector3(1, 0.01, 1)
	beam_mat = _beam_material(Color(0.25, 1.0, 0.6, 0.3))
	core_mat = _beam_material(Color(0.8, 1.0, 0.9, 0.85))
	var bm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.34
	cm.height = 480.0
	cm.radial_segments = 14
	cm.rings = 1
	bm.mesh = cm
	bm.material_override = beam_mat
	bm.position = Vector3(0, 240.0, 0)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bm.extra_cull_margin = 300.0
	beam.add_child(bm)
	var core := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.04
	cc.bottom_radius = 0.07
	cc.height = 480.0
	cc.radial_segments = 8
	cc.rings = 1
	core.mesh = cc
	core.material_override = core_mat
	core.position = Vector3(0, 240.0, 0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.extra_cull_margin = 300.0
	beam.add_child(core)
	# glowing disc on the ground that pulses faster as the strike nears
	disc = MeshInstance3D.new()
	disc.mesh = MeshGen.ring_mesh(2.2, 3.0, 40)
	disc.material_override = Toon.unlit(Color(0.3, 1.0, 0.6, 0.55), true)
	disc.position = Vector3(0, 0.15, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)

static func _beam_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.albedo_color = c
	return mat

func _spawn_rock() -> void:
	if Game.world == null or not is_instance_valid(Game.world.fx_root):
		return
	rock = Node3D.new()
	Game.world.fx_root.add_child(rock)
	var geo: Dictionary = Projectile._boulder_geometry(Rng.new(int(Time.get_ticks_usec() & 0xffff)), 3.6)
	var mi := MeshInstance3D.new()
	mi.mesh = geo["mesh"] as ArrayMesh
	mi.material_override = Toon.emissive(Color("#ff6a1a"), 1.6, false)
	mi.set_instance_shader_parameter("glow", 0.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rock.add_child(mi)
	light = OmniLight3D.new()
	light.light_color = Color("#ff9a4a")
	light.light_energy = 6.0
	light.omni_range = 140.0
	rock.add_child(light)
	trail = Trail.new()
	trail.max_points = 70
	trail.width = 5.0
	trail.color = Color(1.0, 0.55, 0.2, 0.85)
	Game.world.fx_root.add_child(trail)
	rock.global_position = target - dir_in * dist
	Sfx.play("whoosh", target, 1.0, 5)

func _free_nodes() -> void:
	for n in [root, rock, trail]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	root = null
	rock = null
	trail = null

static func tick_all(dt: float) -> void:
	_clock += dt
	var i: int = strikes.size() - 1
	while i >= 0:
		var m: Meteor = strikes[i]
		m._tick(dt)
		if m.state >= 2:
			strikes.remove_at(i)
		i -= 1

func _tick(dt: float) -> void:
	if state >= 2:
		return
	t += dt
	if state == 0:
		var grow: float = clampf(t / 0.6, 0.0, 1.0)
		if beam != null:
			beam.scale = Vector3(1, maxf(grow, 0.01), 1)
			var pulse: float = 0.5 + 0.5 * sin(t * (6.0 + t * 3.0))
			beam_mat.albedo_color.a = 0.22 + 0.2 * pulse
			core_mat.albedo_color.a = 0.6 + 0.3 * pulse
		if disc != null:
			var k: float = 1.0 + 0.25 * sin(t * (5.0 + t * 4.0))
			disc.scale = Vector3(k, 1, k)
		if t >= WARN_TIME:
			state = 1
			_spawn_rock()
		return
	# falling
	dist -= FALL_SPEED * dt
	var p: Vector3 = target - dir_in * maxf(dist, 0.0)
	if rock != null:
		rock.global_position = p
		rock.rotate_y(dt * 2.0)
		rock.rotate_x(dt * 1.3)
		_fx_acc += dt
		if _fx_acc >= 0.05:
			_fx_acc = 0.0
			Fx.burst("flame", p, Color(0, 0, 0, -1), 2.0)
			if Quality.current_id != "low":
				Fx.burst("smoke", p - dir_in * 3.0, Color(0, 0, 0, -1), 0.9)
		_snd_acc += dt
		if _snd_acc >= 0.55:
			_snd_acc = 0.0
			Sfx.play("whoosh", p, clampf(1.0 - dist / START_DIST + 0.3, 0.3, 1.2), 4)
		if trail != null:
			trail.push(p)
		if light != null:
			light.light_energy = 6.0 + 10.0 * (1.0 - clampf(dist / 120.0, 0.0, 1.0))
	# the sky rumbles harder the closer it gets
	if dist < 140.0:
		Events.camera_shake.emit(clampf((140.0 - dist) / 140.0, 0.0, 1.0) * 0.35)
	if disc != null:
		var k2: float = 1.0 + 0.35 * sin(t * 18.0)
		disc.scale = Vector3(k2, 1, k2)
	if dist <= 0.0:
		_impact()

func _impact() -> void:
	state = 2
	last_boom = _clock
	boom_pos = target
	Explosion.explode(target, RADIUS, DAMAGE, {"source": source, "sound": "bigboom", "fire": true, "color": Color("#ff7a2a"), "cat_scale": 0.12, "no_crater": true, "no_slowmo": true})
	# the fat crater with a raised rim; steep surroundings slide into it
	if Terrain.current != null:
		Terrain.current.dig(target, 30.0, 12.0, 1.0, 0.85, 3.2)
		Landslide.trigger(target, 18.0, source)
	Fx.burst("flame", target + Vector3.UP * 2.0, Color(0, 0, 0, -1), 3.0)
	Fx.burst("dust", target + Vector3.UP, Color("#6b5a44"), 2.5, Vector3.UP)
	Fx.burst("smoke", target + Vector3.UP * 6.0, Color(0, 0, 0, -1), 2.0)
	Fx.comic_kind("explosion", target + Vector3.UP * 28.0)
	Events.banner.emit(I18n.t("banner.meteor_boom"), "fire")
	Events.camera_shake.emit(1.5)
	Projectile.spawn_embers(target + Vector3.UP * 2.0, source, 22)
	Projectile.release_stuck_logs(target, RADIUS * 0.8)
	if trail != null and is_instance_valid(trail):
		trail.stop()
	if rock != null and is_instance_valid(rock):
		rock.queue_free()
	rock = null
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null

## Cinematic camera of the newest strike (called by the turn manager every physics tick). No bullet time.
static func camera(cam: CameraRig, dt: float) -> void:
	if cam == null or strikes.is_empty():
		if cam != null and boom_pos != Vector3.INF and _clock - last_boom < BOOM_HOLD:
			_boom_cam(cam, dt)
		return
	var m: Meteor = strikes[strikes.size() - 1]
	m._camera(cam, dt)

func _camera(cam: CameraRig, dt: float) -> void:
	if state == 0:
		# a slow orbit round the beam, the view tilting up along it
		var u: float = clampf(t / WARN_TIME, 0.0, 1.0)
		var yaw: float = _cam_yaw + u * 0.55
		_last_yaw = yaw
		var r: float = lerpf(66.0, 54.0, u)
		_cam_pos = target + Vector3(sin(yaw) * r, 3.0 + u * 5.0, cos(yaw) * r)
		var aim: Vector3 = target + Vector3(0, lerpf(6.0, 70.0, u * u), 0)
		cam.cinema(_cam_pos, aim, lerpf(62.0, 54.0, u))
	else:
		# the camera stays where it is and follows the falling rock, in the last moments down to the point of impact
		var look: Vector3 = target - dir_in * maxf(dist, 0.0)
		var low: float = clampf(1.0 - dist / 90.0, 0.0, 1.0)
		look = look.lerp(target + Vector3(0, 4.0, 0), low * low)
		cam.cinema(_cam_pos, look, lerpf(54.0, 46.0, clampf(1.0 - dist / START_DIST, 0.0, 1.0)))

static func _boom_cam(cam: CameraRig, dt: float) -> void:
	var u: float = clampf((_clock - last_boom) / BOOM_HOLD, 0.0, 1.0)
	if cam.mode != CameraRig.Mode.IMPACT:
		cam.mode = CameraRig.Mode.IMPACT
		cam.focus = boom_pos
		cam.dist = 72.0
		cam.pitch = deg_to_rad(22.0)
		cam.yaw = _last_yaw
	cam.focus = boom_pos + Vector3(0, 6.0, 0)
	cam.dist = lerpf(cam.dist, 120.0, dt * 0.35)
	cam.pitch = lerpf(cam.pitch, deg_to_rad(34.0), dt * 0.3)
	cam.yaw += dt * 0.12 * (1.0 - u * 0.5)
