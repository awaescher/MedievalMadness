class_name Animal
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Animals (spec 10.1): chicken, sheep, cow, horse, duck, goose. Procedural models, wander AI, and a
## 2-body ragdoll (body + head, cone-twist joint) when hurt hard or dead.

enum State { WANDER, IDLE, FLEE, RAGDOLL, DEAD }

const HP: Dictionary = {"chicken": 15.0, "sheep": 20.0, "cow": 60.0, "horse": 60.0, "duck": 8.0, "goose": 8.0}
const SPEED: Dictionary = {"chicken": 1.0, "sheep": 0.9, "cow": 0.6, "horse": 1.4, "duck": 0.7, "goose": 1.4}
const SOUND: Dictionary = {"chicken": "bawk", "sheep": "baa", "cow": "moo", "horse": "neigh", "duck": "quack", "goose": "honk"}

static var all: Array[Animal] = []
static var world_root: Node3D
static var rng: Rng = Rng.new(23)
static var _mesh_cache: Dictionary = {}
static var _ragdolls: int = 0

var kind: String = "chicken"
var state: int = State.IDLE
var hp: float = 15.0
var dead: bool = false
var home: Vector3 = Vector3.ZERO
var roam: float = 10.0
var owner_id: int = -1
var body_node: MeshInstance3D
var head_node: MeshInstance3D
var _head_home: Vector3 = Vector3.ZERO
var _bodies: Array[int] = []
var _joint: RID
var _timer: float = 0.0
var _target: Vector3 = Vector3.ZERO
var _phase: float = 0.0
var _rag_time: float = 0.0
var _asleep: float = 0.0
var _flame: Fx.Flame
var _burn: float = 0.0
var floats: bool = false
var _size: Vector3 = Vector3(0.4, 0.4, 0.6)
var _head_r: float = 0.1
var _tick: int = 0
var _last_sound: float = -10.0
var scale_f: float = 1.0
var stable_door: Vector3 = Vector3.INF

static func reset() -> void:
	for a in all:
		if is_instance_valid(a):
			a._free_bodies()
			a.queue_free()
	all.clear()
	_ragdolls = 0

## Remove an animal from the world for good (used by events that spawn temporary animals)
func remove_from_world() -> void:
	_free_bodies()
	all.erase(self)
	if _flame != null and Fx.inst != null:
		Fx.inst.release_flame(_flame)
		_flame = null
	queue_free()

