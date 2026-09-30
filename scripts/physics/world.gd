class_name PhysWorld
extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Thin wrapper over PhysicsServer3D (spec 15.2 / 20). Owns all body RIDs, ids, freeing and the
## id -> object registry. One instance is created by main.gd ("PhysRoot"); everything else is static.

class ShapeDesc extends RefCounted:
	var type: String = "box"          # box | cyl | sphere | capsule
	var size: Vector3 = Vector3.ONE    # box: full extents; cyl: x=radius, y=height; sphere: x=radius; capsule: x=radius,y=height
	var xf: Transform3D = Transform3D.IDENTITY
	var points: PackedVector3Array = PackedVector3Array()   # type "convex": hull points
	var uid: String = ""                                     # type "convex": unique cache key

class BodyDesc extends RefCounted:
	var shapes: Array[ShapeDesc] = []
	var xf: Transform3D = Transform3D.IDENTITY
	var mass: float = 1.0
	var friction: float = 0.6
	var bounce: float = 0.2
	var layer: int = Cfg.LAYER_PART
	var mask: int = Cfg.LAYER_ALL
	var mode: String = "rigid"        # rigid | static | kinematic
	var kind: String = "part"         # part | shard | projectile | catapult | settler | prop | struct | ragdoll
	var owner: Object = null
	var visual: Node3D = null
	var contacts: int = 0             # max contacts reported (0 = none)
	var ccd: bool = false
	var sleeping: bool = false
	var damp_lin: float = 0.05
	var damp_ang: float = 0.1
	var velocity: Vector3 = Vector3.ZERO
	var ang_velocity: Vector3 = Vector3.ZERO
	var on_contact: Callable = Callable()
	var on_sync: Callable = Callable()
	var can_sleep: bool = true

class PBody extends RefCounted:
	var id: int = 0
	var rid: RID
	var shape_rids: Array[RID] = []
	var kind: String = "part"
	var owner: Object = null
	var visual: Node3D = null
	var xform: Transform3D = Transform3D.IDENTITY
	var mass: float = 1.0
	var on_contact: Callable = Callable()
	var on_sync: Callable = Callable()
	var last_active: int = 0
	var freed: bool = false
	var contacts: int = 0
	var buoy: float = 0.0          # water density / body density (0 = ignore water)
	var radius: float = 0.5        # approx radius for buoyancy
	var under: bool = false

static var root: PhysWorld
static var space: RID
static var bodies: Dictionary = {}          # id -> PBody
static var rid_map: Dictionary = {}         # rid id (int) -> PBody
static var _next_id: int = 1
static var _kill_queue: Array[int] = []
static var _shape_cache: Dictionary = {}
static var _sphere_query: SphereShape3D
static var _terrain_rid: RID
static var dynamic_count: int = 0

func _enter_tree() -> void:
	root = self

func _exit_tree() -> void:
	shutdown()
	if root == self:
		root = null

static func init_physics(node: Node) -> void:
	space = node.get_viewport().world_3d.space
	if _sphere_query == null:
		_sphere_query = SphereShape3D.new()

static func shutdown() -> void:
	clear_all()
	for k in _shape_cache:
		PhysicsServer3D.free_rid(_shape_cache[k] as RID)
	_shape_cache.clear()

static func register_terrain(rid: RID) -> void:
	_terrain_rid = rid

static func is_terrain(rid: RID) -> bool:
	return rid == _terrain_rid

# ------------------------------------------------------------ shapes
static func _shape_rid(sd: ShapeDesc) -> RID:
	var key: String
	match sd.type:
		"box":
			key = "b%.3f,%.3f,%.3f" % [sd.size.x, sd.size.y, sd.size.z]
		"cyl":
			key = "c%.3f,%.3f" % [sd.size.x, sd.size.y]
		"sphere":
			key = "s%.3f" % sd.size.x
		"convex":
			key = "v" + sd.uid
		_:
			key = "k%.3f,%.3f" % [sd.size.x, sd.size.y]
	if _shape_cache.has(key):
		return _shape_cache[key] as RID
	var r: RID
	match sd.type:
		"box":
			r = PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_data(r, sd.size * 0.5)
		"cyl":
			r = PhysicsServer3D.cylinder_shape_create()
			PhysicsServer3D.shape_set_data(r, {"radius": maxf(sd.size.x, 0.01), "height": maxf(sd.size.y, 0.01)})
		"sphere":
			r = PhysicsServer3D.sphere_shape_create()
			PhysicsServer3D.shape_set_data(r, maxf(sd.size.x, 0.01))
		"convex":
			r = PhysicsServer3D.convex_polygon_shape_create()
			PhysicsServer3D.shape_set_data(r, sd.points)
		_:
			r = PhysicsServer3D.capsule_shape_create()
			PhysicsServer3D.shape_set_data(r, {"radius": maxf(sd.size.x, 0.01), "height": maxf(sd.size.y, sd.size.x * 2.0 + 0.01)})
	_shape_cache[key] = r
	return r

