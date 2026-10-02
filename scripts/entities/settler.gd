class_name Settler
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Settler (spec 16.4 / 12.9): procedural villager with a 10 Hz behavior state machine, walk animation,
## ragdoll (6 bodies + cone-twist joints) on hit, fire panic, bucket brigade and speech bubbles.

enum State { IDLE, WANDER, WORK, PANIC, EXTINGUISH, BURNING, RAGDOLL, DEAD, GONE }

const TUNICS: Array[String] = ["#c0392b", "#2980b9", "#27ae60", "#f39c12", "#8e44ad", "#d35400", "#16a085", "#7f8c9a"]
const SKIN := Color("#f0c8a0")
const MAX_RAGDOLLS := 40

static var all: Array[Settler] = []
static var world_root: Node3D
static var camera_pos: Vector3 = Vector3.ZERO
static var obstacles: Dictionary = {}          # owner_id -> Array[Vector3] (x, z, radius)
static var water_points: Dictionary = {}       # owner_id -> Array[Vector3]
static var ragdoll_count: int = 0
static var rng: Rng = Rng.new(17)
static var _torso_cache: Dictionary = {}
static var _head_cache: Dictionary = {}
static var _limb_cache: Dictionary = {}
static var _ghost_tex: ImageTexture
static var _slice: int = 0
static var _acc: float = 0.0

var state: int = State.IDLE
var owner_id: int = -1
var settler_name: String = "Bob"
var hp: float = Cfg.SETTLER_HP
var home: Vector3 = Vector3.ZERO
var zone_radius: float = Cfg.ZONE_RADIUS
var tunic: Color = Color.RED
var hat: String = "none"
## Smooth walking at any frame rate: the 10 Hz behaviour only sets a walking velocity and a facing; the position, the facing and
## the limb animation advance every rendered frame (_process), so people do not stutter at 120 FPS.
var _move_vel: Vector3 = Vector3.ZERO
var _face_target: float = 0.0
var _has_face: bool = false
static var _tick_msec: int = 0         # last time the world ticked (not while paused)
var scream_pitch: float = 1.0
var last_source: Dictionary = {}
var launched_flag: bool = false

var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var limbs: Array[Node3D] = []
var _limb_home: Array[Transform3D] = []
var _bodies: Array[int] = []
var _joints: Array[RID] = []
var _target: Vector3 = Vector3.ZERO
var _timer: float = 0.0
var _phase: float = 0.0
var _speed: float = 1.2
var _dir: Vector3 = Vector3.FORWARD
var _panic_from: Vector3 = Vector3.ZERO
var _ragdoll_time: float = 0.0
var _rag_asleep: float = 0.0
var _rag_damped: bool = false
var _burn_time: float = 0.0
var _flame: Fx.Flame
var _last_bubble: float = -10.0
var _dead_time: float = 0.0
var _hit_cool: float = 0.0
var _carry_bucket: MeshInstance3D
var brigade: RefCounted = null
var _lod_near: bool = true
var gag_time: float = 0.0
var bees_time: float = 0.0
var _work_target: Vector3 = Vector3.ZERO
var _stung: float = 0.0
var is_archer: bool = false
var is_tax: bool = false
var _chat_cool: float = 0.0
## Rebuilding (Repair): the part this settler is walking to / working on, how long it has hammered, the hammer in the hand
var _repair: Part = null
var _repair_left: float = 0.0
var _tool: MeshInstance3D
var _tool_sound: float = 0.0

static func reset() -> void:
	for s in all:
		s.cleanup()
	all.clear()
	obstacles.clear()
	water_points.clear()
	ragdoll_count = 0

# ------------------------------------------------------------------ model
static func _torso_mesh(col: Color, patch: Color) -> ArrayMesh:
	var key: String = col.to_html() + patch.to_html()
	if _torso_cache.has(key):
		return _torso_cache[key] as ArrayMesh
	var b := MeshGen.Buf.new()
	MeshGen.add_frustum(b, 0.22, 0.17, 0.55, 8, Transform3D(Basis(), Vector3.ZERO), col, 0.02)
	MeshGen.add_cyl(b, 0.235, 0.07, 8, Transform3D(Basis(), Vector3(0, -0.06, 0)), Color("#5a381c"), 0.015)   # belt
	MeshGen.add_box(b, Vector3(0.09, 0.09, 0.12), Transform3D(Basis(), Vector3(0.19, 0.23, 0)), patch, 0.012)  # shoulder patch
	var m: ArrayMesh = b.to_mesh()
	_torso_cache[key] = m
	return m

