class_name Damage
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Damage sources (spec 5.4). `source` = {player_id: int, ammo: String}. Indirect damage (collapse, fire)
## inherits the last source that hit the structure within 20 s.

static func make_source(player_id: int, ammo: String) -> Dictionary:
	return {"player_id": player_id, "ammo": ammo}

static func source_for(s: Structure) -> Dictionary:
	if Breakable.time_now - s.last_source_time < 20.0:
		return s.last_source
	return {}

## Core: reduce a part's hp, break it at 0.
static func damage_part(p: Part, amount: float, source: Dictionary, dir: Vector3 = Vector3.ZERO) -> void:
	if p.state == Part.State.DEAD or amount <= 0.0:
		return
	var s: Structure = p.structure
	if not s.awake:
		Breakable.awaken(s)
	var applied: float = minf(amount, p.hp)
	p.hp -= amount
	if not source.is_empty():
		s.last_source = source
		s.last_source_time = Breakable.time_now
	s.last_hit_time = Breakable.time_now
	if not source.is_empty():
		Scoring.on_damage(source, s.owner_id, applied)
		if s.kind == "tree":
			Unlocks.on_tree_damaged(source, s)
	if p.hp <= 0.0:
		Breakable.break_part(p, source, dir)
	else:
		# cracked look: darken with damage
		if p.mesh != null and p.shape != "compound":
			var f: float = clampf(p.hp / p.max_hp, 0.0, 1.0)
			var col: Color = p.color.lerp(Color(0.25, 0.2, 0.18), (1.0 - f) * 0.35 + p.charred * 0.6)
			p.mesh.set_instance_shader_parameter("tint", col)
		if s.behavior != null:
			s.behavior.call("on_hit", s, p, amount)

## impulse (N*s) hitting a part: over the break force -> damage (spec section 4)
static func apply_impact(p: Part, impulse: float, source: Dictionary) -> void:
	var bf: float = p.mat.break_force * p.size_factor
	if bf <= 0.0 or impulse <= bf:
		return
	damage_part(p, (impulse - bf) / bf * 40.0, source, Vector3.ZERO)

## Explosion-style damage on structures + props within `radius`. Also pushes free parts.
static func damage_in_radius(center: Vector3, radius: float, max_damage: float, source: Dictionary, falloff: String = "linear", impulse_scale: float = 0.6) -> void:
	Breakable.awaken_in_radius(center, radius + 2.0)
	var box := AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	var hits: Array[Part] = []
	for s in Breakable.structures:
		if not s.awake:
			continue
		if not s.aabb.grow(2.0).intersects(box):
			continue
		for p in s.parts:
			if p.state == Part.State.DEAD:
				continue
			var d: float = (p.xf.origin - center).length() - p.radius() * 0.5
			if d < radius:
				hits.append(p)
	for p2 in hits:
		if p2.state == Part.State.DEAD:
			continue
		var d2: float = maxf((p2.xf.origin - center).length() - p2.radius() * 0.5, 0.0)
		var f: float = 1.0 - clampf(d2 / radius, 0.0, 1.0)
		if falloff == "quad":
			f = f * f
		elif falloff == "none":
			f = 1.0
		if f <= 0.0:
			continue
		var dir: Vector3 = (p2.xf.origin - center)
		dir = (dir.normalized() if dir.length() > 0.01 else Vector3.UP) + Vector3.UP * 0.4
		dir = dir.normalized()
		var impulse: float = max_damage * f * impulse_scale
		if p2.state == Part.State.FREE:
			PhysWorld.apply_impulse_capped(p2.body_id, dir * impulse, 30.0)
		else:
			p2.kick += dir * minf(impulse / maxf(p2.mass, 1.0), 22.0)
		damage_part(p2, max_damage * f, source, dir)

# ------------------------------------------------------------------ living things
static func damage_catapult(c: Catapult, amount: float, source: Dictionary, reason: String = "hit") -> void:
	if c == null or c.destroyed or amount <= 0.0:
		return
	c.take_damage(amount, source, reason)

static func damage_catapults_in_radius(center: Vector3, radius: float, max_damage: float, source: Dictionary, impulse_scale: float = 0.6, scale: float = 0.14) -> void:
	for p in Game.players:
		for c in p.catapults:
			if not is_instance_valid(c):
				continue
			var cat: Catapult = c as Catapult
			if cat.destroyed:
				continue
			var d: float = (cat.global_pos() - center).length()
			if d < radius + 1.5:
				var f: float = 1.0 - clampf(d / (radius + 1.5), 0.0, 1.0)
				# catapults are sturdy oak: steep falloff so one blast never wipes out a whole village
				damage_catapult(cat, max_damage * f * f * scale, source, "explosion")
				var dir: Vector3 = (cat.global_pos() - center)
				dir = (dir.normalized() + Vector3.UP * 0.4).normalized()
				cat.apply_impulse(dir * max_damage * f * impulse_scale * 0.5)

