class_name Projectile
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Projectile entity (spec 6.2 / 6.4): a dynamic body with CCD, wind acceleration, contact based
## detonation and per-ammo behavior (stone, rolling fire barrel, boulder, powder keg, buckshot, cow, beehive, red keg).

const IMPACT_K := 14.0            # crushing factor: kinetic momentum -> effective impact impulse for parts
const OWN_CATAPULT_GRACE := 0.3

static var primary: Projectile = null
static var all_live: Array[Projectile] = []
static var world_root: Node3D
static var rng: Rng = Rng.new(21)
static var last_impact_info: Dictionary = {}
static var last_impact_pos: Vector3 = Vector3.INF     # first impact of the current shot (kept after the projectile is gone)
static var last_pos: Vector3 = Vector3.INF            # last known position of any projectile of the shot (pellets, chunks)
static var impact_log: Array = []

var ammo: AmmoDef
var player_id: int = -1
var body_id: int = 0
var head_id: int = 0                    # cow head
var joint: RID
var visual: Node3D
var head_visual: Node3D
var age: float = 0.0
var alive: bool = true
var detonated: bool = false
var is_sub: bool = false                # scatter pellet / cow chunk
var trail: Trail
var start_pos: Vector3 = Vector3.ZERO
var launch_catapult: Catapult
var _prev_vel: Vector3 = Vector3.ZERO
var _pending: Dictionary = {}
var _scattered: bool = false
var _mask_restored: bool = false
var _impacts: int = 0
var _last_moo: float = -10.0
var first_impact_pos: Vector3 = Vector3.INF
var impact_time: float = -1.0
var landed: bool = false
var source: Dictionary = {}
var rest_timer: float = 0.0
var _boulder_mesh: ArrayMesh          # the potato shape of this boulder (same vertices as its collision hull)
var sub_color: Color = Color(0.55, 0.55, 0.6)
var is_extra: bool = false           # second / third keg of a powder volley: no own score, no own camera
var _last_roll_pos: Vector3 = Vector3.INF
var roll_age: float = 0.0            # fire barrel: seconds since its first impact
var _roll_dir: Vector3 = Vector3.ZERO
var _fb_acc: float = 0.0
var pellet_energy: float = 0.0
var is_event: bool = false           # cow rain etc.: does not hold up the turn

static func reset() -> void:
	for p in all_live:
		p._cleanup(false)
	all_live.clear()
	primary = null

static func busy() -> bool:
	for p in all_live:
		if p.alive and not p.is_sub and not p.is_event:
			return true
	return false

static func any_alive() -> bool:
	for p in all_live:
		if p.alive and not p.is_event:
			return true
	return false

## A cow that falls from the sky (random event): acts like a fired cow but never becomes the primary shot
static func spawn_event_cow(pos: Vector3, vel: Vector3) -> Projectile:
	var pr := Projectile.new()
	pr.ammo = AmmoDef.get_def("cow")
	pr.player_id = -1
	pr.is_event = true
	pr.source = {}
	pr.start_pos = pos
	pr._create_body(pos, vel)
	pr.alive = true
	all_live.append(pr)
	return pr

# ------------------------------------------------------------------ launch
static func launch(ammo_id: String, muzzle_pos: Vector3, velocity: Vector3, owner_player_id: int, from_catapult: Catapult = null) -> Projectile:
	var pr := Projectile.new()
	pr.ammo = AmmoDef.get_def(ammo_id)
	pr.player_id = owner_player_id
	pr.launch_catapult = from_catapult
	pr.source = Damage.make_source(owner_player_id, ammo_id)
	pr.start_pos = muzzle_pos
	# random spread of +-0.5 degrees (mandatory for everyone)
	var dir: Vector3 = velocity.normalized()
	var spd: float = velocity.length()
	var spread: float = deg_to_rad(Cfg.LAUNCH_SPREAD_DEG)
	var perp1: Vector3 = dir.cross(Vector3.UP).normalized()
	if perp1.length() < 0.01:
		perp1 = Vector3.RIGHT
	var perp2: Vector3 = dir.cross(perp1).normalized()
	var ang: float = rng.range_f(0.0, TAU)
	var amt: float = rng.range_f(0.0, spread)
	dir = (dir + (perp1 * cos(ang) + perp2 * sin(ang)) * tan(amt)).normalized()
	pr._create_body(muzzle_pos, dir * spd)
	pr.alive = true
	all_live.append(pr)
	primary = pr
	if ammo_id == "powdertrail":
		# a volley of FIVE small kegs in a tight fan
		for side in [-2.0, -1.0, 1.0, 2.0]:
			var ex := Projectile.new()
			ex.ammo = pr.ammo
			ex.player_id = owner_player_id
			ex.launch_catapult = from_catapult
			ex.source = pr.source
			ex.start_pos = muzzle_pos
			ex.is_extra = true
			var dir2: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(float(side) * rng.range_f(0.8, 1.5)))
			ex._create_body(muzzle_pos + dir.cross(Vector3.UP).normalized() * float(side) * 0.55, dir2 * spd * rng.range_f(0.96, 1.04))
			ex.alive = true
			all_live.append(ex)
	last_impact_pos = Vector3.INF
	last_pos = Vector3.INF
	Events.projectile_launch.emit(owner_player_id, ammo_id, muzzle_pos, dir * spd)
	Scoring.on_shot(owner_player_id, ammo_id)
	Sfx.play("whoosh", muzzle_pos, 0.9, 3)
	if ammo_id == "redkeg":
		Events.banner.emit(I18n.t("banner.redkeg"), "fire")
	return pr

