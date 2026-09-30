class_name RandomEvents
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Random events (spec 11.5): dragon, cheese meteor, cow rain, earthquake, goose army, tax collector,
## fireworks accident, wizard bubble, flood. Chance 12% at each TURN_END with a cooldown of 3 turns.

const IDS: Array[String] = ["dragon", "cheese_meteor", "cow_rain", "earthquake", "goose_army", "tax_collector", "fireworks_accident", "bubble", "flood"]
const WEIGHTS: Array = [25.0, 10.0, 12.0, 10.0, 8.0, 8.0, 8.0, 6.0, 5.0]

static var world: GameWorld
static var cam: CameraRig
static var fx_root: Node3D
static var active: Array[Dictionary] = []
static var cooldown: int = 0
static var rng: Rng = Rng.new(55)
static var debug_cycle: int = 0
static var flood_base: float = Cfg.WATER_LEVEL

static func reset() -> void:
	for e in active:
		_free_event(e)
	active.clear()
	cooldown = 0
	if Terrain.current != null:
		Terrain.current.set_water_level(Cfg.WATER_LEVEL)

static func busy() -> bool:
	return not active.is_empty()

static func _free_event(e: Dictionary) -> void:
	for k in ["node", "sphere"]:
		if e.has(k) and is_instance_valid(e[k]):
			(e[k] as Node).queue_free()
	if e.has("geese"):
		for g in (e["geese"] as Array):
			if is_instance_valid(g):
				(g as Animal).remove_from_world()
	if e.has("rockets"):
		for r in (e["rockets"] as Array):
			var rd: Dictionary = r as Dictionary
			if is_instance_valid(rd["node"]):
				(rd["node"] as Node).queue_free()
			if is_instance_valid(rd["trail"]):
				(rd["trail"] as Node).queue_free()

## Called by the turn manager at TURN_END
static func turn_end_check() -> void:
	if cooldown > 0:
		cooldown -= 1
	if not Game.events_on:
		return
	if cooldown > 0 or not Game.rng_battle.chance(0.12):
		return
	var id: String = IDS[Game.rng_battle.pick_weighted(WEIGHTS)]
	if id == "flood" and not _flood_possible():
		return
	trigger(id)

static func _flood_possible() -> bool:
	for p in Game.players:
		if not p.eliminated and p.village_center.y < Cfg.WATER_LEVEL + 2.5:
			return true
	return false

static func debug_next() -> void:
	trigger(IDS[debug_cycle % IDS.size()])
	debug_cycle += 1

static func trigger(id: String) -> void:
	cooldown = 3
	Events.event_start.emit(id)
	Events.banner.emit(I18n.t("event." + id), "event")
	Sfx.play("stinger_event", Vector3.INF, 0.9, 5)
	var e: Dictionary = {"id": id, "t": 0.0}
	match id:
		"dragon":
			_start_dragon(e)
		"cheese_meteor":
			_start_meteor(e)
		"cow_rain":
			_start_cow_rain(e)
		"earthquake":
			_start_quake(e)
		"goose_army":
			_start_geese(e)
		"tax_collector":
			_start_tax(e)
		"fireworks_accident":
			_start_fireworks(e)
		"bubble":
			_start_bubble(e)
		"flood":
			_start_flood(e)
	active.append(e)

static func _random_village() -> PlayerData:
	var living: Array[PlayerData] = Game.living_players()
	if living.is_empty():
		return Game.players[0]
	return living[rng.range_i(0, living.size() - 1)]

static func _village_point(p: PlayerData, radius: float = 14.0) -> Vector3:
	var off: Vector2 = rng.in_circle(radius)
	var v := Vector3(p.village_center.x + off.x, 0, p.village_center.z + off.y)
	v.y = Terrain.h(v.x, v.z)
	return v

