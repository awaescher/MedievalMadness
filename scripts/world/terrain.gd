class_name Terrain
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Heightmap terrain: chunked ArrayMesh with vertex colors + one HeightMapShape3D collider
## (server body, scaled by cell size). Supports throttled crater deformation (spec 7.6).

const CHUNK_CELLS := 24
const GRASS_A := Color("#7ec850")
const GRASS_B := Color("#5aa53c")
const SAND := Color("#e8d8a0")
const ROCK := Color("#8a8a8a")
const DIRT := Color("#b98a5a")

static var current: Terrain

var data: MapData
## Set by the game world: called with an AABB whenever the ground under buildings may have changed (keeps Terrain free of game dependencies)
static var ground_hook: Callable = Callable()
static var wake_hook: Callable = Callable()          # called with an AABB after the collider changed: wake what lies there
var _wake_box: AABB = AABB()
var _wake_has: bool = false
var change_box: AABB = AABB()          # everything changed since the last sweep (merged)
var change_has: bool = false
var change_stamp: int = 0              # counts every change of the soil (Breakable sweeps for things left hanging in the air)
var dirt: PackedFloat32Array = PackedFloat32Array()
var scorch: PackedFloat32Array = PackedFloat32Array()
var chunks: Dictionary = {}          # Vector2i -> MeshInstance3D
var _dirty_chunks: Dictionary = {}
var _collider_dirty: bool = false
var _flush_timer: float = 0.0
var _shape: HeightMapShape3D
var _body: RID
var water_root: Node3D
var water_inner: MeshInstance3D
var water_outer: MeshInstance3D
var seabed: MeshInstance3D
var water_y: float = Cfg.WATER_LEVEL
var _water_mat_inner: ShaderMaterial
var _water_mat_outer: ShaderMaterial

func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	if current == self:
		current = null

func build(map: MapData) -> void:
	data = map
	current = self
	dirt.resize(map.n * map.n)
	dirt.fill(0.0)
	scorch.resize(map.n * map.n)
	scorch.fill(0.0)
	var cn: int = ceili(float(map.n - 1) / float(CHUNK_CELLS))
	for cz in cn:
		for cx in cn:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.material_override = Toon.terrain()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			chunks[Vector2i(cx, cz)] = mi
			_rebuild_chunk(cx, cz)
	_build_collider()
	_build_water()

# ------------------------------------------------------------ sampling
static func h(x: float, z: float) -> float:
	if current == null or current.data == null:
		return 0.0
	return current.data.height_at(x, z)

static func normal(x: float, z: float) -> Vector3:
	if current == null or current.data == null:
		return Vector3.UP
	return current.data.normal_at(x, z)

static func slope_deg(x: float, z: float) -> float:
	if current == null or current.data == null:
		return 0.0
	return current.data.slope_deg_at(x, z)

static func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, h(p.x, p.z), p.z)

## Ray vs heightfield (marching + bisection). Returns Vector3.INF when nothing is hit.
static func pick(origin: Vector3, dir: Vector3, max_dist: float = 600.0) -> Vector3:
	if current == null or current.data == null:
		return Vector3.INF
	var t: float = 0.0
	var step: float = 1.5
	var prev_t: float = 0.0
	var d: Vector3 = dir.normalized()
	while t < max_dist:
		var p: Vector3 = origin + d * t
		if p.y <= h(p.x, p.z):
			# refine between prev_t and t
			var lo: float = prev_t
			var hi: float = t
			for i in 14:
				var mid: float = (lo + hi) * 0.5
				var pm: Vector3 = origin + d * mid
				if pm.y <= h(pm.x, pm.z):
					hi = mid
				else:
					lo = mid
			var hit: Vector3 = origin + d * hi
			return Vector3(hit.x, h(hit.x, hit.z), hit.z)
		prev_t = t
		t += step
		if t > 60.0:
			step = 3.0
	return Vector3.INF

static func is_water(x: float, z: float) -> bool:
	return h(x, z) < (current.water_y if current != null else Cfg.WATER_LEVEL)