func _create_body(pos: Vector3, vel: Vector3) -> void:
	var d := PhysWorld.BodyDesc.new()
	var bounce: float = 0.15
	var friction: float = 0.7
	match ammo.id:
		"boulder":
			# a lumpy potato, never the same twice: the shape decides how it tumbles and rolls
			var geo: Dictionary = _boulder_geometry(Rng.new(rng.next_u32()), ammo.radius)
			var sd := PhysWorld.ShapeDesc.new()
			sd.type = "convex"
			sd.points = geo["points"] as PackedVector3Array
			sd.uid = str(Time.get_ticks_usec()) + "_" + str(rng.next_u32())
			d.shapes.append(sd)
			_boulder_mesh = geo["mesh"] as ArrayMesh
			d.xf = Transform3D(Basis.from_euler(Vector3(rng.range_f(0, TAU), rng.range_f(0, TAU), rng.range_f(0, TAU))), pos)
			d.mass = ammo.mass
			d.ang_velocity = Vector3(rng.range_f(-2.5, 2.5), rng.range_f(-2.5, 2.5), rng.range_f(-2.5, 2.5))
			bounce = 0.0
			friction = 0.85
		"firebarrel", "powdertrail":
			# a barrel lying on its side, axis perpendicular to the flight: it rolls like a barrel (curved belly!) when it lands
			var vdir: Vector3 = vel.normalized()
			var axis: Vector3 = Vector3.UP.cross(vdir)
			if axis.length() < 0.05:
				axis = Vector3.RIGHT
			axis = axis.normalized()
			var bx: Vector3 = (vdir - axis * vdir.dot(axis)).normalized()
			d.shapes.append(_barrel_shape(0.42, 0.98) if ammo.id == "firebarrel" else _barrel_shape(0.27, 0.62))
			d.xf = Transform3D(Basis(bx, axis, bx.cross(axis)), pos)
			d.mass = ammo.mass
			d.ang_velocity = axis * 7.0
			bounce = 0.3
			friction = 0.7
		"powderkeg", "redkeg":
			# real barrels: a bulging stave shape that tumbles like a barrel, not a ball
			d.shapes.append(_barrel_shape(0.42, 0.78) if ammo.id == "powderkeg" else _barrel_shape(0.68, 1.12))
			d.xf = Transform3D(Basis.from_euler(Vector3(rng.range_f(0, TAU), rng.range_f(0, TAU), rng.range_f(0, TAU))), pos)
			d.mass = ammo.mass
			d.ang_velocity = Vector3(rng.range_f(-4.0, 4.0), rng.range_f(-4.0, 4.0), rng.range_f(-4.0, 4.0))
			bounce = 0.1
			friction = 0.7
		"cow":
			var basis_ := Basis.looking_at(vel.normalized(), Vector3.UP) * Basis(Vector3.UP, PI * 0.5)
			d.shapes.append(PhysWorld.box_desc(Vector3(1.5, 0.85, 0.75)))
			d.xf = Transform3D(basis_, pos)
			d.mass = 200.0
			bounce = 0.35
		_:
			d.shapes.append(PhysWorld.sphere_desc(ammo.radius))
			d.xf = Transform3D(Basis(), pos)
			d.mass = ammo.mass
			if ammo.id == "beehive":
				bounce = 0.05
			elif ammo.id == "redkeg":
				bounce = 0.1
	d.friction = friction
	d.bounce = bounce
	d.layer = Cfg.LAYER_PROJECTILE
	d.mask = Cfg.LAYER_TERRAIN | Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_SETTLER
	if launch_catapult == null:
		d.mask |= Cfg.LAYER_CATAPULT
	d.kind = "projectile"
	d.owner = self
	d.contacts = 4
	d.ccd = true
	d.velocity = vel
	d.damp_lin = ammo.drag
	d.damp_ang = 0.05 if (ammo.id == "firebarrel" or ammo.id == "powdertrail") else 0.1
	d.on_contact = Callable(self, "_on_contact")
	d.can_sleep = false
	visual = _make_visual()
	if visual != null:
		world_root.add_child(visual)
		d.visual = visual
	body_id = PhysWorld.add_body(d)
	var pb: PhysWorld.PBody = PhysWorld.body(body_id)
	if pb != null:
		pb.buoy = 0.6 if ammo.id != "cow" else 1.3
		pb.radius = ammo.radius
	if ammo.id == "cow":
		_create_cow_head(pos, vel)
	# trail
	trail = Trail.new()
	trail.max_points = 26
	trail.width = clampf(ammo.radius * 0.7, 0.15, 0.5)
	trail.color = _trail_color()
	world_root.add_child(trail)
	_prev_vel = vel

func _trail_color() -> Color:
	match ammo.id:
		"firebarrel":
			return Color(1.0, 0.55, 0.15, 0.9)
		"powdertrail":
			return Color(0.3, 0.3, 0.33, 0.6)
		"redkeg":
			return Color(1.0, 0.25, 0.15, 0.95)
		"powderkeg":
			return Color(1.0, 0.8, 0.3, 0.6)
		"beehive":
			return Color(1.0, 0.9, 0.3, 0.5)
		_:
			return Color(1, 1, 1, 0.45)

func _create_cow_head(_pos: Vector3, vel: Vector3) -> void:
	var d := PhysWorld.BodyDesc.new()
	var bxf: Transform3D = PhysWorld.get_transform(body_id)
	var head_pos: Vector3 = bxf * Vector3(0.95, 0.25, 0)
	d.shapes.append(PhysWorld.sphere_desc(0.36))
	d.xf = Transform3D(bxf.basis, head_pos)
	d.mass = 50.0
	d.friction = 0.7
	d.bounce = 0.35
	d.layer = Cfg.LAYER_PROJECTILE
	d.mask = Cfg.LAYER_TERRAIN | Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_SETTLER
	d.kind = "projectile"
	d.owner = self
	d.contacts = 4
	d.ccd = true
	d.velocity = vel
	d.damp_lin = ammo.drag
	d.damp_ang = 0.5
	d.on_contact = Callable(self, "_on_contact")
	d.can_sleep = false
	head_visual = _make_cow_head_visual()
	world_root.add_child(head_visual)
	d.visual = head_visual
	head_id = PhysWorld.add_body(d)
	joint = PhysicsServer3D.joint_create()
	PhysicsServer3D.joint_make_cone_twist(joint, PhysWorld.body_rid(body_id), Transform3D(Basis(), Vector3(0.75, 0.25, 0)), PhysWorld.body_rid(head_id), Transform3D(Basis(), Vector3(-0.2, 0.0, 0)))

