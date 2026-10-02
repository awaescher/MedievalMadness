class_name Specials
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Special behaviors of individual building types (spec 9 "Special behavior" column).
## Breakable calls these hooks by name: on_awaken, on_release, on_hit, on_part_break, on_fire, on_destroyed, tick.

class Behavior extends RefCounted:
	var fired: bool = false
	func on_awaken(_s: Structure) -> void:
		pass
	func on_release(_s: Structure, _p: Part) -> void:
		pass
	func on_hit(_s: Structure, _p: Part, _amount: float) -> void:
		pass
	func on_part_break(_s: Structure, _p: Part) -> void:
		pass
	func on_fire(_s: Structure, _p: Part) -> void:
		pass
	func on_destroyed(_s: Structure) -> void:
		pass
	func tick(_s: Structure, _dt: float) -> void:
		pass

## Church: bell rings on any impact within 30 m
class Church extends Behavior:
	pass

## Tavern: destroyed -> 6 beer geysers
class Tavern extends Behavior:
	func on_destroyed(s: Structure) -> void:
		for i in 6:
			var a: float = float(i) / 6.0 * TAU
			var p: Vector3 = s.center + Vector3(cos(a) * 2.5, 0.5, sin(a) * 2.0)
			Fx.burst("beer", p, Color(0, 0, 0, -1), 1.0, Vector3.UP)
		Fx.burst("splash", s.center, Color("#e8b03a"), 1.0)
		Sfx.play("splash", s.center, 1.0, 3)
		Fx.comic_kind("water", s.center + Vector3.UP * 4.0)

## Watchtower: the archer falls when the tower goes
class Watchtower extends Behavior:
	var archer: Settler = null
	var released: bool = false
	func tick(s: Structure, _dt: float) -> void:
		if archer == null or released:
			return
		if s.destroyed_fraction() > 0.3 or not s.has_tag("platform"):
			released = true
			archer.is_archer = false
			archer.push(Vector3(randf_range(-4, 4), 7.0, randf_range(-4, 4)), s.last_source)

## Powder store: any fire / big hit -> all kegs explode in a chain
class PowderStore extends Behavior:
	var kegs: Array[Part] = []
	var armed: bool = true
	func _chain(s: Structure) -> void:
		if not armed:
			return
		armed = false
		var src: Dictionary = Damage.source_for(s)
		Events.banner.emit(I18n.t("banner.powder"), "powder")
		var delay: float = 0.15
		for k in kegs:
			if k.state != Part.State.DEAD:
				Explosion.schedule_keg(k, delay, src)
				delay += 0.18
		Fx.burst("smoke", s.center + Vector3.UP * 3.0, Color(0.15, 0.13, 0.13), 1.0)
	func on_fire(s: Structure, _p: Part) -> void:
		_chain(s)
	func on_hit(s: Structure, _p: Part, amount: float) -> void:
		if amount > 60.0:
			_chain(s)
	func on_part_break(s: Structure, _p: Part) -> void:
		if s.destroyed_fraction() > 0.25:
			_chain(s)

## Water tower: tank rupture releases a flood
class WaterTower extends Behavior:
	func on_part_break(s: Structure, p: Part) -> void:
		if fired or p.tag != "tank":
			return
		fired = true
		var pos: Vector3 = p.xf.origin
		var src: Dictionary = Damage.source_for(s)
		WaterSys.splash(pos, 10.0, src, 2.2, 20.0, 9.0)
		for i in 30:
			Fx.burst("droplet", pos + Vector3(randf_range(-1.5, 1.5), randf_range(-1, 1), randf_range(-1.5, 1.5)), Color(0, 0, 0, -1), 0.4)
		Fx.comic_kind("water", pos + Vector3.UP * 3.0)

## Well: destroyed -> fountain for 10 s that puts out fires within 6 m
class Well extends Behavior:
	var gush: float = 0.0
	var pos: Vector3
	func on_destroyed(s: Structure) -> void:
		gush = 10.0
		pos = s.center
		Settler.water_points[s.owner_id] = (Settler.water_points.get(s.owner_id, []) as Array).filter(func(v: Variant) -> bool: return (v as Vector3).distance_to(s.center) > 1.0)
	func tick(_s: Structure, dt: float) -> void:
		if gush > 0.0:
			gush -= dt
			if int(gush * 4.0) != int((gush + dt) * 4.0):
				Fx.burst("splash", pos + Vector3.UP * 0.5, Color(0, 0, 0, -1), 0.5, Vector3.UP)
				Fx.burst("droplet", pos + Vector3.UP * 0.5, Color(0, 0, 0, -1), 0.5, Vector3.UP)
			if int(gush) != int(gush + dt):
				Fire.extinguish_in_radius(pos, 6.0, {}, 0.0)
				WaterSys.add_puddle(pos, 1.6)

## Granary: sacks burst into flour; flour dust explodes near fire
class Granary extends Behavior:
	func on_part_break(s: Structure, p: Part) -> void:
		if p.tag != "sack":
			return
		Fx.burst("puff", p.xf.origin, Color("#f8f4ea"), 1.0)
		if Fire.fires_near(p.xf.origin, 5.0) or p.burning > 0.2:
			Explosion.explode(p.xf.origin, 4.0, 250.0, {"source": Damage.source_for(s), "fire": true, "sound": "boom", "no_crater": true})

