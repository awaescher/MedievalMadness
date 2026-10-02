class_name SupplyCrate
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Supply crates sink on parachutes and stay on the ground until a shot hits one (any projectile, `try_hit`).
##  - METEOR crate: the only way to earn the Meteor Marker. Glowing green, beam and label, announced with a banner, a short
##    camera look and an epic sound; a fanfare plays when somebody hits it. It lands between two villages, appears at the
##    earliest after EVERY living player has fired 5 shots, with 45 % chance per turn end, at most once (Standard / Quarry /
##    core) or twice (Powerplay, Chaos) per match, and a new one 8 / 6 / 4 turns after the last was collected.
##  - SMALL crates: plain, not shiny, quiet (no announcement). Hold 3 boulders or 5 logs, land near the villages (so you
##    see them and sometimes hit them by accident). As many as there are players (+30 % Powerplay, +50 % Chaos), refilled
##    one per turn end. All crates can be switched off in the options (Settings.crates_on -> Game.crates_on).
## Host / local game decides; online clients only show them (messages `crate` / `cratego`).

const MIN_SHOTS := 5
const CHANCE := 0.45               # meteor crate: per turn end once eligible
const METEOR_START_H := 75.0
const METEOR_SPEED := 2.2          # m/s
const SMALL_START_H := 45.0
const SMALL_SPEED := 2.6

static var crates: Array[Dictionary] = []     # id, kind ("meteor" | "small"), node, canopy, land, height, ammo, n, hit_r
static var spawned_meteor: int = 0
static var meteor_next_turn: int = 0
static var _next_id: int = 1
static var _t: float = 0.0
static var _beam_mat: StandardMaterial3D

static func reset() -> void:
	for c in crates:
		var nd: Node3D = c["node"] as Node3D
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	crates.clear()
	spawned_meteor = 0
	meteor_next_turn = 0
	_next_id = 1

static func meteor_active() -> bool:
	return not _first("meteor").is_empty()

static func small_count() -> int:
	var n: int = 0
	for c in crates:
		if c["kind"] == "small":
			n += 1
	return n

static func _first(kind: String) -> Dictionary:
	for c in crates:
		if c["kind"] == kind:
			return c
	return {}

static func _by_id(id: int) -> Dictionary:
	for c in crates:
		if int(c["id"]) == id:
			return c
	return {}

static func max_meteor() -> int:
	return 2 if Game.rule_level >= 1 else 1

static func _gap() -> int:
	return 4 if Game.rule_level >= 2 else (6 if Game.rule_level >= 1 else 8)

static func small_target() -> int:
	var mult: float = 1.5 if Game.rule_level >= 2 else (1.3 if Game.rule_level >= 1 else 1.0)
	var alive: int = 0
	for p in Game.players:
		if not p.eliminated:
			alive += 1
	return maxi(1, roundi(float(alive) * mult)) if alive >= 2 else 0

## called at the end of every turn (host / local game)
static func turn_end_check() -> void:
	if Net.is_client() or not Game.crates_on:
		return
	if small_count() < small_target():
		var sp: Vector3 = _pick_small_spot()
		if sp != Vector3.INF:
			var ammo: String = "boulder" if Game.rng_battle.chance(0.5) else "log"
			_announce_spawn("small", sp, ammo, 3 if ammo == "boulder" else 5)
	if meteor_active() or spawned_meteor >= max_meteor() or Game.turn_number < meteor_next_turn:
		return
	for p2 in Game.players:
		if not p2.eliminated and p2.stats.shots < MIN_SHOTS:
			return
	if not Game.rng_battle.chance(CHANCE):
		return
	var spot: Vector3 = _pick_meteor_spot()
	if spot == Vector3.INF:
		return
	spawned_meteor += 1
	_announce_spawn("meteor", spot, "meteor", 1)

static func _announce_spawn(kind: String, spot: Vector3, ammo: String, n: int) -> void:
	var id: int = _next_id
	_next_id += 1
	spawn(id, kind, spot, ammo, n)
	if Net.is_host:
		Net.send_all({"k": "crate", "id": id, "kind": kind, "x": spot.x, "y": spot.y, "z": spot.z, "ammo": ammo, "n": n})

static func _far_from_villages(pos: Vector3, margin: float) -> bool:
	for v in Game.players:
		if Util.dist_xz(v.village_center, pos) < Cfg.ZONE_RADIUS + margin:
			return false
	return true

## meteor crate: between two villages, away from every village and from the water
static func _pick_meteor_spot() -> Vector3:
	var alive: Array[PlayerData] = []
	for p in Game.players:
		if not p.eliminated:
			alive.append(p)
	if alive.size() < 2:
		return Vector3.INF
	for i in 40:
		var a: PlayerData = alive[Game.rng_battle.range_i(0, alive.size() - 1)]
		var b: PlayerData = alive[Game.rng_battle.range_i(0, alive.size() - 1)]
		if a.id == b.id:
			continue
		var mid: Vector3 = a.village_center.lerp(b.village_center, Game.rng_battle.range_f(0.35, 0.65))
		var side := Vector3(-(b.village_center.z - a.village_center.z), 0.0, b.village_center.x - a.village_center.x).normalized()
		mid += side * Game.rng_battle.range_f(-8.0, 8.0)
		mid.y = Terrain.h(mid.x, mid.z)
		if mid.y >= Cfg.WATER_LEVEL + 0.6 and _far_from_villages(mid, 10.0):
			return mid
	return Vector3.INF