# ------------------------------------------------------------------ visuals
func _make_visual() -> Node3D:
	var buf := MeshGen.Buf.new()
	var mat: ShaderMaterial = Toon.main()
	match ammo.id:
		"stone":
			MeshGen.add_sphere(buf, ammo.radius, Transform3D(Basis(), Vector3.ZERO), Color("#8d8d94"), 0.04, 8, 12)
			MeshGen.add_sphere(buf, ammo.radius * 0.35, Transform3D(Basis(), Vector3(ammo.radius * 0.6, 0.1, 0.3)), Color("#a9a9b0"), 0.0, 5, 8)
		"powderkeg":
			MeshGen.add_cyl(buf, 0.42, 0.75, 10, Transform3D(Basis(), Vector3.ZERO), Color("#2b2b33"))
			MeshGen.add_cyl(buf, 0.45, 0.07, 10, Transform3D(Basis(), Vector3(0, 0.22, 0)), Color("#6d7683"))
			MeshGen.add_cyl(buf, 0.45, 0.07, 10, Transform3D(Basis(), Vector3(0, -0.22, 0)), Color("#6d7683"))
			MeshGen.add_box(buf, Vector3(0.24, 0.26, 0.06), Transform3D(Basis(), Vector3(0, 0.02, 0.42)), Color("#f0f0e8"))
			MeshGen.add_cyl(buf, 0.03, 0.3, 5, Transform3D(Basis(), Vector3(0, 0.5, 0)), Color("#e8c060"))
		"firebarrel":
			MeshGen.add_cyl(buf, 0.42, 0.98, 12, Transform3D(Basis(), Vector3.ZERO), Color("#8a5a2a"))
			MeshGen.add_cyl(buf, 0.45, 0.07, 12, Transform3D(Basis(), Vector3(0, 0.3, 0)), Color("#3a3a44"))
			MeshGen.add_cyl(buf, 0.45, 0.07, 12, Transform3D(Basis(), Vector3(0, -0.3, 0)), Color("#3a3a44"))
			MeshGen.add_cyl(buf, 0.36, 0.06, 12, Transform3D(Basis(), Vector3(0, 0.5, 0)), Color("#ff8a2a"))
			MeshGen.add_cyl(buf, 0.36, 0.06, 12, Transform3D(Basis(), Vector3(0, -0.5, 0)), Color("#ff8a2a"))
			mat = Toon.emissive(Color("#c2651c"), 0.6)
		"powdertrail":
			MeshGen.add_cyl(buf, 0.27, 0.62, 10, Transform3D(Basis(), Vector3.ZERO), Color("#3a342c"))
			MeshGen.add_cyl(buf, 0.3, 0.05, 10, Transform3D(Basis(), Vector3(0, 0.17, 0)), Color("#6d7683"))
			MeshGen.add_cyl(buf, 0.3, 0.05, 10, Transform3D(Basis(), Vector3(0, -0.17, 0)), Color("#6d7683"))
			MeshGen.add_box(buf, Vector3(0.14, 0.16, 0.04), Transform3D(Basis(), Vector3(0, 0.0, 0.27)), Color("#f0f0e8"))
		"redkeg":
			MeshGen.add_cyl(buf, 0.68, 1.1, 14, Transform3D(Basis(), Vector3.ZERO), Color("#d6281f"))
			MeshGen.add_cyl(buf, 0.73, 0.1, 14, Transform3D(Basis(), Vector3(0, 0.34, 0)), Color("#2b2b33"))
			MeshGen.add_cyl(buf, 0.73, 0.1, 14, Transform3D(Basis(), Vector3(0, -0.34, 0)), Color("#2b2b33"))
			MeshGen.add_box(buf, Vector3(0.4, 0.4, 0.06), Transform3D(Basis(), Vector3(0, 0.02, 0.68)), Color("#f7f0e0"))
			MeshGen.add_box(buf, Vector3(0.22, 0.06, 0.07), Transform3D(Basis(), Vector3(0, 0.08, 0.69)), Color("#2b2b33"))
			MeshGen.add_cyl(buf, 0.04, 0.4, 5, Transform3D(Basis(), Vector3(0, 0.78, 0)), Color("#e8c060"))
			mat = Toon.emissive(Color("#d6281f"), 0.35)
		"scatter":
			MeshGen.add_sphere(buf, ammo.radius, Transform3D(Basis(), Vector3.ZERO), Color("#c9a15a"), 0.03, 8, 12)
			MeshGen.add_cyl(buf, 0.1, 0.16, 6, Transform3D(Basis(), Vector3(0, ammo.radius, 0)), Color("#8a5a2a"))
			MeshGen.add_cyl(buf, 0.42, 0.06, 10, Transform3D(Basis(), Vector3(0, 0.04, 0)), Color("#8a5a2a"))
		"beehive":
			for i in 5:
				var r: float = 0.4 - abs(float(i) - 2.0) * 0.07
				MeshGen.add_cyl(buf, r, 0.16, 10, Transform3D(Basis(), Vector3(0, -0.32 + float(i) * 0.16, 0)), Color("#f1c40f") if i % 2 == 0 else Color("#e0a80c"))
			MeshGen.add_box(buf, Vector3(0.14, 0.08, 0.05), Transform3D(Basis(), Vector3(0, -0.2, 0.36)), Color("#2b2b33"))
		"cow":
			_add_cow_body(buf)
		_:
			MeshGen.add_sphere(buf, ammo.radius, Transform3D(Basis(), Vector3.ZERO), ammo.color)
	var mi := MeshInstance3D.new()
	mi.mesh = _boulder_mesh if (ammo.id == "boulder" and _boulder_mesh != null) else buf.to_mesh()
	mi.material_override = mat
	if ammo.id == "redkeg" or ammo.id == "firebarrel":
		mi.set_instance_shader_parameter("glow", 0.45)
	return mi

func _add_cow_body(buf: MeshGen.Buf) -> void:
	var white: Color = Color("#f4f1e8")
	var black: Color = Color("#2b2b33")
	MeshGen.add_box(buf, Vector3(1.5, 0.85, 0.75), Transform3D(Basis(), Vector3.ZERO), white)
	MeshGen.add_box(buf, Vector3(0.5, 0.05, 0.5), Transform3D(Basis(), Vector3(-0.2, 0.44, 0.1)), black)
	MeshGen.add_box(buf, Vector3(0.4, 0.5, 0.05), Transform3D(Basis(), Vector3(0.3, 0.05, 0.39)), black)
	MeshGen.add_box(buf, Vector3(0.3, 0.3, 0.05), Transform3D(Basis(), Vector3(-0.4, -0.1, -0.39)), black)
	for lx in [-0.55, 0.55]:
		for lz in [-0.25, 0.25]:
			MeshGen.add_box(buf, Vector3(0.18, 0.55, 0.18), Transform3D(Basis(), Vector3(lx as float, -0.65, lz as float)), white)
			MeshGen.add_box(buf, Vector3(0.2, 0.12, 0.2), Transform3D(Basis(), Vector3(lx as float, -0.95, lz as float)), black)
	MeshGen.add_box(buf, Vector3(0.08, 0.5, 0.08), Transform3D(Basis(Vector3(0, 0, 1), 0.3), Vector3(-0.85, 0.0, 0)), white)
	MeshGen.add_box(buf, Vector3(0.22, 0.2, 0.2), Transform3D(Basis(), Vector3(-0.85, -0.28, 0)), black)

func _make_cow_head_visual() -> Node3D:
	var buf := MeshGen.Buf.new()
	MeshGen.add_box(buf, Vector3(0.6, 0.55, 0.5), Transform3D(Basis(), Vector3.ZERO), Color("#f4f1e8"))
	MeshGen.add_box(buf, Vector3(0.28, 0.28, 0.44), Transform3D(Basis(), Vector3(0.36, -0.1, 0)), Color("#f2b6b6"))
	MeshGen.add_box(buf, Vector3(0.05, 0.1, 0.1), Transform3D(Basis(), Vector3(0.32, 0.12, 0.26)), Color("#2b2b33"))
	MeshGen.add_box(buf, Vector3(0.05, 0.1, 0.1), Transform3D(Basis(), Vector3(0.32, 0.12, -0.26)), Color("#2b2b33"))
	MeshGen.add_box(buf, Vector3(0.07, 0.22, 0.07), Transform3D(Basis(Vector3(1, 0, 0), 0.4), Vector3(-0.05, 0.36, 0.2)), Color("#e8dcb0"))
	MeshGen.add_box(buf, Vector3(0.07, 0.22, 0.07), Transform3D(Basis(Vector3(1, 0, 0), -0.4), Vector3(-0.05, 0.36, -0.2)), Color("#e8dcb0"))
	var mi := MeshInstance3D.new()
	mi.mesh = buf.to_mesh()
	mi.material_override = Toon.main()
	return mi

