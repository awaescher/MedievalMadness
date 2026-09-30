class_name Powder
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Black powder (spec 6.4 "Black Powder Kegs"): small kegs roll through a village and leave irregular heaps of powder on
## the ground and smeared on building parts. The powder lies there - also in later turns - until something sets it
## alight; then it goes up in violent flash flames (about 5x the strength of normal fire, but only for a moment) that run
## along the trail in a blink and burn black marks into the ground.

const CELL := 3.0
const MAX_DUST := 520
const FLASH_DAMAGE := 150.0        # area damage of one flash (normal fire: ~15 hp/s on a wood part)

class Dust extends RefCounted:
	var pos: Vector3
	var amount: float = 1.0
	var source: Dictionary = {}
	var part: Part = null           # smeared on a building part (follows it)
	var lit: bool = false
	var delay: float = 0.0

static var dust: Array[Dust] = []
static var grid: Dictionary = {}    # Vector2i -> Array[Dust]
static var mm_node: MultiMeshInstance3D
static var _mm: MultiMesh
static var _dirty: bool = true
static var suppress: bool = false   # set while a flash ignites its surroundings (no feedback loop)
static var rng: Rng = Rng.new(57)
static var _lit_count: int = 0

static func attach(root: Node3D) -> void:
	if mm_node != null and is_instance_valid(mm_node):
		return
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.55
	cyl.height = 0.05
	cyl.radial_segments = 7
	cyl.rings = 1
	_mm.mesh = cyl
	_mm.instance_count = MAX_DUST
	_mm.visible_instance_count = 0
	mm_node = MultiMeshInstance3D.new()
	mm_node.name = "PowderDust"
	mm_node.multimesh = _mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11, 0.1, 0.1)
	m.roughness = 1.0
	mm_node.material_override = m
	mm_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm_node.extra_cull_margin = 400.0
	root.add_child(mm_node)

static func reset() -> void:
	dust.clear()
	grid.clear()
	_dirty = true
	_lit_count = 0
	if _mm != null:
		_mm.visible_instance_count = 0

static func active() -> bool:
	return _lit_count > 0

static func count() -> int:
	return dust.size()

static func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

static func _add(d: Dust) -> void:
	if dust.size() >= MAX_DUST:
		_remove(dust[0])
	dust.append(d)
	var k: Vector2i = _key(d.pos)
	if not grid.has(k):
		grid[k] = []
	(grid[k] as Array).append(d)
	_dirty = true

static func _remove(d: Dust) -> void:
	dust.erase(d)
	var k: Vector2i = _key(d.pos)
	if grid.has(k):
		(grid[k] as Array).erase(d)
		if (grid[k] as Array).is_empty():
			grid.erase(k)
	_dirty = true

## A heap of powder on the ground
static func drop(pos: Vector3, source: Dictionary, amount: float = 1.0) -> void:
	var p := Vector3(pos.x, Terrain.h(pos.x, pos.z), pos.z)
	if Terrain.is_water(p.x, p.z):
		return
	for d in _near(p, 0.6):
		if d.part == null and not d.lit:
			d.amount = minf(d.amount + amount * 0.5, 3.0)
			return
	var nd := Dust.new()
	nd.pos = p
	nd.amount = amount
	nd.source = source
	_add(nd)

