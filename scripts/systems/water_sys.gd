class_name WaterSys
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Water logic (spec 11.3): buoyancy + drag for bodies below the surface, surface-crossing splashes,
## water releases (barrels, tower, well, water balloon) with impulse volume, puddles that make things wet.

class Puddle extends RefCounted:
	var node: MeshInstance3D
	var t: float = 0.0
	var dur: float = 12.0
	var radius: float = 2.0
	var pos: Vector3
	var ground: PackedFloat32Array = PackedFloat32Array()   # soil heights (centre + 4 edge points) when it was made: if they change (crater, landslide) the puddle vanishes

static var puddles: Array[Puddle] = []
static var root: Node3D
static var rng: Rng = Rng.new(11)
static var _splash_cool: float = 0.0
static var flood_level: float = 0.0     # extra height added by the flood event
static var _disc: Mesh

static func reset() -> void:
	for p in puddles:
		if p.node != null and is_instance_valid(p.node):
			p.node.queue_free()
	puddles.clear()
	flood_level = 0.0

static func water_y() -> float:
	return Terrain.current.water_y if Terrain.current != null else Cfg.WATER_LEVEL

static func depth_at(x: float, z: float) -> float:
	return maxf(water_y() - Terrain.h(x, z), 0.0)

static func tick(dt: float) -> void:
	var wy: float = water_y()
	_splash_cool -= dt
	for id in PhysWorld.buoyant:
		var pb: PhysWorld.PBody = PhysWorld.buoyant[id] as PhysWorld.PBody
		if pb.buoy <= 0.0 or pb.mass <= 0.0:
			continue
		var y: float = pb.xform.origin.y
		var r: float = pb.radius
		if y - r > wy and not pb.under:
			continue
		var frac: float = clampf((wy - (y - r)) / (2.0 * r), 0.0, 1.0)
		var now_under: bool = frac > 0.0
		if now_under != pb.under:
			pb.under = now_under
			if _splash_cool <= 0.0 and PhysWorld.is_awake_recent(pb):
				var v: Vector3 = PhysWorld.get_velocity(pb.id)
				if v.length() > 3.0:
					_splash_cool = 0.05
					var pos := Vector3(pb.xform.origin.x, wy, pb.xform.origin.z)
					Fx.burst("splash", pos, Color(0, 0, 0, -1), clampf(v.length() / 14.0, 0.25, 1.0))
					Sfx.play("splash", pos, clampf(v.length() / 15.0, 0.2, 1.0), 0)
		if frac > 0.0 and PhysWorld.is_awake_recent(pb):
			var vel: Vector3 = PhysWorld.get_velocity(pb.id)
			var up: float = pb.mass * 19.62 * pb.buoy * frac
			var drag: Vector3 = -vel * pb.mass * 2.2 * frac
			PhysWorld.apply_force(pb.id, Vector3(0, up, 0) + drag)
		elif frac > 0.0 and pb.buoy > 1.0:
			PhysWorld.wake(pb.id)
	# puddles
	var i: int = puddles.size() - 1
	while i >= 0:
		var pd: Puddle = puddles[i]
		pd.t += dt
		if pd.t >= pd.dur or _ground_changed(pd):
			if pd.node != null:
				pd.node.queue_free()
			puddles.remove_at(i)
		else:
			var a: float = 0.6 * (1.0 - clampf((pd.t - pd.dur * 0.5) / (pd.dur * 0.5), 0.0, 1.0))
			pd.node.transparency = 1.0 - a
			var grow: float = clampf(pd.t * 3.0, 0.0, 1.0)
			pd.node.scale = Vector3(pd.radius * grow, 1.0, pd.radius * grow)
		i -= 1

const _PROBES: Array[Vector2] = [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

static func _probe_heights(pos: Vector3, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for o in _PROBES:
		out.append(Terrain.h(pos.x + o.x * radius * 0.7, pos.z + o.y * radius * 0.7))
	return out

static func _ground_changed(pd: Puddle) -> bool:
	var now: PackedFloat32Array = _probe_heights(pd.pos, pd.radius)
	for k in now.size():
		if absf(now[k] - pd.ground[k]) > 0.25:
			return true
	return false

## Water released at `pos` (barrel, tower, well, balloon)
static func splash(pos: Vector3, radius: float, source: Dictionary, strength: float = 1.0, wet_seconds: float = 15.0, wet_radius: float = 6.0) -> void:
	Fire.extinguish_in_radius(pos, radius, source, 0.0)
	Fire.set_wet(pos, minf(wet_radius, radius + 2.0), wet_seconds)
	Fx.burst("splash", pos + Vector3.UP * 0.3, Color(0, 0, 0, -1), clampf(strength, 0.3, 1.0), Vector3.UP)
	Fx.burst("droplet", pos + Vector3.UP * 0.5, Color(0, 0, 0, -1), clampf(strength, 0.3, 1.0), Vector3.UP)
	Sfx.play("splash", pos, clampf(0.5 + strength * 0.5, 0.4, 1.2), 2)
	Fx.comic_kind("water", pos + Vector3.UP * 2.0)
	# impulse volume on light bodies
	var imp: float = 260.0 * strength
	PhysWorld.overlap_sphere(pos, radius + 1.0, func(pb: PhysWorld.PBody, _shape: int, _rid: RID) -> void:
		if pb == null or pb.mass <= 0.0 or pb.mass > 260.0 or PhysicsServer3D.body_get_mode(pb.rid) != PhysicsServer3D.BODY_MODE_RIGID:
			return
		var d: Vector3 = pb.xform.origin - pos
		var f: float = 1.0 - clampf(d.length() / (radius + 1.0), 0.0, 1.0)
		var dir: Vector3 = (d.normalized() if d.length() > 0.05 else Vector3.UP) + Vector3.UP * 0.5
		PhysWorld.apply_impulse(pb.id, dir.normalized() * imp * f * minf(pb.mass, 60.0) / 30.0))
	for st in Settler.all:
		var d2: float = (st.global_pos() - pos).length()
		if d2 < radius + 1.0:
			var dir2: Vector3 = ((st.global_pos() - pos).normalized() + Vector3.UP * 0.6).normalized()
			st.push(dir2 * 7.0 * strength * (1.0 - d2 / (radius + 1.0)), source)
	add_puddle(pos, radius * 0.6)

static func add_puddle(pos: Vector3, radius: float) -> void:
	if root == null:
		return
	if _disc == null:
		_disc = MeshGen.disc_mesh(1.0, 24)
	# water does not lie on a slope: a flat disc would hover over the downhill side (and the water would just run off)
	var probes: PackedFloat32Array = _probe_heights(pos, radius)
	var lo: float = probes[0]
	var hi: float = probes[0]
	for hv in probes:
		lo = minf(lo, hv)
		hi = maxf(hi, hv)
	if hi - lo > 0.18 + radius * 0.04:
		return
	var pd := Puddle.new()
	pd.node = MeshInstance3D.new()
	pd.node.mesh = _disc
	pd.node.material_override = Toon.unlit(Color("#4aa8ff"), false)
	pd.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pd.node.position = Vector3(pos.x, Terrain.h(pos.x, pos.z) + 0.06, pos.z)
	pd.node.scale = Vector3(0.1, 1.0, 0.1)
	root.add_child(pd.node)
	pd.radius = radius
	pd.pos = pos
	pd.ground = _probe_heights(pos, radius)
	puddles.append(pd)
	if puddles.size() > 24:
		var old: Puddle = puddles.pop_front()
		if old.node != null:
			old.node.queue_free()
