class_name Explosion
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Explosion system (spec 11.2): impulses on bodies, damage on parts/settlers/catapults, crater,
## fireball + smoke + shockwave fx, screen shake, slow motion, chain reactions for powder kegs.

static var _pending: Array = []      # [{t, pos, radius, dmg, opts}]
static var rng: Rng = Rng.new(13)
static var active_until: float = 0.0
static var _time: float = 0.0

const SHOCK_SPEED := 42.0           # m/s the pressure wave front travels

class Shock extends RefCounted:
	var pos: Vector3
	var radius: float
	var strength: float                # impulse (N*s) at the center
	var t: float = 0.0
	var done: Dictionary = {}          # body id / part id / settler instance id -> true
	var ring: MeshInstance3D
	var mat: StandardMaterial3D
	var source: Dictionary = {}

static var shocks: Array[Shock] = []

static func reset() -> void:
	_pending.clear()
	active_until = 0.0
	for sh in shocks:
		if sh.ring != null and is_instance_valid(sh.ring):
			sh.ring.queue_free()
	shocks.clear()

static func is_active() -> bool:
	return _time < active_until or not _pending.is_empty() or not shocks.is_empty()

static func schedule(delay: float, pos: Vector3, radius: float, dmg: float, opts: Dictionary) -> void:
	_pending.append({"t": delay, "pos": pos, "radius": radius, "dmg": dmg, "opts": opts})

static func schedule_keg(part: Part, delay: float, source: Dictionary) -> void:
	_pending.append({"t": delay, "keg": part, "source": source})

static func tick(dt: float) -> void:
	_time += dt
	_tick_shocks(dt)
	var i: int = _pending.size() - 1
	while i >= 0:
		var e: Dictionary = _pending[i]
		e["t"] = float(e["t"]) - dt
		if float(e["t"]) <= 0.0:
			_pending.remove_at(i)
			if e.has("keg"):
				var kp: Part = e["keg"] as Part
				if kp.state != Part.State.DEAD:
					Props.detonate_powder(kp, e["source"] as Dictionary)
			else:
				explode(e["pos"] as Vector3, float(e["radius"]), float(e["dmg"]), e["opts"] as Dictionary)
		i -= 1