static func _meshes(k: String) -> Dictionary:
	if _mesh_cache.has(k):
		return _mesh_cache[k] as Dictionary
	var b := MeshGen.Buf.new()
	var h := MeshGen.Buf.new()
	var info: Dictionary = {}
	var id := Transform3D.IDENTITY
	match k:
		"chicken":
			MeshGen.add_ellipsoid(b, Vector3(0.17, 0.16, 0.24), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color("#f6f2e8"), 0.02, 6, 8)
			MeshGen.add_box(b, Vector3(0.08, 0.14, 0.2), Transform3D(Basis(Vector3(1, 0, 0), 0.5), Vector3(0, 0.38, -0.22)), Color("#e8e2d0"), 0.012)
			for lx in [-0.06, 0.06]:
				MeshGen.add_box(b, Vector3(0.025, 0.2, 0.025), Transform3D(Basis(), Vector3(lx as float, 0.1, 0.02)), Color("#f0a020"), 0.008)
			MeshGen.add_sphere(h, 0.09, id, Color("#f6f2e8"), 0.015, 5, 8)
			MeshGen.add_box(h, Vector3(0.04, 0.03, 0.08), Transform3D(Basis(), Vector3(0, -0.01, 0.1)), Color("#f0a020"), 0.008)
			MeshGen.add_box(h, Vector3(0.03, 0.06, 0.08), Transform3D(Basis(), Vector3(0, 0.1, 0.0)), Color("#e02020"), 0.008)
			info = {"size": Vector3(0.34, 0.32, 0.5), "body_off": Vector3(0, 0.3, 0), "head_r": 0.09, "head_off": Vector3(0, 0.5, 0.2), "scale": 1.0}
		"sheep":
			MeshGen.add_ellipsoid(b, Vector3(0.32, 0.3, 0.5), Transform3D(Basis(), Vector3(0, 0.6, 0)), Color("#f3ead6"), 0.03, 7, 10)
			MeshGen.add_sphere(b, 0.2, Transform3D(Basis(), Vector3(0, 0.8, -0.2)), Color("#f6eed9"), 0.02, 5, 8)
			for lx2 in [-0.16, 0.16]:
				for lz in [-0.28, 0.28]:
					MeshGen.add_box(b, Vector3(0.08, 0.4, 0.08), Transform3D(Basis(), Vector3(lx2 as float, 0.2, lz as float)), Color("#3a3a40"), 0.01)
			MeshGen.add_sphere(h, 0.15, id, Color("#45454c"), 0.02, 5, 8)
			MeshGen.add_box(h, Vector3(0.06, 0.08, 0.06), Transform3D(Basis(), Vector3(0.14, 0.06, -0.03)), Color("#45454c"), 0.008)
			MeshGen.add_box(h, Vector3(0.06, 0.08, 0.06), Transform3D(Basis(), Vector3(-0.14, 0.06, -0.03)), Color("#45454c"), 0.008)
			info = {"size": Vector3(0.6, 0.6, 1.0), "body_off": Vector3(0, 0.6, 0), "head_r": 0.15, "head_off": Vector3(0, 0.75, 0.55), "scale": 1.0}
		"cow":
			var white := Color("#f4f1e8")
			var black := Color("#2b2b33")
			MeshGen.add_box(b, Vector3(0.8, 0.75, 1.5), Transform3D(Basis(), Vector3(0, 1.0, 0)), white, 0.03)
			MeshGen.add_box(b, Vector3(0.5, 0.05, 0.6), Transform3D(Basis(), Vector3(0.05, 1.39, 0.1)), black, 0.01)
			MeshGen.add_box(b, Vector3(0.05, 0.4, 0.4), Transform3D(Basis(), Vector3(0.41, 1.05, -0.3)), black, 0.01)
			for lx3 in [-0.28, 0.28]:
				for lz2 in [-0.55, 0.55]:
					MeshGen.add_box(b, Vector3(0.16, 0.65, 0.16), Transform3D(Basis(), Vector3(lx3 as float, 0.33, lz2 as float)), white, 0.01)
					MeshGen.add_box(b, Vector3(0.18, 0.1, 0.18), Transform3D(Basis(), Vector3(lx3 as float, 0.05, lz2 as float)), black, 0.008)
			MeshGen.add_box(b, Vector3(0.28, 0.32, 0.2), Transform3D(Basis(), Vector3(0, 0.6, -0.3)), Color("#f2b6b6"), 0.01)
			MeshGen.add_box(h, Vector3(0.5, 0.5, 0.6), id, white, 0.02)
			MeshGen.add_box(h, Vector3(0.36, 0.26, 0.24), Transform3D(Basis(), Vector3(0, -0.12, 0.38)), Color("#f2b6b6"), 0.01)
			MeshGen.add_box(h, Vector3(0.06, 0.2, 0.06), Transform3D(Basis(Vector3(0, 0, 1), 0.5), Vector3(0.22, 0.32, 0.0)), Color("#e8dcb0"), 0.008)
			MeshGen.add_box(h, Vector3(0.06, 0.2, 0.06), Transform3D(Basis(Vector3(0, 0, 1), -0.5), Vector3(-0.22, 0.32, 0.0)), Color("#e8dcb0"), 0.008)
			info = {"size": Vector3(0.8, 0.9, 1.5), "body_off": Vector3(0, 1.0, 0), "head_r": 0.32, "head_off": Vector3(0, 1.3, 0.95), "scale": 1.0}
		"horse":
			var brown := Color("#8a5a2a")
			var dark := Color("#3a2a1a")
			MeshGen.add_box(b, Vector3(0.6, 0.7, 1.4), Transform3D(Basis(), Vector3(0, 1.15, 0)), brown, 0.03)
			MeshGen.add_box(b, Vector3(0.28, 0.9, 0.3), Transform3D(Basis(Vector3(1, 0, 0), -0.5), Vector3(0, 1.75, 0.62)), brown, 0.02)
			for lx4 in [-0.2, 0.2]:
				for lz3 in [-0.5, 0.5]:
					MeshGen.add_box(b, Vector3(0.13, 0.95, 0.13), Transform3D(Basis(), Vector3(lx4 as float, 0.48, lz3 as float)), brown, 0.01)
					MeshGen.add_box(b, Vector3(0.15, 0.1, 0.15), Transform3D(Basis(), Vector3(lx4 as float, 0.05, lz3 as float)), dark, 0.008)
			MeshGen.add_box(b, Vector3(0.1, 0.7, 0.3), Transform3D(Basis(Vector3(1, 0, 0), 0.25), Vector3(0, 1.0, -0.85)), dark, 0.01)
			MeshGen.add_box(b, Vector3(0.1, 0.6, 0.4), Transform3D(Basis(Vector3(1, 0, 0), -0.5), Vector3(0, 1.85, 0.5)), dark, 0.008)
			MeshGen.add_box(h, Vector3(0.28, 0.32, 0.7), Transform3D(Basis(Vector3(1, 0, 0), 0.3), Vector3.ZERO), brown, 0.02)
			MeshGen.add_box(h, Vector3(0.06, 0.2, 0.06), Transform3D(Basis(), Vector3(0.09, 0.26, -0.22)), brown, 0.008)
			MeshGen.add_box(h, Vector3(0.06, 0.2, 0.06), Transform3D(Basis(), Vector3(-0.09, 0.26, -0.22)), brown, 0.008)
			info = {"size": Vector3(0.6, 1.0, 1.4), "body_off": Vector3(0, 1.15, 0), "head_r": 0.22, "head_off": Vector3(0, 1.95, 0.95), "scale": 1.0}
		"duck":
			MeshGen.add_ellipsoid(b, Vector3(0.2, 0.15, 0.28), Transform3D(Basis(), Vector3(0, 0.17, 0)), Color("#f4f0e0"), 0.02, 6, 8)
			MeshGen.add_box(b, Vector3(0.1, 0.12, 0.1), Transform3D(Basis(), Vector3(0, 0.3, -0.27)), Color("#e8e2d0"), 0.01)
			MeshGen.add_sphere(h, 0.09, id, Color("#2f8a3a"), 0.012, 5, 8)
			MeshGen.add_box(h, Vector3(0.09, 0.03, 0.12), Transform3D(Basis(), Vector3(0, -0.02, 0.11)), Color("#f0a020"), 0.008)
			info = {"size": Vector3(0.4, 0.3, 0.56), "body_off": Vector3(0, 0.17, 0), "head_r": 0.09, "head_off": Vector3(0, 0.38, 0.22), "scale": 1.0}
		_:   # goose
			MeshGen.add_ellipsoid(b, Vector3(0.22, 0.2, 0.36), Transform3D(Basis(), Vector3(0, 0.4, 0)), Color("#ffffff"), 0.02, 6, 8)
			MeshGen.add_box(b, Vector3(0.09, 0.4, 0.09), Transform3D(Basis(Vector3(1, 0, 0), -0.25), Vector3(0, 0.72, 0.3)), Color("#ffffff"), 0.01)
			for lx5 in [-0.08, 0.08]:
				MeshGen.add_box(b, Vector3(0.03, 0.22, 0.03), Transform3D(Basis(), Vector3(lx5 as float, 0.11, 0.0)), Color("#f0a020"), 0.008)
			MeshGen.add_box(b, Vector3(0.14, 0.05, 0.3), Transform3D(Basis(Vector3(1, 0, 0), 0.4), Vector3(0, 0.5, -0.38)), Color("#f2f2f2"), 0.01)
			MeshGen.add_sphere(h, 0.1, id, Color("#ffffff"), 0.012, 5, 8)
			MeshGen.add_box(h, Vector3(0.06, 0.04, 0.13), Transform3D(Basis(), Vector3(0, -0.02, 0.12)), Color("#f0a020"), 0.008)
			info = {"size": Vector3(0.44, 0.4, 0.8), "body_off": Vector3(0, 0.4, 0), "head_r": 0.1, "head_off": Vector3(0, 0.95, 0.4), "scale": 1.0}
	info["body_mesh"] = b.to_mesh()
	info["head_mesh"] = h.to_mesh()
	_mesh_cache[k] = info
	return info