# ------------------------------------------------------------------ contacts (physics callback: only records)
func _on_contact(_pb: PhysWorld.PBody, state: PhysicsDirectBodyState3D) -> void:
	if not alive:
		return
	var n: int = mini(state.get_contact_count(), 4)
	var best: int = -1
	var best_imp: float = -1.0
	for i in n:
		var imp: float = state.get_contact_impulse(i).length()
		if imp > best_imp:
			best_imp = imp
			best = i
	if best < 0:
		return
	var rid: RID = state.get_contact_collider(best)
	if is_sub and pellet_energy < 0.0:
		return
	if not _pending.is_empty():
		return
	_pending = {
		"pos": state.get_contact_collider_position(best),
		"normal": state.get_contact_local_normal(best),
		"rid": rid,
		"shape": state.get_contact_collider_shape(best),
		"impulse": best_imp,
		"speed": _prev_vel.length(),
		"vel": _prev_vel,
	}

# ------------------------------------------------------------------ per-physics-tick
func tick(dt: float) -> void:
	if not alive:
		return
	age += dt
	var pb: PhysWorld.PBody = PhysWorld.body(body_id)
	if pb == null:
		_cleanup(false)
		return
	var pos: Vector3 = pb.xform.origin
	var vel: Vector3 = PhysWorld.get_velocity(body_id)
	# wind acceleration
	var accel := Vector3(Game.wind.x, 0.0, Game.wind.y) * Cfg.WIND_ACCEL_FACTOR * ammo.wind_factor
	if not is_sub:
		PhysWorld.apply_force(body_id, accel * pb.mass)
		if head_id != 0:
			PhysWorld.apply_force(head_id, accel * 50.0)
	if trail != null:
		trail.push(pos)
	# re-enable collisions with the own catapult after the grace period
	if not _mask_restored and age > OWN_CATAPULT_GRACE:
		_mask_restored = true
		var m: int = Cfg.LAYER_TERRAIN | Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_SETTLER | Cfg.LAYER_CATAPULT
		PhysWorld.set_layer_mask(body_id, Cfg.LAYER_PROJECTILE, m)
		if head_id != 0:
			PhysWorld.set_layer_mask(head_id, Cfg.LAYER_PROJECTILE, m)
	# awaken structures ahead of the projectile so real part bodies exist when it arrives
	if impact_time < 0.0 or ammo.id == "cow":
		Breakable.awaken_in_radius(pos + vel * dt * 2.0, ammo.radius + 2.0 + minf(vel.length() * dt * 2.0, 3.0))
	# ammo specific mid-flight
	if ammo.id == "scatter" and not _scattered and vel.y <= 0.0 and age > 0.25 and not is_sub:
		_scatter(pos, vel)
		return
	if ammo.id == "redkeg" and int(age * 60.0) % 4 == 0:
		Fx.burst("flame", pos, Color(0, 0, 0, -1), 0.3)
	if ammo.id == "firebarrel" or ammo.id == "powdertrail":
		_tick_firebarrel(dt, pos, vel)
		if not alive:
			return
	if ammo.id == "boulder" and impact_time >= 0.0:
		_tick_boulder(dt, pos, vel)
		if not alive:
			return
	# settlers / animals in the flight path are hit directly (they have no bodies while walking)
	if not is_sub or pellet_energy > 0.0:
		if _sweep_living(pos, vel):
			return
	# water landing
	if pos.y < WaterSys.water_y() + 0.1 and Terrain.h(pos.x, pos.z) < WaterSys.water_y() - 0.25 and ammo.id != "cow":
		_water_impact(pos)
		return
	# pending contact from the last step
	if not _pending.is_empty():
		var info: Dictionary = _pending
		_pending = {}
		_handle_impact(info)
		if not alive:
			return
	_prev_vel = vel
	# timeout / out of world
	var limit: float = Cfg.PROJECTILE_TIMEOUT if impact_time < 0.0 else 40.0
	if age > limit or pos.y < -30.0:
		_finish(pos, true)
		return
	# resting projectiles (stone that rolled to a stop, dead cow) end the flight; the fire barrel rolls on its own clock
	if impact_time >= 0.0 and ammo.id != "firebarrel" and ammo.id != "powdertrail":
		if vel.length() < 0.6:
			rest_timer += dt
			if rest_timer > 0.6:
				_finish(pos, false)
		else:
			rest_timer = 0.0

# ------------------------------------------------------------------ living things
func _sweep_living(pos: Vector3, vel: Vector3) -> bool:
	var reach: float = ammo.radius + 0.55
	var speed: float = vel.length()
	var hit_any: bool = false
	for st in Settler.all:
		if st.state == Settler.State.DEAD or st.state == Settler.State.GONE or st.state == Settler.State.RAGDOLL:
			continue
		var d: float = (st.global_pos() + Vector3(0, 0.8, 0) - pos).length()
		if d < reach:
			hit_any = true
			var e: float = ammo.mass * speed
			var dir: Vector3 = vel.normalized() if speed > 0.5 else Vector3.UP
			var dmg: float = clampf(e / 30.0, 6.0, 80.0)
			st.hurt(dmg, source, (dir + Vector3.UP * 0.5).normalized() * clampf(e / 60.0, 3.0, 22.0), true)
			if ammo.id == "cow":
				if age - _last_moo > 0.4:
					_moo(pos)
			elif ammo.id in ["stone", "scatter"]:
				Sfx.play("boing", pos, 0.6, 1)
			elif ammo.id == "firebarrel":
				st.ignite()
	if hit_any and ammo.id in ["powderkeg", "beehive", "redkeg", "cow"] and not is_sub and impact_time < 0.0:
		_handle_impact({"pos": pos, "normal": Vector3.UP, "rid": RID(), "shape": 0, "impulse": ammo.mass * speed, "speed": speed, "vel": vel})
		return true
	for an in Animal.all:
		if an.dead:
			continue
		if (an.global_pos() + Vector3(0, 0.4, 0) - pos).length() < reach + 0.3:
			an.hurt(ammo.mass * speed / 25.0, vel.normalized() * 8.0 + Vector3.UP * 4.0, source)
	return false

func _moo(pos: Vector3) -> void:
	_last_moo = age
	Sfx.play("moo", pos, 1.0, 3)
	Fx.comic_kind("cow", pos + Vector3.UP * 2.0)
	for st in Settler.all:
		if st.state != Settler.State.DEAD and (st.global_pos() - pos).length() < 12.0:
			st.notice_cow()

# ------------------------------------------------------------------ impact handling
func _water_impact(pos: Vector3) -> void:
	var wp := Vector3(pos.x, WaterSys.water_y(), pos.z)
	Fx.burst("splash", wp, Color(0, 0, 0, -1), 1.0)
	Fx.burst("droplet", wp, Color(0, 0, 0, -1), 0.7)
	Sfx.play("splash", wp, 1.0, 3)
	Fx.comic_kind("water", wp + Vector3.UP * 2.0)
	Events.projectile_impact.emit(player_id, ammo.id, wp, _prev_vel.length())
	first_impact_pos = wp
	if not is_sub and last_impact_pos == Vector3.INF:
		last_impact_pos = wp
	impact_time = age
	_finish(pos, true, true)

