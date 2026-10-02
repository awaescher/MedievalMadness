class_name GameWorld
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Owns one match's 3D content: terrain, villages, decor, entities and the per-tick update order of all systems.

var map: MapData
var terrain: Terrain
var sky: SkyRig
var fx: Fx
var comic: ComicText
var speech: Speech
var villages: Array = []               # per player: Array[Village.Placed]
var struct_root: Node3D
var entity_root: Node3D
var fx_root: Node3D
var rng_map: Rng
var rng_battle: Rng
var catapult_parent: Node3D
var decor_root: Node3D
var _think_acc: float = 0.0
var generating_progress: float = 0.0

# ------------------------------------------------------------------ setup / teardown
func setup_roots(sky_rig: SkyRig) -> void:
	sky = sky_rig
	struct_root = Node3D.new()
	struct_root.name = "Structures"
	add_child(struct_root)
	entity_root = Node3D.new()
	entity_root.name = "Entities"
	add_child(entity_root)
	decor_root = Node3D.new()
	decor_root.name = "Decor"
	add_child(decor_root)
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	Powder.attach(fx_root)
	Terrain.ground_hook = Callable(Breakable, "ground_changed")
	Terrain.wake_hook = Callable(PhysWorld, "wake_in_box")
	catapult_parent = Node3D.new()
	catapult_parent.name = "Catapults"
	add_child(catapult_parent)
	fx = Fx.new()
	fx.name = "Particles"
	fx_root.add_child(fx)
	comic = ComicText.new()
	comic.name = "Comic"
	fx_root.add_child(comic)
	speech = Speech.new()
	speech.name = "Speech"
	fx_root.add_child(speech)
	Fire.light_root = fx_root
	WaterSys.root = fx_root
	Breakable.world_root = struct_root
	Settler.world_root = entity_root
	Animal.world_root = entity_root
	Projectile.world_root = fx_root
	Flag.world_root = entity_root

func reset_systems() -> void:
	Breakable.reset()
	Fire.reset()
	Explosion.reset()
	Landslide.reset()
	Powder.reset()
	WaterSys.reset()
	Projectile.reset()
	Settler.reset()
	Repair.reset()
	Animal.reset()
	Meteor.reset()
	Stink.reset()
	Village.reset()
	Flag.reset()
	Scoring.reset()
	Debris.reset()
	Brigade.reset()

func teardown() -> void:
	reset_systems()
	PhysWorld.clear_all()
	for p in Game.players:
		for c in p.catapults:
			if is_instance_valid(c):
				(c as Node).queue_free()
		p.catapults.clear()
	if terrain != null and is_instance_valid(terrain):
		terrain.queue_free()
	terrain = null
	for ch in [struct_root, entity_root, decor_root, catapult_parent]:
		if ch != null:
			for k in (ch as Node).get_children():
				k.queue_free()
	MeshGen.clear_caches()
	Toon.clear()
	Toon.outlines_on = Quality.current.outlines if Quality.current != null else true

# ------------------------------------------------------------------ generation
## Generates terrain, villages, decor. `progress` is called with (0..1, message) between steps.
func _step(progress: Callable, p: float, msg: int) -> void:
	progress.call(p, msg)
	await get_tree().process_frame