static func _head_mesh(hat_kind: String, patch: Color) -> ArrayMesh:
	var key: String = hat_kind + patch.to_html()
	if _head_cache.has(key):
		return _head_cache[key] as ArrayMesh
	var b := MeshGen.Buf.new()
	MeshGen.add_sphere(b, 0.17, Transform3D(Basis(), Vector3.ZERO), SKIN, 0.02, 7, 10)
	MeshGen.add_frustum(b, 0.045, 0.008, 0.13, 6, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -0.02, 0.19)), Color("#e8b088"), 0.008)
	MeshGen.add_sphere(b, 0.025, Transform3D(Basis(), Vector3(0.07, 0.04, 0.15)), Color("#2b2b33"), 0.0, 4, 6)
	MeshGen.add_sphere(b, 0.025, Transform3D(Basis(), Vector3(-0.07, 0.04, 0.15)), Color("#2b2b33"), 0.0, 4, 6)
	match hat_kind:
		"straw":
			MeshGen.add_cyl(b, 0.3, 0.03, 10, Transform3D(Basis(), Vector3(0, 0.13, 0)), Color("#e6cf6a"), 0.012)
			MeshGen.add_cyl(b, 0.15, 0.14, 8, Transform3D(Basis(), Vector3(0, 0.2, 0)), Color("#d9b955"), 0.015)
		"cap":
			MeshGen.add_sphere(b, 0.18, Transform3D(Basis(), Vector3(0, 0.08, 0)), Color("#3b5a8a"), 0.015, 5, 8)
			MeshGen.add_box(b, Vector3(0.2, 0.03, 0.14), Transform3D(Basis(), Vector3(0, 0.1, 0.2)), Color("#2f4a70"), 0.01)
		"wizard":
			MeshGen.add_cyl(b, 0.28, 0.03, 10, Transform3D(Basis(), Vector3(0, 0.13, 0)), Color("#5a2a8a"), 0.012)
			MeshGen.add_frustum(b, 0.17, 0.02, 0.5, 8, Transform3D(Basis(), Vector3(0, 0.4, 0)), Color("#7d3fb8"), 0.015)
		"bucket":
			MeshGen.add_frustum(b, 0.16, 0.2, 0.26, 8, Transform3D(Basis(), Vector3(0, 0.18, 0)), Color("#8a5a2a"), 0.015)
		"crown":
			MeshGen.add_cyl(b, 0.16, 0.12, 8, Transform3D(Basis(), Vector3(0, 0.2, 0)), Color("#ffd700"), 0.012)
			for i in 5:
				var a: float = float(i) / 5.0 * TAU
				MeshGen.add_box(b, Vector3(0.05, 0.1, 0.05), Transform3D(Basis(), Vector3(cos(a) * 0.14, 0.3, sin(a) * 0.14)), Color("#ffd700"), 0.01)
		"feather":
			# a soft beret in the team colour with a little stalk (the old tilted slab looked like something stuck to the head)
			MeshGen.add_frustum(b, 0.2, 0.13, 0.12, 8, Transform3D(Basis(), Vector3(0, 0.16, 0)), patch, 0.012)
			MeshGen.add_cyl(b, 0.025, 0.05, 6, Transform3D(Basis(), Vector3(0, 0.25, 0)), patch.darkened(0.3), 0.006)
		_:
			pass
	var m: ArrayMesh = b.to_mesh()
	_head_cache[key] = m
	return m

static func _limb_mesh(kind: String, col: Color) -> ArrayMesh:
	var key: String = kind + col.to_html()
	if _limb_cache.has(key):
		return _limb_cache[key] as ArrayMesh
	var b := MeshGen.Buf.new()
	if kind == "arm":
		MeshGen.add_box(b, Vector3(0.09, 0.42, 0.09), Transform3D(Basis(), Vector3(0, -0.2, 0)), col, 0.012)
		MeshGen.add_sphere(b, 0.06, Transform3D(Basis(), Vector3(0, -0.43, 0)), SKIN, 0.01, 4, 6)
	else:
		MeshGen.add_box(b, Vector3(0.11, 0.5, 0.11), Transform3D(Basis(), Vector3(0, -0.22, 0)), col, 0.012)
		MeshGen.add_box(b, Vector3(0.13, 0.07, 0.2), Transform3D(Basis(), Vector3(0, -0.47, 0.04)), Color("#3a2a1a"), 0.01)
	var m: ArrayMesh = b.to_mesh()
	_limb_cache[key] = m
	return m

func setup(village_owner: int, home_pos: Vector3, player_color: Color, r: Rng) -> void:
	owner_id = village_owner
	home = home_pos
	settler_name = str(r.pick(Game.SETTLER_NAMES))
	name = "Settler_" + settler_name
	tunic = Color.html(TUNICS[r.range_i(0, TUNICS.size() - 1)])
	var roll: float = r.next_f()
	if roll < 0.005:
		hat = "crown"
	elif roll < 0.035:
		hat = "bucket"
	elif roll < 0.25:
		hat = "none"
	elif roll < 0.45:
		hat = "straw"
	elif roll < 0.65:
		hat = "cap"
	elif roll < 0.78:
		hat = "wizard"
	else:
		hat = "feather"
	scream_pitch = r.range_f(0.8, 1.35)
	var patch: Color = player_color
	torso = _mk_node(_torso_mesh(tunic, patch), Vector3(0, 0.8, 0))
	head = _mk_node(_head_mesh(hat, patch), Vector3(0, 1.21, 0))
	var sleeve: Color = tunic.darkened(0.15)
	arm_l = _mk_node(_limb_mesh("arm", sleeve), Vector3(-0.25, 1.02, 0))
	arm_r = _mk_node(_limb_mesh("arm", sleeve), Vector3(0.25, 1.02, 0))
	var pants: Color = Color("#4a3a2a")
	leg_l = _mk_node(_limb_mesh("leg", pants), Vector3(-0.1, 0.5, 0))
	leg_r = _mk_node(_limb_mesh("leg", pants), Vector3(0.1, 0.5, 0))
	limbs = [torso, head, arm_l, arm_r, leg_l, leg_r]
	# a hammer for rebuilding (only shown while working on a house)
	var tb := MeshGen.Buf.new()
	MeshGen.add_box(tb, Vector3(0.045, 0.34, 0.045), Transform3D(Basis(), Vector3(0, -0.6, 0.0)), Color("#8a5a2a"), 0.008)
	MeshGen.add_box(tb, Vector3(0.1, 0.1, 0.22), Transform3D(Basis(), Vector3(0, -0.79, 0.04)), Color("#6a7480"), 0.01)
	_tool = MeshInstance3D.new()
	_tool.mesh = tb.to_mesh()
	_tool.material_override = Toon.main()
	_tool.visible = false
	arm_r.add_child(_tool)
	for l in limbs:
		_limb_home.append(l.transform)
	_phase = r.range_f(0.0, TAU)
	_timer = r.range_f(0.2, 3.0)
	position = Terrain.ground(home_pos)
	all.append(self)