func _handle_impact(info: Dictionary) -> void:
	var pos: Vector3 = info["pos"] as Vector3
	var speed: float = float(info["speed"])
	var vel: Vector3 = info["vel"] as Vector3
	var normal: Vector3 = info["normal"] as Vector3
	var rid: RID = info["rid"] as RID
	var target: Object = PhysWorld.owner_of(rid)
	var terrain_hit: bool = PhysWorld.is_terrain(rid)
	last_impact_info = {"pos": pos, "speed": speed, "age": age, "terrain": terrain_hit, "target": (target.get_class() if target != null else "null"), "kind": (((target as Part).structure.kind) if target is Part else "")}
	if impact_log.size() < 12:
		impact_log.append(last_impact_info.duplicate())
	# ignore grazing our own launching catapult in the grace period
	if target is Catapult and target == launch_catapult and age < OWN_CATAPULT_GRACE * 2.0:
		return
	_impacts += 1
	if impact_time < 0.0:
		impact_time = age
		first_impact_pos = pos
		if not is_sub and last_impact_pos == Vector3.INF:
			last_impact_pos = pos
		ReplayRec.mark_impact()
		Events.projectile_impact.emit(player_id, ammo.id, pos, speed)
		# hits on the ground end quickly; hits on buildings may roll / plough on a few meters; the fire barrel keeps rolling
		if not is_sub:
			var ground: bool = terrain_hit or target == null
			var ld: float = 1.2 if ground else 0.25
			var ad: float = 3.0 if ground else 1.0
			if ammo.id == "boulder":
				ld = 0.1
				ad = 0.2
			if ammo.id == "firebarrel" or ammo.id == "powdertrail":
				ld = 0.04
				ad = 0.15
				_roll_dir = Util.flat(vel).normalized() if Util.flat(vel).length() > 0.5 else Util.flat(-normal)
			for bid in [body_id, head_id]:
				if bid != 0 and PhysWorld.bodies.has(bid):
					var brid: RID = PhysWorld.body_rid(bid)
					PhysicsServer3D.body_set_param(brid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, ld)
					PhysicsServer3D.body_set_param(brid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, ad)
	var energy: float = ammo.mass * speed
	var dir: Vector3 = vel.normalized() if vel.length() > 0.5 else -normal
	# direct catapult hit: impulse / 40 (spec 6.6)
	if target is Catapult:
		Damage.damage_catapult(target as Catapult, energy / 22.0, source, "projectile")
	match ammo.id:
		"stone":
			var broken: int = _kinetic(pos, energy, dir, 1.6 + clampf(speed / 40.0, 0.0, 2.6))
			Events.camera_shake.emit(clampf(energy / 3500.0, 0.1, 0.6))
			_impact_fx(pos, energy, target, terrain_hit)
			_plough(broken, speed, dir, terrain_hit, 0.92)
		"firebarrel":
			# bounces and rolls on: every touch sets flammable stuff alight
			_kinetic(pos, energy * 0.3, dir, 1.3)
			Fire.ignite_in_radius(pos, 3.2, 1.0, source)
			Fx.burst("flame", pos, Color(0, 0, 0, -1), 0.8)
			Fx.burst("splinter", pos, Color("#7a4a25"), 0.4)
			Sfx.play("crunch", pos, 0.7, 2)
			if _impacts == 1:
				Sfx.play("fwump", pos, 1.0, 3)
				Events.camera_shake.emit(0.3)
				Events.banner.emit(I18n.pick("banner.fire", Game.rng_battle), "fire")
		"powdertrail":
			# a small keg: bounces on and leaves powder where it touches
			_kinetic(pos, energy * 0.15, dir, 0.9)
			Powder.stain(pos, 1.5, source)
			Powder.drop(pos, source, 1.4)
			Sfx.play("thunk", pos, 0.5, 1)
		"boulder":
			# twice the size of a stone: drives through walls, keeps rolling and crushes on the way
			var bbroken: int = _kinetic(pos, energy * 1.73, dir, 2.75 + clampf(speed / 26.0, 0.0, 3.4))
			# whatever it hits head-on is torn out for certain: no glancing off a wall
			if speed > 6.0 and PhysWorld.bodies.has(body_id):
				bbroken += Damage.smash_in_radius(PhysWorld.body(body_id).xform.origin, ammo.radius * 1.3 + 0.4, source, dir)
			Events.camera_shake.emit(clampf(energy / 6000.0, 0.2, 0.9))
			_impact_fx(pos, energy, target, terrain_hit)
			Sfx.play("crunch", pos, 0.9, 2)
			_plough(bbroken, speed, dir, terrain_hit, 0.95, 0.9, 0.015, 0.6)
		"powderkeg":
			detonated = true
			Explosion.explode(pos, 12.0, 1700.0, {"source": source, "sound": "bigboom", "fire": false})
			_finish(pos, false)
		"scatter":
			_scatter(pos, vel)
			_kinetic(pos, energy * 0.6, dir, 1.0)
			return
		"cow":
			# the cow bursts into red chunks that fly in every direction and hurt whatever they hit
			_kinetic(pos, energy * 0.7, dir, 2.4 + clampf(speed / 30.0, 0.0, 3.0))
			_moo(pos)
			Events.camera_shake.emit(clampf(energy / 3000.0, 0.3, 1.0))
			Damage.damage_settlers_in_radius(pos, 6.0, 80.0, source, dir, 1.0)
			Explosion.shockwave(pos, 11.0, clampf(energy * 0.12, 300.0, 2200.0), source, Color("#ff5a4a"))
			_cow_burst(pos, normal, dir)
			detonated = true
			_finish(pos, false)
		"beehive":
			detonated = true
			Bees.spawn(pos, source)
			Fx.burst("bee", pos, Color(0, 0, 0, -1), 1.4)
			Sfx.play("splat", pos, 0.8, 3)
			Damage.damage_settlers_in_radius(pos, 3.0, 40.0, source, dir, 0.4)
			_finish(pos, false)
		"redkeg":
			detonated = true
			_redkeg_explode(pos)
			_finish(pos, false)
		_:
			_kinetic(pos, energy, dir, 1.4)
	if is_sub:
		return

func _kinetic(pos: Vector3, energy: float, dir: Vector3, radius: float) -> int:
	var broken: int = Damage.impact_at(pos, radius, energy * IMPACT_K, dir, source)
	# ragdoll launch of settlers close to the impact
	Damage.damage_settlers_in_radius(pos, radius + 1.2, clampf(energy / 30.0, 15.0, 90.0), source, dir, 0.8)
	return broken

## A hit that smashes parts does not stop the projectile: it keeps most of its speed along its old direction and
## ploughs on through the building (the more it breaks, the more it is slowed).
func _plough(broken: int, speed: float, dir: Vector3, terrain_hit: bool, keep_max: float, restore: float = 0.8, per_broken: float = 0.04, keep_min: float = 0.45) -> void:
	if broken <= 0 or terrain_hit or is_sub or speed < 8.0 or not PhysWorld.bodies.has(body_id):
		return
	var keep: float = clampf(keep_max - per_broken * float(broken), keep_min, keep_max)
	var cur: Vector3 = PhysWorld.get_velocity(body_id)
	var want: Vector3 = (dir * restore + cur.normalized() * (1.0 - restore)).normalized() * speed * keep
	if want.length() > cur.length():
		PhysWorld.set_velocity(body_id, want, Vector3.ZERO)
		_prev_vel = want

