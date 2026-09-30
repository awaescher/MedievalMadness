class_name MeshGen
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Procedural mesh generation. All meshes carry COLOR and CUSTOM0 (= pre-scaled outline
## offset per vertex, see outline.gdshader). Box/cylinder/sphere primitives + a buffer that
## merges many primitives into one ArrayMesh (used for dormant structures, settlers etc.).

const THIN_LIMIT := 0.15
const OUTLINE_W := 0.03
const OUTLINE_W_THIN := 0.015

class Buf extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var o := PackedFloat32Array()
	var idx := PackedInt32Array()
	var srgb: bool = true     # incoming colors are sRGB hex values -> stored linear

	func vert(p: Vector3, nrm: Vector3, col: Color, off: Vector3) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col.srgb_to_linear() if srgb else col)
		o.append(off.x)
		o.append(off.y)
		o.append(off.z)
		return v.size() - 1

	## Adds a triangle; winding is fixed up so the front face matches the normal `fn` (Godot: clockwise front).
	func tri(a: int, b: int, cc: int, fn: Vector3) -> void:
		var cr: Vector3 = (v[b] - v[a]).cross(v[cc] - v[a])
		if cr.dot(fn) > 0.0:
			idx.append(a)
			idx.append(cc)
			idx.append(b)
		else:
			idx.append(a)
			idx.append(b)
			idx.append(cc)

	func quad(a: int, b: int, cc: int, d: int, fn: Vector3) -> void:
		tri(a, b, cc, fn)
		tri(a, cc, d, fn)

	func is_empty() -> bool:
		return idx.is_empty()

	func to_mesh(existing: ArrayMesh = null) -> ArrayMesh:
		var mesh: ArrayMesh = existing if existing != null else ArrayMesh.new()
		if idx.is_empty():
			return mesh
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_CUSTOM0] = o
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return mesh

static var _box_cache: Dictionary = {}
static var _cyl_cache: Dictionary = {}
static var _sph_cache: Dictionary = {}
static var _frustum_cache: Dictionary = {}

static func outline_width(min_dim: float) -> float:
	return OUTLINE_W_THIN if min_dim < THIN_LIMIT else OUTLINE_W

