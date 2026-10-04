class_name CowMesh
extends RefCounted
## The cow model (village cow and the flying Moo-nition): rounded body, spots, udder, tail, and a head with muzzle, horns, ears.
## Local space: +Z forward, +Y up, hooves at y = 0, body centre at y = 1. `root` places / rotates the whole animal.

const WHITE := Color("#f4f1e8")
const BLACK := Color("#2b2b33")
const PINK := Color("#f2b6b6")
const HORN := Color("#e8dcb0")

static func _e(buf: MeshGen.Buf, root: Transform3D, radii: Vector3, pos: Vector3, col: Color, ow: float = 0.02, basis: Basis = Basis()) -> void:
	MeshGen.add_ellipsoid(buf, radii, root * Transform3D(basis, pos), col, ow, 6, 10)

## Body ellipsoids (centre, radii) a spot can sit on; the spot is projected onto the outermost one along `dir`
const _SKIN := [
	[Vector3(0, 1.0, 0), Vector3(0.5, 0.48, 0.88)],
	[Vector3(0, 1.06, 0.55), Vector3(0.44, 0.46, 0.4)],
	[Vector3(0, 1.04, -0.55), Vector3(0.45, 0.45, 0.4)],
]

## A thin disc on the body surface in direction `dir` (seen from the body centre), `size` = its two radii.
## Its middle sits just above the skin and its rim dips into the body, so it reads as paint, not as a bump.
static func _spot(buf: MeshGen.Buf, root: Transform3D, dir: Vector3, size: Vector2) -> void:
	var o := Vector3(0, 1.0, 0)
	var d := dir.normalized()
	var best_t := 0.0
	var normal := d
	for sk in _SKIN:
		var c: Vector3 = sk[0]
		var r: Vector3 = sk[1]
		var po := (o - c) / r
		var pd := d / r
		var a := pd.dot(pd)
		var b := 2.0 * po.dot(pd)
		var k := po.dot(po) - 1.0
		var disc := b * b - 4.0 * a * k
		if disc < 0.0:
			continue
		var t := (-b + sqrt(disc)) / (2.0 * a)
		if t > best_t:
			best_t = t
			var hit := (o + d * t - c) / (r * r)
			normal = hit.normalized()
	var thick := 0.05
	var pos := o + d * best_t + normal * (0.012 - thick)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(-normal, up)
	MeshGen.add_ellipsoid(buf, Vector3(size.x, size.y, thick), root * Transform3D(basis, pos), BLACK, 0.004, 8, 14)

static func body(buf: MeshGen.Buf, root: Transform3D) -> void:
	# barrel, shoulders, rump, a soft neck into the head
	_e(buf, root, Vector3(0.5, 0.48, 0.88), Vector3(0, 1.0, 0), WHITE, 0.03)
	_e(buf, root, Vector3(0.44, 0.46, 0.4), Vector3(0, 1.06, 0.55), WHITE, 0.02)
	_e(buf, root, Vector3(0.45, 0.45, 0.4), Vector3(0, 1.04, -0.55), WHITE, 0.02)
	_e(buf, root, Vector3(0.27, 0.3, 0.34), Vector3(0, 1.2, 0.95), WHITE, 0.02, Basis(Vector3.RIGHT, -0.5))
	# black spots: thin discs lying on the skin, tilted to the surface normal so they do not stick out
	_spot(buf, root, Vector3(0.45, 0.1, -0.2), Vector2(0.3, 0.22))
	_spot(buf, root, Vector3(-0.46, 0.02, 0.3), Vector2(0.22, 0.2))
	_spot(buf, root, Vector3(0.12, 0.46, 0.1), Vector2(0.3, 0.3))
	_spot(buf, root, Vector3(-0.25, 0.4, -0.5), Vector2(0.2, 0.2))
	_spot(buf, root, Vector3(0.43, 0.12, 0.6), Vector2(0.2, 0.17))
	# legs (tapered) with dark hooves
	for lx in [-0.27, 0.27]:
		for lz in [-0.55, 0.55]:
			MeshGen.add_frustum(buf, 0.07, 0.11, 0.62, 7, root * Transform3D(Basis(), Vector3(float(lx), 0.36, float(lz))), WHITE, 0.012)
			MeshGen.add_frustum(buf, 0.1, 0.075, 0.1, 7, root * Transform3D(Basis(), Vector3(float(lx), 0.05, float(lz))), BLACK, 0.008)
	# udder with teats, belly line
	_e(buf, root, Vector3(0.17, 0.14, 0.2), Vector3(0, 0.62, -0.42), PINK, 0.012)
	for tx in [-0.06, 0.06]:
		for tz in [-0.5, -0.34]:
			MeshGen.add_cyl(buf, 0.022, 0.09, 5, root * Transform3D(Basis(), Vector3(float(tx), 0.5, float(tz))), PINK, 0.006)
	# tail with a dark tuft
	MeshGen.add_cyl(buf, 0.022, 0.78, 5, root * Transform3D(Basis(), Vector3(0, 0.98, -0.99)), WHITE, 0.006)
	_e(buf, root, Vector3(0.07, 0.15, 0.07), Vector3(0, 0.55, -0.99), BLACK, 0.006)

## The head is a separate mesh (it is a second body in the ragdoll); its origin is the middle of the skull
static func head(buf: MeshGen.Buf, root: Transform3D) -> void:
	_e(buf, root, Vector3(0.23, 0.26, 0.28), Vector3.ZERO, WHITE, 0.02)
	_e(buf, root, Vector3(0.19, 0.15, 0.17), Vector3(0, -0.12, 0.27), PINK, 0.015)
	for nx in [-0.07, 0.07]:
		_e(buf, root, Vector3(0.03, 0.025, 0.02), Vector3(float(nx), -0.1, 0.42), BLACK, 0.004)
	# eyes with a dark patch around one of them
	_e(buf, root, Vector3(0.09, 0.11, 0.1), Vector3(0.16, 0.08, 0.1), BLACK, 0.006)
	for ex in [-0.19, 0.19]:
		_e(buf, root, Vector3(0.035, 0.045, 0.04), Vector3(float(ex), 0.1, 0.16), Color("#15151a"), 0.004)
		_e(buf, root, Vector3(0.012, 0.015, 0.012), Vector3(float(ex) * 1.03, 0.12, 0.19), Color("#ffffff"), 0.0)
	# ears (one black) and short curved horns
	_e(buf, root, Vector3(0.17, 0.05, 0.09), Vector3(0.3, 0.1, -0.06), WHITE, 0.01, Basis(Vector3.BACK, 0.35))
	_e(buf, root, Vector3(0.17, 0.05, 0.09), Vector3(-0.3, 0.1, -0.06), BLACK, 0.01, Basis(Vector3.BACK, -0.35))
	for hx in [-1.0, 1.0]:
		MeshGen.add_frustum(buf, 0.045, 0.015, 0.24, 6, root * Transform3D(Basis(Vector3.BACK, -0.75 * float(hx)), Vector3(0.18 * float(hx), 0.3, -0.02)), HORN, 0.008)
	# a little tuft between the horns
	_e(buf, root, Vector3(0.1, 0.05, 0.08), Vector3(0, 0.27, 0.04), Color("#e0dccd"), 0.008)