## Blacksmith: forge coals scatter as fire when destroyed
class Blacksmith extends Behavior:
	var flame: Fx.Flame = null
	func on_part_break(s: Structure, p: Part) -> void:
		if p.tag != "coal" or fired:
			return
		fired = true
		var src: Dictionary = Damage.source_for(s)
		if flame != null and Fx.inst != null:
			Fx.inst.release_flame(flame)
			flame = null
		for i in 5:
			var a: float = randf_range(0.0, TAU)
			var q: Vector3 = p.xf.origin + Vector3(cos(a) * randf_range(1.0, 3.0), 0.0, sin(a) * randf_range(1.0, 3.0))
			Fire.spawn_ground_fire(q, src, 3.0)
		Fire.ignite_in_radius(p.xf.origin, 3.0, 0.9, src)
		Fx.burst("spark", p.xf.origin, Color(0, 0, 0, -1), 1.0)

## Outhouse: the occupant is launched with "OCCUPIED!!!"
class Outhouse extends Behavior:
	var has_occupant: bool = false
	func on_destroyed(s: Structure) -> void:
		if fired:
			return
		fired = true
		Fx.comic_kind("outhouse", s.center + Vector3.UP * 3.0)
		Sfx.play("scream", s.center, 1.0, 3)
		if has_occupant and Game.world != null:
			var st: Settler = Game.world.call("spawn_settler", s.owner_id, s.center, 0.0) as Settler
			if st != null:
				st.position = Vector3(s.center.x, Terrain.h(s.center.x, s.center.z) + 0.3, s.center.z)
				Speech.say_random("speech.outhouse", st, st, Game.rng_battle, 2.6)
				var a: float = Game.rng_battle.range_f(0.0, TAU)
				st.hurt(5.0, Damage.source_for(s), Vector3(cos(a) * 9.0, 15.0, sin(a) * 9.0), true, true)

## Barn: hay bursts when hit
class Barn extends Behavior:
	func on_part_break(_s: Structure, p: Part) -> void:
		if p.tag == "hay":
			Fx.burst("straw", p.xf.origin, Color("#e6cf6a"), 1.0)