func generate(seed_text: String, players: Array[PlayerData], progress: Callable) -> void:
	reset_systems()
	rng_map = Rng.from_string(seed_text + "-map")
	rng_battle = Rng.from_string(seed_text + "-battle")
	Game.rng_battle = rng_battle
	var n: int = players.size()
	await _step(progress, 0.05, 0)
	map = MapGen.generate(seed_text, n, Game.terrain_hills, Game.layout_nonce)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(map)
	PhysWorld.register_terrain(terrain.terrain_body())
	terrain.set_process(true)
	sky.build_clouds(map.map_radius, Rng.from_string(seed_text + "-clouds"))
	await _step(progress, 0.2, 1)
	# villages
	villages.clear()
	for i in n:
		var site: Vector3 = map.sites[i]
		players[i].village_center = Vector3(site.x, Terrain.h(site.x, site.z), site.z)
		var vrng := Rng.from_string("%s-village-%d" % [seed_text, i])
		var placed: Array[Village.Placed] = Village.generate(players[i], players[i].village_center, vrng, self)
		villages.append(placed)
		await _step(progress, 0.2 + 0.5 * float(i + 1) / float(n), i % 10)
	# decor
	await _step(progress, 0.72, 5)
	_build_decor(seed_text)
	# center feature
	if map.center_kind == "ruin":
		var ctx := BuildContext.new()
		var res: BuildResult = Buildings.build("ruin", ctx, Rng.from_string(seed_text + "-ruin"))
		var base := Transform3D(Basis(), Vector3(0, Terrain.h(0, 0), 0))
		var rs: Structure = Breakable.create("ruin", -1, res, base)
		rs.is_decor = true
	# rubber duck easter egg
	if map.duck_pos != Vector3.INF:
		var lift: float = maxf(WaterSys.water_y() - Terrain.h(map.duck_pos.x, map.duck_pos.z), 0.0) + 0.35
		Props.spawn("rubberduck", Vector3(map.duck_pos.x, 0, map.duck_pos.z), rng_map.range_f(0, TAU), -1, rng_map, Color.WHITE, lift)
	# ducks on natural water near villages
	for i in n:
		var waters: Array = Settler.water_points.get(i, []) as Array
		if not waters.is_empty() and rng_map.chance(0.6):
			var w: Vector3 = waters[waters.size() - 1] as Vector3
			if Terrain.is_water(w.x, w.z):
				for k in rng_map.range_i(1, 2):
					Animal.spawn("duck", Vector3(w.x + rng_map.range_f(-2, 2), 0, w.z + rng_map.range_f(-2, 2)), i, 4.0, rng_map)
	await _step(progress, 0.85, 7)
	# settlers + animals
	for i in n:
		_populate(players[i], i)
	Fire.build_grid()
	Specials.connect_signals()
	await _step(progress, 1.0, 9)

func _populate(p: PlayerData, idx: int) -> void:
	var c: Vector3 = p.village_center
	var count: int = Quality.settlers_per_village
	for i in count:
		spawn_settler(idx, c, 0.0)
	for i in rng_map.range_i(3, 6):
		var a: float = rng_map.range_f(0, TAU)
		var d: float = rng_map.range_f(6.0, Cfg.ZONE_RADIUS - 3.0)
		Animal.spawn("chicken", Vector3(c.x + cos(a) * d, 0, c.z + sin(a) * d), idx, 5.0, rng_map)
	for i in rng_map.range_i(2, 4):
		var a2: float = rng_map.range_f(0, TAU)
		var d2: float = rng_map.range_f(6.0, Cfg.ZONE_RADIUS - 3.0)
		Animal.spawn("sheep", Vector3(c.x + cos(a2) * d2, 0, c.z + sin(a2) * d2), idx, 6.0, rng_map)
	# every village keeps two cows, on open ground (not inside a building)
	var cow_angle: float = rng_map.range_f(0, TAU)
	for ci in 2:
		var spot: Vector3 = _free_animal_spot(idx, c, cow_angle + float(ci) * PI * 0.85)
		Animal.spawn("cow", spot, idx, 5.0, rng_map)

## A spot of the village that is clear of buildings, searched along a ray from the centre (starts at `angle`, tries others)
func _free_animal_spot(idx: int, c: Vector3, angle: float) -> Vector3:
	var obstacles: Array = Settler.obstacles.get(idx, []) as Array
	for t in 24:
		var a: float = angle + float(t) * 0.9
		var d: float = 9.0 + float(t % 5) * 2.0
		var p := Vector3(c.x + cos(a) * d, 0, c.z + sin(a) * d)
		if Terrain.is_water(p.x, p.z) or Terrain.slope_deg(p.x, p.z) > 14.0:
			continue
		var ok: bool = true
		for o in obstacles:
			var ov: Vector3 = o as Vector3
			if Vector2(p.x - ov.x, p.z - ov.y).length() < ov.z + 2.2:
				ok = false
				break
		if ok:
			return p
	return Vector3(c.x + cos(angle) * 12.0, 0, c.z + sin(angle) * 12.0)

## Spawns a settler of village `idx` near `around` (random free spot inside the zone)
func spawn_settler(idx: int, around: Vector3, spread: float) -> Settler:
	var pl: PlayerData = Game.player(idx)
	if pl == null:
		return null
	var c: Vector3 = pl.village_center
	var pos: Vector3 = around
	if spread <= 0.0 and around.distance_to(c) < 0.5:
		for t in 12:
			var off: Vector2 = rng_map.in_circle(Cfg.ZONE_RADIUS * 0.85)
			var p := Vector3(c.x + off.x, 0, c.z + off.y)
			var blocked: bool = false
			for o in (Settler.obstacles.get(idx, []) as Array):
				var ov: Vector3 = o as Vector3
				if Vector2(p.x - ov.x, p.z - ov.y).length() < ov.z + 0.8:
					blocked = true
					break
			if not blocked and not Terrain.is_water(p.x, p.z):
				pos = p
				break
	var st := Settler.new()
	st.setup(idx, pos, pl.color, rng_map)
	entity_root.add_child(st)
	return st

