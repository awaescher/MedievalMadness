class_name Catapult
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Catapult entity (spec 16.3 / 6.6): procedural model, one dynamic base body, animated arm,
## hp 100, fire/tip/drown handling, destruction into dynamic parts.

signal released

const HP_MAX := 100.0
const ARM_LEN_UP := 2.3
const PIVOT := Vector3(0, 1.35, 0.15)

static var _bar_shader: Shader
static var _ring_mesh: Mesh
static var _quad: QuadMesh

var player: PlayerData
var player_id: int = -1
var hp: float = HP_MAX
var destroyed: bool = false
var body_id: int = 0
var yaw: float = 0.0
var elevation_deg: float = Cfg.DEFAULT_ELEVATION
var power: float = 0.0
var selected: bool = false
var burning: bool = false
var index: int = 0

var arm_pivot: Node3D
var arm_angle: float = -0.17
var _pull: float = 0.0
var _fire_t: float = -1.0
var _fire_from: float = 0.0
var _fire_to: float = 0.0
var _released_flag: bool = false
var _rope: MeshInstance3D
var _ammo_vis: MeshInstance3D
var _bar: MeshInstance3D
var _bar_timer: float = 0.0
var _ring: MeshInstance3D
var _plate: Label3D
var _tip_time: float = 0.0
var _water_time: float = 0.0
var _fire_exposure: float = 0.0
var _flame: Fx.Flame
var _burn_t: float = 0.0
var _buried_t: float = 0.0
var _pos_cache: Vector3 = Vector3.ZERO
var _sleep_check: float = 0.0
var last_source: Dictionary = {}
var damaged_recently: float = 0.0
var placed_ghost: bool = false

# ---------------------------------------------------------------- construction
func setup(p: PlayerData, ground_pos: Vector3, yaw_rad: float) -> void:
	player = p
	player_id = p.id
	yaw = yaw_rad
	name = "Catapult_%d" % p.id
	var col: Color = p.color
	_build_model(col)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(ground_pos.x, ground_pos.y + 0.03, ground_pos.z))
	transform = xf
	_pos_cache = xf.origin
	var d := PhysWorld.BodyDesc.new()
	d.shapes.append(PhysWorld.box_desc(Vector3(1.9, 0.9, 2.4), Transform3D(Basis(), Vector3(0, 0.47, 0))))
	d.xf = xf
	d.mass = 400.0
	d.friction = 0.8
	d.bounce = 0.05
	d.layer = Cfg.LAYER_CATAPULT
	d.mask = Cfg.LAYER_ALL
	d.kind = "catapult"
	d.owner = self
	d.visual = self
	d.damp_lin = 0.3
	d.damp_ang = 0.6
	d.sleeping = true
	body_id = PhysWorld.add_body(d)
	set_selected(false)

func _mat_col(col: Color) -> ShaderMaterial:
	return Toon.colored(col)