func _mk_node(mesh: Mesh, pos: Vector3) -> Node3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = Toon.main()
	n.position = pos
	n.visibility_range_end = 110.0
	add_child(n)
	return n

func global_pos() -> Vector3:
	if state == State.RAGDOLL and not _bodies.is_empty():
		return PhysWorld.get_transform(_bodies[0]).origin
	return global_position

func cleanup() -> void:
	_cancel_repair()
	_free_bodies()
	if _flame != null and Fx.inst != null:
		Fx.inst.release_flame(_flame)
		_flame = null
	if is_inside_tree():
		queue_free()

# ------------------------------------------------------------------ external events
func notice_cow() -> void:
	if state == State.IDLE or state == State.WANDER:
		Speech.say_random("speech.cow", self, self, rng)

func gag(seconds: float) -> void:
	if state == State.DEAD or state == State.GONE or state == State.RAGDOLL:
		return
	if gag_time <= 0.0:
		Speech.say_random("speech.cheese", self, self, rng)
	gag_time = seconds

func sting(dt: float, source: Dictionary) -> void:
	if state == State.DEAD or state == State.GONE:
		return
	if bees_time <= 0.0:
		Speech.say_random("speech.bees", self, self, rng)
	bees_time = 1.2
	hurt(8.0 * dt, source, Vector3.ZERO, false, true)
	_panic(global_pos() + Vector3(rng.range_f(-4, 4), 0, rng.range_f(-4, 4)), 1.0)

func push(velocity: Vector3, source: Dictionary) -> void:
	if state == State.DEAD or state == State.GONE:
		return
	if state != State.RAGDOLL:
		_to_ragdoll(velocity, source)
	else:
		for id in _bodies:
			PhysWorld.apply_impulse(id, velocity * 4.0)

func panic_from(pos: Vector3, seconds: float = 2.5) -> void:
	_panic(pos, seconds)

func _panic(from: Vector3, seconds: float) -> void:
	if state == State.DEAD or state == State.GONE or state == State.RAGDOLL or state == State.BURNING:
		return
	state = State.PANIC
	_panic_from = from
	_timer = seconds
	_speed = 3.5
	if brigade != null:
		brigade.call("leave", self)
	_drop_bucket()
	if Time.get_ticks_msec() * 0.001 - _last_bubble > 2.5 and rng.chance(0.6):
		_last_bubble = Time.get_ticks_msec() * 0.001
		Speech.say_random("speech.panic", self, self, rng)
		if rng.chance(0.4):
			Sfx.play("scream", global_pos(), 0.5, 1)

## Apply damage. `launch_vel` (m/s) when non-zero launches the settler as a ragdoll.
func hurt(amount: float, source: Dictionary, launch_vel: Vector3, do_launch: bool, silent: bool = false) -> void:
	if state == State.DEAD or state == State.GONE or amount <= 0.0 and not do_launch:
		return
	if state == State.RAGDOLL and _hit_cool > 0.0 and not do_launch:
		return
	var was_alive: bool = hp > 0.0
	hp -= amount
	if is_tax and do_launch and launch_vel.length() > 1.0:
		Fx.comic_text_glug(global_pos()) if false else ComicText.spawn_text(I18n.t("banner.audit"), global_pos() + Vector3.UP * 2.5)
	if not source.is_empty():
		last_source = source
	if not silent:
		Events.settler_hit.emit(settler_name, owner_id, last_source, do_launch)
	if do_launch and launch_vel.length() > 1.0:
		if state != State.RAGDOLL:
			if not launched_flag:
				launched_flag = true
				Scoring.on_settler_launched(last_source, owner_id)
			_to_ragdoll(launch_vel, source)
			if not silent:
				Speech.say_random("speech.hit", self, self, rng)
				Sfx.play("yeet" if rng.chance(0.5) else "scream", global_pos(), 0.8, 2)
				if rng.chance(0.25):
					Fx.comic_kind("settler", global_pos() + Vector3.UP * 2.0)
		else:
			for id in _bodies:
				PhysWorld.apply_impulse(id, launch_vel * 3.0)
	if hp <= 0.0 and was_alive:
		_die()

func _die() -> void:
	hp = -1.0
	Events.settler_killed.emit(settler_name, owner_id, last_source)
	Scoring.on_settler_killed(last_source, owner_id)
	if brigade != null:
		brigade.call("leave", self)
	_drop_bucket()
	_spawn_ghost()
	if state != State.RAGDOLL:
		state = State.DEAD
		_lay_down()
	_dead_time = 0.0