# ---------------------------------------------------------------- primitives
static func add_box(buf: Buf, size: Vector3, xf: Transform3D, col: Color, ow: float = -1.0) -> void:
	var h: Vector3 = size * 0.5
	var w: float = ow if ow >= 0.0 else outline_width(minf(size.x, minf(size.y, size.z)))
	var b: Basis = xf.basis.orthonormalized()
	# 6 faces: normal, u axis, v axis (all unit local axes)
	var faces: Array = [
		[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var nl: Vector3 = f[0]
		var ul: Vector3 = f[1]
		var vl: Vector3 = f[2]
		var ids: Array[int] = []
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var corner: Vector3 = nl * h + ul * (su as float) * h + vl * (sv as float) * h
				var sgn := Vector3(signf(corner.x), signf(corner.y), signf(corner.z))
				ids.append(buf.vert(xf * corner, b * nl, col, b * (sgn * w)))
		buf.quad(ids[0], ids[1], ids[3], ids[2], b * nl)

## Frustum along Y (r_bottom at -h/2, r_top at +h/2), smooth side normals, optional caps.
static func add_frustum(buf: Buf, r_bottom: float, r_top: float, height: float, segs: int, xf: Transform3D, col: Color, ow: float = -1.0, caps: bool = true) -> void:
	var hh: float = height * 0.5
	var w: float = ow if ow >= 0.0 else outline_width(minf(height, minf(r_bottom, maxf(r_top, 0.001)) * 2.0))
	var b: Basis = xf.basis.orthonormalized()
	var slope: float = (r_bottom - r_top) / maxf(height, 0.0001)
	var side_bot: Array[int] = []
	var side_top: Array[int] = []
	for i in segs + 1:
		var a: float = float(i) / float(segs) * TAU
		var dx: float = cos(a)
		var dz: float = sin(a)
		var nl := Vector3(dx, slope, dz).normalized()
		var off_b := Vector3(dx, -1.0, dz) * w
		var off_t := Vector3(dx, 1.0, dz) * w
		side_bot.append(buf.vert(xf * Vector3(dx * r_bottom, -hh, dz * r_bottom), b * nl, col, b * off_b))
		side_top.append(buf.vert(xf * Vector3(dx * r_top, hh, dz * r_top), b * nl, col, b * off_t))
	for i in segs:
		var nmid: Vector3 = b * Vector3(cos((float(i) + 0.5) / float(segs) * TAU), slope, sin((float(i) + 0.5) / float(segs) * TAU)).normalized()
		buf.tri(side_bot[i], side_bot[i + 1], side_top[i + 1], nmid)
		if r_top > 0.0005:
			buf.tri(side_bot[i], side_top[i + 1], side_top[i], nmid)
	if caps:
		for cap in 2:
			var y: float = -hh if cap == 0 else hh
			var r: float = r_bottom if cap == 0 else r_top
			if r < 0.0005:
				continue
			var nl := Vector3(0, -1.0 if cap == 0 else 1.0, 0)
			var center: int = buf.vert(xf * Vector3(0, y, 0), b * nl, col, b * (nl * w))
			var ring: Array[int] = []
			for i in segs + 1:
				var a: float = float(i) / float(segs) * TAU
				var dx: float = cos(a)
				var dz: float = sin(a)
				ring.append(buf.vert(xf * Vector3(dx * r, y, dz * r), b * nl, col, b * (Vector3(dx, nl.y, dz) * w)))
			for i in segs:
				buf.tri(center, ring[i], ring[i + 1], b * nl)

static func add_cyl(buf: Buf, radius: float, height: float, segs: int, xf: Transform3D, col: Color, ow: float = -1.0) -> void:
	add_frustum(buf, radius, radius, height, segs, xf, col, ow, true)

static func add_sphere(buf: Buf, radius: float, xf: Transform3D, col: Color, ow: float = -1.0, rings: int = 8, segs: int = 12) -> void:
	var w: float = ow if ow >= 0.0 else outline_width(radius * 2.0)
	var b: Basis = xf.basis.orthonormalized()
	var grid: Array = []
	for r in rings + 1:
		var phi: float = float(r) / float(rings) * PI
		var row: Array[int] = []
		for s in segs + 1:
			var th: float = float(s) / float(segs) * TAU
			var nl := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			row.append(buf.vert(xf * (nl * radius), b * nl, col, b * (nl * w)))
		grid.append(row)
	for r in rings:
		for s in segs:
			var a: int = (grid[r] as Array[int])[s]
			var bb: int = (grid[r] as Array[int])[s + 1]
			var c: int = (grid[r + 1] as Array[int])[s + 1]
			var d: int = (grid[r + 1] as Array[int])[s]
			var nmid: Vector3 = ((buf.n[a] + buf.n[bb] + buf.n[c] + buf.n[d]) * 0.25).normalized()
			if r == 0:
				buf.tri(a, c, d, nmid)
			elif r == rings - 1:
				buf.tri(a, bb, c, nmid)
			else:
				buf.quad(a, bb, c, d, nmid)

## Ellipsoid helper (sphere scaled non-uniformly, outline offsets scaled the same)
static func add_ellipsoid(buf: Buf, radii: Vector3, xf: Transform3D, col: Color, ow: float = -1.0, rings: int = 8, segs: int = 12) -> void:
	var start: int = buf.v.size()
	add_sphere(buf, 1.0, xf, col, ow if ow >= 0.0 else 0.03, rings, segs)
	for i in range(start, buf.v.size()):
		var local: Vector3 = xf.affine_inverse() * buf.v[i]
		buf.v[i] = xf * (local * radii)
		# normal for ellipsoid: n / radii
		var nn: Vector3 = xf.basis.inverse() * buf.n[i]
		buf.n[i] = (xf.basis * (nn / radii)).normalized()

static func add_tri_prism(buf: Buf, size: Vector3, xf: Transform3D, col: Color, ow: float = -1.0) -> void:
	## Gable prism: triangular cross-section in XY (base width size.x, height size.y), extruded along Z.
	var w: float = ow if ow >= 0.0 else 0.03
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	var b: Basis = xf.basis.orthonormalized()
	var p := [Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(0, hy, -hz), Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(0, hy, hz)]
	var sl: Vector3 = Vector3(size.y, size.x * 0.5, 0.0).normalized()
	var sr := Vector3(-sl.x, sl.y, 0.0)
	var faces: Array = [
		[[0, 1, 2], Vector3(0, 0, -1)],
		[[3, 5, 4], Vector3(0, 0, 1)],
		[[0, 3, 4, 1], Vector3(0, -1, 0)],
		[[0, 2, 5, 3], Vector3(-sl.x, sl.y, 0.0).normalized()],
		[[1, 4, 5, 2], sr.normalized()],
	]
	for f in faces:
		var ids: Array[int] = []
		var nl: Vector3 = f[1]
		for pi in (f[0] as Array):
			var pv: Vector3 = p[int(pi)]
			var sgn := Vector3(signf(pv.x), signf(pv.y), signf(pv.z))
			ids.append(buf.vert(xf * pv, b * nl, col, b * (sgn * w)))
		if ids.size() == 3:
			buf.tri(ids[0], ids[1], ids[2], b * nl)
		else:
			buf.quad(ids[0], ids[1], ids[2], ids[3], b * nl)

# ---------------------------------------------------------------- cached meshes (white vertex color)
static func box_mesh(size: Vector3) -> ArrayMesh:
	var key: String = "%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if _box_cache.has(key):
		return _box_cache[key] as ArrayMesh
	var buf := Buf.new()
	add_box(buf, size, Transform3D.IDENTITY, Color.WHITE)
	var m: ArrayMesh = buf.to_mesh()
	_box_cache[key] = m
	return m

static func cyl_mesh(radius: float, height: float, segs: int = 12) -> ArrayMesh:
	var key: String = "%.3f,%.3f,%d" % [radius, height, segs]
	if _cyl_cache.has(key):
		return _cyl_cache[key] as ArrayMesh
	var buf := Buf.new()
	add_cyl(buf, radius, height, segs, Transform3D.IDENTITY, Color.WHITE)
	var m: ArrayMesh = buf.to_mesh()
	_cyl_cache[key] = m
	return m

static func frustum_mesh(r_bottom: float, r_top: float, height: float, segs: int = 12) -> ArrayMesh:
	var key: String = "%.3f,%.3f,%.3f,%d" % [r_bottom, r_top, height, segs]
	if _frustum_cache.has(key):
		return _frustum_cache[key] as ArrayMesh
	var buf := Buf.new()
	add_frustum(buf, r_bottom, r_top, height, segs, Transform3D.IDENTITY, Color.WHITE)
	var m: ArrayMesh = buf.to_mesh()
	_frustum_cache[key] = m
	return m

static func sphere_mesh(radius: float, rings: int = 8, segs: int = 12) -> ArrayMesh:
	var key: String = "%.3f,%d,%d" % [radius, rings, segs]
	if _sph_cache.has(key):
		return _sph_cache[key] as ArrayMesh
	var buf := Buf.new()
	add_sphere(buf, radius, Transform3D.IDENTITY, Color.WHITE, -1.0, rings, segs)
	var m: ArrayMesh = buf.to_mesh()
	_sph_cache[key] = m
	return m

static func clear_caches() -> void:
	_box_cache.clear()
	_cyl_cache.clear()
	_sph_cache.clear()
	_frustum_cache.clear()

## Flat unlit-friendly quad mesh facing +Z (used by billboards, rings).
static func ring_mesh(inner: float, outer: float, segs: int = 32) -> ArrayMesh:
	var buf := Buf.new()
	for i in segs:
		var a0: float = float(i) / float(segs) * TAU
		var a1: float = float(i + 1) / float(segs) * TAU
		var p0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var p1 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var p2 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		var p3 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var up := Vector3.UP
		var i0: int = buf.vert(p0, up, Color.WHITE, Vector3.ZERO)
		var i1: int = buf.vert(p1, up, Color.WHITE, Vector3.ZERO)
		var i2: int = buf.vert(p2, up, Color.WHITE, Vector3.ZERO)
		var i3: int = buf.vert(p3, up, Color.WHITE, Vector3.ZERO)
		buf.quad(i0, i1, i2, i3, up)
	return buf.to_mesh()

static func disc_mesh(radius: float, segs: int = 24) -> ArrayMesh:
	var buf := Buf.new()
	var up := Vector3.UP
	var c: int = buf.vert(Vector3.ZERO, up, Color.WHITE, Vector3.ZERO)
	var ring: Array[int] = []
	for i in segs + 1:
		var a: float = float(i) / float(segs) * TAU
		ring.append(buf.vert(Vector3(cos(a) * radius, 0, sin(a) * radius), up, Color.WHITE, Vector3.ZERO))
	for i in segs:
		buf.tri(c, ring[i], ring[i + 1], up)
	return buf.to_mesh()