func _build_model(player_col: Color) -> void:
	var frame := MeshGen.Buf.new()
	var wood: Color = Color("#b5763a")
	var dark: Color = Color("#8a5a2a")
	var plank: Color = Color("#c48748")
	# base frame
	for sx in [-0.62, 0.62]:
		MeshGen.add_box(frame, Vector3(0.24, 0.26, 2.5), Transform3D(Basis(), Vector3(sx as float, 0.62, 0.0)), wood)
	for sz in [-0.9, 0.0, 0.95]:
		MeshGen.add_box(frame, Vector3(1.4, 0.2, 0.22), Transform3D(Basis(), Vector3(0, 0.62, sz as float)), dark)
	# wheels (axis along X)
	var wheel_rot := Basis(Vector3(0, 0, 1), PI * 0.5)
	for sx2 in [-0.93, 0.93]:
		for sz2 in [-0.78, 0.78]:
			MeshGen.add_cyl(frame, 0.5, 0.16, 12, Transform3D(wheel_rot, Vector3(sx2 as float, 0.5, sz2 as float)), Color("#8a5a2a"))
			MeshGen.add_cyl(frame, 0.16, 0.24, 8, Transform3D(wheel_rot, Vector3(sx2 as float * 1.04, 0.5, sz2 as float)), Color("#7f8c9a"))
	# axles
	for sz3 in [-0.78, 0.78]:
		MeshGen.add_cyl(frame, 0.07, 1.9, 8, Transform3D(wheel_rot, Vector3(0, 0.5, sz3 as float)), dark)
	# vertical frames (A-shape) either side of the pivot
	for sx3 in [-0.5, 0.5]:
		var lean_a := Basis(Vector3(1, 0, 0), 0.32)
		var lean_b := Basis(Vector3(1, 0, 0), -0.32)
		MeshGen.add_box(frame, Vector3(0.18, 1.5, 0.18), Transform3D(lean_a, Vector3(sx3 as float, 1.35, -0.28 + PIVOT.z)), wood)
		MeshGen.add_box(frame, Vector3(0.18, 1.5, 0.18), Transform3D(lean_b, Vector3(sx3 as float, 1.35, 0.28 + PIVOT.z)), wood)
	MeshGen.add_cyl(frame, 0.09, 1.3, 8, Transform3D(wheel_rot, PIVOT), Color("#7f8c9a"))
	# stop bar (front)
	MeshGen.add_box(frame, Vector3(1.3, 0.14, 0.14), Transform3D(Basis(), Vector3(0, 1.05, -0.95)), plank)
	# crank on the rear side
	MeshGen.add_cyl(frame, 0.08, 0.5, 8, Transform3D(wheel_rot, Vector3(0, 0.85, 1.0)), Color("#7f8c9a"))
	var mi := MeshInstance3D.new()
	mi.mesh = frame.to_mesh()
	mi.material_override = Toon.main()
	add_child(mi)
	# player color accents: flag + rear plate
	var acc := MeshGen.Buf.new()
	MeshGen.add_cyl(acc, 0.05, 1.7, 6, Transform3D(Basis(), Vector3(0.75, 1.45, 1.05)), dark)
	MeshGen.add_box(acc, Vector3(0.04, 0.5, 0.85), Transform3D(Basis(), Vector3(0.75, 2.05, 0.65)), player_col)
	MeshGen.add_box(acc, Vector3(1.0, 0.3, 0.05), Transform3D(Basis(), Vector3(0, 0.62, 1.28)), player_col)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = acc.to_mesh()
	mi2.material_override = Toon.main()
	add_child(mi2)
	# arm assembly
	arm_pivot = Node3D.new()
	arm_pivot.position = PIVOT
	add_child(arm_pivot)
	var arm := MeshGen.Buf.new()
	MeshGen.add_box(arm, Vector3(0.24, 3.3, 0.24), Transform3D(Basis(), Vector3(0, 0.72, 0)), Color("#c58a4a"))
	# counterweight
	MeshGen.add_box(arm, Vector3(0.62, 0.55, 0.62), Transform3D(Basis(), Vector3(0, -0.95, 0)), Color("#7d848c"))
	# bucket at the tip
	var ty: float = ARM_LEN_UP
	MeshGen.add_box(arm, Vector3(0.75, 0.1, 0.75), Transform3D(Basis(), Vector3(0, ty, 0)), Color("#8a5a2a"))
	MeshGen.add_box(arm, Vector3(0.75, 0.32, 0.08), Transform3D(Basis(), Vector3(0, ty + 0.16, 0.34)), Color("#a0622d"))
	MeshGen.add_box(arm, Vector3(0.75, 0.32, 0.08), Transform3D(Basis(), Vector3(0, ty + 0.16, -0.34)), Color("#a0622d"))
	MeshGen.add_box(arm, Vector3(0.08, 0.32, 0.75), Transform3D(Basis(), Vector3(0.34, ty + 0.16, 0)), Color("#a0622d"))
	MeshGen.add_box(arm, Vector3(0.08, 0.32, 0.75), Transform3D(Basis(), Vector3(-0.34, ty + 0.16, 0)), Color("#a0622d"))
	var mi3 := MeshInstance3D.new()
	mi3.mesh = arm.to_mesh()
	mi3.material_override = Toon.main()
	arm_pivot.add_child(mi3)
	# ammo shown in the bucket
	_ammo_vis = MeshInstance3D.new()
	_ammo_vis.position = Vector3(0, ty + 0.35, 0)
	arm_pivot.add_child(_ammo_vis)
	_ammo_vis.visible = false
	# rope from bucket tip to the front hook
	_rope = MeshInstance3D.new()
	_rope.mesh = MeshGen.cyl_mesh(0.03, 1.0, 5)
	_rope.material_override = Toon.colored(Color("#d8c9a0"), false)
	add_child(_rope)
	# selection ring
	if _ring_mesh == null:
		_ring_mesh = MeshGen.ring_mesh(2.3, 2.7, 40)
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring.material_override = Toon.unlit(Color(player_col.r, player_col.g, player_col.b, 0.9), true)
	_ring.position = Vector3(0, 0.05, 0)
	_ring.top_level = true
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.visible = false
	# hp bar
	if _bar_shader == null:
		_bar_shader = load("res://scripts/render/shaders/bar.gdshader") as Shader
		_quad = QuadMesh.new()
		_quad.size = Vector2(2.0, 0.28)
	_bar = MeshInstance3D.new()
	_bar.mesh = _quad
	var bm := ShaderMaterial.new()
	bm.shader = _bar_shader
	_bar.material_override = bm
	_bar.position = Vector3(0, 4.3, 0)
	_bar.top_level = true
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	_bar.visible = false
	# nameplate
	_plate = Label3D.new()
	_plate.text = player.name if player != null else ""
	_plate.font = Speech.ui_font()
	_plate.font_size = 40
	_plate.outline_size = 10
	_plate.modulate = Color(player_col.r * 0.4 + 0.6, player_col.g * 0.4 + 0.6, player_col.b * 0.4 + 0.6)
	_plate.outline_modulate = Color(0.08, 0.05, 0.1)
	_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plate.fixed_size = true
	_plate.pixel_size = 0.0007
	_plate.no_depth_test = true
	_plate.shaded = false
	_plate.top_level = true
	_plate.visible = false
	add_child(_plate)