static func tick(dt: float) -> void:
	var i: int = active.size() - 1
	while i >= 0:
		var e: Dictionary = active[i]
		e["t"] = float(e["t"]) + dt
		var done: bool = false
		match str(e["id"]):
			"dragon":
				done = _tick_dragon(e, dt)
			"cheese_meteor":
				done = _tick_meteor(e, dt)
			"cow_rain":
				done = _tick_cow_rain(e, dt)
			"earthquake":
				done = _tick_quake(e, dt)
			"goose_army":
				done = _tick_geese(e, dt)
			"tax_collector":
				done = _tick_tax(e, dt)
			"fireworks_accident":
				done = _tick_fireworks(e, dt)
			"bubble":
				done = _tick_bubble(e, dt)
			"flood":
				done = _tick_flood(e, dt)
		if done:
			_free_event(e)
			active.remove_at(i)
		i -= 1

# ------------------------------------------------------------------ dragon
static func _dragon_model() -> Node3D:
	var root := Node3D.new()
	var green: Color = Color("#3fae4a")
	var dark: Color = Color("#2a7d36")
	var buf := MeshGen.Buf.new()
	MeshGen.add_ellipsoid(buf, Vector3(1.4, 1.1, 2.6), Transform3D(Basis(), Vector3.ZERO), green, 0.06, 7, 10)
	# neck + head
	MeshGen.add_frustum(buf, 0.55, 0.4, 2.4, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.6), Vector3(0, 0.6, -2.7)), green, 0.05)
	MeshGen.add_ellipsoid(buf, Vector3(0.7, 0.55, 1.0), Transform3D(Basis(), Vector3(0, 1.4, -4.1)), green, 0.05, 6, 8)
	MeshGen.add_box(buf, Vector3(0.5, 0.25, 0.7), Transform3D(Basis(), Vector3(0, 1.2, -4.9)), dark, 0.03)
	for sx in [-0.3, 0.3]:
		MeshGen.add_box(buf, Vector3(0.14, 0.5, 0.14), Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3((sx as float), 2.0, -3.9)), Color("#f0e8c0"), 0.02)
		MeshGen.add_sphere(buf, 0.12, Transform3D(Basis(), Vector3((sx as float) * 1.6, 1.55, -4.5)), Color("#ffe14a"), 0.0, 4, 6)
	# tail (tapered segments)
	for k in 5:
		var r: float = 0.55 - float(k) * 0.09
		MeshGen.add_ellipsoid(buf, Vector3(r, r, 0.9), Transform3D(Basis(), Vector3(0, -0.1 - float(k) * 0.05, 2.9 + float(k) * 1.0)), dark if k % 2 == 0 else green, 0.04, 5, 7)
	# back spikes
	for k in 7:
		MeshGen.add_frustum(buf, 0.18, 0.02, 0.5, 5, Transform3D(Basis(), Vector3(0, 1.2, -1.8 + float(k) * 0.7)), Color("#c0392b"), 0.02)
	var body := MeshInstance3D.new()
	body.mesh = buf.to_mesh()
	body.material_override = Toon.main()
	root.add_child(body)
	# wings (flap)
	for side in [-1.0, 1.0]:
		var wing_pivot := Node3D.new()
		wing_pivot.name = "WingL" if (side as float) < 0.0 else "WingR"
		wing_pivot.position = Vector3((side as float) * 0.9, 0.7, -0.5)
		var wb := MeshGen.Buf.new()
		MeshGen.add_box(wb, Vector3(3.2, 0.12, 0.2), Transform3D(Basis(), Vector3((side as float) * 1.6, 0.0, 0.0)), dark, 0.03)
		MeshGen.add_box(wb, Vector3(3.0, 0.06, 2.2), Transform3D(Basis(), Vector3((side as float) * 1.7, -0.05, 1.0)), Color("#e05a3a"), 0.03)
		var wm := MeshInstance3D.new()
		wm.mesh = wb.to_mesh()
		wm.material_override = Toon.main()
		wing_pivot.add_child(wm)
		root.add_child(wing_pivot)
	return root

