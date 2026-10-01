class_name Props
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Prop builders (spec section 10). A prop is a `Structure` with `free_parts = true`: its parts are dynamic
## bodies from the start (asleep until touched) and share the part damage/fire code.

const KINDS: Array[String] = ["barrel_beer", "barrel_water", "barrel_powder", "crate", "haybale", "pumpkin", "cart",
	"fence", "lantern", "banner", "tent", "anvil", "mug", "bucket", "rubberduck", "fruit", "cheese_chunk"]

static var rng: Rng = Rng.new(5)

static func _sub(shape: String, mat: String, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> PartDef:
	var d := PartDef.new()
	d.shape = shape
	d.material = mat
	d.size = size
	d.pos = pos
	d.rot = rot
	d.color = col
	return d

static func _compound(mat: String, size: Vector3, pos: Vector3, subs: Array[PartDef], mass: float) -> PartDef:
	var d := PartDef.new()
	d.shape = "compound"
	d.material = mat
	d.size = size
	d.pos = pos
	d.subs = subs
	d.mass_override = mass
	d.color = Color.WHITE
	return d

## Build a prop blueprint. Local y = 0 is the ground.
static func build(kind: String, r: Rng, player_color: Color = Color.WHITE) -> BuildResult:
	var b := BuildResult.new()
	match kind:
		"barrel_beer", "barrel_water":
			var col: Color = Color("#a5672f") if kind == "barrel_beer" else Color("#7a9fc4")
			var subs: Array[PartDef] = []
			subs.append(_sub("cyl", "barrel_wood", Vector3(0.9, 0.9, 0.9), Vector3(0, 0, 0), col))
			var band: Color = Color("#3a3f4a") if kind == "barrel_beer" else Color("#2d6fb5")
			subs.append(_sub("cyl", "metal", Vector3(0.96, 0.08, 0.96), Vector3(0, 0.28, 0), band))
			subs.append(_sub("cyl", "metal", Vector3(0.96, 0.08, 0.96), Vector3(0, -0.28, 0), band))
			var p := _compound("barrel_wood", Vector3(0.96, 0.9, 0.96), Vector3(0, 0.45, 0), subs, 60.0 if kind == "barrel_beer" else 120.0)
			p.tag = kind
			b.add(p)
		"barrel_powder":
			var subs2: Array[PartDef] = []
			subs2.append(_sub("cyl", "barrel_wood", Vector3(0.64, 0.7, 0.64), Vector3.ZERO, Color("#2b2b33")))
			subs2.append(_sub("cyl", "metal", Vector3(0.68, 0.06, 0.68), Vector3(0, 0.22, 0), Color("#6d7683")))
			subs2.append(_sub("cyl", "metal", Vector3(0.68, 0.06, 0.68), Vector3(0, -0.22, 0), Color("#6d7683")))
			subs2.append(_sub("box", "plank", Vector3(0.22, 0.2, 0.05), Vector3(0, 0.02, 0.33), Color("#f0f0e8")))   # skull plate
			var p2 := _compound("barrel_wood", Vector3(0.68, 0.7, 0.68), Vector3(0, 0.35, 0), subs2, 40.0)
			p2.tag = "barrel_powder"
			b.add(p2)
		"crate":
			var c := Kit.box(b, "wood", Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), r, Kit.NO_COLOR, false, "crate")
			c.mass_override = 30.0
		"haybale":
			var h := Kit.box(b, "hay", Vector3(1.0, 0.7, 0.7), Vector3(0, 0.35, 0), r, Kit.NO_COLOR, false, "haybale")
			h.mass_override = 25.0
			h.restitution_override = 0.02
		"pumpkin":
			var pk := Kit.sph(b, "flesh", 0.3, Vector3(0, 0.27, 0), r, Color("#ff8a1f"), "pumpkin")
			pk.hp_override = 12.0
			pk.mass_override = 6.0
			pk.restitution_override = 0.5
		"cart":
			# bed + shaft poles as one compound, two wheels connected by hinge joints (see post_spawn)
			var subs3: Array[PartDef] = []
			subs3.append(_sub("box", "wood", Vector3(2.0, 0.2, 1.0), Vector3(0, 0.0, 0), Color("#b5763a")))
			subs3.append(_sub("box", "plank", Vector3(2.0, 0.32, 0.08), Vector3(0, 0.26, 0.5), Color("#c48748")))
			subs3.append(_sub("box", "plank", Vector3(2.0, 0.32, 0.08), Vector3(0, 0.26, -0.5), Color("#c48748")))
			subs3.append(_sub("box", "plank", Vector3(0.08, 0.32, 1.0), Vector3(-1.0, 0.26, 0), Color("#c48748")))
			subs3.append(_sub("box", "wood", Vector3(1.6, 0.09, 0.09), Vector3(1.75, -0.02, 0.3), Color("#8a5a2a")))
			subs3.append(_sub("box", "wood", Vector3(1.6, 0.09, 0.09), Vector3(1.75, -0.02, -0.3), Color("#8a5a2a")))
			var bed := _compound("wood", Vector3(3.6, 0.5, 1.1), Vector3(0, 0.7, 0), subs3, 40.0)
			bed.tag = "cart_bed"
			b.add(bed)
			for sgn in [-1.0, 1.0]:
				var wheel := Kit.cyl(b, "wood", 0.45, 0.12, Vector3(-0.35, 0.45, (sgn as float) * 0.62), r, Color("#7a4a25"), false, "cart_wheel", Vector3(PI * 0.5, 0, 0))
				wheel.mass_override = 12.0
		"fence":
			var subs4: Array[PartDef] = []
			for i in 3:
				subs4.append(_sub("box", "plank", Vector3(0.12, 0.95, 0.1), Vector3(-0.9 + float(i) * 0.9, 0.0, 0), Color("#d09a5a")))
			subs4.append(_sub("box", "plank", Vector3(2.0, 0.09, 0.06), Vector3(0, 0.22, 0.05), Color("#c48748")))
			subs4.append(_sub("box", "plank", Vector3(2.0, 0.09, 0.06), Vector3(0, -0.12, 0.05), Color("#c48748")))
			var f := _compound("plank", Vector3(2.0, 0.95, 0.14), Vector3(0, 0.475, 0), subs4, 25.0)
			f.tag = "fence"
			b.add(f)
		"lantern":
			var subs5: Array[PartDef] = []
			subs5.append(_sub("cyl", "wood", Vector3(0.12, 2.4, 0.12), Vector3(0, 0, 0), Color("#7a4a25")))
			subs5.append(_sub("box", "wood", Vector3(0.5, 0.06, 0.5), Vector3(0, 1.05, 0), Color("#5a381c")))
			subs5.append(_sub("box", "glass", Vector3(0.36, 0.4, 0.36), Vector3(0, 1.28, 0), Color("#ffe98a")))
			subs5.append(_sub("box", "wood", Vector3(0.5, 0.06, 0.5), Vector3(0, 1.52, 0), Color("#5a381c")))
			var l := _compound("wood", Vector3(0.5, 2.6, 0.5), Vector3(0, 1.3, 0), subs5, 15.0)
			l.tag = "lantern"
			b.add(l)
		"banner":
			var subs6: Array[PartDef] = []
			subs6.append(_sub("cyl", "wood", Vector3(0.1, 3.0, 0.1), Vector3(0, 0, 0), Color("#7a4a25")))
			subs6.append(_sub("box", "cloth", Vector3(0.05, 0.9, 1.1), Vector3(0.0, 0.85, 0.6), player_color))
			var bn := _compound("wood", Vector3(0.2, 3.0, 1.3), Vector3(0, 1.5, 0.3), subs6, 10.0)
			bn.tag = "banner"
			b.add(bn)
		"tent":
			var subs7: Array[PartDef] = []
			var cols: Array[String] = ["#e74c3c", "#f4f1e8"]
			subs7.append(_sub("cyl", "wood", Vector3(0.14, 4.6, 0.14), Vector3(0, 0.6, 0), Color("#7a4a25")))
			subs7.append(_sub("frustum", "cloth", Vector3(4.4, 1.2, 3.4), Vector3(0, -0.6, 0), Color(cols[0])))
			var sd: PartDef = subs7[subs7.size() - 1]
			sd.segs = 8
			var s2 := _sub("frustum", "cloth", Vector3(3.4, 1.2, 1.0), Vector3(0, 0.6, 0), Color(cols[1]))
			s2.segs = 8
			subs7.append(s2)
			var s3 := _sub("frustum", "cloth", Vector3(1.0, 1.0, 0.1), Vector3(0, 1.7, 0), Color(cols[0]))
			s3.segs = 8
			subs7.append(s3)
			var t := _compound("cloth", Vector3(4.4, 4.6, 4.4), Vector3(0, 2.3, 0), subs7, 40.0)
			t.tag = "tent"
			b.add(t)
		"anvil":
			var subs8: Array[PartDef] = []
			subs8.append(_sub("box", "metal", Vector3(0.5, 0.25, 0.9), Vector3(0, 0.2, 0), Color("#5c6672")))
			subs8.append(_sub("box", "metal", Vector3(0.3, 0.3, 0.4), Vector3(0, -0.05, 0), Color("#5c6672")))
			subs8.append(_sub("box", "metal", Vector3(0.6, 0.12, 0.6), Vector3(0, -0.25, 0), Color("#4d5762")))
			var an := _compound("metal", Vector3(0.6, 0.75, 0.9), Vector3(0, 0.4, 0), subs8, 150.0)
			an.tag = "anvil"
			b.add(an)
		"cheese_chunk":
			var cs: Array[PartDef] = []
			var pr := _sub("box", "flesh", Vector3(0.7, 0.5, 0.5), Vector3.ZERO, Color("#ffd54a"))
			cs.append(pr)
			cs.append(_sub("sphere", "flesh", Vector3(0.14, 0.14, 0.14), Vector3(0.15, 0.1, 0.26), Color("#d9a91c")))
			var ch := _compound("flesh", Vector3(0.7, 0.5, 0.5), Vector3(0, 0.25, 0), cs, 8.0)
			ch.tag = "cheese_chunk"
			b.add(ch)
		"fruit":
			var fr := Kit.sph(b, "flesh", 0.11, Vector3(0, 0.11, 0), r, Color("#e03a2a") if r.chance(0.6) else Color("#8fce3a"), "fruit")
			fr.mass_override = 0.3
			fr.hp_override = 8.0
			fr.restitution_override = 0.4
		"mug":
			var m := Kit.cyl(b, "glass", 0.08, 0.16, Vector3(0, 0.08, 0), r, Color("#f0c040"), false, "mug")
			m.mass_override = 0.5
			m.hp_override = 10.0
		"bucket":
			var bk := Kit.cyl(b, "wood", 0.17, 0.28, Vector3(0, 0.14, 0), r, Color("#8a5a2a"), false, "bucket")
			bk.mass_override = 3.0
			bk.hp_override = 30.0
		"rubberduck":
			var subs9: Array[PartDef] = []
			subs9.append(_sub("sphere", "flesh", Vector3(1.0, 1.0, 1.0), Vector3(0, 0, 0), Color("#ffe14a")))
			subs9.append(_sub("sphere", "flesh", Vector3(0.6, 0.6, 0.6), Vector3(0.28, 0.5, 0), Color("#ffe14a")))
			subs9.append(_sub("box", "flesh", Vector3(0.3, 0.1, 0.3), Vector3(0.62, 0.48, 0), Color("#ff8a1f")))
			subs9.append(_sub("sphere", "flesh", Vector3(0.7, 0.7, 0.7), Vector3(-0.32, 0.12, 0), Color("#ffe14a")))
			var du := _compound("flesh", Vector3(1.2, 1.2, 0.9), Vector3(0, 0.5, 0), subs9, 8.0)
			du.tag = "rubberduck"
			du.restitution_override = 0.8
			du.hp_override = 60.0
			b.add(du)
		_:
			Kit.box(b, "wood", Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0), r, Kit.NO_COLOR, false, kind)
	return b

