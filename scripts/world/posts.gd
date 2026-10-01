class_name Posts
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Player palisade posts (spec 2.3b): after the catapults every player sets a few tree-trunk thick wooden posts
## (half the height of the watchtower) as a wall. They can stand side by side anywhere around the own village but not
## near an enemy, and they can be stacked to build taller palisades. A column is a dictionary
## {base: Vector3, structs: Array[Structure]} stored in PlayerData.posts.

const POST_H := 5.5
const POST_R := 0.25
const SPACING := 0.52              # touching posts
const MAX_STACK := 4
const OWN_REACH := 25.0            # metres beyond the own village zone
const ENEMY_MARGIN := 12.0         # metres beyond an enemy village zone

## A post only holds up what stands on it: if it breaks or is released the post above falls down too
class PostBehavior extends Specials.Behavior:
	var above: Structure = null
	func _release_above() -> void:
		if above == null or above.parts.is_empty():
			return
		var up: Structure = above
		above = null
		Breakable.awaken(up)
		for p in up.parts:
			if p.state == Part.State.FROZEN:
				Breakable.release_part(p, Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)))
	func on_part_break(_s: Structure, _p: Part) -> void:
		_release_above()
	func on_release(_s: Structure, _p: Part) -> void:
		_release_above()

static func count(p: PlayerData) -> int:
	return p.post_log.size()

static func area_ok(p: PlayerData, pos: Vector3) -> bool:
	if Util.dist_xz(pos, p.village_center) > Cfg.ZONE_RADIUS + OWN_REACH:
		return false
	for o in Game.players:
		if o.id != p.id and Util.dist_xz(pos, o.village_center) < Cfg.ZONE_RADIUS + ENEMY_MARGIN:
			return false
	return true

## Ground placement: dry, not too steep, allowed area, nothing solid in the way
static func ground_valid(p: PlayerData, pos: Vector3) -> bool:
	if not area_ok(p, pos):
		return false
	if Terrain.is_water(pos.x, pos.z) or Terrain.h(pos.x, pos.z) < Cfg.WATER_LEVEL + 0.3:
		return false
	if Terrain.slope_deg(pos.x, pos.z) > 35.0:
		return false
	var blocked: bool = false
	var probe := Vector3(pos.x, Terrain.h(pos.x, pos.z) + 1.0, pos.z)
	PhysWorld.overlap_sphere(probe, 0.2, func(pb: PhysWorld.PBody, _s: int, _r: RID) -> void:
		if pb != null and pb.kind != "projectile":
			blocked = true, Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_CATAPULT)
	return not blocked