## small crate: just outside a living village, in plain view
static func _pick_small_spot() -> Vector3:
	var alive: Array[PlayerData] = []
	for p in Game.players:
		if not p.eliminated:
			alive.append(p)
	if alive.is_empty():
		return Vector3.INF
	for i in 30:
		var v: PlayerData = alive[Game.rng_battle.range_i(0, alive.size() - 1)]
		var ang: float = Game.rng_battle.range_f(0.0, TAU)
		var d: float = Cfg.ZONE_RADIUS + Game.rng_battle.range_f(3.0, 9.0)
		var pos: Vector3 = v.village_center + Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		pos.y = Terrain.h(pos.x, pos.z)
		if pos.y < Cfg.WATER_LEVEL + 0.4:
			continue
		var ok: bool = true
		for o in Game.players:
			if o.id != v.id and Util.dist_xz(o.village_center, pos) < Cfg.ZONE_RADIUS + 2.0:
				ok = false
		for c in crates:
			if Util.dist_xz(c["land"] as Vector3, pos) < 9.0:
				ok = false
		if ok:
			return pos
	return Vector3.INF

static func _mi(mesh: Mesh, col: Color, glow: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = Toon.emissive(col, glow) if glow > 0.0 else Toon.colored(col)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

static func _lines(canopy: Node3D, top_y: float, rad: float, bot_y: float) -> void:
	for k in 4:
		var ang: float = float(k) * PI * 0.5 + PI * 0.25
		var top := Vector3(cos(ang) * rad * 0.9, top_y, sin(ang) * rad * 0.9)
		var bot := Vector3(cos(ang) * 0.5, bot_y, sin(ang) * 0.5)
		var line := BoxMesh.new()
		line.size = Vector3(0.05, top.distance_to(bot), 0.05)
		var ln: MeshInstance3D = _mi(line, Color("#fff4d6"))
		ln.position = (top + bot) * 0.5
		ln.basis = Basis(Quaternion(Vector3.UP, (top - bot).normalized()))
		canopy.add_child(ln)

## builds a crate (host and clients)
static func spawn(id: int, kind: String, spot: Vector3, ammo: String, n: int) -> void:
	var root: Node3D = RandomEvents.fx_root
	if root == null or not _by_id(id).is_empty():
		return
	var meteor: bool = kind == "meteor"
	var node := Node3D.new()
	root.add_child(node)
	var sz: float = 1.7 if meteor else 1.15
	var box := BoxMesh.new()
	box.size = Vector3(sz, sz * 0.82, sz)
	var body: MeshInstance3D = _mi(box, Color("#b07a3e") if meteor else Color("#a06c38"))
	body.position = Vector3(0, sz * 0.41, 0)
	node.add_child(body)
	var canopy := Node3D.new()
	node.add_child(canopy)
	var rad: float = 3.4 if meteor else 2.2
	var top_y: float = 6.4 if meteor else 4.2
	var dome: MeshInstance3D = _mi(MeshGen.sphere_mesh(rad, 6, 12), Color("#f4f1e4") if meteor else Color("#c9b27a"))
	dome.scale = Vector3(1.0, 0.55, 1.0)
	dome.position = Vector3(0, top_y, 0)
	canopy.add_child(dome)
	_lines(canopy, top_y, rad, sz * 0.82)
	if meteor:
		var band := BoxMesh.new()
		band.size = Vector3(1.78, 0.28, 1.78)
		for yy in [0.3, 1.1]:
			var b: MeshInstance3D = _mi(band, Color("#7dff9a"), 1.4)
			b.position = Vector3(0, float(yy), 0)
			node.add_child(b)
		var star := BoxMesh.new()
		star.size = Vector3(0.9, 0.9, 1.76)
		var mark: MeshInstance3D = _mi(star, Color("#baffc8"), 1.8)
		mark.position = Vector3(0, 0.7, 0)
		mark.rotation.z = PI * 0.25
		node.add_child(mark)
		var stripe: MeshInstance3D = _mi(MeshGen.sphere_mesh(rad + 0.04, 6, 12), Color("#3fcf6a"))
		stripe.scale = Vector3(1.0, 0.55, 0.38)
		stripe.position = Vector3(0, top_y, 0)
		canopy.add_child(stripe)
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mat.disable_fog = true
		_beam_mat.albedo_color = Color(0.2, 0.9, 0.35) * 0.55
		var bm := CylinderMesh.new()
		bm.top_radius = 0.3
		bm.bottom_radius = 1.2
		bm.height = 120.0
		bm.cap_top = false
		bm.cap_bottom = false
		bm.radial_segments = 8
		var beam: MeshInstance3D = _mi(bm, Color.WHITE)
		beam.material_override = _beam_mat
		beam.position = Vector3(0, 60.0, 0)
		beam.extra_cull_margin = 200.0
		node.add_child(beam)
		var label := Label3D.new()
		label.font = Speech.ui_font()
		label.text = I18n.t("crate.label")
		label.font_size = 64
		label.outline_size = 10
		label.outline_modulate = Color(0.04, 0.12, 0.06)
		label.modulate = Color("#9dffb4")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.pixel_size = 0.0009
		label.no_depth_test = true
		label.shaded = false
		label.position = Vector3(0, 10.5, 0)
		node.add_child(label)
	var h: float = METEOR_START_H if meteor else SMALL_START_H
	node.position = spot + Vector3(0, h, 0)
	crates.append({"id": id, "kind": kind, "node": node, "canopy": canopy, "land": spot, "height": h, "ammo": ammo, "n": n,
		"hit_r": 2.4 if meteor else 1.6, "sway": float(id) * 1.7})
	if meteor:
		if Turn.cam != null:
			Turn.cam.focus_on(spot + Vector3(0, 22, 0), 75.0, 30.0)         # a short look at the newcomer
		Events.banner.emit(I18n.t("crate.banner"), "unlock")
		Events.toast.emit(I18n.t("crate.toast"))
		Sfx.play("crate_epic", Vector3.INF, 0.9, 5)

static func tick(dt: float) -> void:
	if crates.is_empty():
		return
	_t += dt
	for c in crates:
		var node: Node3D = c["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var land: Vector3 = c["land"] as Vector3
		var h: float = float(c["height"])
		if h > 0.0:
			h = maxf(0.0, h - (METEOR_SPEED if c["kind"] == "meteor" else SMALL_SPEED) * dt)
			c["height"] = h
			var sw: float = minf(h, 3.0) * 0.4
			var ph: float = float(c["sway"])
			node.position = Vector3(land.x + sin(_t * 0.9 + ph) * sw, land.y + h, land.z + cos(_t * 0.7 + ph) * sw)
			node.rotation.z = sin(_t * 1.3 + ph) * 0.08 * minf(h, 3.0) / 3.0
			if h <= 0.0:
				(c["canopy"] as Node3D).visible = false
				node.rotation = Vector3.ZERO
				node.position = land
				Fx.burst("dust", land + Vector3.UP * 0.4, Color(0, 0, 0, -1), 0.6 if c["kind"] == "small" else 0.8)
				Sfx.play("thunk", land, 0.5 if c["kind"] == "small" else 0.8, 2)
	if _beam_mat != null:
		_beam_mat.albedo_color = Color(0.2, 0.9, 0.35) * (0.5 + 0.15 * sin(_t * 3.0))

## a projectile at `pos` (radius r): did it hit a crate? Host / local game only.
static func try_hit(pos: Vector3, r: float, source: Dictionary) -> bool:
	if crates.is_empty() or Net.is_client() or source.is_empty() or not source.has("player_id"):
		return false
	for c in crates:
		var node: Node3D = c["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var top: float = 6.4 if c["kind"] == "meteor" else 4.2
		var hit: bool = (node.position + Vector3(0, 0.7, 0)).distance_to(pos) < float(c["hit_r"]) + r
		var cn: Node3D = c["canopy"] as Node3D
		if not hit and cn.visible:
			hit = (node.position + Vector3(0, top, 0)).distance_to(pos) < float(c["hit_r"]) + 1.2 + r
		if hit:
			var pid: int = int(source["player_id"])
			var id: int = int(c["id"])
			collect(id, pid)
			if Net.is_host:
				Net.send_all({"k": "cratego", "id": id, "pid": pid})
			return true
	return false

## crate `id` was hit by player `pid` (online clients: announced by the host)
static func collect(id: int, pid: int) -> void:
	var c: Dictionary = _by_id(id)
	if c.is_empty():
		return
	var node: Node3D = c["node"] as Node3D
	var at: Vector3 = node.position + Vector3(0, 1.0, 0)
	var meteor: bool = c["kind"] == "meteor"
	Fx.burst("confetti", at, Color(0, 0, 0, -1), 1.0 if meteor else 0.5)
	Fx.burst("splinter", at, Color("#b07a3e"), 1.0 if meteor else 0.7)
	Sfx.play("crunch", at, 1.0 if meteor else 0.6, 3)
	if meteor:
		Fx.comic_kind("explosion", at + Vector3.UP * 2.0)
		Sfx.play("fanfare", Vector3.INF, 1.0, 5)
		meteor_next_turn = Game.turn_number + _gap()
	node.queue_free()
	crates.erase(c)
	if not Net.is_client():
		Unlocks.grant(pid, str(c["ammo"]), int(c["n"]), "crate" if meteor else "crate_small")
