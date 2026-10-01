class_name Breakable
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Destructible structure system (spec 5): dormant/awake structures, glue links (logical, no joints),
## support checks, part breaking with shards, and the registry of all structures.

static var world_root: Node3D
static var structures: Array[Structure] = []
static var awake_list: Array[Structure] = []
static var time_now: float = 0.0
static var _next_part_id: int = 1
static var _next_struct_id: int = 1
static var _stamp: int = 0
static var _rr: int = 0
static var rng: Rng = Rng.new(7)

static func reset() -> void:
	for s in structures:
		Props.free_joints(s)
		if s.behavior != null and s.behavior.has_method("cleanup"):
			s.behavior.call("cleanup")
		# break the Part <-> Structure / Part <-> Part reference cycles so RefCounted objects are freed
		for p in s.parts:
			p.links.clear()
			p.structure = null
			p.mesh = null
			p.subs = []
		s.parts.clear()
		s.extras.clear()
		s.behavior = null
		s.dormant_shape_parts.clear()
		s.dormant_extra.clear()
		if s.root != null and is_instance_valid(s.root):
			s.root.queue_free()
	structures.clear()
	awake_list.clear()
	time_now = 0.0
	_next_part_id = 1
	_next_struct_id = 1
	Debris.reset()

## The ground under buildings changed (landslide, crater): parts that were anchored to ground that is no longer
## there lose their anchor; the support check then lets whatever hangs in the air fall down.
static func ground_changed(box: AABB) -> int:
	var n: int = 0
	for s in structures:
		if s.free_parts or s.destroyed or not s.aabb.grow(1.0).intersects(box):
			continue
		var any: bool = false
		for p in s.parts:
			if p.anchor and p.state != Part.State.DEAD:
				var bb: AABB = p.world_aabb()
				var gh: float = minf(Terrain.h(bb.position.x + bb.size.x * 0.5, bb.position.z + bb.size.z * 0.5), Terrain.h(p.xf.origin.x, p.xf.origin.z))
				if bb.position.y > gh + 0.7:
					p.anchor = false
					any = true
					n += 1
		if any:
			if not s.awake:
				awaken(s)
			s.support_dirty = true
			s.support_timer = 0.0
	return n

## Removes a structure that was just created (placement undo); never used during a battle
static func remove_structure(s: Structure) -> void:
	for p in s.parts:
		if PhysWorld.bodies.has(p.body_id):
			PhysWorld.remove_body(p.body_id)
		Fire.on_part_removed(p)
		p.state = Part.State.DEAD
		p.links.clear()
		p.structure = null
		p.mesh = null
	if s.dormant_body != 0 and PhysWorld.bodies.has(s.dormant_body):
		PhysWorld.remove_body(s.dormant_body)
	s.dormant_body = 0
	s.parts.clear()
	s.behavior = null
	if s.root != null and is_instance_valid(s.root):
		s.root.queue_free()
	structures.erase(s)
	awake_list.erase(s)

# ------------------------------------------------------------------ creation
static func create(kind: String, owner_id: int, br: BuildResult, base: Transform3D, free_parts: bool = false, name_key: String = "") -> Structure:
	var s := Structure.new()
	s.id = _next_struct_id
	_next_struct_id += 1
	s.kind = kind
	s.owner_id = owner_id
	s.free_parts = free_parts
	s.name_key = name_key if name_key != "" else "building." + kind
	s.root = Node3D.new()
	s.root.name = "%s_%d" % [kind, s.id]
	world_root.add_child(s.root)
	var have_aabb: bool = false
	for d in br.parts:
		var p := Part.new()
		p.id = _next_part_id
		_next_part_id += 1
		p.index = s.parts.size()
		p.structure = s
		var col: Color = d.color if d.color.r >= 0.0 else Kit.pick_color(d.material, null)
		p.setup(d.material, d.shape, d.size, base * d.xf(), col, d)
		p.segs = d.segs
		p.glow = d.glow
		p.anchor = d.anchor
		p.tag = d.tag
		p.born = time_now
		s.parts.append(p)
		var bb: AABB = p.world_aabb()
		if not have_aabb:
			s.aabb = bb
			have_aabb = true
		else:
			s.aabb = s.aabb.merge(bb)
	s.live_count = s.parts.size()
	s.initial_count = s.parts.size()
	var hp_sum: float = 0.0
	for p2 in s.parts:
		hp_sum += p2.hp
	s.initial_hp = hp_sum
	s.center = s.aabb.get_center()
	s.radius = maxf(s.aabb.size.x, s.aabb.size.z) * 0.5
	s.height = s.aabb.size.y
	if free_parts:
		_make_props_awake(s)
	else:
		_build_links(s)
		for p3 in s.parts:
			if not p3.anchor:
				var bottom: float = p3.world_aabb().position.y
				if bottom <= Terrain.h(p3.xf.origin.x, p3.xf.origin.z) + 0.15:
					p3.anchor = true
		_build_dormant(s)
	structures.append(s)
	Fire.build_grid_add(s)      # flammable parts join the fire spatial hash right away
	return s