func _impact_fx(pos: Vector3, energy: float, target: Object, terrain_hit: bool) -> void:
	var sc: float = clampf(energy / 1800.0, 0.3, 1.0)
	if terrain_hit or target == null:
		Fx.burst("dust", pos, Color("#8a6d4a"), sc, Vector3.UP)
		Sfx.play("thunk", pos, clampf(sc, 0.4, 1.0), 2)
		if energy > 500.0 and _impacts <= 2 and Terrain.current != null and not Terrain.is_water(pos.x, pos.z):
			if ammo.id == "boulder":
				# a big dent with a torn-up rim
				Terrain.current.dig(pos, 3.0 + clampf(energy / 9000.0, 0.0, 2.5), 1.0 + clampf(energy / 18000.0, 0.0, 1.4), 0.0, 0.6, 0.35)
			else:
				# a small dent
				Terrain.current.dig(pos, 0.9 + clampf(energy / 5000.0, 0.0, 1.0), 0.18 + clampf(energy / 12000.0, 0.0, 0.3), 0.0, 0.45)
			Landslide.trigger(pos, energy / 9000.0 * (1.6 if ammo.id == "boulder" else 1.0), source)
	else:
		Fx.burst("dust", pos, Color("#9a9a9a"), sc * 0.7, Vector3.UP)
	if energy > 1000.0 and rng.chance(0.5):
		Fx.comic_kind("impact", pos + Vector3.UP * 1.5)

# ------------------------------------------------------------------ scatter shot / cheese
func _scatter(pos: Vector3, vel: Vector3) -> void:
	if _scattered:
		return
	_scattered = true
	var dir: Vector3 = vel.normalized() if vel.length() > 0.5 else Vector3.DOWN
	var perp1: Vector3 = dir.cross(Vector3.UP).normalized()
	if perp1.length() < 0.01:
		perp1 = Vector3.RIGHT
	var perp2: Vector3 = dir.cross(perp1).normalized()
	for i in 24:
		var a: float = rng.range_f(0.0, TAU)
		var cone: float = tan(deg_to_rad(rng.range_f(2.0, 20.0)))
		var v: Vector3 = (dir + (perp1 * cos(a) + perp2 * sin(a)) * cone).normalized() * vel.length() * rng.range_f(0.85, 1.1)
		_spawn_pellet(pos + (perp1 * cos(a) + perp2 * sin(a)) * 0.3, v)
	Fx.burst("puff", pos, Color("#c9a15a"), 0.8)
	Sfx.play("pop", pos, 0.8, 2)
	# the sack itself is gone
	_finish(pos, false, false, true)

func _spawn_pellet(pos: Vector3, vel: Vector3, mass_kg: float = 9.0, burn: float = 0.0, col: Color = Color(0.55, 0.55, 0.6), bright: bool = false) -> void:
	var pr := Projectile.new()
	pr.ammo = AmmoDef.get_def("stone")
	pr.is_sub = true
	pr.player_id = player_id
	pr.source = source
	pr.pellet_energy = mass_kg * vel.length()
	pr.sub_color = col
	pr.roll_age = burn     # (reused) > 0: sets things alight when it hits
	var d := PhysWorld.BodyDesc.new()
	d.shapes.append(PhysWorld.sphere_desc(0.24))
	d.xf = Transform3D(Basis(), pos)
	d.mass = mass_kg
	d.friction = 0.6
	d.bounce = 0.3
	d.layer = Cfg.LAYER_PROJECTILE
	d.mask = Cfg.LAYER_TERRAIN | Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_CATAPULT
	d.kind = "projectile"
	d.owner = pr
	d.contacts = 2
	d.ccd = true
	d.velocity = vel
	d.damp_lin = 0.02
	d.on_contact = Callable(pr, "_on_contact")
	var mi := MeshInstance3D.new()
	mi.mesh = MeshGen.sphere_mesh(0.24, 5, 8)
	mi.material_override = Toon.emissive(col, 0.8) if bright else Toon.colored(col)
	world_root.add_child(mi)
	d.visual = mi
	pr.visual = mi
	pr.body_id = PhysWorld.add_body(d)
	pr.visual = mi
	pr.alive = true
	pr.impact_time = -1.0
	pr.start_pos = pos
	all_live.append(pr)

func _pellet_hit(info: Dictionary) -> void:
	var pos: Vector3 = info["pos"] as Vector3
	if last_impact_pos == Vector3.INF:
		last_impact_pos = pos
		ReplayRec.mark_impact()
	var vel: Vector3 = info["vel"] as Vector3
	var target: Object = PhysWorld.owner_of(info["rid"] as RID)
	Damage.impact_at(pos, 1.3, pellet_energy * 9.0, vel.normalized(), source)
	Damage.damage_settlers_in_radius(pos, 2.2, 30.0, source, vel.normalized(), 0.6)
	if roll_age > 0.0:
		Fire.ignite_in_radius(pos, 2.0, 0.8, source)
		Fx.burst("flame", pos, Color(0, 0, 0, -1), 0.4)
	if target is Catapult:
		Damage.damage_catapult(target as Catapult, 16.0, source, "pellet")
	if ammo.id == "stone" and sub_color.r > 0.5 and sub_color.g < 0.3:
		Fx.burst("splash", pos, Color("#b3122b"), 0.5)
	else:
		Fire.ignite_in_radius(pos, 0.8, 0.12, source, true)
	Fx.burst("dust", pos, Color("#9a9a9a"), 0.3)
	Sfx.play("clack", pos, 0.5, 1)
	_finish(pos, false, false, true)

func _redkeg_explode(pos: Vector3) -> void:
	# the big red barrel: one good hit flattens most of a village
	Explosion.explode(pos, 32.0, 9000.0, {"source": source, "sound": "bigboom", "fire": true, "color": Color("#ff3b2a"), "cat_scale": 0.06})
	Fx.burst("flame", pos + Vector3.UP, Color(0, 0, 0, -1), 1.6)
	Fx.comic_kind("explosion", pos + Vector3.UP * 12.0)
	Events.banner.emit(I18n.t("banner.redkeg_boom"), "fire")
	for i in 14:
		var a: float = TAU * float(i) / 14.0 + rng.range_f(-0.2, 0.2)
		var v := Vector3(cos(a) * rng.range_f(10.0, 26.0), rng.range_f(12.0, 26.0), sin(a) * rng.range_f(10.0, 26.0))
		_spawn_pellet(pos + Vector3(0, 1.5, 0), v, 14.0, 0.3, Color("#ff7a1a"), true)