static func spawn(kind_name: String, pos: Vector3, owner: int, roam_radius: float, r: Rng) -> Animal:
	var a := Animal.new()
	a.kind = kind_name
	a.owner_id = owner
	a.hp = float(HP.get(kind_name, 15.0))
	a.home = pos
	a.roam = roam_radius
	a.name = kind_name.capitalize()
	var info: Dictionary = _meshes(kind_name)
	a._size = info["size"] as Vector3
	a._head_r = float(info["head_r"])
	a.body_node = MeshInstance3D.new()
	a.body_node.mesh = info["body_mesh"] as Mesh
	a.body_node.material_override = Toon.main()
	a.body_node.visibility_range_end = 120.0
	a.add_child(a.body_node)
	a.head_node = MeshInstance3D.new()
	a.head_node.mesh = info["head_mesh"] as Mesh
	a.head_node.material_override = Toon.main()
	a.head_node.position = info["head_off"] as Vector3
	a.head_node.visibility_range_end = 120.0
	a._head_home = a.head_node.position
	a.add_child(a.head_node)
	a.floats = kind_name == "duck"
	a.position = Vector3(pos.x, Terrain.h(pos.x, pos.z) if not a.floats else WaterSys.water_y(), pos.z)
	a.rotation.y = r.range_f(0.0, TAU)
	a._timer = r.range_f(0.5, 4.0)
	a._phase = r.range_f(0.0, TAU)
	world_root.add_child(a)
	all.append(a)
	return a