static func _build_links(s: Structure) -> void:
	var n: int = s.parts.size()
	var boxes: Array[AABB] = []
	var order: Array[int] = []
	for i in n:
		boxes.append(s.parts[i].world_aabb().grow(0.05))
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return boxes[a].position.x < boxes[b].position.x)
	for oi in n:
		var i: int = order[oi]
		var bi: AABB = boxes[i]
		var max_x: float = bi.position.x + bi.size.x
		var oj: int = oi + 1
		while oj < n:
			var j: int = order[oj]
			var bj: AABB = boxes[j]
			if bj.position.x > max_x:
				break
			if bi.intersects(bj):
				var a: Part = s.parts[i]
				var b: Part = s.parts[j]
				a.links.append(b)
				b.links.append(a)
			oj += 1

static func shapes_for(p: Part, local: bool) -> Array[PhysWorld.ShapeDesc]:
	var out: Array[PhysWorld.ShapeDesc] = []
	if p.shape == "compound":
		var base: Transform3D = p.xf if not local else Transform3D.IDENTITY
		for sp in p.subs:
			var sd: PhysWorld.ShapeDesc = shape_desc_for_def(sp, base * sp.xf())
			out.append(sd)
	else:
		out.append(shape_desc_for(p, local))
	return out

static func shape_desc_for_def(sp: PartDef, xf: Transform3D) -> PhysWorld.ShapeDesc:
	match sp.shape:
		"cyl":
			return PhysWorld.cyl_desc(sp.size.x * 0.5, sp.size.y, xf)
		"sphere":
			return PhysWorld.sphere_desc(sp.size.x * 0.5, xf)
		"frustum":
			return PhysWorld.cyl_desc((sp.size.x + sp.size.z) * 0.25 + 0.01, sp.size.y, xf)
		_:
			return PhysWorld.box_desc(sp.size, xf)

static func shape_desc_for(p: Part, local: bool) -> PhysWorld.ShapeDesc:
	var xf: Transform3D = p.xf if not local else Transform3D.IDENTITY
	match p.shape:
		"cyl":
			return PhysWorld.cyl_desc(p.size.x * 0.5, p.size.y, xf)
		"sphere":
			return PhysWorld.sphere_desc(p.size.x * 0.5, xf)
		"frustum":
			return PhysWorld.cyl_desc((p.size.x + p.size.z) * 0.25 + 0.01, p.size.y, xf)
		_:
			return PhysWorld.box_desc(p.size, xf)

static func add_def_to_buf(buf: MeshGen.Buf, sp: PartDef, xf: Transform3D, col: Color) -> void:
	match sp.shape:
		"cyl":
			MeshGen.add_cyl(buf, sp.size.x * 0.5, sp.size.y, sp.segs, xf, col)
		"sphere":
			MeshGen.add_sphere(buf, sp.size.x * 0.5, xf, col)
		"frustum":
			MeshGen.add_frustum(buf, sp.size.x * 0.5, sp.size.z * 0.5, sp.size.y, sp.segs, xf, col)
		_:
			MeshGen.add_box(buf, sp.size, xf, col)

static func compound_mesh(p: Part, world: bool) -> ArrayMesh:
	var buf := MeshGen.Buf.new()
	var base: Transform3D = p.xf if world else Transform3D.IDENTITY
	for sp in p.subs:
		var col: Color = sp.color if sp.color.r >= 0.0 else Kit.pick_color(sp.material, null)
		add_def_to_buf(buf, sp, base * sp.xf(), col)
	return buf.to_mesh()