## Powder smeared on the building parts within `radius` of `pos`
static func stain(pos: Vector3, radius: float, source: Dictionary) -> void:
	var box := AABB(pos - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	var n: int = 0
	for s in Breakable.structures:
		if s.free_parts or not s.aabb.grow(1.0).intersects(box):
			continue
		for p in s.parts:
			if p.state == Part.State.DEAD or (p.xf.origin - pos).length() - p.radius() * 0.5 > radius:
				continue
			if rng.chance(0.55):
				continue
			var nd := Dust.new()
			nd.pos = p.xf.origin
			nd.part = p
			nd.source = source
			_add(nd)
			if p.mesh != null:
				p.mesh.set_instance_shader_parameter("tint", p.color.lerp(Color(0.1, 0.1, 0.1), 0.55))
			n += 1
			if n >= 14:
				return

static func _near(pos: Vector3, r: float) -> Array[Dust]:
	var out: Array[Dust] = []
	var k0: Vector2i = _key(pos - Vector3(r, 0, r))
	var k1: Vector2i = _key(pos + Vector3(r, 0, r))
	var r2: float = r * r
	for x in range(k0.x, k1.x + 1):
		for z in range(k0.y, k1.y + 1):
			var k := Vector2i(x, z)
			if grid.has(k):
				for d in (grid[k] as Array):
					var dd: Dust = d as Dust
					var dp: Vector3 = dd.part.xf.origin if dd.part != null else dd.pos
					if (dp - pos).length_squared() <= r2:
						out.append(dd)
	return out

## Something burns here: every heap of powder within `radius` catches (with a tiny delay, so the flames run along the trail)
static func ignite(pos: Vector3, radius: float, source: Dictionary = {}) -> int:
	if suppress or dust.is_empty():
		return 0
	var n: int = 0
	for d in _near(pos, radius):
		if d.lit:
			continue
		d.lit = true
		d.delay = rng.range_f(0.04, 0.16) + Util.dist_xz(d.pos, pos) * 0.03
		if not source.is_empty():
			d.source = source
		_lit_count += 1
		n += 1
	return n

static func tick(dt: float) -> void:
	if _lit_count > 0:
		var fire_now: Array[Dust] = []
		for d in dust:
			if d.lit:
				d.delay -= dt
				if d.delay <= 0.0:
					fire_now.append(d)
		for d2 in fire_now:
			_flash(d2)
	if _dirty and _mm != null:
		_refresh_mm()

static func _flash(d: Dust) -> void:
	var pos: Vector3 = d.part.xf.origin if d.part != null and d.part.state != Part.State.DEAD else d.pos
	var src: Dictionary = d.source
	_lit_count = maxi(_lit_count - 1, 0)
	_remove(d)
	var big: float = clampf(d.amount, 0.7, 2.2)
	Fx.burst("flame", pos + Vector3.UP * 0.4, Color(0, 0, 0, -1), 1.5 * big, Vector3.UP)
	if rng.chance(0.5):
		Fx.burst("spark", pos + Vector3.UP * 0.3, Color(0, 0, 0, -1), 0.8, Vector3.UP)
	if rng.chance(0.3):
		Sfx.play("fwump", pos, 0.8, 1)
	# the flames run on along the trail
	suppress = true
	Damage.damage_in_radius(pos, 2.3, FLASH_DAMAGE * big, src, "linear", 0.25)
	Damage.damage_settlers_in_radius(pos, 2.5, 34.0 * big, src, Vector3.UP, 0.5)
	Fire.ignite_in_radius(pos, 2.4, 1.0, src, true)
	for st in Settler.all:
		if st.state != Settler.State.DEAD and st.state != Settler.State.GONE and (st.global_pos() + Vector3.UP - pos).length() < 2.0:
			st.ignite()
	for pl in Game.players:
		for c in pl.catapults:
			if is_instance_valid(c) and not (c as Catapult).destroyed and (c as Catapult).global_pos().distance_to(pos) < 2.4:
				(c as Catapult).ignite()
	suppress = false
	if Terrain.current != null:
		Terrain.current.paint(pos, 1.7, 0.0, 0.95)
	ignite(pos, 2.8, src)

static func _refresh_mm() -> void:
	_dirty = false
	var n: int = mini(dust.size(), MAX_DUST)
	_mm.visible_instance_count = n
	for i in n:
		var d: Dust = dust[i]
		var p: Vector3 = d.part.xf.origin if d.part != null else d.pos
		var sc: float = clampf(0.6 + d.amount * 0.35, 0.6, 1.5)
		if d.part != null:
			sc = 0.0          # smeared on a part: the tinted part shows it, no floating disk
		var b := Basis(Vector3.UP, float(i) * 1.7).scaled(Vector3(sc, 1.0, sc * 0.8))
		_mm.set_instance_transform(i, Transform3D(b, p + Vector3(0, 0.04, 0)))