## The own column the ray points at (or an empty dictionary)
static func hover_column(p: PlayerData, origin: Vector3, dir: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = POST_R + 0.3
	for col in p.posts:
		var c: Dictionary = col as Dictionary
		var structs: Array = c["structs"] as Array
		if structs.is_empty():
			continue
		var base: Vector3 = c["base"] as Vector3
		var pts: PackedVector3Array = Geometry3D.get_closest_points_between_segments(origin, origin + dir * 400.0, base, base + Vector3.UP * POST_H * float(structs.size()))
		var d: float = pts[0].distance_to(pts[1])
		if d < bd:
			bd = d
			best = c
	return best

static func can_stack(col: Dictionary) -> bool:
	return not col.is_empty() and (col["structs"] as Array).size() < MAX_STACK

static func stack_base(col: Dictionary) -> Vector3:
	return (col["base"] as Vector3) + Vector3.UP * POST_H * float((col["structs"] as Array).size())

## A free spot snaps to touch the nearest post so walls are easy to build
static func snap_adjacent(p: PlayerData, pos: Vector3) -> Vector3:
	var best: Dictionary = {}
	var bd: float = 1.1
	for col in p.posts:
		var c: Dictionary = col as Dictionary
		var d: float = Util.dist_xz(pos, c["base"] as Vector3)
		if d < bd:
			bd = d
			best = c
	if best.is_empty():
		return pos
	var b: Vector3 = best["base"] as Vector3
	var dv: Vector3 = Util.flat(pos - b)
	if dv.length() < 0.01:
		dv = Vector3.RIGHT
	var np: Vector3 = b + dv.normalized() * SPACING
	np.y = Terrain.h(np.x, np.z)
	return np

static func _make(owner_id: int, base: Vector3, anchor: bool, rng: Rng) -> Structure:
	var r := BuildResult.new()
	r.footprint_radius = POST_R
	r.height = POST_H
	Kit.cyl(r, "wood", POST_R, POST_H, Vector3(0, POST_H * 0.5, 0), rng, Color("#7a5230"), anchor, "post")
	var s: Structure = Breakable.create("palisadepost", owner_id, r, Transform3D(Basis(), base))
	s.behavior = PostBehavior.new()
	return s

static func place_ground(p: PlayerData, pos: Vector3, rng: Rng, log: bool = true) -> Dictionary:
	var base := Vector3(pos.x, Terrain.h(pos.x, pos.z), pos.z)
	var s: Structure = _make(p.id, base, true, rng)
	var col: Dictionary = {"base": base, "structs": [s]}
	p.posts.append(col)
	if log:
		p.post_log.append([s])
	return col

static func place_stack(p: PlayerData, col: Dictionary, rng: Rng, log: bool = true) -> Structure:
	if not can_stack(col):
		return null
	var structs: Array = col["structs"] as Array
	var below: Structure = structs[structs.size() - 1] as Structure
	var s: Structure = _make(p.id, stack_base(col), false, rng)
	(below.behavior as PostBehavior).above = s
	structs.append(s)
	if log:
		p.post_log.append([s])
	return s

## One undo step removes the last action: a whole fence (3 posts) or a whole stacked row
static func remove_last(p: PlayerData) -> void:
	if p.post_log.is_empty():
		return
	var group: Array = p.post_log.pop_back() as Array
	for gi in range(group.size() - 1, -1, -1):
		var s: Structure = group[gi] as Structure
		for col in p.posts.duplicate():
			var structs: Array = (col as Dictionary)["structs"] as Array
			if not structs.has(s):
				continue
			structs.erase(s)
			if structs.is_empty():
				p.posts.erase(col)
				for f in p.fences:
					((f as Dictionary)["cols"] as Array).erase(col)
			else:
				((structs[structs.size() - 1] as Structure).behavior as PostBehavior).above = null
			break
		Breakable.remove_structure(s)
	for fi in range(p.fences.size() - 1, -1, -1):
		if ((p.fences[fi] as Dictionary)["cols"] as Array).is_empty():
			p.fences.remove_at(fi)

# ------------------------------------------------------------------ fences: always 3 posts side by side
const FENCE_POSTS := 3

## Direction along which a fence with `yaw` runs (perpendicular to the way it faces)
static func axis(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

static func fence_positions(center: Vector3, yaw: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a: Vector3 = axis(yaw)
	for i in FENCE_POSTS:
		var pos: Vector3 = center + a * SPACING * float(i - 1)
		pos.y = Terrain.h(pos.x, pos.z)
		out.append(pos)
	return out

static func fence_valid(p: PlayerData, center: Vector3, yaw: float) -> bool:
	for pos in fence_positions(center, yaw):
		for col in p.posts:
			if Util.dist_xz(pos, (col as Dictionary)["base"] as Vector3) < SPACING - 0.03:
				return false
		if not ground_valid(p, pos):
			return false
	return true

static func fence_of(p: PlayerData, col: Dictionary) -> Dictionary:
	for f in p.fences:
		if int((f as Dictionary)["id"]) == int(col.get("fence", -1)):
			return f as Dictionary
	return {}

static func fence_layers(f: Dictionary) -> int:
	var cols: Array = f["cols"] as Array
	if cols.is_empty():
		return 0
	return ((cols[0] as Dictionary)["structs"] as Array).size()

static func fence_can_stack(f: Dictionary) -> bool:
	if f.is_empty():
		return false
	for col in f["cols"] as Array:
		if not can_stack(col as Dictionary):
			return false
	return true

## Base height of the next row on a fence
static func fence_stack_center(f: Dictionary) -> Vector3:
	var c: Vector3 = f["center"] as Vector3
	return Vector3(c.x, Terrain.h(c.x, c.z) + POST_H * float(fence_layers(f)), c.z)

static func place_fence(p: PlayerData, center: Vector3, yaw: float, rng: Rng) -> Dictionary:
	p.fence_counter += 1
	var cols: Array = []
	var group: Array = []
	for pos in fence_positions(center, yaw):
		var col: Dictionary = place_ground(p, pos, rng, false)
		col["fence"] = p.fence_counter
		cols.append(col)
		group.append((col["structs"] as Array)[0])
	var f: Dictionary = {"id": p.fence_counter, "cols": cols, "center": center, "yaw": yaw}
	p.fences.append(f)
	p.post_log.append(group)
	return f

## A new row of 3 posts on top of an existing fence
static func stack_fence(p: PlayerData, f: Dictionary, rng: Rng) -> bool:
	if not fence_can_stack(f):
		return false
	var group: Array = []
	for col in f["cols"] as Array:
		var s: Structure = place_stack(p, col as Dictionary, rng, false)
		if s != null:
			group.append(s)
	p.post_log.append(group)
	return true

## A fence next to the end of an existing one continues it in a straight line
static func snap_fence(p: PlayerData, cursor: Vector3, yaw: float) -> Dictionary:
	for f in p.fences:
		var fd: Dictionary = f as Dictionary
		var a: Vector3 = axis(float(fd["yaw"]))
		for sgn in [1.0, -1.0]:
			var c: Vector3 = (fd["center"] as Vector3) + a * SPACING * float(FENCE_POSTS) * float(sgn)
			c.y = Terrain.h(c.x, c.z)
			if Util.dist_xz(cursor, c) < 2.4:
				return {"center": c, "yaw": float(fd["yaw"])}
	var cc := Vector3(cursor.x, Terrain.h(cursor.x, cursor.z), cursor.z)
	return {"center": cc, "yaw": yaw}

## CPU / Auto button: short fences in front of the village (facing the nearest enemy), some of them stacked
static func auto_place(p: PlayerData, r: Rng) -> void:
	var toward := Vector3.ZERO
	var bd: float = 1e9
	for o in Game.players:
		if o.id != p.id and not o.eliminated:
			var d: float = Util.dist_xz(o.village_center, p.village_center)
			if d < bd:
				bd = d
				toward = Util.flat(o.village_center - p.village_center).normalized()
	if toward == Vector3.ZERO:
		toward = Vector3(0, 0, -1)
	var face_yaw: float = Util.dir_to_yaw(toward)
	var guard: int = 0
	var last: Dictionary = {}
	while count(p) < Game.palisades_per_player and guard < 300:
		guard += 1
		if p.fences.size() >= 2 and r.chance(0.35):
			var f: Dictionary = p.fences[r.range_i(0, p.fences.size() - 1)] as Dictionary
			if fence_layers(f) < 3 and stack_fence(p, f, r):
				continue
		var center: Vector3
		var yaw: float = face_yaw + r.range_f(-0.2, 0.2)
		if not last.is_empty() and r.chance(0.8):
			var sn: Dictionary = snap_fence(p, (last["center"] as Vector3) + axis(float(last["yaw"])) * SPACING * float(FENCE_POSTS) * (1.0 if guard % 2 == 0 else -1.0), yaw)
			center = sn["center"] as Vector3
			yaw = float(sn["yaw"])
		else:
			var ang: float = r.range_f(-0.9, 0.9)
			center = p.village_center + toward.rotated(Vector3.UP, ang) * r.range_f(Cfg.ZONE_RADIUS * 0.75, Cfg.ZONE_RADIUS + 5.0)
			center.y = Terrain.h(center.x, center.z)
		if fence_valid(p, center, yaw):
			last = place_fence(p, center, yaw, r)