static func part_mesh(p: Part) -> Mesh:
	match p.shape:
		"compound":
			return compound_mesh(p, false)
		"cyl":
			return MeshGen.cyl_mesh(p.size.x * 0.5, p.size.y, p.segs)
		"sphere":
			return MeshGen.sphere_mesh(p.size.x * 0.5)
		"frustum":
			return MeshGen.frustum_mesh(p.size.x * 0.5, p.size.z * 0.5, p.size.y, p.segs)
		_:
			return MeshGen.box_mesh(p.size)

static func add_part_to_buf(buf: MeshGen.Buf, p: Part) -> void:
	match p.shape:
		"compound":
			for sp in p.subs:
				var col: Color = sp.color if sp.color.r >= 0.0 else Kit.pick_color(sp.material, null)
				add_def_to_buf(buf, sp, p.xf * sp.xf(), col)
		"cyl":
			MeshGen.add_cyl(buf, p.size.x * 0.5, p.size.y, p.segs, p.xf, p.color)
		"sphere":
			MeshGen.add_sphere(buf, p.size.x * 0.5, p.xf, p.color)
		"frustum":
			MeshGen.add_frustum(buf, p.size.x * 0.5, p.size.z * 0.5, p.size.y, p.segs, p.xf, p.color)
		_:
			MeshGen.add_box(buf, p.size, p.xf, p.color)

static func _build_dormant(s: Structure) -> void:
	var buf := MeshGen.Buf.new()
	var desc := PhysWorld.BodyDesc.new()
	desc.mode = "static"
	desc.layer = Cfg.LAYER_STRUCT
	desc.mask = 0
	desc.kind = "struct"
	desc.owner = s
	desc.friction = 0.8
	desc.bounce = 0.1
	for p in s.parts:
		p.state = Part.State.DORMANT
		if p.glow:
			var mi := MeshInstance3D.new()
			mi.mesh = part_mesh(p)
			mi.material_override = Toon.emissive(p.color, 1.2)
			mi.transform = p.xf
			s.root.add_child(mi)
			s.dormant_extra.append(mi)
		else:
			add_part_to_buf(buf, p)
		for sd in shapes_for(p, false):
			desc.shapes.append(sd)
			s.dormant_shape_parts.append(p)
	if not buf.is_empty():
		s.dormant_mesh = MeshInstance3D.new()
		s.dormant_mesh.mesh = buf.to_mesh()
		s.dormant_mesh.material_override = Toon.main()
		s.dormant_mesh.name = "Dormant"
		s.dormant_mesh.visibility_range_end = 400.0 if s.kind != "tree" else 170.0
		s.root.add_child(s.dormant_mesh)
	s.dormant_body = PhysWorld.add_body(desc)

static func _make_props_awake(s: Structure) -> void:
	s.awake = true
	awake_list.append(s)
	for p in s.parts:
		_make_part_body(p, "rigid", true)
		p.state = Part.State.FREE

## Creates the body + visual of a part. `sleeping` bodies (props) start asleep.
static func _make_part_body(p: Part, mode: String, sleeping: bool = false) -> void:
	var s: Structure = p.structure
	var mi := MeshInstance3D.new()
	mi.mesh = part_mesh(p)
	if p.glow:
		mi.material_override = Toon.emissive(p.color, 1.2)
	else:
		mi.material_override = Toon.main()
		mi.set_instance_shader_parameter("tint", Color.WHITE if p.shape == "compound" else p.color)
	s.root.add_child(mi)
	p.mesh = mi
	var desc := PhysWorld.BodyDesc.new()
	for sd2 in shapes_for(p, true):
		desc.shapes.append(sd2)
	desc.xf = p.xf
	desc.mass = p.mass
	desc.friction = p.mat.friction
	desc.bounce = p.mat.restitution if p.bounce_override < 0.0 else p.bounce_override
	desc.layer = Cfg.LAYER_PART if not s.free_parts else Cfg.LAYER_PROP
	desc.mask = Cfg.LAYER_ALL
	desc.mode = mode
	desc.kind = "part"
	desc.owner = p
	desc.visual = mi
	desc.sleeping = sleeping
	if mode == "rigid":
		desc.contacts = 4
		desc.on_contact = Callable(Breakable, "_part_contact")
		desc.damp_lin = 0.06
		desc.damp_ang = 0.25
	p.body_id = PhysWorld.add_body(desc)
	var pbody: PhysWorld.PBody = PhysWorld.body(p.body_id)
	if pbody != null:
		pbody.buoy = 1000.0 / p.mat.density if p.prop_kind != "rubberduck" else 3.0
		pbody.radius = maxf(p.radius(), 0.15)

