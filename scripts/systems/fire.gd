class_name Fire
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Fire system (spec 11.1): per-part `burning` 0..1, spread through a spatial hash of flammable parts,
## wind/upward boosts, rain, wet immunity, ground fires, pooled flame emitters + lights.

class GroundFire extends RefCounted:
	var pos: Vector3
	var t: float = 0.0
	var dur: float = 6.0
	var flame: Fx.Flame
	var source: Dictionary = {}

static var grid: Dictionary = {}                   # cell key -> Array[Part]
static var mobile: Array[Part] = []                # released flammable parts (positions change)
static var burning_list: Array[Part] = []
static var heated_list: Array[Part] = []
static var ground_fires: Array[GroundFire] = []
static var burn_grid: Dictionary = {}              # cell -> true (rebuilt each tick, cell 3 m)
static var _tick: float = 0.0
static var _rr: int = 0
static var raining: bool = false
static var _time: float = 0.0
static var rng: Rng = Rng.new(31)
static var _lights: Array[OmniLight3D] = []
static var light_root: Node3D
const CELL := 3.2
const BURN_TIME := 10.0             # a part burns at most this long (then it is charred and cannot catch fire again)
const SPREAD_RATE := 0.5            # per second, times flammability: fire creeps from part to part
const BURN_MULT := 2.6              # buildings are eaten slowly by fire

static func reset() -> void:
	grid.clear()
	mobile.clear()
	burning_list.clear()
	heated_list.clear()
	for g in ground_fires:
		if g.flame != null and Fx.inst != null:
			Fx.inst.release_flame(g.flame)
	ground_fires.clear()
	burn_grid.clear()
	_tick = 0.0
	raining = false
	for l in _lights:
		if is_instance_valid(l):
			l.queue_free()
	_lights.clear()

static func _key(p: Vector3) -> int:
	var cx: int = floori(p.x / CELL)
	var cy: int = floori(p.y / CELL)
	var cz: int = floori(p.z / CELL)
	return (cx & 0x1FFFFF) | ((cy & 0x3FF) << 21) | ((cz & 0x1FFFFF) << 31)

## Register all flammable parts of all structures (call after villages are generated)
static func build_grid() -> void:
	grid.clear()
	mobile.clear()
	for s in Breakable.structures:
		for p in s.parts:
			if p.mat.flammability > 0.0:
				if p.state == Part.State.FREE and not p.structure.free_parts:
					mobile.append(p)
				else:
					var k: int = _key(p.xf.origin)
					if grid.has(k):
						(grid[k] as Array).append(p)
					else:
						grid[k] = [p]

## Register the flammable parts of a newly spawned structure (dynamic props, catapult wreckage)
static func build_grid_add(s: Structure) -> void:
	for p in s.parts:
		if p.mat.flammability > 0.0 and p.state != Part.State.DEAD:
			var k: int = _key(p.xf.origin)
			if grid.has(k):
				(grid[k] as Array).append(p)
			else:
				grid[k] = [p]

static func register_mobile(p: Part) -> void:
	if p.mat.flammability > 0.0 and not mobile.has(p):
		mobile.append(p)

static func on_part_removed(p: Part) -> void:
	if p.on_fire or p.burning > 0.0:
		_stop_fire(p, false)
	burning_list.erase(p)
	heated_list.erase(p)
	mobile.erase(p)

static func _nearby(pos: Vector3, r: float, out: Array[Part]) -> void:
	out.clear()
	var c0x: int = floori((pos.x - r) / CELL)
	var c1x: int = floori((pos.x + r) / CELL)
	var c0y: int = floori((pos.y - r) / CELL)
	var c1y: int = floori((pos.y + r) / CELL)
	var c0z: int = floori((pos.z - r) / CELL)
	var c1z: int = floori((pos.z + r) / CELL)
	var r2: float = r * r
	for x in range(c0x, c1x + 1):
		for y in range(c0y, c1y + 1):
			for z in range(c0z, c1z + 1):
				var k: int = (x & 0x1FFFFF) | ((y & 0x3FF) << 21) | ((z & 0x1FFFFF) << 31)
				if grid.has(k):
					for p in (grid[k] as Array):
						var pp: Part = p as Part
						if pp.state != Part.State.DEAD and (pp.state != Part.State.FREE or pp.structure.free_parts) and (pp.xf.origin - pos).length_squared() <= r2:
							out.append(pp)
	for m in mobile:
		if m.state == Part.State.FREE and (m.xf.origin - pos).length_squared() <= r2:
			out.append(m)

