class_name Walls
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Stone walls built during the battle as a turn action. They work exactly like the palisade fences (ground click, Q/E
## turns, continues the end of another wall, click on a wall stacks another layer) but a layer is as wide as four
## fences (4 x 3 posts) and 60 % as high as a post. Only the topmost layer carries crenellations. Stored in PlayerData.walls
## as {id, center (ground base), yaw, layers: Array[Structure]}.

const WIDTH := Posts.SPACING * float(Posts.FENCE_POSTS) * 4.0   # four palisade fences side by side
const LAYER_H := Posts.POST_H * 0.6
const THICK := 1.0
const MAX_LAYERS := 6
const MAX_PER_PLAYER := 14                                      # layers in total, keeps the physics cheap
const STONE := Color("#8a9096")                                  # same grey as the castle ruin

## A layer only holds up what stands on it: broken or released blocks drop the blocks above them
class LayerBehavior extends Specials.Behavior:
	var above: Structure = null
	func _drop_above(p: Part) -> void:
		if above == null or above.parts.is_empty():
			return
		var up: Structure = above
		Breakable.awaken(up)
		var reach: float = p.size.x * 0.5 + 0.9
		for q in up.parts:
			if q.state == Part.State.FROZEN and Util.dist_xz(q.xf.origin, p.xf.origin) < reach:
				Breakable.release_part(q, Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5)))
		up.support_dirty = true
		up.support_timer = 0.0
	func on_part_break(_s: Structure, p: Part) -> void:
		_drop_above(p)
	func on_release(_s: Structure, p: Part) -> void:
		_drop_above(p)

static func axis(yaw: float) -> Vector3:
	return Posts.axis(yaw)

static func layer_count(w: Dictionary) -> int:
	return (w["layers"] as Array).size()

static func total_layers(p: PlayerData) -> int:
	var n: int = 0
	for w in p.walls:
		n += layer_count(w as Dictionary)
	return n

static func top_y(w: Dictionary) -> float:
	return (w["center"] as Vector3).y + LAYER_H * float(layer_count(w))

static func can_stack(w: Dictionary) -> bool:
	return not w.is_empty() and layer_count(w) < MAX_LAYERS