static func _start_dragon(e: Dictionary) -> void:
	var dr: Node3D = _dragon_model()
	fx_root.add_child(dr)
	e["node"] = dr
	var r: float = world.map.map_radius + 40.0
	var a: float = rng.range_f(0.0, TAU)
	var start := Vector3(cos(a) * r, 26.0, sin(a) * r)
	var target_village: PlayerData = _random_village()
	var mid: Vector3 = target_village.village_center + Vector3(rng.range_f(-6, 6), 26.0, rng.range_f(-6, 6))
	var endp := Vector3(-cos(a) * r * 0.9 + rng.range_f(-30, 30), 28.0, -sin(a) * r * 0.9 + rng.range_f(-30, 30))
	# curve: quadratic bezier through the target village
	var ctrl: Vector3 = mid * 2.0 - (start + endp) * 0.5
	e["p0"] = start
	e["p1"] = ctrl
	e["p2"] = endp
	e["village"] = target_village.id
	e["breaths"] = 0
	e["next_breath"] = 3.2
	e["dur"] = 8.0
	Sfx.play("moo", start, 1.0, 5)   # placeholder roar
	for st in Settler.all:
		if rng.chance(0.4):
			Speech.say_random("speech.dragon", st, st, rng)

static func _bez(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return p0 * u * u + p1 * 2.0 * u * t + p2 * t * t

static func _tick_dragon(e: Dictionary, _dt: float) -> bool:
	var dr: Node3D = e["node"] as Node3D
	var t: float = clampf(float(e["t"]) / float(e["dur"]), 0.0, 1.0)
	var p0: Vector3 = e["p0"] as Vector3
	var p1: Vector3 = e["p1"] as Vector3
	var p2: Vector3 = e["p2"] as Vector3
	var pos: Vector3 = _bez(p0, p1, p2, t)
	var ahead: Vector3 = _bez(p0, p1, p2, minf(t + 0.02, 1.0))
	dr.global_position = pos
	var d: Vector3 = ahead - pos
	if d.length() > 0.01:
		# model faces -Z
		dr.look_at(pos + d, Vector3.UP)
	var flap: float = sin(float(e["t"]) * 9.0) * 0.6
	var wl: Node3D = dr.get_node("WingL") as Node3D
	var wr: Node3D = dr.get_node("WingR") as Node3D
	wl.rotation.z = -flap
	wr.rotation.z = flap
	# breaths: every 0.6 s, 3 times near the target village
	if int(e["breaths"]) < 3 and float(e["t"]) >= float(e["next_breath"]):
		e["breaths"] = int(e["breaths"]) + 1
		e["next_breath"] = float(e["next_breath"]) + 0.6
		var v: PlayerData = Game.player(int(e["village"]))
		var tgt: Vector3 = _village_point(v, 13.0)
		_dragon_breath(pos + d.normalized() * 4.5 + Vector3(0, 0.5, 0), tgt)
	return t >= 1.0

static func _dragon_breath(from: Vector3, target: Vector3) -> void:
	var steps: int = 6
	for k in steps:
		var p: Vector3 = from.lerp(target, float(k) / float(steps - 1))
		Fx.burst("flame", p, Color(0, 0, 0, -1), 0.7, (target - from).normalized())
	Fx.burst("flame", target + Vector3.UP * 0.5, Color(0, 0, 0, -1), 1.0)
	Fx.burst("smoke", target + Vector3.UP * 1.0, Color(0, 0, 0, -1), 0.6)
	Fire.ignite_in_radius(target, 4.0, 1.0, {})
	Fire.spawn_ground_fire(target, {}, 3.5)
	Sfx.play("fwump", target, 1.0, 4)
	Events.camera_shake.emit(0.2)
	Fx.comic_kind("fire", target + Vector3.UP * 3.0)

# ------------------------------------------------------------------ cheese meteor
static func _start_meteor(e: Dictionary) -> void:
	var v: PlayerData = _random_village()
	var tgt: Vector3 = _village_point(v, 12.0)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshGen.sphere_mesh(1.4, 8, 12)
	mi.material_override = Toon.emissive(Color("#ffd54a"), 1.5)
	fx_root.add_child(mi)
	e["node"] = mi
	e["target"] = tgt
	e["pos"] = tgt + Vector3(30.0, 110.0, 25.0)
	var tr := Trail.new()
	tr.max_points = 40
	tr.width = 1.2
	tr.color = Color(1.0, 0.85, 0.2, 0.95)
	fx_root.add_child(tr)
	e["trail"] = tr

static func _tick_meteor(e: Dictionary, dt: float) -> bool:
	var tgt: Vector3 = e["target"] as Vector3
	var pos: Vector3 = e["pos"] as Vector3
	var dir: Vector3 = (tgt - pos).normalized()
	pos += dir * 62.0 * dt
	e["pos"] = pos
	(e["node"] as Node3D).global_position = pos
	(e["node"] as Node3D).rotate_y(dt * 3.0)
	if e.has("trail"):
		(e["trail"] as Trail).push(pos)
	if pos.distance_to(tgt) < 2.0 or pos.y <= tgt.y + 0.5:
		Explosion.explode(tgt, 6.0, 500.0, {"source": {}, "sound": "bigboom", "color": Color("#ffd54a")})
		Stink.spawn(tgt, 10.0)
		Fx.burst("cheese", tgt + Vector3.UP, Color(0, 0, 0, -1), 1.0)
		for k in 4:
			var a: float = float(k) * 1.6 + rng.range_f(-0.3, 0.3)
			Props.spawn("cheese_chunk", tgt + Vector3(cos(a) * 3.0, 0, sin(a) * 3.0), rng.range_f(0, TAU), -1, rng, Color.WHITE, 0.8)
		if e.has("trail"):
			(e["trail"] as Trail).stop()
			e.erase("trail")
		return true
	return false

# ------------------------------------------------------------------ cow rain
static func _start_cow_rain(e: Dictionary) -> void:
	var n: int = rng.range_i(6, 10)
	var list: Array = []
	for i in n:
		var v: PlayerData = _random_village()
		var p: Vector3 = _village_point(v, 18.0)
		list.append({"pos": p + Vector3(0, 40.0, 0), "delay": rng.range_f(0.0, 3.2), "spawned": false})
	e["cows"] = list

static func _tick_cow_rain(e: Dictionary, _dt: float) -> bool:
	var all_spawned: bool = true
	for c in (e["cows"] as Array):
		var cd: Dictionary = c as Dictionary
		if not bool(cd["spawned"]):
			all_spawned = false
			if float(e["t"]) >= float(cd["delay"]):
				cd["spawned"] = true
				Projectile.spawn_event_cow(cd["pos"] as Vector3, Vector3(0, -6.0, 0))
				Sfx.play("moo", cd["pos"] as Vector3, 0.8, 3)
	return all_spawned and float(e["t"]) > 4.0

# ------------------------------------------------------------------ earthquake
static func _start_quake(e: Dictionary) -> void:
	e["fired"] = false
	Sfx.play("thunder", Vector3.INF, 1.0, 5)
	Fx.comic_kind("stone", cam.focus + Vector3.UP * 5.0 if cam != null else Vector3.UP * 5.0)

static func _tick_quake(e: Dictionary, _dt: float) -> bool:
	var t: float = float(e["t"])
	Events.camera_shake.emit(0.5)
	if not bool(e["fired"]) and t > 0.4:
		e["fired"] = true
		for s in Breakable.structures:
			if s.free_parts and not s.destroyed:
				for p in s.parts:
					if p.state == Part.State.FREE:
						PhysWorld.apply_impulse(p.body_id, Vector3(rng.range_f(-1, 1), rng.range_f(0.5, 1.5), rng.range_f(-1, 1)) * p.mass * 2.5)
			elif s.kind in ["watchtower", "church", "windmill", "watertower"] and not s.destroyed:
				if rng.chance(0.35):
					Breakable.awaken(s)
					# release the upper half so the tower topples in one direction
					var dir := Vector3(rng.range_f(-1, 1), 0, rng.range_f(-1, 1)).normalized()
					for p2 in s.parts:
						if p2.state == Part.State.FROZEN:
							var rel: float = (p2.xf.origin.y - s.aabb.position.y) / maxf(s.aabb.size.y, 1.0)
							if rel > 0.15:
								Breakable.release_part(p2, dir * (3.0 + rel * 4.0))
					Fx.burst("dust", s.center, Color("#9a9a9a"), 1.0)
		for st in Settler.all:
			st.panic_from(st.global_pos() + Vector3(rng.range_f(-3, 3), 0, rng.range_f(-3, 3)), 3.0)
	return t > 3.0

# ------------------------------------------------------------------ geese
static func _start_geese(e: Dictionary) -> void:
	var v: PlayerData = _random_village()
	var a: float = rng.range_f(0.0, TAU)
	var dir := Vector3(cos(a), 0, sin(a))
	var start: Vector3 = v.village_center - dir * (world.map.map_radius * 0.9)
	var geese: Array = []
	var perp := Vector3(-dir.z, 0, dir.x)
	for i in 20:
		var off: float = rng.range_f(-9.0, 9.0)
		var back: float = rng.range_f(0.0, 14.0)
		var p: Vector3 = start + perp * off - dir * back
		var g: Animal = Animal.spawn("goose", Vector3(p.x, 0, p.z), -1, 1.0, rng)
		g.rotation.y = atan2(dir.x, dir.z)
		geese.append(g)
	e["geese"] = geese
	e["dir"] = dir
	Sfx.play("quack", start, 1.0, 3)

static func _tick_geese(e: Dictionary, dt: float) -> bool:
	var dir: Vector3 = e["dir"] as Vector3
	var t: float = float(e["t"])
	for g in (e["geese"] as Array):
		var goose: Animal = g as Animal
		if not is_instance_valid(goose):
			continue
		goose.state = Animal.State.IDLE   # keep the wander AI quiet
		goose._timer = 10.0
		var pos: Vector3 = goose.position + dir * 7.5 * dt
		pos.y = Terrain.h(pos.x, pos.z) if not Terrain.is_water(pos.x, pos.z) else WaterSys.water_y() - 0.05
		goose.position = pos
		goose.body_node.position.y = absf(sin(t * 14.0 + goose.position.x)) * 0.12
		# knock settlers and light props over
		for st in Settler.all:
			if st.state != Settler.State.RAGDOLL and st.state != Settler.State.DEAD and st.state != Settler.State.GONE:
				if (st.global_pos() - pos).length() < 1.1:
					st.hurt(4.0, {}, (dir + Vector3.UP * 0.8).normalized() * 6.0, true)
		if rng.chance(dt * 0.4):
			Sfx.play("quack", pos, 0.5, 0)
	# light props
	for s in Breakable.structures:
		if s.free_parts and not s.destroyed:
			for p in s.parts:
				if p.state == Part.State.FREE and p.mass < 60.0:
					for g2 in (e["geese"] as Array):
						if is_instance_valid(g2) and ((g2 as Animal).position - p.xf.origin).length() < 1.0:
							PhysWorld.apply_impulse(p.body_id, dir * p.mass * 4.0 + Vector3.UP * p.mass * 2.0)
							break
	return t > 10.0

# ------------------------------------------------------------------ tax collector
static func _start_tax(e: Dictionary) -> void:
	var v: PlayerData = _random_village()
	var st: Settler = world.spawn_settler(v.id, v.village_center + Vector3(Cfg.ZONE_RADIUS + 12.0, 0, 0), 5.0)
	if st == null:
		e["done"] = true
		return
	st.torso.mesh = Settler._torso_mesh(Color("#ffd700"), Color("#ffffff"))
	st.is_tax = true
	st.position = Terrain.ground(v.village_center + Vector3(Cfg.ZONE_RADIUS + 14.0, 0, rng.range_f(-6, 6)))
	e["settler"] = st
	e["village"] = v.id
	e["arrived"] = false
	Speech.say(I18n.t("banner.tax"), st, st, 2.0, 2.6)

static func _tick_tax(e: Dictionary, _dt: float) -> bool:
	if e.has("done"):
		return true
	var st: Settler = e["settler"] as Settler
	if not is_instance_valid(st) or st.state == Settler.State.DEAD or st.state == Settler.State.GONE:
		return true
	var v: PlayerData = Game.player(int(e["village"]))
	if not bool(e["arrived"]):
		# walk to the village center (steered by the settler walker)
		st._target = v.village_center
		st.state = Settler.State.WANDER
		st._timer = 8.0
		st._speed = 1.6
		if Util.dist_xz(st.global_pos(), v.village_center) < 3.0:
			e["arrived"] = true
			e["arrive_t"] = float(e["t"])
			Speech.say(I18n.t("banner.tax"), st, st, 2.5, 2.6)
			Sfx.play("stinger_event", st.global_pos(), 0.6, 2)
			var count: int = 0
			for s2 in Settler.all:
				if s2.owner_id == v.id and s2 != st and s2.state != Settler.State.DEAD and count < 3:
					Fx.burst("coin", s2.global_pos() + Vector3.UP * 1.5, Color(0, 0, 0, -1), 0.8)
					count += 1
	else:
		if float(e["t"]) - float(e["arrive_t"]) > 3.5:
			# walk away
			st._target = v.village_center + Vector3(40, 0, 0)
			st.state = Settler.State.WANDER
			st._timer = 8.0
			if Util.dist_xz(st.global_pos(), v.village_center) > Cfg.ZONE_RADIUS + 10.0:
				st.state = Settler.State.GONE
				return true
	return float(e["t"]) > 60.0

# ------------------------------------------------------------------ fireworks accident
static func _start_fireworks(e: Dictionary) -> void:
	var v: PlayerData = _random_village()
	var origin: Vector3 = _village_point(v, 10.0) + Vector3.UP * 1.0
	var rockets: Array = []
	for i in 15:
		var a: float = rng.range_f(0.0, TAU)
		var vel := Vector3(cos(a) * rng.range_f(6.0, 16.0), rng.range_f(14.0, 24.0), sin(a) * rng.range_f(6.0, 16.0))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshGen.sphere_mesh(0.18, 5, 8)
		mi.material_override = Toon.emissive(Color("#ff5b5b") if i % 2 == 0 else Color("#ffd34a"), 1.5)
		fx_root.add_child(mi)
		mi.global_position = origin
		var tr := Trail.new()
		tr.max_points = 16
		tr.width = 0.16
		tr.color = Color(1.0, 0.7, 0.3, 0.9)
		fx_root.add_child(tr)
		rockets.append({"node": mi, "trail": tr, "pos": origin, "vel": vel, "delay": rng.range_f(0.0, 1.0), "alive": true})
	e["rockets"] = rockets
	Sfx.play("stinger_event", origin, 0.8, 3)

static func _tick_fireworks(e: Dictionary, dt: float) -> bool:
	var alive: int = 0
	for r in (e["rockets"] as Array):
		var rd: Dictionary = r as Dictionary
		if not bool(rd["alive"]):
			continue
		if float(e["t"]) < float(rd["delay"]):
			alive += 1
			continue
		var pos: Vector3 = rd["pos"] as Vector3
		var vel: Vector3 = rd["vel"] as Vector3
		vel.y += Cfg.GRAVITY * 0.6 * dt
		var np: Vector3 = pos + vel * dt
		var hit: bool = np.y < Terrain.h(np.x, np.z)
		if not hit:
			var rc: Dictionary = PhysWorld.raycast(pos, (np - pos).normalized(), pos.distance_to(np) + 0.2, Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP)
			hit = not rc.is_empty()
		rd["pos"] = np
		rd["vel"] = vel
		(rd["node"] as Node3D).global_position = np
		(rd["trail"] as Trail).push(np)
		if hit or float(e["t"]) - float(rd["delay"]) > 6.0:
			rd["alive"] = false
			Explosion.explode(np, 2.0, 80.0, {"source": {}, "sound": "boom", "color": Color("#ff9a3a"), "no_crater": true})
			Fx.burst("spark", np, Color(0, 0, 0, -1), 1.0)
			Fx.burst("confetti", np + Vector3.UP, Color(0, 0, 0, -1), 0.3)
			(rd["node"] as Node3D).visible = false
			(rd["trail"] as Trail).stop()
		else:
			alive += 1
	return alive == 0

# ------------------------------------------------------------------ wizard bubble
static func _start_bubble(e: Dictionary) -> void:
	var pool: Array[Settler] = []
	for s in Settler.all:
		if s.state != Settler.State.DEAD and s.state != Settler.State.GONE and s.state != Settler.State.RAGDOLL and not s.is_archer:
			pool.append(s)
	if pool.size() < 2:
		e["done"] = true
		return
	var lead: Settler = pool[rng.range_i(0, pool.size() - 1)]
	var group: Array[Settler] = []
	for s2 in pool:
		if s2.owner_id == lead.owner_id and Util.dist_xz(s2.global_pos(), lead.global_pos()) < 6.0 and group.size() < 5:
			group.append(s2)
	var center: Vector3 = lead.global_pos()
	var sphere := MeshInstance3D.new()
	sphere.mesh = MeshGen.sphere_mesh(4.0, 10, 16)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.7, 0.9, 1.0, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	sphere.material_override = m
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(sphere)
	sphere.global_position = center + Vector3.UP * 2.0
	e["sphere"] = sphere
	e["group"] = group
	e["center"] = center
	for s3 in group:
		s3.state = Settler.State.WORK
		s3._timer = 99.0
		Speech.say(I18n.t("speech.hit.0") if false else "…?", s3, s3, 2.0)

static func _tick_bubble(e: Dictionary, _dt: float) -> bool:
	if e.has("done"):
		return true
	var t: float = float(e["t"])
	var center: Vector3 = e["center"] as Vector3
	var lift: float = minf(t / 4.5, 1.0) * 8.0
	var sphere: MeshInstance3D = e["sphere"] as MeshInstance3D
	sphere.global_position = center + Vector3(0, 2.0 + lift, 0)
	for s in (e["group"] as Array):
		var st: Settler = s as Settler
		if is_instance_valid(st) and st.state == Settler.State.WORK:
			st.position.y = Terrain.h(st.position.x, st.position.z) + lift + 0.3
	if t > 5.0:
		Fx.burst("splash", sphere.global_position, Color("#bfe6ff"), 1.0)
		Fx.burst("confetti", sphere.global_position, Color(0, 0, 0, -1), 0.5)
		Sfx.play("pop", sphere.global_position, 1.0, 3)
		for s2 in (e["group"] as Array):
			var st2: Settler = s2 as Settler
			if is_instance_valid(st2) and st2.state == Settler.State.WORK:
				st2.hurt(1.0, {}, Vector3(rng.range_f(-2, 2), 0.5, rng.range_f(-2, 2)), true, true)
		return true
	return false

# ------------------------------------------------------------------ flood
static func _start_flood(_e: Dictionary) -> void:
	flood_base = Cfg.WATER_LEVEL
	Sfx.play("splash", Vector3.INF, 1.0, 4)

static func _tick_flood(e: Dictionary, dt: float) -> bool:
	var t: float = float(e["t"])
	var lvl: float = 0.0
	if t < 4.0:
		lvl = 1.2 * Util.smooth01(t / 4.0)
	elif t < 8.0:
		lvl = 1.2
	elif t < 16.0:
		lvl = 1.2 * (1.0 - Util.smooth01((t - 8.0) / 8.0))
	else:
		lvl = 0.0
	if Terrain.current != null:
		Terrain.current.set_water_level(flood_base + lvl)
	# fires on submerged parts go out
	if int(t * 2.0) != int((t - dt) * 2.0):
		var wy: float = flood_base + lvl
		var list: Array[Part] = []
		for p in Fire.burning_list:
			if p.xf.origin.y < wy:
				list.append(p)
		for p2 in list:
			Fire.extinguish_in_radius(p2.xf.origin, 0.5, {}, 0.0)
	if t >= 16.0:
		if Terrain.current != null:
			Terrain.current.set_water_level(flood_base)
		return true
	return false