# ------------------------------------------------------------------ ignition / extinguish
static func ignite(p: Part, amount: float, source: Dictionary = {}) -> void:
	if p.state == Part.State.DEAD or p.mat.flammability <= 0.0 or p.wet > 0.0 or amount <= 0.0 or p.charred >= 0.999:
		return
	if raining and amount < 0.9:
		return
	var was: float = p.burning
	p.burning = minf(p.burning + amount, 1.0)
	if not source.is_empty() and p.structure != null:
		p.structure.last_source = source
		p.structure.last_source_time = Breakable.time_now
	if was <= 0.0 and p.burning > 0.0 and not heated_list.has(p):
		heated_list.append(p)
	if p.burning >= 1.0 and not p.on_fire:
		_start_fire(p, source)

static func _start_fire(p: Part, source: Dictionary) -> void:
	Powder.ignite(p.xf.origin, 1.8, source)
	p.on_fire = true
	p.fire_time = 0.0
	burning_list.append(p)
	heated_list.erase(p)
	var s: Structure = p.structure
	if not s.awake:
		Breakable.awaken(s)
	if Fx.inst != null and p.fire_slot < 0:
		var f: Fx.Flame = Fx.inst.acquire_flame(clampf(p.size_factor * 1.4, 1.0, 3.0))
		if f != null:
			f.part = p
			p.fire_slot = Fx.inst._flames.find(f)
	Events.fire_started.emit(p.xf.origin, source)
	if not source.is_empty():
		Scoring.on_fire_started(source)
	Sfx.play("fwump", p.xf.origin, 0.5, 0)
	if s.behavior != null:
		s.behavior.call("on_fire", s, p)

static func _stop_fire(p: Part, by_water: bool) -> void:
	var was_on: bool = p.on_fire
	p.on_fire = false
	p.burning = 0.0
	p.fire_time = 0.0
	burning_list.erase(p)
	heated_list.erase(p)
	if p.fire_slot >= 0 and Fx.inst != null:
		if p.fire_slot < Fx.inst._flames.size():
			var f: Fx.Flame = Fx.inst._flames[p.fire_slot]
			if f.part == p:
				Fx.inst.release_flame(f)
		p.fire_slot = -1
	if p.mesh != null:
		p.mesh.set_instance_shader_parameter("glow", 0.0)
	if was_on:
		Events.fire_out.emit(p.xf.origin, by_water)

static func extinguish_in_radius(center: Vector3, r: float, source: Dictionary = {}, wet_seconds: float = 0.0) -> int:
	var n: int = 0
	var list: Array[Part] = []
	var to_check: Array[Part] = []
	for p in burning_list:
		to_check.append(p)
	for p in heated_list:
		to_check.append(p)
	for p in to_check:
		if (p.xf.origin - center).length() <= r:
			list.append(p)
	for p in list:
		var was_on: bool = p.on_fire
		_stop_fire(p, true)
		if was_on:
			n += 1
			Fx.burst("steam", p.xf.origin, Color(0, 0, 0, -1), 0.4)
			if not source.is_empty():
				Scoring.on_fire_extinguished(source)
	if wet_seconds > 0.0:
		set_wet(center, r, wet_seconds)
	# burning catapults / settlers / animals in the water's reach
	for pl in Game.players:
		for c in pl.catapults:
			if not is_instance_valid(c):
				continue
			var cat: Catapult = c as Catapult
			if cat.burning and cat.global_pos().distance_to(center) <= r + 1.0:
				cat.extinguish()
				n += 1
				if not source.is_empty():
					Scoring.on_fire_extinguished(source)
	for st in Settler.all:
		if st.state == Settler.State.BURNING and st.global_pos().distance_to(center) <= r + 1.0:
			st.extinguish()
	# ground fires
	var gi: int = ground_fires.size() - 1
	while gi >= 0:
		var g: GroundFire = ground_fires[gi]
		if (g.pos - center).length() <= r:
			_end_ground_fire(g)
			ground_fires.remove_at(gi)
			n += 1
		gi -= 1
	return n