# ------------------------------------------------------------------ decor: trees, rocks, bushes, flowers
func _in_any_zone(x: float, z: float, margin: float) -> bool:
	for s in map.sites:
		if Vector2(x - s.x, z - s.z).length() < Cfg.ZONE_RADIUS + margin:
			return true
	return false

func _build_decor(seed_text: String) -> void:
	var r := Rng.from_string(seed_text + "-decor")
	var n: int = map.player_count
	var area_k: float = clampf(map.map_radius / (60.0 + 14.0 * float(n)), 1.0, 2.6)
	var tree_count: int = int(float(60 + 14 * n) * area_k)
	var placed: int = 0
	var tries: int = 0
	var ctx := BuildContext.new()
	var tree_pos: Array[Vector2] = []
	while placed < tree_count and tries < tree_count * 12:
		tries += 1
		var p: Vector2 = r.in_circle(map.map_radius - 20.0)
		if not map.in_bounds(p.x, p.y):
			continue
		var h: float = map.height_at(p.x, p.y)
		if h < Cfg.WATER_LEVEL + 0.8 or map.slope_deg_at(p.x, p.y) > 28.0:
			continue
		var in_zone: bool = _in_any_zone(p.x, p.y, 0.0)
		if in_zone:
			var edge: bool = _in_any_zone(p.x, p.y, -Cfg.ZONE_RADIUS * 0.25) == false
			if not (edge and r.chance(0.15)):
				continue
		var too_close: bool = false
		for q in tree_pos:
			if q.distance_to(p) < 3.2:
				too_close = true
				break
		if too_close:
			continue
		tree_pos.append(p)
		var res: BuildResult = Buildings.build("tree", ctx, r, {"pine": r.chance(0.4)})
		var base := Transform3D(Basis(Vector3.UP, r.range_f(0, TAU)), Vector3(p.x, h - 0.05, p.y))
		var s: Structure = Breakable.create("tree", -1, res, base)
		s.is_decor = true
		placed += 1
	# rocks (static collider compound) + bushes + flowers (pure visuals, MultiMesh)
	_multimesh_decor(r, int(float(40 + 8 * n) * area_k * area_k), "rock")
	_multimesh_decor(r, int(float(90 + 20 * n) * area_k * area_k), "bush")
	_multimesh_decor(r, int(float(260 + 40 * n) * area_k * area_k), "flower")

