class_name Brigade
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Bucket brigade (spec 16.4 "extinguish"): idle settlers of a burning village form a line between the nearest water
## source (well / pond / river) and the nearest fire (max 20 m). The bucket is passed along the line; the last settler
## throws it (each throw extinguishes fire within 1.6 m). With fewer than 3 idle settlers they run back and forth alone.

static var brigades: Array[Brigade] = []
static var _timer: float = 0.0
static var rng: Rng = Rng.new(61)

var owner_id: int = -1
var members: Array[Settler] = []
var slots: Array[Vector3] = []
var water_pos: Vector3 = Vector3.ZERO
var fire_pos: Vector3 = Vector3.ZERO
var chain: bool = true
var cycle_t: float = 0.0
var bucket: MeshInstance3D
var _bucket_from: int = 0
var _bucket_t: float = 0.0
var _phase: int = 0            # chain: 0 walking to slots, 1 passing
var _solo_state: int = 0       # solo: 0 to water, 1 to fire
var alive: bool = true

static func reset() -> void:
	for b in brigades:
		b.disband()
	brigades.clear()
	_timer = 0.0

static func active_for(owner: int) -> Brigade:
	for b in brigades:
		if b.owner_id == owner and b.alive:
			return b
	return null

## Called every physics tick
static func tick_all(dt: float) -> void:
	var i: int = brigades.size() - 1
	while i >= 0:
		var b: Brigade = brigades[i]
		if not b.alive:
			brigades.remove_at(i)
		else:
			b.tick(dt)
		i -= 1
	_timer += dt
	if _timer < 0.6:
		return
	_timer = 0.0
	for p in Game.players:
		if p.eliminated and false:
			continue
		if active_for(p.id) != null:
			continue
		_try_form(p)

static func _try_form(p: PlayerData) -> void:
	if Fire.in_village_count(p.id) <= 0:
		return
	var c: Vector3 = p.village_center
	# nearest fire (within 20 m of the village center's buildings)
	var best: Vector3 = Vector3.INF
	var bd: float = 24.0
	for part in Fire.burning_list:
		if part.structure.owner_id != p.id:
			continue
		var d: float = Util.dist_xz(part.xf.origin, c)
		if d < bd and part.xf.origin.y < Terrain.h(part.xf.origin.x, part.xf.origin.z) + 8.0:
			bd = d
			best = part.xf.origin
	if best == Vector3.INF:
		return
	# water source: wells / natural water registered for this village
	var waters: Array = Settler.water_points.get(p.id, []) as Array
	if waters.is_empty():
		return
	var water: Vector3 = waters[0] as Vector3
	var wd: float = 1e9
	for w in waters:
		var dd: float = (w as Vector3).distance_to(best)
		if dd < wd:
			wd = dd
			water = w as Vector3
	if wd > 45.0:
		return
	var idle: Array[Settler] = []
	for st in Settler.all:
		if st.owner_id == p.id and st.brigade == null and not st.is_archer and st.hp > 0.0 and (st.state == Settler.State.IDLE or st.state == Settler.State.WANDER or st.state == Settler.State.WORK):
			idle.append(st)
	if idle.is_empty():
		return
	# closest settlers to the water first
	idle.sort_custom(func(a: Settler, b2: Settler) -> bool: return a.global_pos().distance_to(water) < b2.global_pos().distance_to(water))
	var b := Brigade.new()
	b.owner_id = p.id
	b.water_pos = Vector3(water.x, Terrain.h(water.x, water.z), water.z)
	var fp: Vector3 = Vector3(best.x, Terrain.h(best.x, best.z), best.z)
	b.fire_pos = fp
	b.chain = idle.size() >= 3
	var n: int = mini(idle.size(), 4 if b.chain else 1)
	for i in n:
		b.members.append(idle[i])
		idle[i].brigade = b
		idle[i].state = Settler.State.EXTINGUISH
	if b.chain:
		# line from the water to 1.6 m short of the fire
		var dir: Vector3 = (fp - b.water_pos)
		dir.y = 0.0
		var len: float = dir.length()
		var end: Vector3 = fp - dir.normalized() * 1.7 if len > 3.0 else b.water_pos + dir.normalized() * 1.5
		for i in n:
			var t: float = float(i) / float(maxi(n - 1, 1))
			var sp: Vector3 = b.water_pos.lerp(end, t)
			sp.y = Terrain.h(sp.x, sp.z)
			b.slots.append(sp)
	b.bucket = MeshInstance3D.new()
	b.bucket.mesh = MeshGen.cyl_mesh(0.15, 0.24, 8)
	b.bucket.material_override = Toon.colored(Color("#8a5a2a"))
	b.bucket.visible = false
	Settler.world_root.add_child(b.bucket)
	brigades.append(b)
	Events.banner.emit(I18n.pick("banner.fire", Game.rng_battle), "fire")
	if b.members.size() > 0:
		Speech.say_random("speech.bucket", b.members[0], b.members[0], rng)