## opts: {fire: bool, source: Dictionary, sound: String, keg: bool, color: Color, no_crater: bool}
static func explode(pos: Vector3, radius: float, max_damage: float, opts: Dictionary = {}) -> void:
	var source: Dictionary = opts.get("source", {}) as Dictionary
	var with_fire: bool = bool(opts.get("fire", false))
	var sound: String = str(opts.get("sound", "boom"))
	active_until = _time + 0.8
	Scoring.on_explosion()
	# 1+2. physical impulses on non-part bodies
	PhysWorld.overlap_sphere(pos, radius, func(pb: PhysWorld.PBody, _shape: int, _rid: RID) -> void:
		if pb == null or pb.mass <= 0.0 or pb.owner is Part:
			return
		if PhysicsServer3D.body_get_mode(pb.rid) != PhysicsServer3D.BODY_MODE_RIGID:
			return
		var d: Vector3 = pb.xform.origin - pos
		var f: float = 1.0 - clampf(d.length() / radius, 0.0, 1.0)
		var dir: Vector3 = ((d.normalized() if d.length() > 0.05 else Vector3.UP) + Vector3.UP * 0.4).normalized()
		PhysWorld.apply_impulse_capped(pb.id, dir * max_damage * f * 0.6, 28.0))
	# 3. damage
	Damage.damage_in_radius(pos, radius, max_damage, source)
	var killed: int = Damage.damage_settlers_in_radius(pos, radius, max_damage, source)
	Damage.damage_catapults_in_radius(pos, radius, max_damage, source, 0.6, float(opts.get("cat_scale", 0.14)))
	# 4. crater
	if not bool(opts.get("no_crater", false)) and Terrain.current != null and radius >= 2.5:
		# blasts near the ground dig real craters (and can start landslides on steep slopes)
		var above: float = pos.y - Terrain.h(pos.x, pos.z)
		var near_ground: float = clampf(1.0 - above / (radius * 1.2), 0.0, 1.0)
		if near_ground > 0.15:
			# a real crater with a raised rim of thrown-out soil
			var crater_depth: float = radius * 0.4 * near_ground
			Terrain.current.dig(pos, radius * 0.7, crater_depth, 0.85, 0.6, crater_depth * 0.2)
			Landslide.trigger(pos, max_damage / 1200.0 * near_ground, source)
	# 5. fx
	var col: Color = opts.get("color", Color("#ffb347")) as Color
	var big: bool = max_damage >= 700.0
	Fx.explosion_visual(pos, radius, col, big)
	if radius >= 4.0:
		Fx.comic_kind("explosion", pos + Vector3.UP * (radius * 0.8))
	Sfx.play("bigboom" if (big or sound == "bigboom") else sound, pos, clampf(radius / 6.0, 0.6, 1.4), 5)
	Events.camera_shake.emit(minf(1.5, max_damage / 900.0))
	if max_damage >= 5000.0:
		Events.slowmo.emit(0.12, 2.8)         # the red barrel: epic bullet time
	elif max_damage >= 700.0 or killed >= 3:
		Events.slowmo.emit(Cfg.SLOWMO_SCALE, 0.8)
	# 6. fire
	if with_fire:
		Fire.ignite_in_radius(pos, radius * 0.8, 1.0, source)
	else:
		Fire.ignite_in_radius(pos, radius * 0.7, 0.5, source)
	# 6b. pressure wave (big blasts): shoves light things, settlers and props farther out, never hurts catapults
	if bool(opts.get("shock", radius >= 6.0)):
		shockwave(pos, radius * 2.4, max_damage * 0.55, source, col)
	# 7. chain reaction: powder kegs in radius detonate after 0.1-0.35 s
	for st in Breakable.structures:
		if not st.free_parts or not st.aabb.grow(radius).has_point(pos):
			continue
		for p in st.parts:
			if p.state != Part.State.DEAD and p.prop_kind == "barrel_powder" and (p.xf.origin - pos).length() <= radius:
				_pending.append({"t": rng.range_f(0.1, 0.35), "keg": p, "source": source})
	Events.explosion.emit(pos, radius, max_damage, source)

# ------------------------------------------------------------------ pressure wave
## An expanding wave front: bodies, light building parts, settlers and animals are hit when the front passes them
## (nearer things first). Catapults are deliberately ignored: a shockwave never destroys or moves them.
static func shockwave(pos: Vector3, radius: float, strength: float, source: Dictionary, col: Color = Color("#ffb347")) -> void:
	var sh := Shock.new()
	sh.pos = pos
	sh.radius = radius
	sh.strength = strength
	sh.source = source
	if Game.world != null and is_instance_valid(Game.world.fx_root):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.93
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 6
		ring.mesh = tm
		sh.mat = StandardMaterial3D.new()
		sh.mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sh.mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sh.mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sh.mat.disable_fog = true
		sh.mat.albedo_color = Color(col.r, col.g, col.b, 0.7).lerp(Color(1, 1, 1, 0.7), 0.5)
		ring.material_override = sh.mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Game.world.fx_root.add_child(ring)
		ring.global_position = Vector3(pos.x, maxf(Terrain.h(pos.x, pos.z), Cfg.WATER_LEVEL) + 0.6, pos.z)
		ring.scale = Vector3(0.1, 0.1, 0.1)
		sh.ring = ring
	shocks.append(sh)

static func _tick_shocks(dt: float) -> void:
	var i: int = shocks.size() - 1
	while i >= 0:
		var sh: Shock = shocks[i]
		sh.t += dt
		var front: float = minf(sh.t * SHOCK_SPEED, sh.radius)
		_shock_apply(sh, front)
		if sh.ring != null and is_instance_valid(sh.ring):
			var k: float = clampf(front, 0.1, sh.radius)
			sh.ring.scale = Vector3(k, clampf(k * 0.05, 0.2, 1.2), k)
			sh.mat.albedo_color.a = 0.7 * (1.0 - front / sh.radius)
		if front >= sh.radius:
			if sh.ring != null and is_instance_valid(sh.ring):
				sh.ring.queue_free()
			shocks.remove_at(i)
		i -= 1