func _lay_down() -> void:
	# frozen pose lying on the ground
	torso.rotation = Vector3(-PI * 0.5, 0, 0)
	torso.position = Vector3(0, 0.2, 0)
	head.position = Vector3(0, 0.2, 0.55)
	arm_l.position = Vector3(-0.3, 0.15, 0.1)
	arm_r.position = Vector3(0.3, 0.15, 0.1)
	arm_l.rotation = Vector3(-PI * 0.5, 0, 0.3)
	arm_r.rotation = Vector3(-PI * 0.5, 0, -0.3)
	leg_l.position = Vector3(-0.1, 0.1, -0.3)
	leg_r.position = Vector3(0.1, 0.1, -0.3)
	leg_l.rotation = Vector3(-PI * 0.5, 0, 0)
	leg_r.rotation = Vector3(-PI * 0.5, 0, 0)

func _spawn_ghost() -> void:
	if _ghost_tex == null:
		_ghost_tex = _make_ghost_tex()
	var sp := Sprite3D.new()
	sp.texture = _ghost_tex
	sp.pixel_size = 0.012
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.modulate = Color(1, 1, 1, 0.75)
	sp.no_depth_test = false
	sp.top_level = true
	world_root.add_child(sp)
	sp.global_position = global_pos() + Vector3.UP * 0.8
	var tw: Tween = sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "global_position", sp.global_position + Vector3.UP * 3.5, 2.0)
	tw.tween_property(sp, "modulate:a", 0.0, 2.0).set_delay(0.6)
	tw.chain().tween_callback(sp.queue_free)