static func set_wet(center: Vector3, r: float, seconds: float) -> void:
	for s in Breakable.structures:
		if not s.aabb.grow(r).has_point(center):
			continue
		for p in s.parts:
			if p.state != Part.State.DEAD and p.mat.flammability > 0.0 and (p.xf.origin - center).length() <= r:
				p.wet = maxf(p.wet, seconds)
				if p.mesh != null:
					p.mesh.set_instance_shader_parameter("wet", 1.0)

## Ignite all flammable parts within radius (falloff optional)
static func ignite_in_radius(center: Vector3, r: float, amount: float, source: Dictionary = {}, falloff: bool = true) -> void:
	Powder.ignite(center, r * 0.9, source)
	if amount >= 0.5:
		for pl in Game.players:
			for c in pl.catapults:
				if is_instance_valid(c) and not (c as Catapult).destroyed and (c as Catapult).global_pos().distance_to(center) <= r * 0.9:
					(c as Catapult).ignite()
	Breakable.awaken_in_radius(center, r)
	for s in Breakable.structures:
		if not s.aabb.grow(r).has_point(center):
			continue
		for p in s.parts:
			if p.state == Part.State.DEAD or p.mat.flammability <= 0.0:
				continue
			var d: float = (p.xf.origin - center).length()
			if d <= r:
				var f: float = (1.0 - d / r * 0.6) if falloff else 1.0
				ignite(p, amount * f, source)
	spawn_ground_fire(center, source)

static func fires_near(pos: Vector3, r: float) -> bool:
	var k0x: int = floori((pos.x - r) / 3.0)
	var k1x: int = floori((pos.x + r) / 3.0)
	var k0z: int = floori((pos.z - r) / 3.0)
	var k1z: int = floori((pos.z + r) / 3.0)
	for x in range(k0x, k1x + 1):
		for z in range(k0z, k1z + 1):
			if burn_grid.has(Vector2i(x, z)):
				return true
	return false

## Is something burning within `r` metres (a burning part or a ground fire)? Precise version of fires_near()
static func fire_within(pos: Vector3, r: float) -> bool:
	if not fires_near(pos, r):
		return false
	var r2: float = r * r
	for p in burning_list:
		# horizontally close, and not more than 3 m above (flames of a roof lick down walls, they do not reach 10 m)
		if p.state != Part.State.DEAD and Util.dist_xz(p.xf.origin, pos) <= r and p.xf.origin.y - pos.y <= 3.0 and pos.y - p.xf.origin.y <= 2.0:
			return true
	for g in ground_fires:
		if g.pos.distance_squared_to(pos) <= r2:
			return true
	return false

static func burning_count() -> int:
	return burning_list.size()

static func in_village_count(owner_id: int) -> int:
	var n: int = 0
	for p in burning_list:
		if p.structure.owner_id == owner_id:
			n += 1
	return n

static func fire_center(owner_id: int) -> Vector3:
	var c := Vector3.ZERO
	var n: int = 0
	for p in burning_list:
		if p.structure.owner_id == owner_id:
			c += p.xf.origin
			n += 1
	if n == 0:
		return Vector3.INF
	return c / float(n)

# ------------------------------------------------------------------ ground fires
static func spawn_ground_fire(pos: Vector3, source: Dictionary = {}, dur: float = 3.0) -> void:
	if ground_fires.size() >= 30 or Terrain.is_water(pos.x, pos.z) or raining:
		return
	for g in ground_fires:
		if (g.pos - pos).length() < 1.6:
			g.t = 0.0
			return
	var gf := GroundFire.new()
	gf.pos = Vector3(pos.x, Terrain.h(pos.x, pos.z), pos.z)
	gf.dur = dur
	gf.source = source
	if Fx.inst != null:
		gf.flame = Fx.inst.acquire_flame(1.5)
		if gf.flame != null:
			gf.flame.part = null
			gf.flame.static_pos = gf.pos + Vector3(0, 0.3, 0)
	ground_fires.append(gf)
	if Terrain.current != null:
		Terrain.current.paint(gf.pos, 2.6, 0.0, 0.85)