static func damage_settlers_in_radius(center: Vector3, radius: float, max_damage: float, source: Dictionary, dir_hint: Vector3 = Vector3.ZERO, impulse_scale: float = 0.6) -> int:
	var killed: int = 0
	for st in Settler.all:
		if st.state == Settler.State.DEAD or st.state == Settler.State.GONE:
			continue
		var d: float = (st.global_pos() + Vector3.UP - center).length()
		if d >= radius:
			continue
		var f: float = 1.0 - d / radius
		var dir: Vector3 = st.global_pos() + Vector3.UP - center
		if dir.length() < 0.05:
			dir = dir_hint if dir_hint.length() > 0.01 else Vector3.UP
		dir = (dir.normalized() + Vector3.UP * 0.6).normalized()
		var was_alive: bool = st.hp > 0.0
		st.hurt(max_damage * f, source, dir * max_damage * f * impulse_scale * 0.06, max_damage * f > 12.0 or impulse_scale > 0.0 and f > 0.15)
		if was_alive and st.hp <= 0.0:
			killed += 1
	for an in Animal.all:
		if an.dead:
			continue
		var d3: float = (an.global_pos() - center).length()
		if d3 < radius:
			var f3: float = 1.0 - d3 / radius
			var dir3: Vector3 = ((an.global_pos() - center).normalized() + Vector3.UP * 0.6).normalized()
			an.hurt(max_damage * f3, dir3 * max_damage * f3 * impulse_scale * 0.05, source)
	return killed

## Everything solid within `radius` of `center` is torn out for certain (a boulder ploughing through walls). Returns the
## number of parts destroyed.
static func smash_in_radius(center: Vector3, radius: float, source: Dictionary, dir: Vector3) -> int:
	Breakable.awaken_in_radius(center, radius + 1.5)
	var box := AABB(center - Vector3.ONE * (radius + 1.0), Vector3.ONE * (radius + 1.0) * 2.0)
	var victims: Array[Part] = []
	for st in Breakable.structures:
		if not st.awake or st.free_parts or not st.aabb.grow(1.0).intersects(box):
			continue
		for p in st.parts:
			if p.state != Part.State.DEAD and (p.xf.origin - center).length() - p.radius() * 0.45 < radius:
				victims.append(p)
	var n: int = 0
	for v in victims:
		if v.state != Part.State.DEAD:
			damage_part(v, 99999.0, source, dir)
			n += 1
	return n

## Kinetic impact of a projectile at `pos`: parts within `radius` receive `energy` (N*s, falloff) through the
## break-force rule (spec section 4) and are pushed along `dir`. Returns the number of parts destroyed.
static func impact_at(pos: Vector3, radius: float, energy: float, dir: Vector3, source: Dictionary) -> int:
	Breakable.awaken_in_radius(pos, radius + 2.0)
	var box := AABB(pos - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	var parts: Array[Part] = []
	for st in Breakable.structures:
		if not st.awake or not st.aabb.grow(1.0).intersects(box):
			continue
		for p in st.parts:
			if p.state != Part.State.DEAD and (p.xf.origin - pos).length() - p.radius() * 0.6 < radius:
				parts.append(p)
	var broken: int = 0
	for p2 in parts:
		if p2.state == Part.State.DEAD:
			continue
		var d: float = maxf((p2.xf.origin - pos).length() - p2.radius() * 0.6, 0.0)
		var f: float = 1.0 - clampf(d / radius, 0.0, 1.0) * 0.75
		var push: Vector3 = dir.normalized() * energy * f * 0.30
		if p2.state == Part.State.FREE:
			PhysWorld.apply_impulse_capped(p2.body_id, push, 24.0)
		else:
			p2.kick += push / maxf(p2.mass, 1.0)
		var before: int = p2.structure.live_count
		# masonry is hit with real force: a fast stone drives through tower walls instead of glancing off
		var boost: float = 2.6 if (p2.mat_id == "stone" or p2.mat_id == "brick") else 1.0
		apply_impact(p2, energy * f * boost, source)
		if p2.state == Part.State.DEAD or p2.structure.live_count < before:
			broken += 1
	return broken
