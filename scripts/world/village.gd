class_name Village
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Village generation (spec 8): mandatory + random buildings on ring slots, props around them,
## perimeter walls, animals and settlers. Everything seeded by the map RNG.

class Placed extends RefCounted:
	var id: String
	var pos: Vector2          # xz
	var radius: float
	var yaw: float
	var structure: Structure

static var smoke_sources: Array = []          # [{pos, s (Structure), t}]
static var gather_points: Dictionary = {}     # owner_id -> Vector3

static func reset() -> void:
	smoke_sources.clear()
	gather_points.clear()

## Generate the village of `player` at center `c`. Returns the list of placed buildings.
static func generate(player: PlayerData, c: Vector3, rng: Rng, world: Node) -> Array[Placed]:
	var placed: Array[Placed] = []
	var ctx := BuildContext.new()
	ctx.player_color = player.color
	ctx.owner_id = player.id
	var zone: float = Cfg.ZONE_RADIUS
	# ---- building list
	var list: Array[String] = ["well", "tavern"]
	list.append("church" if rng.chance(0.5) else "watchtower")
	for i in rng.range_i(2, 3):
		list.append("farmhouse")
	list.append("barn")
	list.append("flagpole")
	for i in rng.range_i(2, 3):
		list.append("stall")
	# random extras (3-5) with weights; powder store max 1, water tower max 1
	var extra_pool: Array[String] = ["blacksmith", "windmill", "stable", "granary", "powderstore", "watertower"]
	var weights: Array = [1.0, 1.0, 1.0, 1.0, 0.4, 0.8]
	var chosen: Dictionary = {}
	var n_extra: int = rng.range_i(3, 5)
	var guard: int = 0
	while chosen.size() < n_extra and guard < 60:
		guard += 1
		var k: int = rng.pick_weighted(weights)
		chosen[extra_pool[k]] = true
	for id in chosen:
		list.append(str(id))
	for i in rng.range_i(1, 2):
		list.append("outhouse")
	# ---- slots
	var slots: Array[Vector2] = []
	for i in 14:
		var a: float = (float(i) + rng.range_f(-0.15, 0.15)) / 14.0 * TAU + deg_to_rad(rng.range_f(-10.0, 10.0))
		var d: float = rng.range_f(9.0, 20.0)
		slots.append(Vector2(cos(a), sin(a)) * d)
	# sort by footprint (largest first), well first at the center
	var sorted_ids: Array[String] = []
	var fp: Dictionary = {}
	for id in list:
		fp[id] = float(Buildings.def(id)["footprint_radius"])
	sorted_ids = list.duplicate()
	sorted_ids.sort_custom(func(a: String, b: String) -> bool: return float(fp[a]) > float(fp[b]))
	sorted_ids.erase("well")
	sorted_ids.push_front("well")
	var used_slots: Array[int] = []
	for id in sorted_ids:
		var rad: float = float(fp[id])
		var pos2: Vector2 = Vector2.ZERO
		var found: bool = false
		if id == "well":
			var a2: float = rng.range_f(0.0, TAU)
			pos2 = Vector2(cos(a2), sin(a2)) * rng.range_f(0.0, 4.0)
			found = true
		elif id == "outhouse":
			# at the edge of the village
			for t in 20:
				var a3: float = rng.range_f(0.0, TAU)
				var p3: Vector2 = Vector2(cos(a3), sin(a3)) * rng.range_f(19.0, 21.0)
				if _free(placed, p3, rad, c, zone):
					pos2 = p3
					found = true
					break
		else:
			# best free slot (random order among the free ones), then random fallback positions
			var order: Array[int] = []
			for i in slots.size():
				if not used_slots.has(i):
					order.append(i)
			rng.shuffle(order)
			for si in order:
				if _free(placed, slots[si], rad, c, zone):
					pos2 = slots[si]
					used_slots.append(si)
					found = true
					break
			if not found:
				for t in 40:
					var a4: float = rng.range_f(0.0, TAU)
					var p4: Vector2 = Vector2(cos(a4), sin(a4)) * rng.range_f(8.0 + rad * 0.5, zone - rad * 0.4)
					if p4.length() > 7.0 + rad * 0.6 and _free(placed, p4, rad, c, zone):
						pos2 = p4
						found = true
						break
		if not found:
			continue
		var world_xz := Vector2(c.x + pos2.x, c.z + pos2.y)
		var to_center: Vector2 = Vector2(c.x, c.z) - world_xz
		var yaw: float = atan2(to_center.x, to_center.y) + deg_to_rad(rng.range_f(-15.0, 15.0))
		if id == "well" or id == "watertower" or id == "windmill":
			yaw = rng.range_f(0.0, TAU)
		yaw += float(Buildings.def(id).get("yaw_offset", 0.0))
		var pl := Placed.new()
		pl.id = id
		pl.pos = world_xz
		pl.radius = rad
		pl.yaw = yaw
		ctx.thatch_roof = rng.chance(0.5)
		var res: BuildResult = Buildings.build(id, ctx, rng)
		var gy: float = Terrain.h(world_xz.x, world_xz.y)
		var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(world_xz.x, gy, world_xz.y))
		pl.structure = Breakable.create(id, player.id, res, base)
		Specials.attach(pl.structure)
		_process_extras(pl.structure, res, base, player, rng, world)
		placed.append(pl)
	_register_obstacles(player, placed, c)
	# ---- perimeter walls (~40% coverage, one gap)
	_perimeter(player, placed, c, rng, ctx)
	# ---- props around buildings + scatter
	_props(player, placed, c, rng)
	# ---- footpaths (dirt)
	if Terrain.current != null:
		var center_pt: Vector3 = Vector3(c.x, 0, c.z)
		for pl2 in placed:
			var p3d := Vector3(pl2.pos.x, 0, pl2.pos.y)
			if pl2.id != "well":
				Terrain.current.paint_path(center_pt, p3d.move_toward(center_pt, pl2.radius * 0.5), 1.3, 0.75)
		Terrain.current.paint(center_pt, 5.5, 0.55, 0.0)
	return placed