static func _end_ground_fire(g: GroundFire) -> void:
	if g.flame != null and Fx.inst != null:
		Fx.inst.release_flame(g.flame)
		g.flame = null

# ------------------------------------------------------------------ update
static func update(dt: float) -> void:
	_time += dt
	_tick += dt
	# glow flicker for burning parts is cheap: do it every frame for a few
	if _tick < Cfg.FIRE_TICK:
		return
	var step: float = _tick
	_tick = 0.0
	_fire_tick(step)

static func _fire_tick(step: float) -> void:
	burn_grid.clear()
	var wind: Vector2 = Game.wind
	var wind_speed: float = wind.length()
	var wind_dir := Vector2.ZERO if wind_speed < 0.01 else wind / wind_speed
	# ---- burning parts (budgeted round-robin)
	var count: int = burning_list.size()
	var budget: int = mini(count, 200)
	var neighbors: Array[Part] = []
	var to_ignite: Array = []
	for k in budget:
		var idx: int = (_rr + k) % count
		if idx >= burning_list.size():
			break
		var p: Part = burning_list[idx]
		if p.state == Part.State.DEAD or not p.on_fire:
			continue
		p.fire_time += step
		# rain extinguishes
		if raining and rng.chance(0.25):
			to_ignite.append([p, -1.0])
			continue
		var src: Dictionary = Damage.source_for(p.structure)
		# spread
		if not raining:
			_nearby(p.xf.origin, Cfg.FIRE_SPREAD_RADIUS, neighbors)
			for q in neighbors:
				if q == p or q.on_fire or q.wet > 0.0:
					continue
				var dirv: Vector3 = q.xf.origin - p.xf.origin
				var boost: float = 1.0
				if wind_speed > 0.01 and Vector2(dirv.x, dirv.z).dot(wind_dir) > 0.0:
					boost = 1.0 + wind_speed * 0.05
				if dirv.y > 0.5:
					boost *= 1.5
				var add: float = q.mat.flammability * SPREAD_RATE * step * boost
				to_ignite.append([q, add, src])
		# ground fire under burning parts
		if p.xf.origin.y < 3.0 and rng.chance(0.3 * step) and not Terrain.is_water(p.xf.origin.x, p.xf.origin.z):
			spawn_ground_fire(p.xf.origin, src)
	_rr = (_rr + budget) % maxi(count, 1)
	for item in to_ignite:
		var pi: Part = item[0] as Part
		var amt: float = float(item[1])
		if amt < 0.0:
			_stop_fire(pi, true)
			Fx.burst("steam", pi.xf.origin, Color(0, 0, 0, -1), 0.3)
		else:
			ignite(pi, amt, item[2] as Dictionary)
	# ---- damage + explosive triggers + visuals for all burning parts
	var i: int = burning_list.size() - 1
	var explode_list: Array[Part] = []
	while i >= 0:
		# damaging parts below can remove entries from the list (fire on breaking parts): keep the index valid
		if i >= burning_list.size():
			i = burning_list.size() - 1
			continue
		var p2: Part = burning_list[i]
		if p2.state == Part.State.DEAD or not p2.on_fire:
			burning_list.remove_at(i)
			i -= 1
			continue
		burn_grid[Vector2i(floori(p2.xf.origin.x / 3.0), floori(p2.xf.origin.z / 3.0))] = true
		p2.charred = minf(p2.charred + step * 0.12, 1.0)
		if p2.mesh != null and p2.shape != "compound":
			p2.mesh.set_instance_shader_parameter("tint", p2.color.lerp(Color(0.06, 0.05, 0.05), p2.charred * 0.85))
			p2.mesh.set_instance_shader_parameter("glow", 0.35 + 0.25 * sin(_time * 9.0 + float(p2.id)))
		var dmg: float = p2.mat.burn_hp * BURN_MULT * step
		if p2.mat.burn_hp > 0.0:
			Damage.damage_part(p2, dmg, Damage.source_for(p2.structure), Vector3.UP)
		if p2.state != Part.State.DEAD and p2.prop_kind == "barrel_powder" and p2.fire_time >= 2.0:
			explode_list.append(p2)
		elif p2.state != Part.State.DEAD and p2.fire_time >= BURN_TIME:
			# burnt out: half as long as before, but it hurt more
			p2.charred = 1.0
			_stop_fire(p2, false)
		i -= 1
	for e in explode_list:
		if e.state != Part.State.DEAD:
			Props.detonate_powder(e, Damage.source_for(e.structure))
	# ---- heated (not on fire) parts cool down
	var hi: int = heated_list.size() - 1
	while hi >= 0:
		var hp: Part = heated_list[hi]
		if hp.state == Part.State.DEAD or hp.on_fire:
			heated_list.remove_at(hi)
		else:
			hp.burning = maxf(hp.burning - 0.15 * step, 0.0)
			if hp.burning <= 0.0:
				heated_list.remove_at(hi)
		hi -= 1
	# ---- wetness decay
	for s in Breakable.structures:
		if not s.awake:
			continue
		for p3 in s.parts:
			if p3.wet > 0.0:
				p3.wet = maxf(p3.wet - step, 0.0)
				if p3.wet <= 0.0 and p3.mesh != null:
					p3.mesh.set_instance_shader_parameter("wet", 0.0)
	# ---- ground fires
	var gi: int = ground_fires.size() - 1
	while gi >= 0:
		var g: GroundFire = ground_fires[gi]
		g.t += step
		burn_grid[Vector2i(floori(g.pos.x / 3.0), floori(g.pos.z / 3.0))] = true
		if raining or g.t >= g.dur:
			_end_ground_fire(g)
			ground_fires.remove_at(gi)
			gi -= 1
			continue
		Powder.ignite(g.pos, 1.6, g.source)
		# ignite flammable parts touching + spread within 2 m
		_nearby(g.pos + Vector3.UP * 0.5, 2.0, neighbors)
		for q2 in neighbors:
			ignite(q2, 0.45 * step, g.source)
		if g.t < g.dur * 0.6 and rng.chance(0.05 * step):
			var ang: float = rng.range_f(0.0, TAU)
			spawn_ground_fire(g.pos + Vector3(cos(ang), 0, sin(ang)) * 1.8, g.source, g.dur * 0.7)
		gi -= 1
	# ---- flame lights on the biggest fires
	_update_lights()