## Create the prop at ground position `pos` facing `yaw`.
static func spawn(kind: String, pos: Vector3, yaw: float, owner_id: int, r: Rng, player_color: Color = Color.WHITE, lift: float = 0.0) -> Structure:
	var b: BuildResult = build(kind, r, player_color)
	var ground: float = Terrain.h(pos.x, pos.z)
	var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, ground + 0.02 + lift, pos.z))
	var s: Structure = Breakable.create("prop_" + kind, owner_id, b, base, true, "prop." + kind)
	for p in s.parts:
		p.prop_kind = kind
	s.is_decor = true
	post_spawn(s, kind)
	return s

static func post_spawn(s: Structure, kind: String) -> void:
	if kind == "cart" and s.parts.size() >= 3:
		var bed: Part = s.parts[0]
		for i in range(1, 3):
			var w: Part = s.parts[i]
			var j: RID = PhysicsServer3D.joint_create()
			# frames: hinge axis of the frame is local Z in Godot; wheel local axis after its rotation is its own Y (cyl axis)
			var wheel_local_pos: Vector3 = bed.xf.affine_inverse() * w.xf.origin
			var fa := Transform3D(Basis(), wheel_local_pos)
			var fb := Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3.ZERO)
			# frame basis: wheel local axes are (X, Z, -Y) -> hinge (Z of frame) matches wheel cylinder axis
			PhysicsServer3D.joint_make_hinge(j, PhysWorld.body_rid(bed.body_id), fa, PhysWorld.body_rid(w.body_id), fb)
			s.extras.append({"joint": j})