# ---------------------------------------------------------------- queries
func global_pos() -> Vector3:
	return _pos_cache

func muzzle_pos() -> Vector3:
	return arm_pivot.to_global(Vector3(0, ARM_LEN_UP + 0.35, 0))

func forward() -> Vector3:
	return Util.yaw_to_dir(yaw)

func up_dot() -> float:
	return global_transform.basis.y.y

# ---------------------------------------------------------------- aiming state
func set_selected(on: bool) -> void:
	selected = on
	if _ring != null:
		_ring.visible = on and not destroyed

func set_nameplate_visible(on: bool) -> void:
	if _plate != null:
		_plate.visible = on and not destroyed

func show_hp_bar(seconds: float = 3.0) -> void:
	_bar_timer = seconds
	_update_bar()

func _update_bar() -> void:
	if _bar == null:
		return
	_bar.set_instance_shader_parameter("fill", clampf(hp / HP_MAX, 0.0, 1.0))

var _ammo_id: String = ""

func set_ammo_visual(ammo_id: String) -> void:
	if ammo_id == _ammo_id and _ammo_vis.get_child_count() > 0:
		_ammo_vis.visible = true
		return
	_ammo_id = ammo_id
	for c in _ammo_vis.get_children():
		c.queue_free()
	_ammo_vis.add_child(Projectile.bucket_visual(ammo_id))
	_ammo_vis.visible = true

func hide_ammo_visual() -> void:
	_ammo_vis.visible = false