static func _make_ghost_tex() -> ImageTexture:
	var img := Image.create(48, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 48:
			var cx: float = float(x) - 23.5
			var inside: bool = false
			if y < 30:
				var cy: float = float(y) - 24.0
				inside = cx * cx + cy * cy < 22.0 * 22.0 and y >= 2
			elif y < 58:
				var wave: float = sin(float(x) * 0.55) * 3.0
				inside = absf(cx) < 22.0 and float(y) < 54.0 + wave
			if inside:
				img.set_pixel(x, y, Color(1, 1, 1, 0.92))
	# eyes + mouth
	for e in [Vector2i(16, 22), Vector2i(31, 22)]:
		for dy in range(-3, 4):
			for dx in range(-2, 3):
				img.set_pixel(e.x + dx, e.y + dy, Color(0.1, 0.1, 0.2, 1.0))
	for dx in range(-4, 5):
		for dy in range(0, 4):
			img.set_pixel(24 + dx, 34 + dy, Color(0.1, 0.1, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ ragdoll
func _free_bodies() -> void:
	for j in _joints:
		if j.is_valid():
			PhysicsServer3D.free_rid(j)
	_joints.clear()
	for id in _bodies:
		if PhysWorld.bodies.has(id):
			var pb: PhysWorld.PBody = PhysWorld.body(id)
			pb.visual = null       # limbs are owned by this settler, not freed with the body
			PhysWorld.remove_body(id)
	_bodies.clear()

func _to_ragdoll(velocity: Vector3, source: Dictionary = {}) -> void:
	if state == State.RAGDOLL or state == State.GONE:
		return
	if not source.is_empty():
		last_source = source
	if ragdoll_count >= MAX_RAGDOLLS:
		# too many active ragdolls: fly as frozen pose instead
		if hp <= 0.0:
			state = State.DEAD
			_lay_down()
		return
	if _flame != null and Fx.inst != null:
		pass
	_drop_bucket()
	if brigade != null:
		brigade.call("leave", self)
	state = State.RAGDOLL
	ragdoll_count += 1
	_ragdoll_time = 0.0
	_rag_asleep = 0.0
	_rag_damped = false
	_hit_cool = 0.6
	var root_xf: Transform3D = global_transform
	# limb transforms in world space
	var specs: Array = [
		{"shape": "box", "size": Vector3(0.36, 0.55, 0.22), "mass": 12.0, "node": torso, "off": Vector3(0, 0, 0)},
		{"shape": "sphere", "size": Vector3(0.17, 0, 0), "mass": 4.0, "node": head, "off": Vector3(0, 0, 0)},
		{"shape": "box", "size": Vector3(0.1, 0.42, 0.1), "mass": 2.5, "node": arm_l, "off": Vector3(0, -0.2, 0)},
		{"shape": "box", "size": Vector3(0.1, 0.42, 0.1), "mass": 2.5, "node": arm_r, "off": Vector3(0, -0.2, 0)},
		{"shape": "box", "size": Vector3(0.12, 0.5, 0.12), "mass": 4.0, "node": leg_l, "off": Vector3(0, -0.22, 0)},
		{"shape": "box", "size": Vector3(0.12, 0.5, 0.12), "mass": 4.0, "node": leg_r, "off": Vector3(0, -0.22, 0)},
	]
	var ids: Array[int] = []
	for i in specs.size():
		var sp: Dictionary = specs[i]
		var node: Node3D = sp["node"] as Node3D
		# restore rest pose before converting (limbs might be mid-animation)
		node.transform = _limb_home[i]
		var wx: Transform3D = root_xf * _limb_home[i]
		node.reparent(world_root, false)
		node.transform = wx
		var d := PhysWorld.BodyDesc.new()
		var sd := PhysWorld.ShapeDesc.new()
		sd.type = str(sp["shape"])
		sd.size = sp["size"] as Vector3
		sd.xf = Transform3D(Basis(), sp["off"] as Vector3)
		d.shapes.append(sd)
		d.xf = wx
		d.mass = float(sp["mass"])
		d.friction = 0.7
		d.bounce = 0.2
		d.layer = Cfg.LAYER_SETTLER
		d.mask = Cfg.LAYER_TERRAIN | Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_CATAPULT | Cfg.LAYER_PROJECTILE
		d.kind = "ragdoll"
		d.owner = self
		d.visual = node
		d.damp_lin = 0.15
		d.damp_ang = 0.6
		d.velocity = velocity * (1.0 + rng.range_f(-0.05, 0.05))
		d.ang_velocity = Vector3(rng.range_f(-6, 6), rng.range_f(-6, 6), rng.range_f(-6, 6))
		if i == 0:
			d.contacts = 4
			d.on_contact = Callable(self, "_torso_contact")
		ids.append(PhysWorld.add_body(d))
	_bodies = ids
	# joints torso <-> limbs (pivot points in torso/limb local space)
	var t_rid: RID = PhysWorld.body_rid(ids[0])
	var pivots: Array = [
		[1, Vector3(0, 0.36, 0), Vector3(0, -0.17, 0)],
		[2, Vector3(-0.25, 0.2, 0), Vector3(0, 0.0, 0)],
		[3, Vector3(0.25, 0.2, 0), Vector3(0, 0.0, 0)],
		[4, Vector3(-0.1, -0.28, 0), Vector3(0, 0.0, 0)],
		[5, Vector3(0.1, -0.28, 0), Vector3(0, 0.0, 0)],
	]
	for pv in pivots:
		var li: int = int(pv[0])
		var a_local: Vector3 = pv[1] as Vector3
		var b_local: Vector3 = pv[2] as Vector3
		# arm/leg meshes hang below their pivot: the collider is offset -0.2 / -0.22 from the limb origin (= pivot)
		var b_pivot: Vector3 = b_local + (Vector3(0, 0.2, 0) if li in [2, 3] else (Vector3(0, 0.22, 0) if li in [4, 5] else Vector3.ZERO))
		var j: RID = PhysicsServer3D.joint_create()
		PhysicsServer3D.joint_make_cone_twist(j, t_rid, Transform3D(Basis(), a_local), PhysWorld.body_rid(ids[li]), Transform3D(Basis(), b_pivot))
		_joints.append(j)
	# recompute: head's collider is centered on its node origin, torso pivot above the torso center
	Fx.burst("puff", global_pos() + Vector3.UP * 0.5, Color("#ffffff"), 0.3)

func _torso_contact(pb: PhysWorld.PBody, state_: PhysicsDirectBodyState3D) -> void:
	if _hit_cool > 0.0:
		return
	var imp: float = 0.0
	for i in mini(state_.get_contact_count(), 4):
		imp += state_.get_contact_impulse(i).length()
	if imp > 260.0 and hp > 0.0:
		var dmg: float = (imp - 260.0) / 45.0
		_hit_cool = 0.5
		hp -= dmg
		if hp <= 0.0:
			_die()
	if imp > 120.0 and _hit_cool <= 0.0:
		_hit_cool = 0.4
		Sfx.play("boing", pb.xform.origin, 0.5, 0)

func _end_ragdoll() -> void:
	if state != State.RAGDOLL:
		return
	ragdoll_count = maxi(ragdoll_count - 1, 0)
	var torso_xf: Transform3D = PhysWorld.get_transform(_bodies[0])
	var dead: bool = hp <= 0.0
	if dead:
		# freeze the pose exactly where it lies (no more bodies)
		var final_xfs: Array[Transform3D] = []
		for id in _bodies:
			final_xfs.append(PhysWorld.get_transform(id))
		_free_bodies()
		for i in limbs.size():
			limbs[i].transform = final_xfs[i]
		position = Vector3(torso_xf.origin.x, Terrain.h(torso_xf.origin.x, torso_xf.origin.z), torso_xf.origin.z)
		state = State.DEAD
		_dead_time = 0.0
		return
	_free_bodies()
	# get up where the torso ended
	var p: Vector3 = torso_xf.origin
	if Terrain.is_water(p.x, p.z) and WaterSys.depth_at(p.x, p.z) > 1.0:
		hp = -1.0
		_die_in_water(p)
		return
	position = Vector3(p.x, Terrain.h(p.x, p.z), p.z)
	rotation = Vector3.ZERO
	for i in limbs.size():
		limbs[i].reparent(self, false)
		limbs[i].transform = _limb_home[i]
	state = State.IDLE
	_timer = rng.range_f(0.5, 2.0)
	launched_flag = false
	Speech.say_random("speech.landed", self, self, rng)

func _die_in_water(p: Vector3) -> void:
	for i in limbs.size():
		limbs[i].reparent(self, false)
		limbs[i].transform = _limb_home[i]
	position = Vector3(p.x, WaterSys.water_y(), p.z)
	state = State.DEAD
	_lay_down()
	Events.settler_killed.emit(settler_name, owner_id, last_source)
	Scoring.on_settler_killed(last_source, owner_id)
	_spawn_ghost()
	Fx.burst("splash", position, Color(0, 0, 0, -1), 0.5)

# ------------------------------------------------------------------ fire
func ignite() -> void:
	if state == State.DEAD or state == State.GONE or state == State.BURNING:
		return
	if state == State.RAGDOLL:
		return
	if brigade != null:
		brigade.call("leave", self)
	_drop_bucket()
	state = State.BURNING
	_burn_time = 0.0
	_timer = 0.0
	_speed = 3.8
	Speech.say_random("speech.fire", self, self, rng)
	Sfx.play("scream", global_pos(), 0.6, 1)
	if Fx.inst != null and _flame == null:
		_flame = Fx.inst.acquire_flame(0.6)
		if _flame != null:
			_flame.part = null
	Events.fire_started.emit(global_pos(), last_source)
	_pick_burn_target()

func extinguish() -> void:
	if state == State.BURNING:
		state = State.IDLE
		_timer = 1.0
	if _flame != null and Fx.inst != null:
		Fx.inst.release_flame(_flame)
		_flame = null

func _pick_burn_target() -> void:
	# nearest water within 25 m (well / pond / river), else random run
	var best: Vector3 = Vector3.INF
	var bd: float = 25.0
	var pos: Vector3 = global_pos()
	var wp: Array = water_points.get(owner_id, []) as Array
	for w in wp:
		var d: float = (w as Vector3).distance_to(pos)
		if d < bd:
			bd = d
			best = w as Vector3
	if best != Vector3.INF:
		_target = best
	else:
		var a: float = rng.range_f(0.0, TAU)
		_target = pos + Vector3(cos(a), 0, sin(a)) * 6.0

# ------------------------------------------------------------------ buckets
func _drop_bucket() -> void:
	if _carry_bucket != null:
		_carry_bucket.queue_free()
		_carry_bucket = null

func carry_bucket(on: bool) -> void:
	if on and _carry_bucket == null:
		_carry_bucket = MeshInstance3D.new()
		(_carry_bucket as MeshInstance3D).mesh = MeshGen.cyl_mesh(0.14, 0.24, 8)
		(_carry_bucket as MeshInstance3D).material_override = Toon.colored(Color("#8a5a2a"))
		_carry_bucket.position = Vector3(0.0, 0.95, 0.35)
		add_child(_carry_bucket)
	elif not on:
		_drop_bucket()

# ------------------------------------------------------------------ 10 Hz behavior
static func update_all(dt: float, cam: Vector3) -> void:
	camera_pos = cam
	_tick_msec = Time.get_ticks_msec()
	# 10 Hz slices: process 1/6 of the settlers each physics tick (60 Hz)
	_acc += dt
	var n: int = all.size()
	if n == 0:
		return
	var slices: int = 6
	var per: int = int(ceil(float(n) / float(slices)))
	var start: int = (_slice % slices) * per
	_slice += 1
	var step: float = 1.0 / 10.0
	var i: int = start
	while i < mini(start + per, n):
		all[i]._think(step)
		i += 1
	# ragdoll timers + dead cleanup run every tick for all
	var k: int = all.size() - 1
	while k >= 0:
		var s: Settler = all[k]
		s._tick_fast(dt)
		if s.state == State.GONE:
			all.remove_at(k)
			s.cleanup()
		k -= 1

func _tick_fast(dt: float) -> void:
	if _repair != null and state != State.WANDER and state != State.WORK:
		_cancel_repair()              # panic, fire, ragdoll, death: no more rebuilding
	_hit_cool = maxf(_hit_cool - dt, 0.0)
	gag_time = maxf(gag_time - dt, 0.0)
	bees_time = maxf(bees_time - dt, 0.0)
	if state == State.RAGDOLL:
		_ragdoll_time += dt
		if _bodies.is_empty():
			return
		var pb: PhysWorld.PBody = PhysWorld.body(_bodies[0])
		if pb == null:
			return
		var speed: float = PhysWorld.get_velocity(_bodies[0]).length()
		# once the flight is over the limbs get heavy damping so ragdolls come to rest reasonably fast
		if _ragdoll_time > 2.5 and not _rag_damped:
			_rag_damped = true
			for bid in _bodies:
				if PhysWorld.bodies.has(bid):
					var brid: RID = PhysWorld.body_rid(bid)
					PhysicsServer3D.body_set_param(brid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 1.2)
					PhysicsServer3D.body_set_param(brid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 4.0)
		if speed < 0.7 and _ragdoll_time > 0.8:
			_rag_asleep += dt
		else:
			_rag_asleep = 0.0
		var dead_now: bool = hp <= 0.0
		if _rag_asleep > (1.0 if dead_now else 2.0) or _ragdoll_time > (5.5 if dead_now else 9.0):
			_end_ragdoll()
	elif state == State.DEAD:
		_dead_time += dt
		if _dead_time > 30.0:
			_fade_and_go(dt)
	# animation for near settlers
	var near: bool = global_position.distance_squared_to(camera_pos) < 80.0 * 80.0
	_lod_near = near
	# (the limb animation runs every rendered frame in _process)

func _process(delta: float) -> void:
	if Time.get_ticks_msec() - _tick_msec > 300:
		return                          # the world is paused (or not running)
	var walking: bool = state == State.WANDER or state == State.PANIC or state == State.BURNING or state == State.EXTINGUISH
	if walking and _move_vel != Vector3.ZERO:
		var np: Vector3 = position + _move_vel * delta
		np.y = Terrain.h(np.x, np.z)
		position = np
	if _has_face and state != State.RAGDOLL and state != State.DEAD and state != State.GONE:
		rotation.y = lerp_angle(rotation.y, _face_target, clampf(delta * 12.0, 0.0, 1.0))
	if _lod_near and (walking or state == State.WORK or state == State.IDLE):
		_animate(delta)

## Give up the rebuilding (panic, fire, death, ...): the claim on the part is released and the hammer disappears
func _cancel_repair() -> void:
	if _repair != null:
		Repair.release(_repair)
	_repair = null
	if _tool != null and is_instance_valid(_tool):
		_tool.visible = false

## Look for a damaged part of the own village and walk to it (called when calm and idle)
func _try_repair() -> bool:
	if not Repair.allowed() or hp <= 0.0 or Repair.builders(owner_id) >= Repair.MAX_WORKERS:
		return false
	var p: Part = Repair.pick_job(owner_id, global_position)
	if p == null:
		return false
	_repair = p
	Repair.claim(p, self)
	var at: Vector3 = p.xf0.origin
	var from: Vector3 = Util.flat(global_position - at)
	if from.length() < 0.1:
		from = Vector3(1, 0, 0)
	# stand right in front of the part: the hammer just touches it
	var stand: Vector3 = at + from.normalized() * (0.55 + 0.5 * minf(p.size.x, p.size.z))
	stand.y = Terrain.h(stand.x, stand.z)
	_target = stand
	_work_target = at
	state = State.WANDER
	_timer = 80.0                    # a long walk across the village is fine
	return true

func _fade_and_go(dt: float) -> void:
	scale = scale * maxf(1.0 - dt * 1.5, 0.01)
	if scale.x < 0.05:
		state = State.GONE

func _animate(dt: float) -> void:
	var moving: bool = state == State.WANDER or state == State.PANIC or state == State.BURNING or state == State.EXTINGUISH
	if moving:
		_phase += dt * _speed * 5.2
		var sw: float = sin(_phase) * clampf(_speed * 0.28, 0.3, 1.0)
		leg_l.rotation.x = sw
		leg_r.rotation.x = -sw
		if _carry_bucket != null:
			arm_l.rotation.x = -1.2
			arm_r.rotation.x = -1.2
		elif state == State.PANIC or state == State.BURNING:
			arm_l.rotation.x = -2.6 + sin(_phase * 2.0) * 0.4
			arm_r.rotation.x = -2.6 - sin(_phase * 2.0) * 0.4
		else:
			arm_l.rotation.x = -sw * 0.8
			arm_r.rotation.x = sw * 0.8
		torso.position.y = 0.8 + absf(sin(_phase)) * 0.04
		head.position.y = 1.21 + absf(sin(_phase)) * 0.04
	elif state == State.WORK:
		_phase += dt * 9.0
		arm_r.rotation.x = -1.6 + sin(_phase) * 0.8
		arm_l.rotation.x = -0.4
		leg_l.rotation.x = 0.0
		leg_r.rotation.x = 0.0
	else:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, minf(dt * 8.0, 1.0))
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, minf(dt * 8.0, 1.0))
		arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, minf(dt * 8.0, 1.0))
		arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, minf(dt * 8.0, 1.0))
	if gag_time > 0.0:
		head.rotation.x = 0.5
	elif head.rotation.x != 0.0:
		head.rotation.x = 0.0

