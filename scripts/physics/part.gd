class_name Part
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## A single rigid box / cylinder / sphere / frustum (spec 5.1).

enum State { DORMANT, FROZEN, FREE, DEAD }

var id: int = 0
var index: int = 0
var mat_id: String = "wood"
var mat: Materials.MaterialDef
var size: Vector3 = Vector3.ONE
var shape: String = "box"
var segs: int = 12
var xf: Transform3D = Transform3D.IDENTITY
var xf0: Transform3D = Transform3D.IDENTITY       # the pose it was built in (online play puts parts back there)
var color: Color = Color.WHITE
var glow: bool = false
var hp: float = 10.0
var max_hp: float = 10.0
var volume: float = 1.0
var size_factor: float = 1.0
var mass: float = 1.0
var structure: Structure
var links: Array[Part] = []
var anchor: bool = false
var tag: String = ""
var state: int = State.DORMANT
var body_id: int = 0
var mesh: MeshInstance3D
var burning: float = 0.0
var on_fire: bool = false
var wet: float = 0.0
var fire_time: float = 0.0          # how long it has been burning (powder kegs explode after 2 s)
var fire_slot: int = -1
var kick: Vector3 = Vector3.ZERO    # pending velocity applied at release (from explosions)
var stamp: int = 0                  # BFS visit stamp
var sup_depth: int = 0              # how many sideways / hanging links away from a part that really stands on something
var _top: float = 0.0               # cached world-space top / bottom (support check)
var _bot: float = 0.0
var born: float = 0.0
var prop_kind: String = ""          # set for props (barrel_beer, crate, ...)
var charred: float = 0.0
var mesh_shared: bool = true
var subs: Array[PartDef] = []       # compound sub-shapes
var bounce_override: float = -1.0

func _init() -> void:
	pass

static func volume_of(shape_name: String, size: Vector3) -> float:
	match shape_name:
		"compound":
			return size.x * size.y * size.z * 0.35
		"cyl":
			var r: float = size.x * 0.5
			return PI * r * r * size.y
		"sphere":
			var r2: float = size.x * 0.5
			return 4.0 / 3.0 * PI * r2 * r2 * r2
		"frustum":
			var rb: float = size.x * 0.5
			var rt: float = size.z * 0.5
			return PI * size.y / 3.0 * (rb * rb + rb * rt + rt * rt)
		_:
			return size.x * size.y * size.z

func setup(mat_name: String, shp: String, sz: Vector3, transform_: Transform3D, col: Color, d: PartDef = null) -> void:
	mat_id = mat_name
	mat = Materials.get_def(mat_name)
	shape = shp
	size = sz
	xf = transform_
	color = col
	volume = maxf(volume_of(shp, sz), 0.0005)
	size_factor = pow(volume, 1.0 / 3.0) / 0.3
	max_hp = maxf(10.0, mat.hp_per_m3 * volume)
	hp = max_hp
	mass = maxf(mat.density * volume, 0.3)
	if d != null:
		subs = d.subs
		if d.mass_override > 0.0:
			mass = d.mass_override
		if d.hp_override > 0.0:
			max_hp = d.hp_override
			hp = max_hp
		if d.restitution_override >= 0.0:
			bounce_override = d.restitution_override
		if shp == "compound":
			var v: float = 0.0
			for sp in d.subs:
				v += volume_of(sp.shape, sp.size)
			volume = maxf(v, 0.0005)
			size_factor = pow(volume, 1.0 / 3.0) / 0.3
			if d.hp_override <= 0.0:
				max_hp = maxf(10.0, mat.hp_per_m3 * volume)
				hp = max_hp
			if d.mass_override <= 0.0:
				mass = maxf(mat.density * volume, 0.3)

func pos() -> Vector3:
	return xf.origin

## Approximate bounding radius (for damage distance)
func radius() -> float:
	match shape:
		"compound":
			return size.length() * 0.4
		"sphere":
			return size.x * 0.5
		"cyl", "frustum":
			return maxf(size.x, size.z) * 0.5 + size.y * 0.25
		_:
			return size.length() * 0.35

func is_flammable() -> bool:
	return mat.flammability > 0.0

func alive() -> bool:
	return state != State.DEAD

func world_aabb() -> AABB:
	var h: Vector3 = size * 0.5
	if shape == "cyl" or shape == "frustum":
		h = Vector3(maxf(size.x, size.z) * 0.5, size.y * 0.5, maxf(size.x, size.z) * 0.5)
	elif shape == "sphere":
		h = Vector3(size.x, size.x, size.x) * 0.5
	var b: Basis = xf.basis
	var ex: float = absf(b.x.x) * h.x + absf(b.y.x) * h.y + absf(b.z.x) * h.z
	var ey: float = absf(b.x.y) * h.x + absf(b.y.y) * h.y + absf(b.z.y) * h.z
	var ez: float = absf(b.x.z) * h.x + absf(b.y.z) * h.y + absf(b.z.z) * h.z
	return AABB(xf.origin - Vector3(ex, ey, ez), Vector3(ex, ey, ez) * 2.0)
