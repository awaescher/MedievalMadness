class_name Repair
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Settlers slowly rebuild the damaged buildings of their own village (never catapults, never trees / palisades / player
## walls): a calm settler (not fleeing, burning or in panic, still alive) walks to a missing part, hammers on it for about
## 11 seconds and puts it back (a broken part is rebuilt, a fallen piece that lies around is carried back). It is meant as
## a slow, mostly cosmetic background activity: at most 3 builders per village, one part per builder at a time, only in the
## calm phases of a turn, and never online on a client (the host's turn snapshot brings the parts back there).

const SKIP: Array[String] = ["tree", "palisadepost", "playerwall"]
const WORK_TIME := 11.0
const MAX_WORKERS := 3

static var claims: Dictionary = {}          # part id -> Settler that works on it

static func reset() -> void:
	claims.clear()

## Calm phases only: while aiming, between turns - not while something flies, burns down or settles
static func allowed() -> bool:
	if Game.state != Game.State.BATTLE or Net.is_client():
		return false
	return Turn.phase == Turn.Phase.TURN_START or Turn.phase == Turn.Phase.AIMING or Turn.phase == Turn.Phase.TURN_END

static func builders(owner_id: int) -> int:
	var n: int = 0
	for k in claims.keys():
		var st: Variant = claims[k]
		if is_instance_valid(st) and (st as Settler).owner_id == owner_id:
			n += 1
	return n

static func claim(p: Part, who: Settler) -> void:
	claims[p.id] = who

static func release(p: Part) -> void:
	if p != null:
		claims.erase(p.id)

static func _aabb0(p: Part) -> AABB:
	var saved: Transform3D = p.xf
	p.xf = p.xf0
	var bb: AABB = p.world_aabb()
	p.xf = saved
	return bb

## A part may only be put back where it has something to rest on: the ground, or a part that stands there now
static func _supported(s: Structure, p: Part, bb: AABB) -> bool:
	if bb.position.y <= Terrain.h(p.xf0.origin.x, p.xf0.origin.z) + 0.25:
		return true
	var grown: AABB = bb.grow(0.07)
	for q in s.parts:
		if q != p and (q.state == Part.State.FROZEN or q.state == Part.State.DORMANT) and grown.intersects(q.world_aabb()):
			return true
	return false

## The next missing part of the village for `who`: low parts first, near ones before far ones
static func pick_job(owner_id: int, from: Vector3) -> Part:
	var best: Part = null
	var best_score: float = INF
	for s in Breakable.structures:
		if s.owner_id != owner_id or s.free_parts or not s.awake or SKIP.has(s.kind) or s.parts.is_empty():
			continue
		if Util.dist_xz(s.center, from) > Cfg.ZONE_RADIUS * 1.6:
			continue
		for p in s.parts:
			if claims.has(p.id):
				continue
			var missing: bool = p.state == Part.State.DEAD
			if p.state == Part.State.FREE:
				missing = PhysWorld.is_sleeping(p.body_id) and not p.on_fire
			if not missing:
				continue
			var bb: AABB = _aabb0(p)
			var score: float = Util.dist_xz(p.xf0.origin, from) + bb.position.y * 1.2 + randf() * 2.0
			if score < best_score and _supported(s, p, bb):
				best_score = score
				best = p
	return best

## The work is done: the part stands there again
static func finish(p: Part) -> void:
	release(p)
	if p.structure == null or p.structure.parts.is_empty():
		return
	if p.state == Part.State.DEAD:
		Breakable.revive_part(p)
	elif p.state == Part.State.FREE:
		Breakable.reattach_part(p)
	else:
		return
	p.charred = 0.0
	Fx.burst("dust", p.xf0.origin, Color("#b9a98a"), 0.35, Vector3.UP)
	Sfx.play("thunk", p.xf0.origin, 0.45, 1)