func leave(s: Settler) -> void:
	members.erase(s)
	s.brigade = null
	if members.size() < (2 if chain else 1):
		disband()

func disband() -> void:
	if not alive:
		return
	alive = false
	for s in members:
		if is_instance_valid(s):
			s.brigade = null
			s.carry_bucket(false)
			if s.state == Settler.State.EXTINGUISH:
				s.state = Settler.State.IDLE
				s._timer = 1.0
	members.clear()
	if bucket != null and is_instance_valid(bucket):
		bucket.queue_free()
		bucket = null

## Called at 10 Hz by each member from Settler._think
func update_member(s: Settler, step: float) -> void:
	if not alive:
		s.state = Settler.State.IDLE
		return
	if chain:
		var idx: int = members.find(s)
		if idx < 0 or idx >= slots.size():
			return
		var slot: Vector3 = slots[idx]
		if Util.dist_xz(s.global_pos(), slot) > 0.7:
			s._target = slot
			s._walk(step, 2.6)
		else:
			# face along the line
			var look: Vector3 = fire_pos if idx == members.size() - 1 else slots[mini(idx + 1, slots.size() - 1)]
			s._face(look - s.global_pos(), step)
	else:
		var target: Vector3 = water_pos if _solo_state == 0 else fire_pos
		var d: float = Util.dist_xz(s.global_pos(), target)
		if d > (1.6 if _solo_state == 1 else 1.2):
			s._target = target
			s._walk(step, 2.4)
		else:
			if _solo_state == 0:
				_solo_state = 1
				s.carry_bucket(true)
			else:
				_throw(s)
				_solo_state = 0
				s.carry_bucket(false)

func _throw(s: Settler) -> void:
	var src: Dictionary = {"player_id": owner_id, "ammo": "bucket"}
	Fx.burst("splash", fire_pos + Vector3.UP * 0.8, Color("#9ad8ff"), 0.4)
	Sfx.play("splash", fire_pos, 0.5, 0)
	var n: int = Fire.extinguish_in_radius(fire_pos, 1.6, src, 6.0)
	if n > 0:
		Speech.say_random("speech.bucket", s, s, rng)

func tick(dt: float) -> void:
	# prune dead / ragdolled members
	var i: int = members.size() - 1
	while i >= 0:
		var m: Settler = members[i]
		if not is_instance_valid(m) or m.state == Settler.State.DEAD or m.state == Settler.State.RAGDOLL or m.state == Settler.State.BURNING or m.state == Settler.State.GONE or m.state == Settler.State.PANIC:
			if is_instance_valid(m):
				m.brigade = null
			members.remove_at(i)
		i -= 1
	if members.size() < (2 if chain else 1):
		disband()
		return
	# done when the fire near the target is out (check every so often)
	cycle_t += dt
	if not Fire.fires_near(fire_pos, 3.5) and cycle_t > 1.0:
		disband()
		return
	if not chain:
		return
	# all in position? then pass the bucket every 1.3 s
	var all_there: bool = true
	for idx in members.size():
		if idx >= slots.size() or Util.dist_xz(members[idx].global_pos(), slots[idx]) > 1.0:
			all_there = false
			break
	if not all_there:
		_phase = 0
		bucket.visible = false
		return
	_phase = 1
	_bucket_t += dt
	var seg: float = 1.3 / float(maxi(members.size(), 1))
	var k: int = int(_bucket_t / seg)
	var frac: float = fmod(_bucket_t, seg) / seg
	if k >= members.size():
		# thrown at the fire by the last settler: restart the chain
		_throw(members[members.size() - 1])
		_bucket_t = 0.0
		bucket.visible = false
		return
	var a: Vector3 = members[k].global_pos() + Vector3(0, 1.1, 0)
	var nxt: Vector3 = fire_pos + Vector3(0, 1.0, 0) if k == members.size() - 1 else members[k + 1].global_pos() + Vector3(0, 1.1, 0)
	bucket.visible = true
	bucket.global_position = a.lerp(nxt, frac) + Vector3(0, sin(frac * PI) * 0.4, 0)
	for m in members:
		m.carry_bucket(false)