## Windmill: the hinged rotor spins until the mill is damaged, then the sails fall off (spec 9)
class Windmill extends Behavior:
	var rotor_id: int = 0
	var hub_id: int = 0
	var joint: RID
	var pos: Vector3
	var base_xf: Transform3D
	var keep: Array = []
	var attached: bool = true
	var visual: MeshInstance3D
	var owner_pid: int = -1
	var speed: float = 0.7
	var spin_boost: float = 0.0
	func setup(s: Structure, world_pos: Vector3, yaw: float) -> void:
		owner_pid = s.owner_id
		pos = world_pos
		base_xf = Transform3D(Basis(Vector3.UP, yaw), world_pos)
		# rotor: one dynamic body with 4 sail shapes forming a cross, visual = same
		var buf := MeshGen.Buf.new()
		var d := PhysWorld.BodyDesc.new()
		for i in 4:
			var a: float = float(i) * PI * 0.5 + PI * 0.25
			var sail_rot := Basis(Vector3(0, 0, 1), a)
			var c: Vector3 = sail_rot * Vector3(0, 2.9, 0)
			var xf := Transform3D(sail_rot, c)
			MeshGen.add_box(buf, Vector3(0.14, 5.4, 0.12), xf, Color("#8a5a2a"))
			var cloth_xf := Transform3D(sail_rot, sail_rot * Vector3(0.0, 3.3, 0.02) + sail_rot * Vector3(0.6, 0, 0))
			MeshGen.add_box(buf, Vector3(1.1, 3.6, 0.05), cloth_xf, Color("#f4efe0"))
			d.shapes.append(PhysWorld.box_desc(Vector3(0.3, 5.4, 0.2), xf))
			d.shapes.append(PhysWorld.box_desc(Vector3(1.1, 3.6, 0.1), cloth_xf))
		MeshGen.add_cyl(buf, 0.35, 0.5, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0)), Color("#5c6672"))
		visual = MeshInstance3D.new()
		visual.mesh = buf.to_mesh()
		visual.material_override = Toon.main()
		s.root.add_child(visual)
		d.xf = base_xf
		d.mass = 220.0
		d.friction = 0.5
		d.bounce = 0.1
		d.layer = Cfg.LAYER_PROP
		d.mask = Cfg.LAYER_TERRAIN | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_PROJECTILE | Cfg.LAYER_DEBRIS
		d.kind = "part"
		d.owner = null
		d.visual = visual
		d.damp_lin = 0.5
		d.damp_ang = 0.05
		d.can_sleep = false
		rotor_id = PhysWorld.add_body(d)
		# hub: tiny static body inside the tower; hinge between hub and rotor, axis = local Z of the frames
		var hd := PhysWorld.BodyDesc.new()
		hd.shapes.append(PhysWorld.box_desc(Vector3(0.2, 0.2, 0.2)))
		hd.xf = base_xf
		hd.mode = "static"
		hd.layer = 0
		hd.mask = 0
		hd.kind = "struct"
		hub_id = PhysWorld.add_body(hd)
		joint = PhysWorld.new_joint()
		PhysicsServer3D.joint_make_hinge(joint, PhysWorld.body_rid(hub_id), Transform3D.IDENTITY, PhysWorld.body_rid(rotor_id), Transform3D.IDENTITY)
		PhysicsServer3D.hinge_joint_set_flag(joint, PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR, true)
		PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY, speed)
		PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE, 400.0)
	func detach(s: Structure) -> void:
		if not attached:
			return
		attached = false
		if joint.is_valid():
			PhysWorld.free_joint(joint)
			joint = RID()
		if not PhysWorld.bodies.has(rotor_id):
			return
		var xf: Transform3D = PhysWorld.get_transform(rotor_id)
		PhysWorld.remove_body(rotor_id)
		rotor_id = 0
		if PhysWorld.bodies.has(hub_id):
			PhysWorld.remove_body(hub_id)
			hub_id = 0
		# four sail parts fall off and roll away
		var b := BuildResult.new()
		var rng: Rng = Game.rng_battle
		for i in 4:
			var a: float = float(i) * PI * 0.5 + PI * 0.25
			var rot := Basis(Vector3(0, 0, 1), a)
			var sail := Kit.box(b, "plank", Vector3(1.0, 5.2, 0.1), rot * Vector3(0.3, 2.9, 0), rng, Color("#e8dcc0"), false, "sail", rot.get_euler())
			sail.mass_override = 40.0
		var sp: Structure = Breakable.create("prop_sails", s.owner_id, b, xf, true, "building.windmill")
		sp.is_decor = true
		for p in sp.parts:
			var out: Vector3 = (p.xf.origin - xf.origin).normalized() + Vector3.UP * 0.6
			PhysWorld.set_velocity(p.body_id, out * rng.range_f(2.0, 6.0), Vector3(rng.range_f(-3, 3), rng.range_f(-3, 3), rng.range_f(-3, 3)))
			Debris.register_part(p)
			Fire.build_grid_add(sp)
		Fx.burst("splinter", xf.origin, Color("#8a5a2a"), 1.0)
		Sfx.play("crunch", xf.origin, 1.0, 3)
		Fx.comic_kind("wood", xf.origin + Vector3.UP * 2.0)
	func on_hit(s: Structure, _p: Part, _amount: float) -> void:
		detach(s)
	func on_part_break(s: Structure, _p: Part) -> void:
		detach(s)
	func on_fire(_s: Structure, _p: Part) -> void:
		spin_boost = 2.0
	func tick(s: Structure, _dt: float) -> void:
		if not attached:
			return
		# burning sails spin faster (glow)
		if spin_boost > 0.0 and joint.is_valid():
			PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY, speed * 3.0)
		# wind: a bit faster in storms
		elif joint.is_valid():
			var target: float = speed * (1.0 + Game.wind.length() * 0.06)
			PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY, target)
		if s.destroyed and attached:
			detach(s)
	func cleanup() -> void:
		if joint.is_valid():
			PhysWorld.free_joint(joint)
			joint = RID()

static func attach(s: Structure, _extras: Array = []) -> void:
	match s.kind:
		"church":
			s.behavior = Church.new()
		"tavern":
			s.behavior = Tavern.new()
		"watchtower":
			s.behavior = Watchtower.new()
		"powderstore":
			s.behavior = PowderStore.new()
		"watertower":
			s.behavior = WaterTower.new()
		"well":
			s.behavior = Well.new()
		"granary":
			s.behavior = Granary.new()
		"blacksmith":
			s.behavior = Blacksmith.new()
		"outhouse":
			s.behavior = Outhouse.new()
		"barn":
			s.behavior = Barn.new()
		"windmill":
			s.behavior = Windmill.new()
		_:
			pass

# ------------------------------------------------------------------ global: bell + signals
static var _connected: bool = false
static var _last_bell: float = -10.0

static func connect_signals() -> void:
	if _connected:
		return
	_connected = true
	Events.explosion.connect(_on_explosion)
	Events.projectile_impact.connect(_on_impact)

static func _on_explosion(pos: Vector3, _r: float, _d: float, _src: Dictionary) -> void:
	_bell(pos)

static func _on_impact(_pid: int, _ammo: String, pos: Vector3, _speed: float) -> void:
	_bell(pos)

static func _bell(pos: Vector3) -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	if now - _last_bell < 1.5:
		return
	for s in Breakable.structures:
		if s.kind != "church" or s.destroyed:
			continue
		if s.center.distance_to(pos) > 30.0:
			continue
		var bell_alive: bool = false
		for p in s.parts:
			if p.tag == "bell" and p.state != Part.State.DEAD:
				bell_alive = true
				break
		if bell_alive:
			_last_bell = now
			Sfx.play("bell", s.center + Vector3.UP * 8.0, 1.0, 4)
			Fx.comic_kind("bell", s.center + Vector3.UP * 11.0)
			return