## Cow chunks: red pieces scattered over the hemisphere around the impact normal
func _cow_burst(pos: Vector3, normal: Vector3, dir: Vector3) -> void:
	var up: Vector3 = normal if normal.length() > 0.1 else Vector3.UP
	if up.y < -0.2:
		up = Vector3.UP
	var perp1: Vector3 = up.cross(Vector3.RIGHT).normalized()
	if perp1.length() < 0.1:
		perp1 = up.cross(Vector3.FORWARD).normalized()
	var perp2: Vector3 = up.cross(perp1).normalized()
	Fx.burst("splash", pos, Color("#c21a2b"), 1.8)
	Fx.burst("dust", pos, Color("#7a1020"), 1.2, Vector3.UP)
	Fx.comic_kind("impact", pos + Vector3.UP * 2.5)
	for i in 34:
		var a: float = rng.range_f(0.0, TAU)
		# a flat fan along the ground, not a fountain: little lift, mostly sideways
		var lift: float = rng.range_f(0.02, 0.22)
		var v: Vector3 = (up * lift + (perp1 * cos(a) + perp2 * sin(a)) * rng.range_f(0.9, 1.4) + dir * 0.3).normalized() * rng.range_f(16.0, 40.0)
		v.y = clampf(v.y, -2.0, 0.22 * v.length())
		_spawn_pellet(pos + up * 0.5, v, 8.0, 0.0, Color("#b3122b").lerp(Color("#e0394a"), rng.range_f(0.0, 1.0)), false)

# ------------------------------------------------------------------ finish / cleanup
## `miss`: shot never hit anything; `in_water`: landed in water. `silent`: sub-projectile removal, no scoring
func _finish(pos: Vector3, miss: bool, in_water: bool = false, silent: bool = false) -> void:
	if not alive:
		return
	alive = false
	if not silent and not is_sub and not is_extra:
		landed = true
		var dist: float = Util.dist_xz(start_pos, first_impact_pos if first_impact_pos != Vector3.INF else pos)
		Scoring.on_shot_landed(player_id, dist, in_water)
		if miss and not in_water:
			pass
	# cow and stone-like bodies remain as debris until the cap removes them; explosives vanish
	var keep: bool = (ammo.id == "cow" or ((ammo.id == "stone" or ammo.id == "boulder") and not is_sub)) and not detonated and not silent
	_cleanup(keep)

func _cleanup(keep_body: bool) -> void:
	if trail != null and is_instance_valid(trail):
		trail.stop()
	trail = null
	if keep_body:
		# leave the bodies as rubble (registered with the debris system)
		if PhysWorld.bodies.has(body_id):
			PhysicsServer3D.body_set_max_contacts_reported(PhysWorld.body_rid(body_id), 0)
			var pb: PhysWorld.PBody = PhysWorld.body(body_id)
			pb.on_contact = Callable()
			pb.owner = null
			PhysicsServer3D.body_set_state(pb.rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, true)
			Debris.register_shard(body_id, visual)
		if head_id != 0 and PhysWorld.bodies.has(head_id):
			var hb: PhysWorld.PBody = PhysWorld.body(head_id)
			hb.on_contact = Callable()
			hb.owner = null
			Debris.register_shard(head_id, head_visual)
	else:
		if PhysWorld.bodies.has(body_id):
			PhysWorld.remove_later(body_id)
		if head_id != 0 and PhysWorld.bodies.has(head_id):
			PhysWorld.remove_later(head_id)
	if joint.is_valid():
		PhysicsServer3D.free_rid(joint)
		joint = RID()
	all_live.erase(self)
	if primary == self:
		primary = null

## Position of the projectile (or Vector3.INF)
func position() -> Vector3:
	var pb: PhysWorld.PBody = PhysWorld.body(body_id)
	return pb.xform.origin if pb != null else Vector3.INF

func velocity() -> Vector3:
	return PhysWorld.get_velocity(body_id) if body_id != 0 else Vector3.ZERO

## Called by the turn manager every physics tick for all live projectiles
static func tick_all(dt: float) -> void:
	var list: Array[Projectile] = all_live.duplicate()
	for p in list:
		if p.is_sub:
			p._tick_sub(dt)
		else:
			p.tick(dt)

func _tick_sub(dt: float) -> void:
	if not alive:
		return
	age += dt
	var pb: PhysWorld.PBody = PhysWorld.body(body_id)
	if pb == null:
		_finish(Vector3.ZERO, false, false, true)
		return
	var pos: Vector3 = pb.xform.origin
	var vel: Vector3 = PhysWorld.get_velocity(body_id)
	last_pos = pos
	if trail != null:
		trail.push(pos)
	if not _pending.is_empty():
		var info: Dictionary = _pending
		_pending = {}
		_pellet_hit(info)
		return
	_prev_vel = vel
	if age > 6.0 or pos.y < -30.0 or (pos.y < WaterSys.water_y() and Terrain.h(pos.x, pos.z) < WaterSys.water_y() - 0.2):
		if pos.y < WaterSys.water_y():
			Fx.burst("splash", Vector3(pos.x, WaterSys.water_y(), pos.z), Color(0, 0, 0, -1), 0.4)
		_finish(pos, false, false, true)
	elif pellet_energy > 0.0:
		# living things in the path of pellets
		for st in Settler.all:
			if st.state != Settler.State.DEAD and st.state != Settler.State.GONE and (st.global_pos() + Vector3(0, 0.8, 0) - pos).length() < 0.7:
				st.hurt(22.0, source, vel.normalized() * 8.0 + Vector3.UP * 4.0, true)

# ------------------------------------------------------------------ rolling fire barrel
func _tick_firebarrel(dt: float, pos: Vector3, vel: Vector3) -> void:
	_fb_acc += dt
	var powder: bool = ammo.id == "powdertrail"
	if _fb_acc >= (0.09 if powder else 0.12):
		_fb_acc = 0.0
		if powder:
			# irregular heaps of black powder where the keg rolls
			if impact_time >= 0.0 and rng.chance(0.85):
				Powder.drop(pos + Vector3(rng.range_f(-1.0, 1.0), 0, rng.range_f(-1.0, 1.0)), source, rng.range_f(0.6, 1.5))
				if rng.chance(0.3):
					Fx.burst("dust", pos, Color("#2a2a2e"), 0.25, Vector3.UP)
		else:
			Fx.burst("flame", pos, Color(0, 0, 0, -1), 0.35)
			if impact_time >= 0.0:
				Fire.ignite_in_radius(pos, 2.1, 0.65, source)
				for st in Settler.all:
					if st.state != Settler.State.DEAD and st.state != Settler.State.GONE and (st.global_pos() + Vector3(0, 0.6, 0) - pos).length() < 1.8:
						st.ignite()
	if impact_time < 0.0:
		return
	roll_age += dt
	var h := Vector3(vel.x, 0.0, vel.z)
	var sp: float = h.length()
	if sp > 1.5:
		_roll_dir = h / sp
	# it keeps rolling like a heavy barrel for several seconds (bounces off houses and trees by itself)
	if roll_age < (4.8 if powder else 3.5) and sp < 9.0 and _roll_dir != Vector3.ZERO:
		PhysWorld.apply_force(body_id, _roll_dir * ammo.mass * 18.0)
	if roll_age >= (7.5 if powder else 5.5) or (roll_age > (4.0 if powder else 3.0) and sp < 0.5):
		if powder:
			# the keg bursts: a last big heap
			for k in 5:
				Powder.drop(pos + Vector3(rng.range_f(-1.6, 1.6), 0, rng.range_f(-1.6, 1.6)), source, 1.3)
			Powder.stain(pos, 1.8, source)
			Fx.burst("dust", pos, Color("#2a2a2e"), 0.7, Vector3.UP)
			Sfx.play("splat", pos, 0.6, 2)
		else:
			Fire.ignite_in_radius(pos, 3.5, 1.0, source)
			Fx.burst("flame", pos, Color(0, 0, 0, -1), 1.0)
			Sfx.play("fwump", pos, 0.9, 3)
		_finish(pos, false)