# ------------------------------------------------------------ mesh
func _vertex_color(ix: int, iz: int) -> Color:
	var n: int = data.n
	var i: int = iz * n + ix
	var ht: float = data.heights[i]
	var x: float = data.origin + float(ix) * data.cell
	var z: float = data.origin + float(iz) * data.cell
	var hx: float = data.heights[iz * n + mini(ix + 1, n - 1)] - data.heights[iz * n + maxi(ix - 1, 0)]
	var hz: float = data.heights[mini(iz + 1, n - 1) * n + ix] - data.heights[maxi(iz - 1, 0) * n + ix]
	var ny: float = Vector3(-hx, 2.0 * data.cell, -hz).normalized().y
	var t: float = VNoise.fbm(x, z, data.seed_int & 0xFFFF, 3, 1.0 / 9.0)
	var col: Color = GRASS_A.lerp(GRASS_B, clampf(t * 1.4 - 0.2, 0.0, 1.0))
	var rel: float = ht - Cfg.WATER_LEVEL
	if rel < 0.9:
		col = col.lerp(SAND, Util.smooth01((0.9 - rel) / 0.6))
	if rel < -0.2:
		col = col.lerp(Color("#b8a878"), clampf(-rel * 0.4, 0.0, 0.7))
	var slope: float = 1.0 - ny
	col = col.lerp(ROCK, Util.smooth01((slope - 0.16) / 0.2))
	var dv: float = dirt[i]
	if dv > 0.0:
		col = col.lerp(DIRT, clampf(dv, 0.0, 1.0))
	var sc: float = scorch[i]
	if sc > 0.0:
		col = col.lerp(Color(0.12, 0.09, 0.08), clampf(sc, 0.0, 0.85))
	return col.srgb_to_linear()

func _rebuild_chunk(cx: int, cz: int) -> void:
	var n: int = data.n
	var x0: int = cx * CHUNK_CELLS
	var z0: int = cz * CHUNK_CELLS
	var x1: int = mini(x0 + CHUNK_CELLS, n - 1)
	var z1: int = mini(z0 + CHUNK_CELLS, n - 1)
	var w: int = x1 - x0 + 1
	var dd: int = z1 - z0 + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	verts.resize(w * dd)
	norms.resize(w * dd)
	cols.resize(w * dd)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var li: int = (iz - z0) * w + (ix - x0)
			var hh: float = data.heights[iz * n + ix]
			verts[li] = Vector3(data.origin + float(ix) * data.cell, hh, data.origin + float(iz) * data.cell)
			var hx: float = data.heights[iz * n + mini(ix + 1, n - 1)] - data.heights[iz * n + maxi(ix - 1, 0)]
			var hz: float = data.heights[mini(iz + 1, n - 1) * n + ix] - data.heights[maxi(iz - 1, 0) * n + ix]
			var span_x: float = float(mini(ix + 1, n - 1) - maxi(ix - 1, 0)) * data.cell
			var span_z: float = float(mini(iz + 1, n - 1) - maxi(iz - 1, 0)) * data.cell
			norms[li] = Vector3(-hx / span_x, 1.0, -hz / span_z).normalized()
			cols[li] = _vertex_color(ix, iz)
	for iz in range(dd - 1):
		for ix in range(w - 1):
			var a: int = iz * w + ix
			var b: int = a + 1
			var c: int = a + w
			var d: int = c + 1
			# clockwise front faces (Godot), seen from above (+Y): a -> b -> c is CW when x right, z toward viewer
			idxs.append(a)
			idxs.append(b)
			idxs.append(c)
			idxs.append(b)
			idxs.append(d)
			idxs.append(c)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi: MeshInstance3D = chunks[Vector2i(cx, cz)] as MeshInstance3D
	mi.mesh = mesh

func _build_collider() -> void:
	_shape = HeightMapShape3D.new()
	_shape.map_width = data.n
	_shape.map_depth = data.n
	_shape.map_data = data.heights
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_add_shape(_body, _shape.get_rid(), Transform3D(Basis.from_scale(Vector3(data.cell, 1.0, data.cell)), Vector3.ZERO))
	PhysicsServer3D.body_set_collision_layer(_body, Cfg.LAYER_TERRAIN)
	PhysicsServer3D.body_set_collision_mask(_body, 0)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
	PhysicsServer3D.body_set_param(_body, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.05)

func terrain_body() -> RID:
	return _body