static func _samples(center: Vector3, yaw: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a: Vector3 = axis(yaw)
	for i in 9:
		var v: Vector3 = center + a * (WIDTH * (float(i) / 8.0 - 0.5))
		v.y = Terrain.h(v.x, v.z)
		out.append(v)
	return out

## Does the ground footprint of the wall touch anything solid? (own walls are handled by `_overlaps_wall`)
static func _blocked(pos: Vector3, h: float) -> bool:
	var blocked: bool = false
	for dy in [0.9, 2.4]:
		PhysWorld.overlap_sphere(Vector3(pos.x, h + float(dy), pos.z), 0.55, func(pb: PhysWorld.PBody, _s: int, _r: RID) -> void:
			if pb != null and pb.kind != "projectile":
				blocked = true, Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_CATAPULT)
	return blocked

static func _rect_axes(yaw: float) -> Array[Vector2]:
	var a: Vector3 = axis(yaw)
	return [Vector2(a.x, a.z), Vector2(-a.z, a.x)]

## Do two wall footprints (WIDTH x THICK) overlap? (separating axis test; `grow` widens the rectangles)
static func rects_overlap(c1: Vector3, y1: float, c2: Vector3, y2: float, grow: float = 0.0) -> bool:
	var axes: Array[Vector2] = _rect_axes(y1) + _rect_axes(y2)
	var d := Vector2(c2.x - c1.x, c2.z - c1.z)
	for ax in axes:
		var r1: float = _extent(y1, ax, grow)
		var r2: float = _extent(y2, ax, grow)
		if absf(d.dot(ax)) > r1 + r2:
			return false
	return true

static func _extent(yaw: float, ax: Vector2, grow: float) -> float:
	var u: Array[Vector2] = _rect_axes(yaw)
	return absf(u[0].dot(ax)) * (WIDTH * 0.5 + grow) + absf(u[1].dot(ax)) * (THICK * 0.5 + grow)

static func _overlaps_wall(p: PlayerData, center: Vector3, yaw: float) -> bool:
	for w in p.walls:
		var wd: Dictionary = w as Dictionary
		if rects_overlap(center, yaw, wd["center"] as Vector3, float(wd["yaw"]), -0.05):
			return true
	return false

static func footprint_valid(p: PlayerData, center: Vector3, yaw: float) -> bool:
	if total_layers(p) >= MAX_PER_PLAYER:
		return false
	var lo: float = INF
	var hi: float = -INF
	for s in _samples(center, yaw):
		if not Posts.area_ok(p, s):
			return false
		if Terrain.is_water(s.x, s.z) or s.y < Cfg.WATER_LEVEL + 0.3 or Terrain.slope_deg(s.x, s.z) > 35.0:
			return false
		lo = minf(lo, s.y)
		hi = maxf(hi, s.y)
	if hi - lo > 1.3:
		return false
	if _overlaps_wall(p, center, yaw):
		return false
	for s2 in _samples(center, yaw):
		if _blocked(s2, lo):
			return false
	return true

## Base point of a wall on the ground (lowest point under it, so no end hangs in the air)
static func ground_base(center: Vector3, yaw: float) -> Vector3:
	var lo: float = INF
	for s in _samples(center, yaw):
		lo = minf(lo, s.y)
	return Vector3(center.x, lo, center.z)

## A wall next to the end of an existing one continues it in a straight line
static func snap(p: PlayerData, cursor: Vector3, yaw: float) -> Dictionary:
	for w in p.walls:
		var wd: Dictionary = w as Dictionary
		var a: Vector3 = axis(float(wd["yaw"]))
		for sgn in [1.0, -1.0]:
			var c: Vector3 = (wd["center"] as Vector3) + a * WIDTH * float(sgn)
			c.y = Terrain.h(c.x, c.z)
			if Util.dist_xz(cursor, c) < 3.4:
				return {"center": c, "yaw": float(wd["yaw"])}
	return {"center": Vector3(cursor.x, Terrain.h(cursor.x, cursor.z), cursor.z), "yaw": yaw}

## The own wall the ray points at (or an empty dictionary)
static func hover(p: PlayerData, origin: Vector3, dir: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bt: float = INF
	for w in p.walls:
		var wd: Dictionary = w as Dictionary
		var c: Vector3 = wd["center"] as Vector3
		var yaw: float = float(wd["yaw"])
		var xf := Transform3D(Basis(Vector3.UP, yaw), c)
		var inv: Transform3D = xf.affine_inverse()
		var o: Vector3 = inv * origin
		var d: Vector3 = inv.basis * dir
		var box := AABB(Vector3(-WIDTH * 0.5, -0.5, -THICK * 0.5 - 0.3), Vector3(WIDTH, LAYER_H * float(layer_count(wd)) + 0.5, THICK + 0.6))
		var hit: Variant = box.intersects_ray(o, d)
		if hit != null:
			var t: float = o.distance_to(hit as Vector3)
			if t < bt:
				bt = t
				best = wd
	return best

# ------------------------------------------------------------------ building
static func _make_layer(owner_id: int, base: Vector3, yaw: float, rng: Rng, crown: bool) -> Structure:
	var r := BuildResult.new()
	r.footprint_radius = WIDTH * 0.5
	r.height = LAYER_H + 0.55
	var half: float = WIDTH * 0.5
	Kit.wall(r, "stone", Vector2(-half, 0.0), Vector2(half, 0.0), 0.0, LAYER_H, THICK, WIDTH / 6.0, LAYER_H / 4.0, rng, [], true, Util.color_jitter(STONE, rng, 0.03), "block")
	if crown:
		_add_crown(r, rng)
	var s: Structure = Breakable.create("playerwall", owner_id, r, Transform3D(Basis(Vector3.UP, yaw), base), false, "building.stonewall")
	s.behavior = LayerBehavior.new()
	return s

static func _add_crown(r: BuildResult, rng: Rng) -> void:
	var n: int = 5
	var mw: float = 0.78
	var step: float = (WIDTH - mw) / float(n - 1)
	for k in n:
		var x: float = -WIDTH * 0.5 + mw * 0.5 + step * float(k)
		Kit.box(r, "stone", Vector3(mw, 0.55, THICK), Vector3(x, LAYER_H + 0.275, 0.0), rng, Util.color_jitter(STONE, rng, 0.03), false, "crenel")

static func place_new(p: PlayerData, center: Vector3, yaw: float, rng: Rng) -> Dictionary:
	p.wall_counter += 1
	var base: Vector3 = ground_base(center, yaw)
	var s: Structure = _make_layer(p.id, base, yaw, rng, true)
	var w: Dictionary = {"id": p.wall_counter, "center": base, "yaw": yaw, "layers": [s]}
	p.walls.append(w)
	return w

## Another layer on top: the crenellations of the layer below disappear, the new top gets them
static func stack(p: PlayerData, w: Dictionary, rng: Rng) -> bool:
	if not can_stack(w):
		return false
	var layers: Array = w["layers"] as Array
	var below: Structure = layers[layers.size() - 1] as Structure
	Breakable.awaken(below)
	for part in below.parts.duplicate():
		if part.tag == "crenel" and part.state != Part.State.DEAD:
			Breakable.discard_part(part)
	var base: Vector3 = (w["center"] as Vector3) + Vector3.UP * LAYER_H * float(layers.size())
	var s: Structure = _make_layer(p.id, base, float(w["yaw"]), rng, true)
	(below.behavior as LayerBehavior).above = s
	layers.append(s)
	return true

## Applies a build action (`d` = {c: [x,y,z], y: yaw, stack: bool}); identical on every machine
static func apply(p: PlayerData, d: Dictionary, rng: Rng) -> bool:
	var c: Array = d["c"] as Array
	var center := Vector3(float(c[0]), float(c[1]), float(c[2]))
	var yaw: float = float(d["y"])
	if bool(d.get("stack", false)):
		for w in p.walls:
			var wd: Dictionary = w as Dictionary
			if Util.dist_xz(wd["center"] as Vector3, center) < 0.5 and absf(Util.angle_diff(float(wd["yaw"]), yaw)) < 0.05:
				return stack(p, wd, rng)
		return false
	place_new(p, center, yaw, rng)
	return true