func _multimesh_decor(r: Rng, count: int, kind: String) -> void:
	var mesh: ArrayMesh
	var buf := MeshGen.Buf.new()
	match kind:
		"rock":
			MeshGen.add_ellipsoid(buf, Vector3(0.9, 0.6, 0.8), Transform3D(Basis(), Vector3(0, 0.25, 0)), Color.WHITE, 0.03, 5, 7)
		"bush":
			MeshGen.add_sphere(buf, 0.6, Transform3D(Basis(), Vector3(0, 0.45, 0)), Color.WHITE, 0.03, 5, 8)
			MeshGen.add_sphere(buf, 0.45, Transform3D(Basis(), Vector3(0.4, 0.35, 0.2)), Color.WHITE, 0.0, 4, 6)
		_:
			MeshGen.add_box(buf, Vector3(0.04, 0.3, 0.04), Transform3D(Basis(), Vector3(0, 0.15, 0)), Color("#4a9a3a"), 0.0)
			MeshGen.add_sphere(buf, 0.09, Transform3D(Basis(), Vector3(0, 0.34, 0)), Color.WHITE, 0.0, 4, 6)
	buf.srgb = false
	mesh = buf.to_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var positions: Array[Transform3D] = []
	var colors: Array[Color] = []
	var rock_shapes: Array[PhysWorld.ShapeDesc] = []
	var tries: int = 0
	while positions.size() < count and tries < count * 6:
		tries += 1
		var p: Vector2 = r.in_circle(map.map_radius - 12.0)
		if not map.in_bounds(p.x, p.y):
			continue
		var h: float = map.height_at(p.x, p.y)
		if h < Cfg.WATER_LEVEL + 0.4:
			continue
		if _in_any_zone(p.x, p.y, 0.0) and kind != "flower":
			continue
		var s: float = r.range_f(0.6, 1.5) if kind != "flower" else r.range_f(0.8, 1.3)
		var basis_ := Basis(Vector3.UP, r.range_f(0, TAU)).scaled(Vector3.ONE * s)
		var xf := Transform3D(basis_, Vector3(p.x, h - 0.05, p.y))
		positions.append(xf)
		var col: Color
		match kind:
			"rock":
				col = Color("#8a8a90").lerp(Color("#a9aeb3"), r.next_f())
			"bush":
				col = Color("#3f9c3f").lerp(Color("#2e8b3d"), r.next_f())
			_:
				var pal: Array[String] = ["#ff5b5b", "#ffd34a", "#ffffff", "#c07cff", "#ff9ad0"]
				col = Color.html(pal[r.range_i(0, pal.size() - 1)])
		colors.append(col.srgb_to_linear())
		if kind == "rock":
			rock_shapes.append(PhysWorld.sphere_desc(0.62 * s, Transform3D(Basis(), Vector3(p.x, h + 0.2, p.y))))
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, positions[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Toon.main() if kind != "flower" else Toon.plain()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "flower" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.visibility_range_end = 160.0 if kind != "rock" else 260.0
	decor_root.add_child(mmi)
	if kind == "rock" and not rock_shapes.is_empty():
		var d := PhysWorld.BodyDesc.new()
		d.mode = "static"
		d.layer = Cfg.LAYER_STRUCT
		d.mask = 0
		d.kind = "struct"
		d.shapes = rock_shapes
		d.friction = 0.8
		PhysWorld.add_body(d)

# ------------------------------------------------------------------ catapults
func spot_valid_for_catapult(p: PlayerData, pos: Vector3) -> bool:
	if Util.dist_xz(pos, p.village_center) > Cfg.ZONE_RADIUS - 1.0:
		return false
	if Terrain.slope_deg(pos.x, pos.z) > 25.0:
		return false
	if Terrain.is_water(pos.x, pos.z):
		return false
	for other in Game.players:
		for c in other.catapults:
			if not is_instance_valid(c):
				continue
			var cat: Catapult = c as Catapult
			if not cat.destroyed and Util.dist_xz(cat.global_pos(), pos) < 4.0:
				return false
	# overlap with buildings / props: raycast down + sphere test
	var blocked: bool = false
	var probe: Vector3 = Vector3(pos.x, Terrain.h(pos.x, pos.z) + 1.4, pos.z)
	PhysWorld.overlap_sphere(probe, 2.2, func(pb: PhysWorld.PBody, _s: int, _r: RID) -> void:
		if pb != null and pb.kind != "projectile":
			blocked = true, Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_CATAPULT)
	if blocked:
		return false
	return true

func place_catapult(p: PlayerData, pos: Vector3, yaw: float) -> Catapult:
	var c := Catapult.new()
	c.setup(p, Vector3(pos.x, Terrain.h(pos.x, pos.z), pos.z), yaw)
	c.index = p.catapults.size()
	catapult_parent.add_child(c)
	p.catapults.append(c)
	return c

# ------------------------------------------------------------------ per-tick update (fixed 60 Hz)
static var prof: Dictionary = {}
func physics_tick(dt: float, cam_pos: Vector3) -> void:
	var _t0: int = 0
	_t0 = Time.get_ticks_usec()
	Breakable.tick(dt)
	prof["Breakable"] = int(prof.get("Breakable", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Debris.tick(dt)
	prof["Debris"] = int(prof.get("Debris", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Projectile.tick_all(dt)
	prof["Projectile"] = int(prof.get("Projectile", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Explosion.tick(dt)
	prof["Explosion"] = int(prof.get("Explosion", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Landslide.tick(dt)
	prof["Landslide"] = int(prof.get("Landslide", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Powder.tick(dt)
	prof["Powder"] = int(prof.get("Powder", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Fire.update(dt)
	prof["Fire"] = int(prof.get("Fire", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	WaterSys.tick(dt)
	prof["WaterSys"] = int(prof.get("WaterSys", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Settler.update_all(dt, cam_pos)
	prof["Settler"] = int(prof.get("Settler", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Animal.update_all(dt)
	prof["Animal"] = int(prof.get("Animal", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Meteor.tick_all(dt)
	prof["Meteor"] = int(prof.get("Meteor", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Stink.tick(dt)
	prof["Stink"] = int(prof.get("Stink", 0)) + Time.get_ticks_usec() - _t0
	_t0 = Time.get_ticks_usec()
	Brigade.tick_all(dt)
	prof["Brigade"] = int(prof.get("Brigade", 0)) + Time.get_ticks_usec() - _t0
	for p in Game.players:
		for c in p.catapults:
			if is_instance_valid(c):
				(c as Catapult).tick(dt)

func frame_tick(dt: float) -> void:
	Flag.update_all(Game.wind, dt)
	Village.update_smoke(dt, Game.wind)