static func free_joints(s: Structure) -> void:
	for e in s.extras:
		if e is Dictionary and (e as Dictionary).has("joint"):
			var j: RID = (e as Dictionary)["joint"] as RID
			if j.is_valid():
				PhysicsServer3D.free_rid(j)
	s.extras = s.extras.filter(func(e: Variant) -> bool: return not (e is Dictionary and (e as Dictionary).has("joint")))

# ------------------------------------------------------------------ break / special behavior
static func on_break(p: Part, source: Dictionary) -> void:
	var pos: Vector3 = p.xf.origin
	match p.prop_kind:
		"barrel_beer":
			Fx.burst("beer", pos + Vector3.UP * 0.4, Color(0, 0, 0, -1), 0.7)
			Fx.burst("splash", pos, Color("#e8b03a"), 0.5)
			Sfx.play("splash", pos, 0.6, 1)
			if p.on_fire or p.burning > 0.3 or Fire.fires_near(pos, 4.0):
				Fire.spawn_ground_fire(pos, source, 2.0)
		"barrel_water":
			WaterSys.splash(pos, 4.0, source, 0.8)
		"barrel_powder":
			detonate_powder(p, source)
		"pumpkin":
			Fx.burst("splash", pos, Color("#ff8a1f"), 0.8)
			Sfx.play("splat", pos, 0.7, 1)
		"fruit":
			Fx.burst("splash", pos, p.color, 0.3)
			Sfx.play("splat", pos, 0.5, 1)
		"lantern":
			if rng.chance(0.3):
				Fire.spawn_ground_fire(pos, source, 2.5)
				Fire.ignite_in_radius(pos, 1.6, 0.6, source)
		"mug":
			pass
		"cart":
			pass
	if p.structure.kind == "prop_cart":
		free_joints(p.structure)

static var _exploding: Dictionary = {}

## Powder keg explosion (radius 5, damage 500). The keg part is removed.
static func detonate_powder(p: Part, source: Dictionary) -> void:
	if _exploding.has(p.id):
		return
	_exploding[p.id] = true
	Unlocks.on_powder_barrel(source)
	var pos: Vector3 = p.xf.origin
	if p.state != Part.State.DEAD:
		Breakable.break_part(p, source, Vector3.UP, true)
	Explosion.explode(pos, 9.0, 1000.0, {"source": source, "fire": true, "sound": "bigboom", "keg": true})
	_exploding.erase(p.id)