static func _free(placed: Array[Placed], p: Vector2, rad: float, c: Vector3, zone: float) -> bool:
	if p.length() + rad * 0.3 > zone + 1.0:
		return false
	for o in placed:
		var local: Vector2 = o.pos - Vector2(c.x, c.z)
		if local.distance_to(p) < o.radius + rad + 1.5 - (0.0 if o.id != "well" else 1.0):
			return false
	var w: Vector2 = Vector2(c.x, c.z) + p
	if Terrain.is_water(w.x, w.y) or Terrain.slope_deg(w.x, w.y) > 12.0:
		return false
	return true

static func _register_obstacles(player: PlayerData, placed: Array[Placed], c: Vector3) -> void:
	var obs: Array = []
	var waters: Array = []
	for pl in placed:
		if pl.id == "palisade" or pl.id == "stonewall":
			obs.append(Vector3(pl.pos.x, pl.pos.y, pl.radius * 0.6))
		else:
			var r: float = pl.radius
			if pl.id == "stable" or pl.id == "blacksmith":
				r *= 0.8
			obs.append(Vector3(pl.pos.x, pl.pos.y, r * 0.8))
		if pl.id == "well":
			waters.append(Vector3(pl.pos.x, Terrain.h(pl.pos.x, pl.pos.y), pl.pos.y))
		if pl.id == "tavern":
			gather_points[player.id] = Vector3(pl.pos.x, 0, pl.pos.y)
	# nearest natural water within 40 m (pond/river/sea): sample rings
	var best: Vector3 = Vector3.INF
	var bd: float = 40.0
	for ring in range(4, 41, 3):
		for k in 24:
			var a: float = float(k) / 24.0 * TAU
			var p := Vector3(c.x + cos(a) * float(ring), 0, c.z + sin(a) * float(ring))
			if Terrain.is_water(p.x, p.z) and float(ring) < bd:
				bd = float(ring)
				best = Vector3(p.x, Terrain.h(p.x, p.z), p.z)
		if best != Vector3.INF:
			break
	if best != Vector3.INF:
		waters.append(best)
	Settler.obstacles[player.id] = obs
	Settler.water_points[player.id] = waters