static func box_desc(size: Vector3, xf: Transform3D = Transform3D.IDENTITY) -> ShapeDesc:
	var s := ShapeDesc.new()
	s.type = "box"
	s.size = size
	s.xf = xf
	return s

static func cyl_desc(radius: float, height: float, xf: Transform3D = Transform3D.IDENTITY) -> ShapeDesc:
	var s := ShapeDesc.new()
	s.type = "cyl"
	s.size = Vector3(radius, height, 0.0)
	s.xf = xf
	return s

static func sphere_desc(radius: float, xf: Transform3D = Transform3D.IDENTITY) -> ShapeDesc:
	var s := ShapeDesc.new()
	s.type = "sphere"
	s.size = Vector3(radius, 0.0, 0.0)
	s.xf = xf
	return s

static func capsule_desc(radius: float, height: float, xf: Transform3D = Transform3D.IDENTITY) -> ShapeDesc:
	var s := ShapeDesc.new()
	s.type = "capsule"
	s.size = Vector3(radius, height, 0.0)
	s.xf = xf
	return s

# ------------------------------------------------------------ bodies
static func add_body(d: BodyDesc) -> int:
	var rid: RID = PhysicsServer3D.body_create()
	var mode: int = PhysicsServer3D.BODY_MODE_RIGID
	match d.mode:
		"static":
			mode = PhysicsServer3D.BODY_MODE_STATIC
		"kinematic":
			mode = PhysicsServer3D.BODY_MODE_KINEMATIC
	PhysicsServer3D.body_set_mode(rid, mode)
	PhysicsServer3D.body_set_space(rid, space)
	var pb := PBody.new()
	for sd in d.shapes:
		var sr: RID = _shape_rid(sd)
		PhysicsServer3D.body_add_shape(rid, sr, sd.xf)
	PhysicsServer3D.body_set_collision_layer(rid, d.layer)
	PhysicsServer3D.body_set_collision_mask(rid, d.mask)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION, d.friction)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_BOUNCE, d.bounce)
	if mode == PhysicsServer3D.BODY_MODE_RIGID:
		PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_MASS, maxf(d.mass, 0.05))
		PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
		PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, d.damp_lin)
		PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, d.damp_ang)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, d.can_sleep)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, d.xf)
	if d.contacts > 0:
		PhysicsServer3D.body_set_max_contacts_reported(rid, d.contacts)
	if d.ccd:
		PhysicsServer3D.body_set_enable_continuous_collision_detection(rid, true)
	pb.id = _next_id
	_next_id += 1
	pb.rid = rid
	pb.kind = d.kind
	pb.owner = d.owner
	pb.visual = d.visual
	pb.xform = d.xf
	pb.mass = d.mass
	pb.on_contact = d.on_contact
	pb.on_sync = d.on_sync
	pb.contacts = d.contacts
	pb.last_active = Engine.get_physics_frames()
	bodies[pb.id] = pb
	rid_map[rid.get_id()] = pb
	if mode == PhysicsServer3D.BODY_MODE_RIGID:
		dynamic_count += 1
		PhysicsServer3D.body_set_force_integration_callback(rid, Callable(root, "_integ"), pb)
		if d.velocity != Vector3.ZERO:
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, d.velocity)
		if d.ang_velocity != Vector3.ZERO:
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, d.ang_velocity)
		if d.sleeping:
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, true)
	if d.visual != null:
		d.visual.transform = d.xf
	return pb.id