# ------------------------------------------------------------------ rolling boulder
## While the big stone rolls it keeps crushing: walls in its path, settlers and animals it runs over
func _tick_boulder(dt: float, pos: Vector3, vel: Vector3) -> void:
	roll_age += dt
	_fb_acc += dt
	var sp: float = vel.length()
	if Terrain.current != null and pos.y - Terrain.h(pos.x, pos.z) < ammo.radius * 1.4 and sp > 3.0:
		if _last_roll_pos != Vector3.INF:
			Terrain.current.furrow(_last_roll_pos, pos, 1.1, 0.4)
		_last_roll_pos = pos
	else:
		_last_roll_pos = Vector3.INF
	if _fb_acc >= 0.1 and sp > 3.5:
		_fb_acc = 0.0
		var dir: Vector3 = vel / sp
		var crushed: int = Damage.impact_at(pos, 2.1, ammo.mass * sp * 0.52 * IMPACT_K, dir, source)
		crushed += Damage.smash_in_radius(pos, ammo.radius * 1.2 + 0.3, source, dir)
		if crushed > 0 and PhysWorld.bodies.has(body_id):
			# everything it smashes takes momentum away: walls slow and turn the boulder
			PhysWorld.set_velocity(body_id, vel * clampf(1.0 - 0.025 * float(crushed), 0.7, 1.0), PhysicsServer3D.body_get_state(PhysWorld.body_rid(body_id), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) as Vector3)
		Damage.damage_settlers_in_radius(pos, 2.6, clampf(sp * 3.0, 20.0, 90.0), source, dir, 0.9)
		if sp > 8.0:
			Fx.burst("dust", pos + Vector3.DOWN * ammo.radius * 0.6, Color("#8a6d4a"), 0.4, Vector3.UP)
			Events.camera_shake.emit(0.12)
	# a heavy ball keeps going; it is taken out after a while or when it has stopped
	if roll_age >= 10.0 or (roll_age > 1.0 and sp < 1.2):
		_finish(pos, false)

# ------------------------------------------------------------------ lumpy boulder geometry
## A potato-like rock: a sphere with a few broad bumps and dents, slightly stretched along random axes, sometimes one
## outlier lump. Returns {points: hull vertices (collision), mesh: ArrayMesh (visual)} built from the SAME vertices.
static func _boulder_geometry(r: Rng, radius: float) -> Dictionary:
	var bump_dir: Array[Vector3] = []
	var bump_amp: Array[float] = []
	var bump_w: Array[float] = []
	for k in r.range_i(4, 6):
		bump_dir.append(r.unit_vec3())
		bump_amp.append(r.range_f(-0.17, 0.15))
		bump_w.append(r.range_f(2.0, 5.0))
	if r.chance(0.3):
		bump_dir.append(r.unit_vec3())
		bump_amp.append(r.range_f(0.22, 0.38))
		bump_w.append(r.range_f(3.5, 6.0))
	var stretch := Vector3(r.range_f(0.85, 1.12), r.range_f(0.8, 1.1), r.range_f(0.85, 1.15))
	var rings: int = 9
	var segs: int = 14
	var pts := PackedVector3Array()
	# pole, rings, pole
	var dirs: Array[Vector3] = [Vector3.UP]
	for i in range(1, rings):
		var phi: float = PI * float(i) / float(rings)
		for j in segs:
			var th: float = TAU * float(j) / float(segs)
			dirs.append(Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)))
	dirs.append(Vector3.DOWN)
	for d in dirs:
		var f: float = 1.0
		for k2 in bump_dir.size():
			f += bump_amp[k2] * exp(-bump_w[k2] * (1.0 - d.dot(bump_dir[k2])))
		f = clampf(f, 0.62, 1.5)
		pts.append(d * radius * f * stretch)
	var buf := MeshGen.Buf.new()
	var base: Color = Color("#7a7a82").lerp(Color("#857b6e"), r.range_f(0.0, 1.0))
	var ids: Array[int] = []
	for i2 in pts.size():
		var n: Vector3 = pts[i2].normalized()
		var tint: float = r.range_f(-0.06, 0.06) + (0.05 if n.y > 0.3 else (-0.05 if n.y < -0.3 else 0.0))
		var col: Color = Color(clampf(base.r + tint, 0.0, 1.0), clampf(base.g + tint, 0.0, 1.0), clampf(base.b + tint, 0.0, 1.0))
		ids.append(buf.vert(pts[i2], n, col, n * MeshGen.OUTLINE_W))
	var last: int = pts.size() - 1
	for j2 in segs:
		var j3: int = (j2 + 1) % segs
		buf.tri(ids[0], ids[1 + j2], ids[1 + j3], Vector3.UP)
		var b0: int = 1 + (rings - 2) * segs
		buf.tri(ids[last], ids[b0 + j2], ids[b0 + j3], Vector3.DOWN)
	for i3 in range(0, rings - 2):
		for j4 in segs:
			var j5: int = (j4 + 1) % segs
			var a0: int = 1 + i3 * segs + j4
			var a1: int = 1 + i3 * segs + j5
			var b1: int = 1 + (i3 + 1) * segs + j4
			var b2: int = 1 + (i3 + 1) * segs + j5
			var fn: Vector3 = (pts[a0] + pts[a1] + pts[b1] + pts[b2]).normalized()
			buf.tri(ids[a0], ids[b1], ids[a1], fn)
			buf.tri(ids[a1], ids[b1], ids[b2], fn)
	return {"points": pts, "mesh": buf.to_mesh()}

## A barrel hull (convex): slightly bulging belly, narrower ends; axis = local Y. Rolls on its side like a barrel.
static func _barrel_shape(radius: float, height: float) -> PhysWorld.ShapeDesc:
	var sd := PhysWorld.ShapeDesc.new()
	sd.type = "convex"
	sd.uid = "barrel%.2f_%.2f" % [radius, height]
	var ring_r: Array[float] = [0.86, 0.96, 1.0, 0.96, 0.86]
	var pts := PackedVector3Array()
	for ri in ring_r.size():
		var y: float = height * (float(ri) / float(ring_r.size() - 1) - 0.5)
		for k in 14:
			var a: float = TAU * float(k) / 14.0
			pts.append(Vector3(cos(a) * radius * ring_r[ri], y, sin(a) * radius * ring_r[ri]))
	sd.points = pts
	return sd