# ------------------------------------------------------------------ awaken / release
static func awaken(s: Structure) -> void:
	if s.awake:
		return
	s.awake = true
	if s.dormant_body != 0:
		PhysWorld.remove_body(s.dormant_body)
		s.dormant_body = 0
	if s.dormant_mesh != null:
		s.dormant_mesh.queue_free()
		s.dormant_mesh = null
	for m in s.dormant_extra:
		m.queue_free()
	s.dormant_extra.clear()
	s.dormant_shape_parts.clear()
	for p in s.parts:
		if p.state == Part.State.DEAD:
			continue
		_make_part_body(p, "static")
		p.state = Part.State.FROZEN
	awake_list.append(s)
	s.support_dirty = false
	if s.behavior != null:
		s.behavior.call("on_awaken", s)

static func awaken_in_radius(pos: Vector3, radius: float) -> void:
	for s in structures:
		if s.awake or s.destroyed:
			continue
		if s.aabb.grow(radius).has_point(pos):
			awaken(s)

static func release_part(p: Part, extra_kick: Vector3 = Vector3.ZERO) -> void:
	if p.state != Part.State.FROZEN:
		return
	p.state = Part.State.FREE
	var kick: Vector3 = p.kick + extra_kick
	p.kick = Vector3.ZERO
	var ang := Vector3(rng.range_f(-1.5, 1.5), rng.range_f(-1.5, 1.5), rng.range_f(-1.5, 1.5))
	PhysWorld.make_dynamic(p.body_id, p.mass, 0.06, 0.25, 4, Callable(Breakable, "_part_contact"), kick, ang)
	PhysWorld.set_layer_mask(p.body_id, Cfg.LAYER_PART, Cfg.LAYER_ALL)
	Debris.register_part(p)
	Fire.register_mobile(p)
	if p.structure.behavior != null:
		p.structure.behavior.call("on_release", p.structure, p)

static func release_all(s: Structure, kick_from: Vector3 = Vector3.INF, strength: float = 0.0) -> void:
	awaken(s)
	for p in s.parts:
		if p.state == Part.State.FROZEN:
			var k: Vector3 = Vector3.ZERO
			if kick_from != Vector3.INF:
				k = (p.xf.origin - kick_from).normalized() * strength
			release_part(p, k)

## Support check (spec 5.3, physics v2): a part stays if it stands on something that stands (resting contact below it, the
## ground counting as the root) or hangs at most CANTILEVER links off such a part. Overhanging walls, floors and roofs
## whose support was shot away therefore come down instead of floating on their glue links.
const CANTILEVER := 3

static func support_check(s: Structure) -> void:
	_stamp += 1
	for p in s.parts:
		if p.state == Part.State.FROZEN:
			var bb: AABB = p.world_aabb()
			p._bot = bb.position.y
			p._top = bb.position.y + bb.size.y
			p.sup_depth = 99
	var q: Array[Part] = []
	for p in s.parts:
		if p.state == Part.State.FROZEN and p.anchor:
			p.sup_depth = 0
			p.stamp = _stamp
			q.append(p)
	var i: int = 0
	while i < q.size():
		var cur: Part = q[i]
		i += 1
		for n in cur.links:
			if n.state != Part.State.FROZEN:
				continue
			var d: int
			if n._bot >= cur._top - 0.25:
				d = 0                       # n rests on cur: fully supported
				if cur.sup_depth > CANTILEVER:
					continue
			elif n._top <= cur._bot + 0.25:
				d = cur.sup_depth + 1       # n hangs below cur
			else:
				d = cur.sup_depth + 1       # n sticks out sideways
			if d <= CANTILEVER and d < n.sup_depth:
				n.sup_depth = d
				n.stamp = _stamp
				q.append(n)
	for p2 in s.parts:
		if p2.state == Part.State.FROZEN and p2.stamp != _stamp:
			release_part(p2)

# ------------------------------------------------------------------ breaking
static func discard_part(p: Part) -> void:
	## Silent removal (debris cap): no shards, no events
	if p.state == Part.State.DEAD:
		return
	p.state = Part.State.DEAD
	p.structure.live_count -= 1
	for q in p.links:
		q.links.erase(p)
	p.links.clear()
	Fire.on_part_removed(p)
	if PhysWorld.bodies.has(p.body_id):
		PhysWorld.remove_body(p.body_id)
	p.mesh = null