static func remove_body(id: int) -> void:
	if not bodies.has(id):
		return
	var pb: PBody = bodies[id] as PBody
	bodies.erase(id)
	rid_map.erase(pb.rid.get_id())
	pb.freed = true
	if PhysicsServer3D.body_get_mode(pb.rid) == PhysicsServer3D.BODY_MODE_RIGID:
		dynamic_count -= 1
	PhysicsServer3D.body_set_force_integration_callback(pb.rid, Callable())
	PhysicsServer3D.body_clear_shapes(pb.rid)
	PhysicsServer3D.free_rid(pb.rid)
	if pb.visual != null and is_instance_valid(pb.visual):
		pb.visual.queue_free()
	pb.visual = null
	pb.owner = null

## Queue removal (safe from inside callbacks)
static func remove_later(id: int) -> void:
	_kill_queue.append(id)

static func body(id: int) -> PBody:
	return bodies.get(id) as PBody

static func body_rid(id: int) -> RID:
	var pb: PBody = bodies.get(id) as PBody
	return pb.rid if pb != null else RID()

static func by_rid(rid: RID) -> PBody:
	return rid_map.get(rid.get_id()) as PBody

static func owner_of(rid: RID) -> Object:
	var pb: PBody = rid_map.get(rid.get_id()) as PBody
	return pb.owner if pb != null else null

static func clear_all() -> void:
	for id in bodies.keys():
		remove_body(int(id))
	bodies.clear()
	rid_map.clear()
	_kill_queue.clear()
	dynamic_count = 0

# ------------------------------------------------------------ body helpers
static func set_mode(id: int, mode_name: String) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	var was_rigid: bool = PhysicsServer3D.body_get_mode(pb.rid) == PhysicsServer3D.BODY_MODE_RIGID
	var m: int = PhysicsServer3D.BODY_MODE_RIGID
	match mode_name:
		"static":
			m = PhysicsServer3D.BODY_MODE_STATIC
		"kinematic":
			m = PhysicsServer3D.BODY_MODE_KINEMATIC
	PhysicsServer3D.body_set_mode(pb.rid, m)
	var is_rigid: bool = m == PhysicsServer3D.BODY_MODE_RIGID
	if is_rigid and not was_rigid:
		dynamic_count += 1
		PhysicsServer3D.body_set_force_integration_callback(pb.rid, Callable(root, "_integ"), pb)
	elif was_rigid and not is_rigid:
		dynamic_count -= 1
		PhysicsServer3D.body_set_force_integration_callback(pb.rid, Callable())

## Convert a (static) body into a dynamic one with the given mass/damping/contact reporting.
static func make_dynamic(id: int, mass: float, damp_lin: float, damp_ang: float, contacts: int, on_contact: Callable, velocity: Vector3 = Vector3.ZERO, ang_velocity: Vector3 = Vector3.ZERO) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	set_mode(id, "rigid")
	var rid: RID = pb.rid
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_MASS, maxf(mass, 0.05))
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, damp_lin)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, damp_ang)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, true)
	pb.mass = mass
	pb.contacts = contacts
	pb.on_contact = on_contact
	PhysicsServer3D.body_set_max_contacts_reported(rid, contacts)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, ang_velocity)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	pb.last_active = Engine.get_physics_frames()