## Rotate the whole catapult (physics body + visual) to face `yaw_rad`
func set_yaw(yaw_rad: float) -> void:
	if destroyed:
		return
	var d: float = Util.angle_diff(yaw_rad, yaw)
	yaw = yaw_rad
	var xf: Transform3D = PhysWorld.get_transform(body_id)
	xf.basis = Basis(Vector3.UP, d) * xf.basis
	PhysWorld.set_transform(body_id, xf)
	PhysWorld.set_velocity(body_id, Vector3.ZERO, Vector3.ZERO)
	_pos_cache = xf.origin

## pull: 0..1 arm pulled back; elevation only influences where the arm ends after release
func set_pull(amount: float, elev_deg: float) -> void:
	_pull = clampf(amount, 0.0, 1.0)
	elevation_deg = elev_deg
	if _fire_t < 0.0:
		var rest: float = -deg_to_rad(10.0)
		arm_angle = lerpf(rest, deg_to_rad(76.0), _pull)

func rest_arm() -> void:
	_pull = 0.0
	if _fire_t < 0.0:
		arm_angle = -deg_to_rad(10.0)

## Swing the arm; emits `released` mid-swing (when the projectile should leave the bucket)
func play_fire() -> void:
	_fire_t = 0.0
	_released_flag = false
	_fire_from = arm_angle
	_fire_to = -deg_to_rad(elevation_deg)
	Sfx.play("twang", global_pos(), 0.9, 3)

func is_firing() -> bool:
	return _fire_t >= 0.0

# ---------------------------------------------------------------- damage
func take_damage(amount: float, source: Dictionary, reason: String = "hit") -> void:
	if destroyed or Net.is_client():
		return          # online: only the host decides about damage (hp arrives with the turn snapshot)
	hp -= amount
	damaged_recently = 4.0
	if not source.is_empty():
		last_source = source
	Scoring.on_catapult_damage(player_id, source, amount)
	show_hp_bar(4.0)
	if hp <= 0.0:
		destroy(reason)
	else:
		Sfx.play("thunk", global_pos(), clampf(amount / 40.0, 0.3, 1.0), 2)
		Fx.burst("splinter", global_pos() + Vector3.UP, Color("#8a5a2a"), clampf(amount / 60.0, 0.3, 1.0))

func apply_impulse(imp: Vector3) -> void:
	if destroyed:
		return
	PhysWorld.apply_impulse(body_id, imp)

## A catapult must stand on the ground to shoot: if it is stuck in the soil it is lifted onto it and set upright; if it is
## buried deeper than 3 m it is destroyed. Returns false when it was destroyed.
func ensure_grounded() -> bool:
	if destroyed or body_id == 0:
		return false
	var xf: Transform3D = PhysWorld.get_transform(body_id)
	var gh: float = Terrain.h(xf.origin.x, xf.origin.z)
	if gh - xf.origin.y > 3.0 and not Net.is_client():
		destroy("buried")
		return false
	var buried: bool = xf.origin.y < gh - 0.3
	var tilted: bool = xf.basis.y.y < 0.75
	if buried or tilted:
		var up_xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(xf.origin.x, gh + 0.35, xf.origin.z))
		PhysWorld.set_transform(body_id, up_xf)
		PhysWorld.set_velocity(body_id, Vector3.ZERO, Vector3.ZERO)
		_pos_cache = up_xf.origin
	return true

func ignite() -> void:
	if burning or destroyed:
		return
	burning = true
	_burn_t = 0.0
	if Fx.inst != null:
		_flame = Fx.inst.acquire_flame(1.4)
		if _flame != null:
			_flame.part = null
	Events.fire_started.emit(global_pos(), last_source)
	Scoring.on_fire_started(last_source)

