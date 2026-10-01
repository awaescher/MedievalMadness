class_name Bees
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Bee swarm from the Angry Beehive (spec 6.4): hovers within 6 m of the impact for 8 s, chases the
## nearest settler, panics them and stings 2 dmg/s. Bees never damage buildings.

class Swarm extends RefCounted:
	var center: Vector3
	var origin: Vector3
	var t: float = 0.0
	var dur: float = 16.0
	var radius: float = 13.0
	var phase: float = 0.0
	var source: Dictionary = {}
	var emit_timer: float = 0.0
	var buzz_timer: float = 0.0

static var swarms: Array[Swarm] = []
static var rng: Rng = Rng.new(37)

static func reset() -> void:
	swarms.clear()

static func active() -> bool:
	return not swarms.is_empty()

static func spawn(pos: Vector3, source: Dictionary) -> void:
	# three swarms burst out of the hive and hunt on their own
	for k in 3:
		var s := Swarm.new()
		var a: float = TAU * float(k) / 3.0 + rng.range_f(0.0, 1.0)
		s.center = pos + Vector3(cos(a) * 1.5, 1.0, sin(a) * 1.5)
		s.origin = pos
		s.phase = a
		s.source = source
		swarms.append(s)
	Sfx.play("buzz", pos, 1.0, 2)
	for st in Settler.all:
		if (st.global_pos() - pos).length() < 28.0:
			st.panic_from(pos, 3.0)

static func tick(dt: float) -> void:
	var i: int = swarms.size() - 1
	while i >= 0:
		var s: Swarm = swarms[i]
		s.t += dt
		if s.t >= s.dur:
			swarms.remove_at(i)
			i -= 1
			continue
		# chase the nearest living settler within the hover radius
		var best: Settler = null
		var bd: float = s.radius
		for st in Settler.all:
			if st.state == Settler.State.DEAD or st.state == Settler.State.GONE:
				continue
			var d: float = Util.dist_xz(st.global_pos(), s.origin)
			if d < s.radius + 6.0:
				var dd: float = st.global_pos().distance_to(s.center)
				if dd < bd or best == null:
					bd = dd
					best = st
		if best != null:
			var tgt: Vector3 = best.global_pos() + Vector3.UP * 1.2
			var dir: Vector3 = tgt - s.center
			if dir.length() > 0.2:
				s.center += dir.normalized() * 8.0 * dt
			# keep within the hunting radius of the hive
			var off: Vector3 = s.center - s.origin
			off.y = 0.0
			if off.length() > s.radius + 6.0:
				s.center = s.origin + off.normalized() * (s.radius + 6.0) + Vector3(0, s.center.y - s.origin.y, 0)
		else:
			# nobody around: circle above the impact
			s.phase += dt * 1.6
			s.center = s.center.lerp(s.origin + Vector3(cos(s.phase), 0, sin(s.phase)) * 3.0, 0.05)
		s.center.y = Terrain.h(s.center.x, s.center.z) + 1.4
		# stings + panic
		for st2 in Settler.all:
			if st2.state == Settler.State.DEAD or st2.state == Settler.State.GONE or st2.state == Settler.State.RAGDOLL:
				continue
			var dist: float = st2.global_pos().distance_to(s.center)
			if dist < 2.8:
				st2.sting(dt, s.source)
			elif dist < 9.0:
				st2.panic_from(s.center, 1.6)
		s.emit_timer -= dt
		if s.emit_timer <= 0.0:
			s.emit_timer = 0.3
			Fx.burst("bee", s.center, Color(0, 0, 0, -1), 1.2, Vector3(rng.range_f(-1, 1), 0.2, rng.range_f(-1, 1)).normalized())
		s.buzz_timer -= dt
		if s.buzz_timer <= 0.0:
			s.buzz_timer = 1.6
			Sfx.play("buzz", s.center, 0.5, 0)
		i -= 1