func global_pos() -> Vector3:
	if state == State.RAGDOLL and not _bodies.is_empty():
		return PhysWorld.get_transform(_bodies[0]).origin
	return global_position

func _process(delta: float) -> void:
	if dead or state == State.RAGDOLL:
		return
	_phase += delta * (4.0 if state == State.WANDER else 1.0) * (2.0 if state == State.FLEE else 1.0)
	if state == State.WANDER or state == State.FLEE:
		body_node.position.y = absf(sin(_phase * 2.0)) * 0.03
		head_node.position = _head_home + Vector3(0, absf(sin(_phase * 2.0)) * 0.03, 0)
	elif kind == "chicken" and state == State.IDLE:
		# peck
		var pk: float = maxf(sin(_phase * 3.0), 0.0)
		head_node.position = _head_home + Vector3(0, -pk * 0.18, pk * 0.06)
	else:
		head_node.position = _head_home

func hurt(amount: float, launch_vel: Vector3, source: Dictionary = {}) -> void:
	if dead:
		return
	hp -= amount
	if state != State.RAGDOLL and (hp <= 0.0 or launch_vel.length() > 6.0):
		_to_ragdoll(launch_vel)
	elif state == State.RAGDOLL:
		for id in _bodies:
			PhysWorld.apply_impulse(id, launch_vel * 6.0)
	if hp <= 0.0:
		dead = true
		Unlocks.on_animal_killed(kind, owner_id)
		var att: int = int(source.get("player_id", -1)) if not source.is_empty() else -1
		if att >= 0 and att != owner_id:
			Scoring.award(att, {"chicken": 30, "cow": 60, "sheep": 40, "horse": 80, "duck": 40, "goose": 40}.get(kind, 30), "animal_" + kind)
		Fx.burst("feather" if kind in ["chicken", "duck", "goose"] else "wool", global_pos() + Vector3.UP * 0.6, Color(0, 0, 0, -1), 0.8)
	_voice()

func _voice() -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	if now - _last_sound < 1.0:
		return
	_last_sound = now
	Sfx.play(str(SOUND.get(kind, "bawk")), global_pos(), 0.8, 1)
	if kind == "cow":
		Fx.comic_kind("cow", global_pos() + Vector3.UP * 2.5)
	if kind in ["chicken", "sheep"]:
		Fx.burst("feather" if kind == "chicken" else "wool", global_pos() + Vector3.UP * 0.5, Color(0, 0, 0, -1), 0.5)