func _think(step: float) -> void:
	if state == State.DEAD or state == State.GONE or state == State.RAGDOLL:
		return
	_chat_cool = maxf(_chat_cool - step, 0.0)
	_move_vel = Vector3.ZERO          # a walking state sets it again below
	var pos: Vector3 = global_position
	# --- detect threats
	var pr: Projectile = Projectile.primary
	if pr != null and pr.alive and state != State.BURNING:
		var pp: Vector3 = pr.position()
		if pp != Vector3.INF and pp.distance_to(pos) < 15.0 and state != State.PANIC:
			_panic(pp, 2.5)
	# --- fire contact
	if state != State.BURNING and Fire.fires_near(pos + Vector3.UP * 0.5, 1.4):
		ignite()
	# --- water while burning
	match state:
		State.IDLE:
			_timer -= step
			if _chat_cool <= 0.0 and rng.chance(0.012):
				_chat_cool = 20.0
				Speech.say_random("speech.idle", self, self, rng)
			if _timer <= 0.0:
				if rng.chance(0.55) and _try_repair():
					pass                      # off to rebuild a damaged house
				elif rng.chance(0.2) and _find_work():
					state = State.WORK
					_timer = rng.range_f(2.0, 5.0)
				else:
					_pick_wander()
		State.WORK:
			_face(_work_target - pos, step)
			if _repair != null:
				# hammering: a knock now and then, the part is back when the work is done (calm phases only)
				_tool.visible = true
				_tool_sound -= step
				if _tool_sound <= 0.0:
					_tool_sound = 0.9
					Sfx.play("clack", _work_target, 0.3, 0)
				if Repair.allowed():
					_repair_left -= step
				if _repair_left <= 0.0:
					Repair.finish(_repair)
					_cancel_repair()
					state = State.IDLE
					_timer = rng.range_f(4.0, 9.0)
			else:
				_timer -= step
				if _timer <= 0.0:
					state = State.IDLE
					_timer = rng.range_f(0.5, 2.0)
		State.WANDER:
			_walk(step, 1.2)
			if _repair != null and pos.distance_to(_target) < 0.4:
				state = State.WORK                    # arrived at the damaged spot
				_repair_left = Repair.WORK_TIME
				_tool_sound = 0.3
			elif (_repair == null and pos.distance_to(_target) < 0.6) or _timer < 0.0:
				_cancel_repair()
				state = State.IDLE
				_timer = rng.range_f(1.0, 4.0)
			_timer -= step
		State.PANIC:
			var away: Vector3 = pos - _panic_from
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3(rng.range_f(-1, 1), 0, rng.range_f(-1, 1))
			_target = pos + away.normalized() * 6.0
			_walk(step, 3.5)
			_timer -= step
			if _timer <= 0.0:
				state = State.IDLE
				_timer = rng.range_f(0.5, 2.0)
		State.BURNING:
			_burn_time += step
			hurt(5.0 * step, last_source, Vector3.ZERO, false, true)
			if state != State.BURNING:
				return
			_walk(step, 3.8)
			if _flame != null:
				_flame.static_pos = global_position + Vector3(0, 1.0, 0)
			# jump into water
			if Terrain.is_water(pos.x, pos.z) or pos.distance_to(_target) < 1.0 and water_points.has(owner_id):
				if Terrain.is_water(pos.x, pos.z) or _near_water(pos):
					Fx.burst("steam", pos + Vector3.UP, Color(0, 0, 0, -1), 0.5)
					extinguish()
					return
			if _burn_time > 4.0:
				extinguish()
			elif rng.chance(0.15):
				_pick_burn_target()
		State.EXTINGUISH:
			# driven by the brigade object
			if brigade != null:
				brigade.call("update_member", self, step)
			else:
				state = State.IDLE
	# stay near home zone
	if state != State.PANIC and state != State.BURNING and Util.dist_xz(pos, home) > zone_radius + 6.0 and state != State.EXTINGUISH:
		_target = home
		state = State.WANDER
		_timer = 6.0