static func set_transform(id: int, xf: Transform3D) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	pb.xform = xf
	PhysicsServer3D.body_set_state(pb.rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	if pb.visual != null:
		pb.visual.transform = xf

static func get_transform(id: int) -> Transform3D:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return Transform3D.IDENTITY
	return pb.xform

static func set_velocity(id: int, v: Vector3, w: Vector3 = Vector3.ZERO) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	PhysicsServer3D.body_set_state(pb.rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
	PhysicsServer3D.body_set_state(pb.rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w)

static func get_velocity(id: int) -> Vector3:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return Vector3.ZERO
	return PhysicsServer3D.body_get_state(pb.rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3

static func apply_impulse(id: int, impulse: Vector3, at: Vector3 = Vector3.INF) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	wake(id)
	if at == Vector3.INF:
		PhysicsServer3D.body_apply_central_impulse(pb.rid, impulse)
	else:
		PhysicsServer3D.body_apply_impulse(pb.rid, impulse, at - pb.xform.origin)

## Impulse with a cap on the resulting velocity change (tiny props must not be shot to the moon)
static func apply_impulse_capped(id: int, impulse: Vector3, max_dv: float = 32.0, at: Vector3 = Vector3.INF) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	var m: float = maxf(pb.mass, 0.05)
	var lim: float = m * max_dv
	if impulse.length() > lim:
		impulse = impulse.normalized() * lim
	apply_impulse(id, impulse, at)

static func apply_force(id: int, force: Vector3) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	PhysicsServer3D.body_apply_central_force(pb.rid, force)

static func wake(id: int) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	PhysicsServer3D.body_set_state(pb.rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)

static func is_sleeping(id: int) -> bool:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return true
	return bool(PhysicsServer3D.body_get_state(pb.rid, PhysicsServer3D.BODY_STATE_SLEEPING))

static func is_awake_recent(pb: PBody) -> bool:
	return Engine.get_physics_frames() - pb.last_active <= 3

static func set_layer_mask(id: int, layer: int, mask: int) -> void:
	var pb: PBody = bodies.get(id) as PBody
	if pb == null:
		return
	PhysicsServer3D.body_set_collision_layer(pb.rid, layer)
	PhysicsServer3D.body_set_collision_mask(pb.rid, mask)

static func for_each_awake(cb: Callable) -> void:
	for id in bodies:
		var pb: PBody = bodies[id] as PBody
		if pb.mass > 0.0 and is_awake_recent(pb):
			cb.call(pb)

static func awake_count() -> int:
	var n: int = 0
	var f: int = Engine.get_physics_frames()
	for id in bodies:
		var pb: PBody = bodies[id] as PBody
		if f - pb.last_active <= 3 and pb.mass > 0.0:
			n += 1
	return n

# ------------------------------------------------------------ queries
static func direct_state() -> PhysicsDirectSpaceState3D:
	return PhysicsServer3D.space_get_direct_state(space)

## Raycast: {} or {point, normal, rid, body (PBody or null), shape}
static func raycast(origin: Vector3, dir: Vector3, max_t: float, mask: int = Cfg.LAYER_ALL, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_t, mask)
	q.exclude = exclude
	var r: Dictionary = direct_state().intersect_ray(q)
	if r.is_empty():
		return {}
	var rid: RID = r["rid"] as RID
	return {"point": r["position"], "normal": r["normal"], "rid": rid, "body": by_rid(rid), "shape": int(r["shape"])}

## Sphere overlap: calls cb(pb: PBody, shape_index: int, rid: RID) for every hit body.
static func overlap_sphere(center: Vector3, r: float, cb: Callable, mask: int = Cfg.LAYER_ALL) -> void:
	_sphere_query.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape_rid = _sphere_query.get_rid()
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = mask
	q.margin = 0.0
	var res: Array[Dictionary] = direct_state().intersect_shape(q, 128)
	for h in res:
		var rid: RID = h["rid"] as RID
		var pb: PBody = by_rid(rid)
		cb.call(pb, int(h["shape"]), rid)

# ------------------------------------------------------------ callbacks
func _integ(state: PhysicsDirectBodyState3D, pb: PBody) -> void:
	if pb.freed:
		return
	var xf: Transform3D = state.transform
	var o: Vector3 = xf.origin
	pb.last_active = Engine.get_physics_frames()
	if not (is_finite(o.x) and is_finite(o.y) and is_finite(o.z)) or absf(o.y) > 500.0 or absf(o.x) > 2000.0 or absf(o.z) > 2000.0:
		_kill_queue.append(pb.id)
		return
	# a 4-tonne boulder must not turn splinters into bullets
	if pb.kind != "projectile" and pb.kind != "catapult" and state.linear_velocity.length_squared() > 3600.0:
		state.linear_velocity = state.linear_velocity.normalized() * 60.0
	pb.xform = xf
	if pb.visual != null:
		pb.visual.transform = xf
	if pb.on_sync.is_valid():
		pb.on_sync.call(pb, state)
	if pb.contacts > 0 and pb.on_contact.is_valid() and state.get_contact_count() > 0:
		pb.on_contact.call(pb, state)

func _physics_process(_delta: float) -> void:
	if not _kill_queue.is_empty():
		var q: Array[int] = _kill_queue.duplicate()
		_kill_queue.clear()
		for id in q:
			remove_body(id)