func extinguish() -> void:
	if not burning:
		return
	burning = false
	_fire_exposure = 0.0
	if _flame != null and Fx.inst != null:
		Fx.inst.release_flame(_flame)
		_flame = null
	Fx.burst("steam", global_pos() + Vector3.UP, Color(0, 0, 0, -1), 0.5)

func destroy(reason: String, from_host: bool = false) -> void:
	if destroyed or (Net.is_client() and not from_host):
		return
	destroyed = true
	if Net.active and Net.is_host:
		NetGame.send_cat_dead(player_id, index, reason)
	hp = 0.0
	var xf: Transform3D = PhysWorld.get_transform(body_id)
	var vel: Vector3 = PhysWorld.get_velocity(body_id)
	var was_burning: bool = burning
	if _flame != null and Fx.inst != null:
		Fx.inst.release_flame(_flame)
		_flame = null
	burning = false
	var own_body: PhysWorld.PBody = PhysWorld.body(body_id)
	if own_body != null:
		own_body.visual = null       # this node is its own visual: do not free it with the body
	PhysWorld.remove_body(body_id)
	body_id = 0
	# break into dynamic parts (frame planks x6, wheels x4, arm x1)
	var b := BuildResult.new()
	var rng: Rng = Game.rng_battle
	for i in 6:
		Kit.box(b, "wood", Vector3(0.24, 0.24, rng.range_f(0.9, 1.4)), Vector3(rng.range_f(-0.7, 0.7), 0.6 + float(i) * 0.05, rng.range_f(-0.9, 0.9)), rng, Kit.NO_COLOR, false, "cat_plank", Vector3(0, rng.range_f(0, PI), 0))
	for sx in [-0.93, 0.93]:
		for sz in [-0.78, 0.78]:
			Kit.cyl(b, "wood", 0.5, 0.16, Vector3(sx as float, 0.5, sz as float), rng, Color("#8a5a2a"), false, "cat_wheel", Vector3(0, 0, PI * 0.5))
	var arm_xf: Transform3D = arm_pivot.transform
	var arm_part := Kit.box(b, "wood", Vector3(0.24, 3.2, 0.24), arm_xf * Vector3(0, 0.72, 0), rng, Color("#c58a4a"), false, "cat_arm", arm_xf.basis.get_euler())
	arm_part.pos = arm_xf * Vector3(0, 0.72, 0)
	var s: Structure = Breakable.create("prop_catapult", player_id, b, xf, true, "hud.catapult")
	s.is_decor = true
	s.last_source = last_source
	s.last_source_time = Breakable.time_now
	for p in s.parts:
		var out: Vector3 = (p.xf.origin - xf.origin)
		out = (out.normalized() if out.length() > 0.05 else Vector3.UP) + Vector3.UP * 0.8
		PhysWorld.set_velocity(p.body_id, vel + out.normalized() * rng.range_f(2.5, 7.0), Vector3(rng.range_f(-4, 4), rng.range_f(-4, 4), rng.range_f(-4, 4)))
		Debris.register_part(p)
		if was_burning or reason == "fire":
			Fire.ignite(p, 1.0, last_source)
	Fire.build_grid_add(s)
	visible = false
	_ring.visible = false
	_bar.visible = false
	_plate.visible = false
	Fx.burst("smoke", xf.origin + Vector3.UP, Color(0, 0, 0, -1), 0.8)
	Fx.burst("splinter", xf.origin + Vector3.UP, Color("#8a5a2a"), 1.0)
	Fx.comic_kind("catapult", xf.origin + Vector3.UP * 3.0)
	Sfx.play("crunch", xf.origin, 1.0, 4)
	Events.catapult_destroyed.emit(player_id, last_source, reason)
	Scoring.on_catapult_destroyed(player_id, last_source)