func _free_bodies() -> void:
	if _joint.is_valid():
		PhysicsServer3D.free_rid(_joint)
		_joint = RID()
	for id in _bodies:
		if PhysWorld.bodies.has(id):
			var pb: PhysWorld.PBody = PhysWorld.body(id)
			pb.visual = null
			PhysWorld.remove_body(id)
	_bodies.clear()

func _to_ragdoll(velocity: Vector3) -> void:
	if state == State.RAGDOLL:
		return
	state = State.RAGDOLL
	_rag_time = 0.0
	_asleep = 0.0
	var info: Dictionary = _meshes(kind)
	var root_xf: Transform3D = global_transform
	var boff: Vector3 = info["body_off"] as Vector3
	var mass_body: float = maxf(_size.x * _size.y * _size.z * 180.0, 2.0)
	# body
	var d := PhysWorld.BodyDesc.new()
	d.shapes.append(PhysWorld.box_desc(_size, Transform3D(Basis(), boff)))
	d.xf = root_xf
	d.mass = mass_body
	d.friction = 0.7
	d.bounce = 0.3 if kind == "sheep" else 0.2
	d.layer = Cfg.LAYER_SETTLER
	d.mask = Cfg.LAYER_TERRAIN | Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_CATAPULT | Cfg.LAYER_PROJECTILE
	d.kind = "ragdoll"
	d.owner = self
	body_node.reparent(world_root, false)
	body_node.transform = root_xf
	d.visual = body_node
	d.velocity = velocity
	d.ang_velocity = Vector3(rng.range_f(-4, 4), rng.range_f(-4, 4), rng.range_f(-4, 4))
	d.damp_lin = 0.12
	d.damp_ang = 0.5
	var b_id: int = PhysWorld.add_body(d)
	# head
	var hoff: Vector3 = head_node.position
	var hd := PhysWorld.BodyDesc.new()
	hd.shapes.append(PhysWorld.sphere_desc(_head_r))
	hd.xf = root_xf * Transform3D(Basis(), hoff)
	hd.mass = maxf(mass_body * 0.15, 0.5)
	hd.friction = 0.7
	hd.bounce = 0.3
	hd.layer = Cfg.LAYER_SETTLER
	hd.mask = d.mask
	hd.kind = "ragdoll"
	hd.owner = self
	head_node.reparent(world_root, false)
	head_node.transform = hd.xf
	hd.visual = head_node
	hd.velocity = velocity * 1.1
	hd.damp_lin = 0.12
	hd.damp_ang = 0.5
	var h_id: int = PhysWorld.add_body(hd)
	_bodies = [b_id, h_id]
	_joint = PhysicsServer3D.joint_create()
	var neck_a: Vector3 = boff + Vector3(0, _size.y * 0.35, _size.z * 0.5)
	if kind == "horse":
		neck_a = boff + Vector3(0, 0.6, 0.6)
	PhysicsServer3D.joint_make_cone_twist(_joint, PhysWorld.body_rid(b_id), Transform3D(Basis(), root_xf.affine_inverse().basis * Vector3.ZERO + neck_a), PhysWorld.body_rid(h_id), Transform3D(Basis(), Vector3(0, 0, -_head_r * 0.8)))
	_ragdolls += 1

func ignite() -> void:
	if dead or _flame != null or state == State.RAGDOLL:
		return
	state = State.FLEE
	_burn = 4.0
	if Fx.inst != null:
		_flame = Fx.inst.acquire_flame(0.6)
	_voice()