static func _perimeter(player: PlayerData, placed: Array[Placed], c: Vector3, rng: Rng, ctx: BuildContext) -> void:
	var rad: float = Cfg.ZONE_RADIUS - 1.2
	var use_stone: bool = rng.chance(0.4)
	var seg_len: float = 4.0 if use_stone else 3.0
	var total: int = int(TAU * rad / seg_len)
	var gap: int = rng.range_i(0, total - 1)
	var arc_start: int = rng.range_i(0, total - 1)
	var arc_len: int = int(float(total) * 0.42)
	for i in arc_len:
		var idx: int = (arc_start + i) % total
		if absi(idx - gap) < 2:
			continue
		var a: float = float(idx) / float(total) * TAU
		var p := Vector2(c.x + cos(a) * rad, c.z + sin(a) * rad)
		if Terrain.is_water(p.x, p.y) or Terrain.slope_deg(p.x, p.y) > 20.0:
			continue
		var blocked: bool = false
		for o in placed:
			if o.pos.distance_to(p) < o.radius + 1.2:
				blocked = true
				break
		if blocked:
			continue
		var id: String = "stonewall" if use_stone else "palisade"
		var res: BuildResult = Buildings.build(id, ctx, rng)
		# segment runs tangentially: local X along the tangent
		var tang := Vector2(-sin(a), cos(a))
		var yaw: float = atan2(-tang.y, tang.x)
		var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, Terrain.h(p.x, p.y), p.y))
		var s: Structure = Breakable.create(id, player.id, res, base)
		var pl := Placed.new()
		pl.id = id
		pl.pos = p
		pl.radius = seg_len * 0.5
		pl.yaw = yaw
		pl.structure = s
		placed.append(pl)

static func _props(player: PlayerData, placed: Array[Placed], c: Vector3, rng: Rng) -> void:
	var col: Color = player.color
	var zone: float = Cfg.ZONE_RADIUS
	var by_id: Dictionary = {}
	for pl in placed:
		if not by_id.has(pl.id):
			by_id[pl.id] = []
		(by_id[pl.id] as Array).append(pl)
	# hints of each building
	for pl2 in placed:
		if pl2.id == "palisade" or pl2.id == "stonewall":
			continue
		var hints: Array = Buildings.def(pl2.id).get("prop_hints", []) as Array
		if hints.is_empty():
			continue
		var n: int = rng.range_i(1, 3)
		for i in n:
			var kind: String = str(hints[rng.range_i(0, hints.size() - 1)])
			if kind == "barrel_powder" and pl2.id != "powderstore":
				kind = "crate"
			var p: Vector2 = _spot_near(pl2, rng, c, zone)
			if p == Vector2.INF:
				continue
			Props.spawn(kind, Vector3(p.x, 0, p.y), rng.range_f(0, TAU), player.id, rng, col)
	# scatter
	var counts: Dictionary = {"haybale": rng.range_i(3, 6), "barrel_beer": rng.range_i(2, 5), "barrel_water": rng.range_i(2, 4), "crate": rng.range_i(6, 12),
		"cart": rng.range_i(1, 2), "pumpkin": rng.range_i(6, 10), "lantern": rng.range_i(4, 8), "banner": rng.range_i(2, 4), "tent": rng.range_i(0, 2)}
	for kind2 in counts:
		var cnt: int = int(counts[kind2])
		for i in cnt:
			var p2: Vector2 = _free_spot(placed, rng, c, zone, kind2 == "lantern" or kind2 == "banner")
			if p2 == Vector2.INF:
				continue
			var yaw: float = rng.range_f(0, TAU)
			if kind2 == "haybale":
				var s1: Structure = Props.spawn("haybale", Vector3(p2.x, 0, p2.y), yaw, player.id, rng, col)
				if rng.chance(0.5):
					Props.spawn("haybale", Vector3(p2.x + 0.15, 0, p2.y + 0.1), yaw, player.id, rng, col, 0.72)
				if s1 == null:
					continue
			else:
				Props.spawn(str(kind2), Vector3(p2.x, 0, p2.y), yaw, player.id, rng, col)
	# fences around farmhouses
	for fh in (by_id.get("farmhouse", []) as Array):
		var pl3: Placed = fh as Placed
		for k in 4:
			var a: float = float(k) / 4.0 * TAU + pl3.yaw + rng.range_f(-0.2, 0.2)
			var fpos := Vector2(pl3.pos.x + cos(a) * (pl3.radius + 1.0), pl3.pos.y + sin(a) * (pl3.radius + 1.0))
			if Terrain.is_water(fpos.x, fpos.y) or fpos.distance_to(Vector2(c.x, c.z)) > zone or fpos.distance_to(Vector2(c.x, c.z)) < 7.0:
				continue
			Props.spawn("fence", Vector3(fpos.x, 0, fpos.y), a + PI * 0.5, player.id, rng, col)
	# rubber duck easter egg is placed by the world (one per map)

static func _spot_near(pl: Placed, rng: Rng, c: Vector3, zone: float) -> Vector2:
	for t in 12:
		var a: float = rng.range_f(0.0, TAU)
		var d: float = pl.radius + rng.range_f(0.6, 2.2)
		var p := Vector2(pl.pos.x + cos(a) * d, pl.pos.y + sin(a) * d)
		var loc: float = p.distance_to(Vector2(c.x, c.z))
		if loc > zone - 1.0 or loc < 6.5:
			continue
		if Terrain.is_water(p.x, p.y):
			continue
		return p
	return Vector2.INF