static func _shock_apply(sh: Shock, front: float) -> void:
	var pos: Vector3 = sh.pos
	var R: float = sh.radius
	# loose bodies (props, debris, free parts are handled below)
	PhysWorld.overlap_sphere(pos, front, func(pb: PhysWorld.PBody, _shape: int, _rid: RID) -> void:
		if pb == null or pb.mass <= 0.0 or pb.owner is Part or pb.kind == "catapult" or sh.done.has(pb.id):
			return
		if PhysicsServer3D.body_get_mode(pb.rid) != PhysicsServer3D.BODY_MODE_RIGID:
			return
		sh.done[pb.id] = true
		var d: Vector3 = pb.xform.origin - pos
		var f: float = 1.0 - clampf(d.length() / R, 0.0, 1.0)
		var dir: Vector3 = ((d.normalized() if d.length() > 0.05 else Vector3.UP) + Vector3.UP * 0.35).normalized()
		PhysWorld.apply_impulse_capped(pb.id, dir * sh.strength * f * f, 14.0))
	# building parts: everything light enough is shoved, the most fragile ones break
	var box := AABB(pos - Vector3.ONE * front, Vector3.ONE * front * 2.0)
	for st in Breakable.structures:
		if not st.aabb.grow(2.0).intersects(box):
			continue
		for p in st.parts:
			if p.state == Part.State.DEAD or sh.done.has(p.id + 1000000):
				continue
			var dv: Vector3 = p.xf.origin - pos
			var dl: float = dv.length()
			if dl > front:
				continue
			sh.done[p.id + 1000000] = true
			var f2: float = 1.0 - clampf(dl / R, 0.0, 1.0)
			if f2 <= 0.02:
				continue
			var light: bool = p.mass < 40.0 and p.mat.break_force < 400.0
			var dir2: Vector3 = ((dv.normalized() if dl > 0.05 else Vector3.UP) + Vector3.UP * 0.3).normalized()
			if p.state == Part.State.FREE:
				PhysWorld.apply_impulse_capped(p.body_id, dir2 * sh.strength * f2 * f2 * (1.0 if light else 0.35), 12.0)
			elif light:
				if not st.awake:
					Breakable.awaken(st)
				p.kick += dir2 * minf(sh.strength * f2 * f2 / maxf(p.mass, 1.0), 10.0)
				Damage.damage_part(p, sh.strength * f2 * 0.05, sh.source, dir2)
	# settlers and animals get knocked over (not killed: the real damage comes from the blast itself)
	for se in Settler.all:
		if se.state == Settler.State.DEAD or se.state == Settler.State.GONE or sh.done.has(se.get_instance_id()):
			continue
		var ds: Vector3 = se.global_pos() - pos
		if ds.length() > front:
			continue
		sh.done[se.get_instance_id()] = true
		var f3: float = 1.0 - clampf(ds.length() / R, 0.0, 1.0)
		if f3 < 0.05:
			continue
		var dir3: Vector3 = ((ds.normalized() if ds.length() > 0.05 else Vector3.UP) + Vector3.UP * 0.6).normalized()
		se.hurt(6.0 * f3, sh.source, dir3 * (4.0 + 12.0 * f3), true)
	for an in Animal.all:
		if an.dead or sh.done.has(an.get_instance_id()):
			continue
		var da: Vector3 = an.global_pos() - pos
		if da.length() > front:
			continue
		sh.done[an.get_instance_id()] = true
		var f4: float = 1.0 - clampf(da.length() / R, 0.0, 1.0)
		if f4 > 0.05:
			an.hurt(5.0 * f4, ((da.normalized() if da.length() > 0.05 else Vector3.UP) + Vector3.UP * 0.6).normalized() * (5.0 + 10.0 * f4), sh.source)