# ------------------------------------------------------------ water
func _build_water() -> void:
	water_root = Node3D.new()
	water_root.name = "Water"
	add_child(water_root)
	var shader: Shader = load("res://scripts/render/shaders/water.gdshader") as Shader
	_water_mat_inner = ShaderMaterial.new()
	_water_mat_inner.shader = shader
	_water_mat_outer = ShaderMaterial.new()
	_water_mat_outer.shader = shader
	_water_mat_outer.set_shader_parameter("wave_height", 0.0)
	_water_mat_outer.set_shader_parameter("crest_strength", 0.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(data.side + 24.0, data.side + 24.0)
	pm.subdivide_width = int((data.side + 24.0) / 3.0)
	pm.subdivide_depth = int((data.side + 24.0) / 3.0)
	water_inner = MeshInstance3D.new()
	water_inner.mesh = pm
	water_inner.material_override = _water_mat_inner
	water_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_inner.position.y = water_y
	water_root.add_child(water_inner)
	var big := PlaneMesh.new()
	big.size = Vector2(6000.0, 6000.0)
	water_outer = MeshInstance3D.new()
	water_outer.mesh = big
	water_outer.material_override = _water_mat_outer
	water_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_outer.position.y = water_y - 0.02
	water_root.add_child(water_outer)
	# deep seabed far below so the outer sea reads as deep blue
	var sb := PlaneMesh.new()
	sb.size = Vector2(6000.0, 6000.0)
	seabed = MeshInstance3D.new()
	seabed.mesh = sb
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#1a5c9a")
	seabed.material_override = mat
	seabed.position.y = -9.0
	seabed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_root.add_child(seabed)

func set_water_level(y: float) -> void:
	water_y = y
	if water_inner != null:
		water_inner.position.y = y
		water_outer.position.y = y - 0.02

# ------------------------------------------------------------ deformation
## Bell-shaped crater. Returns true if the terrain was changed. `depth_k`: depth as a fraction of the radius.
func crater(center: Vector3, radius: float, scorch_amount: float = 0.7, depth_k: float = 0.25) -> bool:
	return dig(center, radius, radius * depth_k, scorch_amount, 0.3)

## Digs a bell-shaped hole of the given radius / depth (metres) and optionally blackens / browns the ground.
func dig(center: Vector3, radius: float, depth: float, scorch_amount: float = 0.0, dirt_amount: float = 0.3, rim: float = 0.0) -> bool:
	if data == null or not data.in_bounds(center.x, center.z):
		return false
	var n: int = data.n
	var reach: float = radius * (1.6 if rim > 0.0 else 1.0)
	var ix0: int = clampi(floori((center.x - reach - data.origin) / data.cell), 0, n - 1)
	var ix1: int = clampi(ceili((center.x + reach - data.origin) / data.cell), 0, n - 1)
	var iz0: int = clampi(floori((center.z - reach - data.origin) / data.cell), 0, n - 1)
	var iz1: int = clampi(ceili((center.z + reach - data.origin) / data.cell), 0, n - 1)
	var changed: bool = false
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var x: float = data.origin + float(ix) * data.cell
			var z: float = data.origin + float(iz) * data.cell
			var d: float = Vector2(x - center.x, z - center.z).length()
			if d >= reach:
				continue
			var i: int = iz * n + ix
			if d >= radius:
				# raised rim of thrown-out soil around the hole
				var rt: float = (d - radius) / (reach - radius)
				data.heights[i] += rim * (1.0 - rt) * (1.0 - rt) * sin(rt * PI) * 2.0
				dirt[i] = clampf(dirt[i] + dirt_amount * 0.6 * (1.0 - rt), 0.0, 1.0)
				changed = true
				continue
			var t: float = d / radius
			var bell: float = (1.0 - t * t)
			bell = bell * bell
			data.heights[i] = maxf(data.heights[i] - depth * bell, -8.0)
			scorch[i] = clampf(scorch[i] + scorch_amount * (1.0 - t), 0.0, 1.0)
			dirt[i] = clampf(dirt[i] + dirt_amount * bell, 0.0, 1.0)
			changed = true
	if changed:
		mark_dirty(ix0 - 1, iz0 - 1, ix1 + 1, iz1 + 1)
		if depth >= 0.5:
			if ground_hook.is_valid():
				ground_hook.call(AABB(Vector3(center.x - reach, -60.0, center.z - reach), Vector3(reach * 2.0, 220.0, reach * 2.0)))
	return changed

## A groove along the path a -> b (a rolling boulder, a plough-through): lots of small dents, browned soil
func furrow(a: Vector3, b: Vector3, width: float, depth: float) -> void:
	var len: float = Util.dist_xz(a, b)
	var steps: int = maxi(int(len / maxf(width * 0.5, 0.3)), 1)
	for i in steps + 1:
		var p: Vector3 = a.lerp(b, float(i) / float(steps))
		dig(p, width, depth * 0.45, 0.0, 0.35)

## Marks a grid rectangle (vertex indices) for mesh rebuild and collider refresh
func mark_dirty(ix0: int, iz0: int, ix1: int, iz1: int) -> void:
	var n: int = data.n
	var cn: int = ceili(float(n - 1) / float(CHUNK_CELLS))
	var cx0: int = clampi(ix0 / CHUNK_CELLS, 0, cn - 1)
	var cx1: int = clampi(ix1 / CHUNK_CELLS, 0, cn - 1)
	var cz0: int = clampi(iz0 / CHUNK_CELLS, 0, cn - 1)
	var cz1: int = clampi(iz1 / CHUNK_CELLS, 0, cn - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			_dirty_chunks[Vector2i(cx, cz)] = true
	_collider_dirty = true
	change_stamp += 1
	var wx0: int = clampi(ix0, 0, n - 1)
	var wz0: int = clampi(iz0, 0, n - 1)
	var bx := AABB(Vector3(data.origin + float(wx0) * data.cell, -100.0, data.origin + float(wz0) * data.cell), Vector3(float(clampi(ix1, 0, n - 1) - wx0 + 1) * data.cell, 400.0, float(clampi(iz1, 0, n - 1) - wz0 + 1) * data.cell))
	_wake_box = bx if not _wake_has else _wake_box.merge(bx)
	change_box = bx if not change_has else change_box.merge(bx)
	change_has = true
	_wake_has = true

## Paint scorch/dirt without changing shape (fire ground marks, footpaths).
func paint(center: Vector3, radius: float, dirt_amt: float, scorch_amt: float) -> void:
	if data == null:
		return
	var n: int = data.n
	var ix0: int = clampi(floori((center.x - radius - data.origin) / data.cell), 0, n - 1)
	var ix1: int = clampi(ceili((center.x + radius - data.origin) / data.cell), 0, n - 1)
	var iz0: int = clampi(floori((center.z - radius - data.origin) / data.cell), 0, n - 1)
	var iz1: int = clampi(ceili((center.z + radius - data.origin) / data.cell), 0, n - 1)
	var cn: int = ceili(float(n - 1) / float(CHUNK_CELLS))
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var x: float = data.origin + float(ix) * data.cell
			var z: float = data.origin + float(iz) * data.cell
			var d: float = Vector2(x - center.x, z - center.z).length()
			if d >= radius:
				continue
			var t: float = 1.0 - d / radius
			var i: int = iz * n + ix
			dirt[i] = clampf(dirt[i] + dirt_amt * t, 0.0, 1.0)
			scorch[i] = clampf(scorch[i] + scorch_amt * t, 0.0, 1.0)
	for cz in range(maxi((iz0 - 1) / CHUNK_CELLS, 0), mini((iz1 + 1) / CHUNK_CELLS, cn - 1) + 1):
		for cx in range(maxi((ix0 - 1) / CHUNK_CELLS, 0), mini((ix1 + 1) / CHUNK_CELLS, cn - 1) + 1):
			_dirty_chunks[Vector2i(cx, cz)] = true

## Paint a dirt path segment (village footpaths)
func paint_path(a: Vector3, b: Vector3, width: float, amount: float = 0.85) -> void:
	var len: float = a.distance_to(b)
	var steps: int = maxi(int(len / (width * 0.6)), 1)
	for i in steps + 1:
		var p: Vector3 = a.lerp(b, float(i) / float(steps))
		paint(p, width, amount, 0.0)

func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer < 0.5:
		return
	_flush_timer = 0.0
	flush()

func flush() -> void:
	if _dirty_chunks.is_empty() and not _collider_dirty:
		return
	for k in _dirty_chunks:
		var c: Vector2i = k as Vector2i
		_rebuild_chunk(c.x, c.y)
	_dirty_chunks.clear()
	if _collider_dirty:
		_shape.map_data = data.heights
		_collider_dirty = false
		# the new ground does not wake sleeping debris by itself: without this it would hang in the air over craters
		if _wake_has and wake_hook.is_valid():
			wake_hook.call(_wake_box)
		_wake_has = false