# ---------------------------------------------------------------- per-frame
func _process(delta: float) -> void:
	if destroyed:
		return
	# fire arm animation
	if _fire_t >= 0.0:
		_fire_t += delta
		var t: float = clampf(_fire_t / 0.24, 0.0, 1.0)
		var e: float = t * t * (1.6 - 0.6 * t)
		arm_angle = lerpf(_fire_from, _fire_to, e)
		if t >= 0.72 and not _released_flag:
			_released_flag = true
			hide_ammo_visual()
			released.emit()
		if t >= 1.0:
			# damped wobble at the stop bar
			var w: float = _fire_t - 0.24
			arm_angle = _fire_to + sin(w * 26.0) * 0.12 * exp(-w * 7.0)
			if w > 0.9:
				_fire_t = -1.0
	arm_pivot.rotation = Vector3(arm_angle, 0, 0)
	_update_rope()
	# ring pulse
	if _ring.visible:
		var pulse: float = 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
		_ring.global_transform = Transform3D(Basis.from_scale(Vector3(pulse, 1.0, pulse)), _pos_cache + Vector3(0, 0.08, 0))
	if _bar.visible or _bar_timer > 0.0 or hp < HP_MAX:
		_bar.visible = _bar_timer > 0.0 or selected
		_bar.global_position = _pos_cache + Vector3(0, 4.4, 0)
	_plate.global_position = _pos_cache + Vector3(0, 5.0, 0)
	_bar_timer = maxf(_bar_timer - delta, 0.0)
	damaged_recently = maxf(damaged_recently - delta, 0.0)

func _update_rope() -> void:
	var a: Vector3 = arm_pivot.transform * Vector3(0, ARM_LEN_UP, 0)
	var b: Vector3 = Vector3(0, 0.95, -1.0)
	var mid: Vector3 = (a + b) * 0.5
	var d: Vector3 = b - a
	var l: float = d.length()
	if l < 0.01:
		return
	var y: Vector3 = d / l
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	_rope.transform = Transform3D(Basis(x, y * l, z), mid)

## Physics-rate checks: tipping, water, fire exposure, burning damage
func tick(dt: float) -> void:
	if destroyed or body_id == 0:
		return
	var xf: Transform3D = PhysWorld.get_transform(body_id)
	_pos_cache = xf.origin
	# stuck in the ground (landslide, crater edge...): lift it out, or it is lost if buried deep
	if xf.origin.y < Terrain.h(xf.origin.x, xf.origin.z) - 0.45:
		_buried_t += dt
		if _buried_t > 0.4:
			_buried_t = 0.0
			if not ensure_grounded():
				return
			xf = PhysWorld.get_transform(body_id)
	else:
		_buried_t = 0.0
	# tipped over
	if xf.basis.y.y < 0.2:
		_tip_time += dt
		if _tip_time >= 3.0:
			destroy("tipped")
			return
	else:
		_tip_time = 0.0
	# deep water
	var depth: float = WaterSys.water_y() - Terrain.h(xf.origin.x, xf.origin.z)
	if depth > 1.0:
		_water_time += dt
		if _water_time >= 2.0:
			Fx.comic_text_glug(xf.origin)
			destroy("drowned")
			return
	else:
		_water_time = 0.0
	# fire
	if not burning:
		if Fire.fires_near(xf.origin, 4.0):
			# fire close by: the wood heats up (damage even before it catches) and catches twice as fast
			_fire_exposure += dt
			hp -= 2.5 * dt
			_update_bar()
			show_hp_bar(1.0)
			if hp <= 0.0:
				destroy("fire")
				return
			if _fire_exposure > 0.9:
				ignite()
		else:
			_fire_exposure = maxf(_fire_exposure - dt * 0.5, 0.0)
	else:
		hp -= 7.2 * dt
		_burn_t += dt
		if _burn_t >= 10.0:
			extinguish()
			return
		if _flame != null:
			_flame.static_pos = xf.origin + Vector3(0, 1.4, 0)
		if hp <= 0.0:
			destroy("fire")
			return
		_update_bar()
		show_hp_bar(1.0)
		if Fire.raining and Game.wind.length() > -1.0 and randf() < 0.02:
			extinguish()