func _near_water(p: Vector3) -> bool:
	for w in (water_points.get(owner_id, []) as Array):
		if (w as Vector3).distance_to(p) < 2.0:
			return true
	return false

func _find_work() -> bool:
	# stand near a random building of the village and hammer
	var obs: Array = obstacles.get(owner_id, []) as Array
	if obs.is_empty():
		return false
	var o: Vector3 = obs[rng.range_i(0, obs.size() - 1)] as Vector3
	var a: float = rng.range_f(0.0, TAU)
	var target := Vector3(o.x + cos(a) * (o.z + 0.9), 0, o.y + sin(a) * (o.z + 0.9))
	# o = (x, z, radius) stored as Vector3(x, z, r)
	target.y = Terrain.h(target.x, target.z)
	_target = target
	_work_target = Vector3(o.x, 0, o.y)
	state = State.WANDER
	_timer = 8.0
	return false

func _pick_wander() -> void:
	for tries in 8:
		var off: Vector2 = rng.in_circle(zone_radius * 0.85)
		var p := Vector3(home.x + off.x, 0, home.z + off.y)
		p.y = Terrain.h(p.x, p.z)
		if _blocked(p, 0.6):
			continue
		if Terrain.is_water(p.x, p.z):
			continue
		_target = p
		state = State.WANDER
		_timer = 12.0
		return
	state = State.IDLE
	_timer = 1.5