static func break_part(p: Part, source: Dictionary = {}, dir: Vector3 = Vector3.ZERO, silent: bool = false) -> void:
	if p.state == Part.State.DEAD:
		return
	var s: Structure = p.structure
	if not s.awake:
		awaken(s)
	var pos: Vector3 = p.xf.origin
	var was_state: int = p.state
	p.state = Part.State.DEAD
	s.live_count -= 1
	for q in p.links:
		q.links.erase(p)
	p.links.clear()
	Fire.on_part_removed(p)
	var vel: Vector3 = Vector3.ZERO
	if was_state == Part.State.FREE:
		vel = PhysWorld.get_velocity(p.body_id)
	if PhysWorld.bodies.has(p.body_id):
		PhysWorld.remove_body(p.body_id)
	p.mesh = null
	s.support_dirty = true
	if not silent:
		_spawn_shards(p, dir, vel)
		Fx.burst(p.mat.shard, pos, p.mat.shard_color, clampf(p.size_factor, 0.5, 2.0))
		Sfx.play(p.mat.sound, pos, clampf(p.size_factor * 0.6, 0.4, 1.2), 1)
		Events.part_break.emit(pos, p.mat_id, pow(p.volume, 1.0 / 3.0))
		if rng.chance(0.05) and p.size_factor > 0.9:
			Fx.comic_kind(p.mat.comic, pos + Vector3.UP * 0.6)
	if p.prop_kind != "":
		Props.on_break(p, source)
	if s.behavior != null:
		s.behavior.call("on_part_break", s, p)
	if not s.destroyed and not s.free_parts and s.destroyed_fraction() > 0.70:
		s.destroyed = true
		Events.building_destroyed.emit(s.kind, s.owner_id, source)
		Fx.comic_kind("crash", s.center + Vector3.UP * (s.height * 0.5))
		if s.behavior != null:
			s.behavior.call("on_destroyed", s)
	Scoring.on_part_broken(s, source)

static func _spawn_shards(p: Part, dir: Vector3, vel: Vector3) -> void:
	var s: Structure = p.structure
	if s.shard_count >= 40 or p.volume < 0.004:
		return
	var n: int = rng.range_i(2, 4)
	var pos: Vector3 = p.xf.origin
	var base_size: Vector3 = p.size
	if p.shape != "box":
		var d: float = maxf(p.size.x, p.size.z)
		base_size = Vector3(d, p.size.y, d)
	for i in n:
		if s.shard_count >= 40:
			break
		var sz: Vector3 = (base_size * 0.4).clamp(Vector3(0.06, 0.06, 0.06), Vector3(1.2, 1.2, 1.2))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshGen.box_mesh(sz)
		mi.material_override = Toon.main()
		var col: Color = p.color.lerp(Color(0.08, 0.06, 0.05), clampf(p.charred, 0.0, 1.0) * 0.85)
		mi.set_instance_shader_parameter("tint", col)
		s.root.add_child(mi)
		var off := Vector3(rng.range_f(-0.5, 0.5), rng.range_f(-0.5, 0.5), rng.range_f(-0.5, 0.5)) * base_size * 0.5
		var desc := PhysWorld.BodyDesc.new()
		desc.shapes.append(PhysWorld.box_desc(sz))
		desc.xf = Transform3D(Basis.from_euler(Vector3(rng.range_f(0, TAU), rng.range_f(0, TAU), rng.range_f(0, TAU))), pos + off)
		desc.mass = maxf(p.mat.density * sz.x * sz.y * sz.z, 0.05)
		desc.friction = p.mat.friction
		desc.bounce = p.mat.restitution
		desc.layer = Cfg.LAYER_DEBRIS
		desc.mask = Cfg.LAYER_TERRAIN | Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP
		desc.kind = "shard"
		desc.visual = mi
		desc.damp_lin = 0.1
		desc.damp_ang = 0.4
		var outward: Vector3 = (off.normalized() if off.length() > 0.01 else Vector3.UP)
		desc.velocity = vel * 0.6 + dir * rng.range_f(1.0, 5.0) + outward * rng.range_f(1.0, 3.5) + Vector3(0, rng.range_f(1.0, 4.0), 0)
		desc.ang_velocity = Vector3(rng.range_f(-6, 6), rng.range_f(-6, 6), rng.range_f(-6, 6))
		var id: int = PhysWorld.add_body(desc)
		var spb: PhysWorld.PBody = PhysWorld.body(id)
		if spb != null:
			spb.buoy = 1000.0 / p.mat.density
			spb.radius = maxf(sz.x, maxf(sz.y, sz.z)) * 0.5
		Debris.register_shard(id, mi)
		s.shard_count += 1