static func _free_spot(placed: Array[Placed], rng: Rng, c: Vector3, zone: float, edge: bool) -> Vector2:
	for t in 30:
		var a: float = rng.range_f(0.0, TAU)
		var d: float = rng.range_f(6.5, zone - 1.5) if not edge else rng.range_f(8.0, zone - 1.0)
		var p := Vector2(c.x + cos(a) * d, c.z + sin(a) * d)
		var ok: bool = not Terrain.is_water(p.x, p.y)
		if ok:
			for o in placed:
				if o.pos.distance_to(p) < o.radius * 0.85 + 0.6:
					ok = false
					break
		if ok:
			return p
	return Vector2.INF

# ------------------------------------------------------------------ extras of buildings
static func _process_extras(s: Structure, res: BuildResult, base: Transform3D, player: PlayerData, rng: Rng, world: Node) -> void:
	for e in res.extras:
		var ex: Dictionary = e as Dictionary
		var kind: String = str(ex["kind"])
		var local: Vector3 = ex["pos"] as Vector3
		var wp: Vector3 = base * local
		match kind:
			"smoke":
				smoke_sources.append({"pos": wp, "s": s, "t": rng.range_f(0.0, 1.5)})
			"flag":
				var col: Color = ex.get("color", player.color) as Color
				var fl: Flag = Flag.spawn(wp, col, s)
				if ex.has("scale"):
					fl.scale = Vector3.ONE * float(ex["scale"])
			"prop":
				var pk: String = str(ex["prop"])
				var lift: float = float(ex.get("lift", 0.0))
				var on_ground: bool = bool(ex.get("ground", true))
				var q: Vector3 = wp
				if on_ground:
					q.y = Terrain.h(wp.x, wp.z)
				var ps: Structure = Props.spawn(pk, Vector3(wp.x, 0, wp.z) if on_ground else wp, rng.range_f(0, TAU), player.id, rng, player.color, lift if on_ground else 0.0)
				if not on_ground:
					# spawned at an explicit height: lift it there
					for p in ps.parts:
						var xf: Transform3D = p.xf
						xf.origin.y = wp.y + (p.xf.origin.y - Terrain.h(wp.x, wp.z))
						PhysWorld.set_transform(p.body_id, xf)
						p.xf = xf
				if s.kind == "powderstore" and pk == "barrel_powder" and s.behavior is Specials.PowderStore:
					for p2 in ps.parts:
						(s.behavior as Specials.PowderStore).kegs.append(p2)
			"animal":
				Animal.spawn(str(ex["animal"]), Vector3(wp.x, 0, wp.z), player.id, 2.5, rng)
			"archer":
				var st: Settler = world.call("spawn_settler", player.id, wp, 0.0) as Settler
				if st != null:
					st.is_archer = true
					st.state = Settler.State.WORK
					st.position = wp
					st.home = wp
					if s.behavior is Specials.Watchtower:
						(s.behavior as Specials.Watchtower).archer = st
			"rotor":
				if s.behavior is Specials.Windmill:
					(s.behavior as Specials.Windmill).setup(s, wp, base.basis.get_euler().y)
			"occupant":
				if s.behavior is Specials.Outhouse:
					(s.behavior as Specials.Outhouse).has_occupant = rng.chance(0.6)
			"forge_fire":
				if s.behavior is Specials.Blacksmith and Fx.inst != null:
					var f: Fx.Flame = Fx.inst.acquire_flame(0.5)
					if f != null:
						f.part = null
						f.static_pos = wp
						(s.behavior as Specials.Blacksmith).flame = f
			_:
				pass

## smoke from chimneys (called every frame from the world)
static func update_smoke(dt: float, wind: Vector2) -> void:
	var i: int = smoke_sources.size() - 1
	while i >= 0:
		var e: Dictionary = smoke_sources[i]
		var s: Structure = e["s"] as Structure
		if s.destroyed_fraction() > 0.6:
			smoke_sources.remove_at(i)
			i -= 1
			continue
		e["t"] = float(e["t"]) - dt
		if float(e["t"]) <= 0.0:
			e["t"] = 1.7
			var dir := Vector3(wind.x * 0.06, 1.0, wind.y * 0.06).normalized()
			Fx.burst("smoke", e["pos"] as Vector3, Color(0.55, 0.55, 0.58, 1), 0.25, dir)
		i -= 1