func _blocked(p: Vector3, margin: float) -> bool:
	for o in (obstacles.get(owner_id, []) as Array):
		var ov: Vector3 = o as Vector3
		if Vector2(p.x - ov.x, p.z - ov.y).length() < ov.z + margin:
			return true
	return false

func _face(dir: Vector3, step: float) -> void:
	if dir.length() < 0.05:
		return
	_face_target = atan2(dir.x, dir.z)
	_has_face = true

func _walk(step: float, speed: float) -> void:
	_speed = speed
	var pos: Vector3 = global_position
	var to: Vector3 = _target - pos
	to.y = 0.0
	if to.length() < 0.05:
		return
	var dir: Vector3 = to.normalized()
	# steer around obstacles
	var next: Vector3 = pos + dir * speed * step
	for o in ([] if _repair != null else (obstacles.get(owner_id, []) as Array)):      # a builder walks right up to the house
		var ov: Vector3 = o as Vector3
		var d2: Vector2 = Vector2(next.x - ov.x, next.z - ov.y)
		var rr: float = ov.z + 0.5
		if d2.length() < rr:
			var out: Vector2 = d2.normalized() if d2.length() > 0.01 else Vector2(1, 0)
			# slide tangentially
			var tang: Vector2 = Vector2(-out.y, out.x)
			var side: float = 1.0 if tang.dot(Vector2(dir.x, dir.z)) >= 0.0 else -1.0
			var nx: Vector2 = Vector2(ov.x, ov.y) + out * rr + tang * side * 0.3
			next = Vector3(nx.x, 0.0, nx.y)
	# don't walk into deep water unless burning
	if state != State.BURNING and Terrain.is_water(next.x, next.z) and WaterSys.depth_at(next.x, next.z) > 0.3:
		state = State.IDLE
		_timer = 1.0
		return
	var moved: Vector3 = next - pos
	moved.y = 0.0
	_move_vel = moved / maxf(step, 0.001)          # integrated every frame in _process
	_face(moved, step)