# ------------------------------------------------------------------ contact callback for released parts / props
## The physics callback only RECORDS contacts (bodies must not be freed/created while the server steps);
## `_process_contacts` handles the damage rules in the next tick.
static var _contact_queue: Array[Dictionary] = []

static func _part_contact(pb: PhysWorld.PBody, state: PhysicsDirectBodyState3D) -> void:
	var p: Part = pb.owner as Part
	if p == null or p.state != Part.State.FREE:
		return
	var imp: float = 0.0
	var n: int = mini(state.get_contact_count(), 4)
	var others: Array[Object] = []
	var cpos: Vector3 = pb.xform.origin
	for i in n:
		imp += state.get_contact_impulse(i).length()
		others.append(PhysWorld.owner_of(state.get_contact_collider(i)))
	if imp <= 1.0:
		return
	if n > 0:
		cpos = state.get_contact_collider_position(0)
	if _contact_queue.size() < 256:
		_contact_queue.append({"p": p, "imp": imp, "others": others, "pos": cpos, "at": pb.xform.origin})

static func _process_contacts() -> void:
	if _contact_queue.is_empty():
		return
	var q: Array[Dictionary] = _contact_queue.duplicate()
	_contact_queue.clear()
	for e in q:
		var p: Part = e["p"] as Part
		if p.state != Part.State.FREE:
			continue
		var imp: float = float(e["imp"])
		var at: Vector3 = e["at"] as Vector3
		var others: Array = e["others"] as Array
		var src: Dictionary = p.structure.last_source if time_now - p.structure.last_source_time < 20.0 else {}
		var thresh: float = p.mat.break_force * p.size_factor
		if p.structure.free_parts:
			thresh *= 0.5    # props are easier to smash
		if imp > thresh:
			Damage.apply_impact(p, imp, src)
		elif imp > thresh * 0.35 and p.mass > 20.0:
			Sfx.play(p.mat.sound, at, clampf(imp / (thresh * 2.0), 0.15, 0.8), 0)
		if p.prop_kind == "rubberduck" and imp > 30.0:
			Sfx.play("squeak", at, 0.7, 1)
		# heavy falling parts hurt catapults / settlers they land on and knock loose neighbours (collapse propagation)
		for o in others:
			if o == null:
				continue
			if o is Catapult and imp > 400.0 and p.mass > 30.0:
				Damage.damage_catapult(o as Catapult, maxf(imp - 500.0, 0.0) / 30.0, src, "debris")
			elif o is Part:
				var other: Part = o as Part
				if other.state == Part.State.FROZEN and imp > other.mat.break_force * other.size_factor * 0.25 and other.mass < p.mass * 6.0:
					var push: Vector3 = (other.xf.origin - at).normalized() * clampf(imp / maxf(other.mass, 5.0), 0.5, 8.0)
					release_part(other, push)
		if imp > 500.0 and p.mass > 20.0 and p.state != Part.State.DEAD:
			Damage.damage_settlers_in_radius(at, 1.4, imp / 40.0, src, (at - (e["pos"] as Vector3)), 0.5)

# ------------------------------------------------------------------ per-tick update
static func tick(dt: float) -> void:
	time_now += dt
	_process_contacts()
	var budget: int = 1
	var count: int = awake_list.size()
	if count > 0:
		for k in count:
			var idx: int = (_rr + k) % count
			var s: Structure = awake_list[idx]
			if s.support_dirty and not s.free_parts:
				s.support_timer -= dt * float(count) if false else dt
				if s.support_timer <= 0.0 and budget > 0:
					s.support_dirty = false
					s.support_timer = 0.1
					support_check(s)
					budget -= 1
		_rr = (_rr + 1) % count
	for s2 in awake_list:
		if s2.behavior != null:
			s2.behavior.call("tick", s2, dt)
	# specials on dormant structures (windmill rotor etc.)
	for s3 in structures:
		if not s3.awake and s3.behavior != null:
			s3.behavior.call("tick", s3, dt)

## Total hp of live parts of a player's village (tie-breaks)
static func village_hp(owner_id: int) -> float:
	var t: float = 0.0
	for s in structures:
		if s.owner_id == owner_id and not s.free_parts and s.kind != "tree":
			t += s.live_hp()
	return t