func think(step: float) -> void:
	# called at ~10 Hz from the world manager
	if dead:
		return
	if state == State.RAGDOLL:
		_rag_time += step
		if not _bodies.is_empty():
			var sp: float = PhysWorld.get_velocity(_bodies[0]).length()
			_asleep = _asleep + step if sp < 0.4 and _rag_time > 0.8 else 0.0
			if _asleep > 2.5 or _rag_time > 10.0:
				_settle()
		return
	var pos: Vector3 = global_position
	if _flame != null:
		_flame.static_pos = pos + Vector3(0, 0.8, 0)
	if _burn > 0.0:
		_burn -= step
		hp -= 6.0 * step
		if hp <= 0.0:
			dead = true
			_to_ragdoll(Vector3.UP * 2.0)
			return
		if _burn <= 0.0 and _flame != null and Fx.inst != null:
			Fx.inst.release_flame(_flame)
			_flame = null
	# flee from fire (horses especially)
	if state != State.FLEE and Fire.fires_near(pos, 3.0 if kind != "horse" else 9.0):
		state = State.FLEE
		_burn = 0.0
		_timer = 3.0
		_target = pos + (pos - Fire.fire_center(owner_id)).normalized() * 8.0 if Fire.fire_center(owner_id) != Vector3.INF else pos + Vector3(rng.range_f(-6, 6), 0, rng.range_f(-6, 6))
	_timer -= step
	match state:
		State.IDLE:
			if _timer <= 0.0:
				_pick_target()
		State.WANDER:
			_walk(step, float(SPEED.get(kind, 1.0)))
			if pos.distance_to(_target) < 0.5 or _timer < -6.0:
				state = State.IDLE
				_timer = rng.range_f(1.0, 5.0)
			if rng.chance(0.01):
				_voice()
		State.FLEE:
			_walk(step, float(SPEED.get(kind, 1.0)) * 3.0)
			if _timer <= 0.0 and _burn <= 0.0:
				state = State.IDLE
				_timer = 2.0

func _pick_target() -> void:
	for t in 6:
		var off: Vector2 = rng.in_circle(roam)
		var p := Vector3(home.x + off.x, 0, home.z + off.y)
		p.y = Terrain.h(p.x, p.z)
		if floats:
			if Terrain.is_water(p.x, p.z):
				_target = p
				state = State.WANDER
				_timer = 6.0
				return
			continue
		if Terrain.is_water(p.x, p.z) or _blocked(p):
			continue
		_target = p
		state = State.WANDER
		_timer = 10.0
		return
	_timer = 2.0

func _blocked(p: Vector3) -> bool:
	for o in (Settler.obstacles.get(owner_id, []) as Array):
		var ov: Vector3 = o as Vector3
		if Vector2(p.x - ov.x, p.z - ov.y).length() < ov.z + 0.5:
			return true
	return false

func _walk(step: float, speed: float) -> void:
	var pos: Vector3 = global_position
	var to: Vector3 = _target - pos
	to.y = 0.0
	if to.length() < 0.05:
		return
	var dir: Vector3 = to.normalized()
	var next: Vector3 = pos + dir * speed * step
	for o in (Settler.obstacles.get(owner_id, []) as Array):
		var ov: Vector3 = o as Vector3
		var d2 := Vector2(next.x - ov.x, next.z - ov.y)
		if d2.length() < ov.z + 0.4:
			state = State.IDLE
			_timer = 1.0
			return
	if not floats and Terrain.is_water(next.x, next.z):
		state = State.IDLE
		_timer = 1.0
		return
	next.y = Terrain.h(next.x, next.z) if not floats else WaterSys.water_y() - 0.03
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(step * 8.0, 0.0, 1.0))
	position = next

func _settle() -> void:
	_ragdolls = maxi(_ragdolls - 1, 0)
	var bxf: Transform3D = PhysWorld.get_transform(_bodies[0])
	var hxf: Transform3D = PhysWorld.get_transform(_bodies[1])
	_free_bodies()
	body_node.transform = bxf
	head_node.transform = hxf
	if hp <= 0.0 or true:
		dead = hp <= 0.0
	if dead:
		state = State.DEAD
		return
	# stand up again
	position = Vector3(bxf.origin.x, Terrain.h(bxf.origin.x, bxf.origin.z), bxf.origin.z)
	rotation = Vector3(0, rotation.y, 0)
	body_node.reparent(self, false)
	head_node.reparent(self, false)
	body_node.transform = Transform3D.IDENTITY
	head_node.position = _head_home
	head_node.rotation = Vector3.ZERO
	state = State.IDLE
	_timer = 2.0

static func update_all(_dt: float) -> void:
	var i: int = all.size() - 1
	while i >= 0:
		var a: Animal = all[i]
		if not is_instance_valid(a):
			all.remove_at(i)
		else:
			a._tick += 1
			if a._tick % 6 == 0:
				a.think(0.1)
		i -= 1