static func _update_lights() -> void:
	if light_root == null:
		return
	var want: int = mini(Quality.max_lights, burning_list.size())
	while _lights.size() < want:
		var l := OmniLight3D.new()
		l.light_color = Color("#ff8a3a")
		l.omni_range = 12.0
		l.light_energy = 1.5
		l.shadow_enabled = false
		l.light_bake_mode = Light3D.BAKE_DISABLED       # short-lived lights must not feed the blocky SDFGI cells
		l.light_volumetric_fog_energy = 0.0        # fire / flashes must not turn the (blocky) volumetric fog into a yellow haze
		light_root.add_child(l)
		_lights.append(l)
	if burning_list.is_empty():
		for l2 in _lights:
			l2.visible = false
		return
	# choose the largest burning parts
	var best: Array[Part] = []
	for p in burning_list:
		if best.size() < want:
			best.append(p)
		else:
			var wi: int = 0
			for j in best.size():
				if best[j].volume < best[wi].volume:
					wi = j
			if p.volume > best[wi].volume:
				best[wi] = p
	for k in _lights.size():
		if k < best.size():
			_lights[k].visible = true
			_lights[k].global_position = best[k].xf.origin + Vector3(0, 1.2, 0)
			_lights[k].light_energy = 1.9 + 0.6 * sin(_time * 7.0 + float(k))
		else:
			_lights[k].visible = false
