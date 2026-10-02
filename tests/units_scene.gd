class_name SceneUnits
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## In-scene unit tests (need the physics server + autoloads): run with
##   godot --path . -- --autotest=units
## They build structures on the generated terrain, drive the systems by hand and print PASS/FAIL; exit code 1 on failure.

static var main: Node
static var tree: SceneTree
static var world: GameWorld

static func frames(n: int) -> void:
	for i in n:
		await tree.process_frame

static func ground_pos(x: float, z: float) -> Vector3:
	return Vector3(x, Terrain.h(x, z), z)

## Free flat spot outside every village for isolated experiments
static func lab_pos() -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var bestd: float = -1.0
	for i in 60:
		var a: float = float(i) * 0.7
		var r: float = 20.0 + float(i % 7) * 9.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var h: float = Terrain.h(p.x, p.z)
		if h < 1.0 or Terrain.slope_deg(p.x, p.z) > 6.0:
			continue
		var d: float = 1e9
		for s in Game.players:
			d = minf(d, Util.dist_xz(s.village_center, p))
		if d > bestd:
			bestd = d
			best = Vector3(p.x, h, p.z)
	return best

static func build(id: String, pos: Vector3, owner: int = 0, yaw: float = 0.0) -> Structure:
	var ctx := BuildContext.new()
	var rng := Rng.from_string("unit-" + id)
	var res: BuildResult = Buildings.build(id, ctx, rng)
	var base := Transform3D(Basis(Vector3.UP, yaw), pos)
	var s: Structure = Breakable.create(id, owner, res, base)
	Specials.attach(s)
	return s

static func run_all() -> void:
	TestBase.reset()
	TestBase.current = "units"
	await _test_support_check()
	_test_church_roof()
	await _test_intact_buildings_stand()
	await _test_every_building_survives_a_blast()
	await _test_props()
	_test_sounds()
	await _test_ragdoll()
	await _test_fire_spread_and_water()
	await _test_powder_chain()
	await _test_debris_cap()
	_test_settings_roundtrip()
	await _test_catapult_placement()
	_test_unlocks()
	await _test_ground_loss()
	_test_powder()
	_test_landslide()
	await _test_posts()
	print("---- scene units: %d passed, %d failed" % [TestBase.passed, TestBase.failed])

# ------------------------------------------------------------------ tests
static func _test_church_roof() -> void:
	TestBase.current = "church_roof"
	var p: Vector3 = lab_pos()
	# a church whose nave walls are gone: the nave roof must come down, not hang from the tower on its glue links
	var ch: Structure = build("church", p, 0)
	Breakable.awaken(ch)
	var tower_x: float = 0.0
	var roofs: Array[Part] = []
	for part in ch.parts:
		if part.tag == "tower":
			tower_x = part.xf.origin.x
	for part in ch.parts.duplicate():
		if part.tag == "wall" or part.tag == "window":
			Breakable.break_part(part, {}, Vector3.ZERO, true)
	Breakable.support_check(ch)
	var roof_total: int = 0
	var roof_frozen: int = 0
	for part in ch.parts:
		if part.tag == "roof" and part.state != Part.State.DEAD and part.xf.origin.y < ch.aabb.position.y + 7.5:
			roof_total += 1
			if part.state == Part.State.FROZEN:
				roof_frozen += 1
	TestBase.check(roof_total > 4 and roof_frozen * 3 <= roof_total, "church nave roof collapses without its walls (%d of %d still glued)" % [roof_frozen, roof_total])

static func _test_support_check() -> void:
	TestBase.current = "support_check"
	var p: Vector3 = lab_pos()
	var s: Structure = build("farmhouse", p)
	TestBase.check(s.parts.size() > 40, "farmhouse has parts (%d)" % s.parts.size())
	Breakable.awaken(s)
	var frozen: int = 0
	for part in s.parts:
		if part.state == Part.State.FROZEN:
			frozen += 1
	TestBase.eq(frozen, s.parts.size(), "all parts frozen after awakening")
	Breakable.support_check(s)
	var released_now: int = 0
	for part in s.parts:
		if part.state == Part.State.FREE:
			released_now += 1
	TestBase.eq(released_now, 0, "an intact building keeps everything glued")
	# remove the foundation -> everything else must be released
	for part in s.parts.duplicate():
		if part.anchor:
			Breakable.break_part(part, {}, Vector3.ZERO, true)
	Breakable.support_check(s)
	var free_n: int = 0
	var frozen_n: int = 0
	for part in s.parts:
		if part.state == Part.State.FREE:
			free_n += 1
		elif part.state == Part.State.FROZEN:
			frozen_n += 1
	TestBase.eq(frozen_n, 0, "removing the foundation releases all parts")
	TestBase.check(free_n > 20, "released parts are dynamic (%d)" % free_n)
	await frames(90)
	var nan: int = 0
	for part in s.parts:
		if part.state == Part.State.FREE:
			var o: Vector3 = PhysWorld.get_transform(part.body_id).origin
			if not Util.is_finite_vec(o) or absf(o.y) > 200.0:
				nan += 1
	TestBase.eq(nan, 0, "collapse stays finite")
	# sleeping bodies cost nothing: after settling most bodies are asleep
	await frames(300)
	var awake: int = 0
	var total: int = 0
	for part in s.parts:
		if part.state == Part.State.FREE:
			total += 1
			if not PhysWorld.is_sleeping(part.body_id):
				awake += 1
	TestBase.check(total == 0 or awake < total, "rubble goes to sleep (%d of %d still awake)" % [awake, total])

static func _test_every_building_survives_a_blast() -> void:
	TestBase.current = "buildings_blast"
	var p0: Vector3 = lab_pos()
	for id in Buildings.all_ids():
		var s: Structure = build(id, Vector3(p0.x + 0.0, Terrain.h(p0.x, p0.z), p0.z))
		Breakable.awaken(s)
		Explosion.explode(s.center, 12.0, 1400.0, {"source": {}, "no_crater": true})
		var ok: bool = true
		for i in 240:
			await tree.physics_frame
			if i % 60 == 59:
				for part in s.parts:
					if part.state == Part.State.FREE:
						var o: Vector3 = PhysWorld.get_transform(part.body_id).origin
						if not Util.is_finite_vec(o) or absf(o.y) > 300.0 or absf(o.x) > 1500.0:
							ok = false
		TestBase.check(ok, "%s: no NaN / runaway bodies after a big explosion + 240 ticks" % id)
		TestBase.check(s.live_count < s.initial_count, "%s takes damage from a 1400 dmg blast (%d/%d parts left)" % [id, s.live_count, s.initial_count])
		# clean up so the next building has room
		for part in s.parts.duplicate():
			if part.state != Part.State.DEAD:
				Breakable.discard_part(part)
		s.destroyed = true
	await frames(10)

static func _test_props() -> void:
	TestBase.current = "props"
	var p: Vector3 = lab_pos()
	var rng := Rng.new(4)
	for kind in Props.KINDS:
		var s: Structure = Props.spawn(kind, p + Vector3(rng.range_f(-4, 4), 0, rng.range_f(-4, 4)), 0.0, 0, rng, Color.RED)
		TestBase.check(s != null and s.parts.size() >= 1, "prop %s spawns" % kind)
		var finite: bool = true
		for part in s.parts:
			if not Util.is_finite_vec(part.xf.origin) or part.body_id == 0:
				finite = false
		TestBase.check(finite, "prop %s has valid bodies" % kind)
	await frames(60)
	# a sleeping prop wakes up when an explosion pushes it
	var crate: Structure = Props.spawn("crate", p, 0.0, 0, rng, Color.RED)
	await frames(90)
	var part: Part = crate.parts[0]
	var y0: float = PhysWorld.get_transform(part.body_id).origin.y
	Explosion.explode(p + Vector3(2, 0, 0), 4.0, 120.0, {"source": {}, "no_crater": true})
	await frames(30)
	TestBase.check(part.state == Part.State.DEAD or PhysWorld.get_transform(part.body_id).origin.distance_to(p) > 0.1 or absf(PhysWorld.get_transform(part.body_id).origin.y - y0) > 0.01, "explosion wakes / moves / breaks a crate")

static func _test_sounds() -> void:
	TestBase.current = "sounds"
	for n in SoundRecipes.NAMES:
		TestBase.check(Sfx.has_sound(n), "sound '%s' exists in the cache" % n)
	TestBase.check(Sfx.synth_seconds < 12.0, "synthesis is quick (%.2f s)" % Sfx.synth_seconds)
	TestBase.check(SoundRecipes.NAMES.size() >= 35, "all recipes present (%d)" % SoundRecipes.NAMES.size())

static func _test_ragdoll() -> void:
	TestBase.current = "ragdoll"
	var p: Vector3 = lab_pos()
	var st: Settler = world.spawn_settler(0, Game.players[0].village_center, 0.0)
	st.position = p
	await frames(5)
	st.hurt(5.0, {"player_id": 1, "ammo": "stone"}, Vector3(4, 12, 3), true, true)
	TestBase.eq(st.state, Settler.State.RAGDOLL, "a hit launches the settler as a ragdoll")
	TestBase.eq(st._bodies.size(), 6, "ragdoll has six bodies")
	var finite: bool = true
	for i in 240:
		await tree.physics_frame
		for id in st._bodies:
			var o: Vector3 = PhysWorld.get_transform(id).origin
			if not Util.is_finite_vec(o) or o.y < -50.0:
				finite = false
	TestBase.check(finite, "ragdoll stays finite and on the ground")
	await tree.create_timer(8.0).timeout
	TestBase.check(st.state != Settler.State.RAGDOLL, "ragdoll ends (state %d)" % st.state)
	# lethal hit
	var st2: Settler = world.spawn_settler(0, Game.players[0].village_center, 0.0)
	st2.position = p + Vector3(3, 0, 0)
	st2.hurt(100.0, {"player_id": 1, "ammo": "stone"}, Vector3(1, 4, 1), true, true)
	await tree.create_timer(9.0).timeout
	TestBase.eq(st2.state, Settler.State.DEAD, "a lethal hit kills the settler")

static func _test_fire_spread_and_water() -> void:
	TestBase.current = "fire"
	var p: Vector3 = lab_pos()
	var barn: Structure = build("barn", p, 0)
	var house: Structure = build("farmhouse", p + Vector3(8.0, 0, 0), 0)
	# ignite the barn's hay
	Breakable.awaken(barn)
	var lit: int = 0
	for part in barn.parts:
		if part.tag == "hay" and lit < 2:
			Fire.ignite(part, 1.0, {})
			lit += 1
	TestBase.check(Fire.burning_count() >= 1, "ignited parts are burning")
	var barn_frac: float = 0.0
	var house_burned: bool = false
	for i in 400:
		Fire._fire_tick(0.5)
		Breakable.tick(0.5)
		if i % 20 == 0:
			await tree.process_frame
		if i % 10 == 9:
			barn_frac = barn.destroyed_fraction()
			for part in house.parts:
				if part.on_fire or part.burning > 0.2 or part.state == Part.State.DEAD:
					house_burned = true
	TestBase.check(barn_frac > 0.25, "a burning barn burns down (%.0f%% destroyed)" % (barn_frac * 100.0))
	TestBase.check(house_burned, "fire spreads to the neighbouring building")
	# water extinguishes
	Fire.extinguish_in_radius(barn.center, 40.0, {}, 5.0)
	Fire.extinguish_in_radius(house.center, 40.0, {}, 5.0)
	TestBase.eq(Fire.burning_count(), 0, "a water burst puts everything out")
	# wet parts are immune for a while
	for part in house.parts:
		if part.state != Part.State.DEAD and part.mat.flammability > 0.0:
			Fire.ignite(part, 1.0, {})
			TestBase.check(not part.on_fire, "wet parts do not ignite")
			break
	Fire.reset()
	Fire.build_grid()

static func _test_powder_chain() -> void:
	TestBase.current = "powder"
	var p: Vector3 = lab_pos()
	var rng := Rng.new(8)
	var kegs: Array[Part] = []
	for i in 6:
		var s: Structure = Props.spawn("barrel_powder", p + Vector3(float(i) * 1.6, 0, 0), 0.0, 0, rng, Color.RED)
		kegs.append(s.parts[0])
	await frames(60)
	var counter: Array[int] = [0]
	var cb := func(_pos: Vector3, _r: float, _d: float, _s: Dictionary) -> void: counter[0] += 1
	Events.explosion.connect(cb)
	Props.detonate_powder(kegs[0], {})
	for i in 300:
		Explosion.tick(1.0 / 60.0)
		await tree.physics_frame
	Events.explosion.disconnect(cb)
	TestBase.check(counter[0] >= 4, "powder kegs explode in a chain (%d explosions)" % counter[0])
	var alive: int = 0
	for k in kegs:
		if k.state != Part.State.DEAD:
			alive += 1
	TestBase.eq(alive, 0, "all six kegs went up")

static func _test_debris_cap() -> void:
	TestBase.current = "debris"
	var p: Vector3 = lab_pos()
	var cap: int = Quality.body_cap
	for i in cap + 300:
		var d := PhysWorld.BodyDesc.new()
		d.shapes.append(PhysWorld.box_desc(Vector3(0.2, 0.2, 0.2)))
		d.xf = Transform3D(Basis(), p + Vector3(float(i % 30) * 0.3, 2.0 + float(i / 30) * 0.3, 0.0))
		d.mass = 1.0
		d.layer = Cfg.LAYER_DEBRIS
		d.mask = Cfg.LAYER_TERRAIN
		d.kind = "shard"
		var id: int = PhysWorld.add_body(d)
		Debris.register_shard(id, null)
	for i in 240:
		await tree.physics_frame
		Debris.tick(1.0 / 60.0)
	TestBase.check(Debris.count() <= cap + 20, "debris cap enforced (%d <= %d)" % [Debris.count(), cap])

static func _test_settings_roundtrip() -> void:
	TestBase.current = "settings"
	# test runs must never touch the player's real settings.cfg (the save is a no-op there)
	TestBase.check(Settings._is_test_run(), "autotest runs are recognised as test runs")
	var old_vol: float = Settings.volume
	var old_lang: String = Settings.language
	Settings.volume = 0.37
	Settings.save_settings()
	Settings.volume = 0.9
	Settings.load_settings()
	Settings.volume = old_vol
	# i18n runtime: a few keys resolve in both languages without falling back to the key
	for lang in ["en", "de"]:
		I18n.set_lang(lang)
		for key in ["menu.start", "hud.wind", "ammo.meteor", "building.church", "banner.win", "title.pyro", "event.dragon", "stats.title", "pause.resume"]:
			TestBase.check(I18n.t(key) != key, "%s resolves in %s" % [key, lang])
	I18n.set_lang(old_lang)

static func _test_catapult_placement() -> void:
	TestBase.current = "placement"
	var p: PlayerData = Game.players[0]
	var c: Vector3 = p.village_center
	TestBase.check(not world.spot_valid_for_catapult(p, c + Vector3(Cfg.ZONE_RADIUS + 5.0, 0, 0)), "outside the zone is invalid")
	var found: int = 0
	for i in 40:
		var a: float = float(i) * 0.9
		var pos := Vector3(c.x + cos(a) * 12.0, 0, c.z + sin(a) * 12.0)
		pos.y = Terrain.h(pos.x, pos.z)
		if world.spot_valid_for_catapult(p, pos):
			found += 1
	TestBase.check(found > 3, "some valid catapult spots exist inside the village (%d)" % found)

# ------------------------------------------------------------------ weapons are earned (spec 6.4b)
static func _test_unlocks() -> void:
	TestBase.current = "unlocks"
	var a: PlayerData = Game.players[0]
	var b: PlayerData = Game.players[1]
	a.reset_ammo()
	b.reset_ammo({"meteor": 2})
	TestBase.eq(a.ammo_count("stone"), -1, "stone is always there")
	TestBase.eq(a.ammo_count("firebarrel"), 0, "no fire barrel at the start (Standard preset)")
	TestBase.eq(a.ammo_count("cow"), 0, "the cow is locked at the start")
	TestBase.eq(b.ammo_count("meteor"), 2, "menu pre-grant works")
	TestBase.check(not a.has_ammo("meteor"), "a locked weapon is not usable")
	var src: Dictionary = {"player_id": a.id, "ammo": "stone"}
	Unlocks.on_animal_killed("cow", b.id)
	TestBase.eq(a.ammo_count("cow"), 0, "killing the ENEMY's cow earns nothing")
	Unlocks.on_animal_killed("cow", a.id)
	TestBase.eq(a.ammo_count("cow"), 1, "losing your own cow earns a cow")
	Unlocks.on_animal_killed("sheep", a.id)
	TestBase.eq(a.ammo_count("cow"), 1, "a sheep earns nothing")
	Unlocks.on_shot_buildings(a.id, 2)
	TestBase.eq(a.ammo_count("quad"), 1, "two buildings with one shot earn the stone hail")
	Unlocks.on_shot_settlers(a.id, 5)
	TestBase.eq(a.ammo_count("chain"), 1, "five settlers with one shot earn the chain shot")
	Unlocks.on_catapult_destroyed(b.id, src, "projectile")
	TestBase.eq(a.ammo_count("scatter"), 1, "destroying an enemy catapult earns buckshot")
	TestBase.eq(b.ammo_count("boulder"), 1, "losing a catapult earns a boulder")
	Unlocks.on_catapult_destroyed(b.id, src, "projectile")
	TestBase.eq(b.ammo_count("powderkeg"), 0, "losing catapults earns no powder keg")
	Unlocks.on_building_destroyed("blacksmith", b.id, src)
	TestBase.eq(b.ammo_count("powderkeg"), 1, "losing your own blacksmith earns a powder keg")
	Unlocks.on_building_destroyed("blacksmith", b.id, src)
	TestBase.eq(a.ammo_count("powdertrail"), 0, "an enemy blacksmith earns the attacker nothing")
	Unlocks.on_building_destroyed("church", b.id, src)
	TestBase.eq(a.ammo_count("meteor"), 0, "a church no longer earns the meteor marker (only the supply crate does)")
	Unlocks.on_building_destroyed("powderstore", b.id, src)
	TestBase.eq(a.ammo_count("boulder"), 0, "the powder store rule is a power rule: off in the core mode")
	Game.rule_level = 1
	Unlocks.on_building_destroyed("powderstore", b.id, src)
	TestBase.eq(a.ammo_count("boulder"), 1, "power mode: wrecking an enemy powder store earns a boulder")
	Game.rule_level = 0
	# fires count once per turn, every 3rd counted turn pays a fire barrel
	var fb0: int = a.ammo_count("firebarrel")
	for t in 6:
		Game.turn_number = 100 + t
		Unlocks.on_fire_started(src)
		Unlocks.on_fire_started(src)
	TestBase.eq(a.ammo_count("firebarrel"), fb0 + 2, "six fire turns = two fire barrels (core rule, one fire per turn)")
	TestBase.check(Unlocks.how("meteor").size() == 1 and Unlocks.how("powderkeg").size() == 2, "core rules listed for the locked weapon tooltips")
	TestBase.check(Unlocks.rules_of_mode(2, false).size() > Unlocks.rules_of_mode(0, false).size() - 1, "chaos lists at least the core rules")
	TestBase.eq(Settings.effective_rule_level(), 0, "Standard uses the core rules")
	# team gifts: a mate offers a weapon for the turn of the player on turn
	var gt0: int = a.team
	var gt1: int = b.team
	var gcur: int = Game.current_player
	var gph: int = Turn.phase
	a.team = 9
	b.team = 9
	Game.current_player = Game.players.find(b)
	Turn.phase = Turn.Phase.AIMING
	a.ammo["boulder"] = 2
	TestBase.check(Turn.set_gift(a.id, "boulder", true), "a team mate can offer a weapon")
	TestBase.eq(int(Turn.gifts.get("boulder", -1)), a.id, "the offer is registered for this turn")
	TestBase.check(not Turn.set_gift(a.id, "stone", true), "the stone cannot be offered")
	TestBase.check(not Turn.set_gift(b.id, "boulder", true), "you cannot offer to yourself")
	TestBase.check(Turn.set_gift(a.id, "boulder", false) and Turn.gifts.is_empty(), "an offer can be taken back")
	a.team = 8
	TestBase.check(not Turn.set_gift(a.id, "boulder", true), "an enemy cannot offer")
	a.team = gt0
	b.team = gt1
	Game.current_player = gcur
	Turn.phase = gph
	Turn.gifts.clear()
	# the supply crate: appears only after 5 shots of everybody, sinks, is hit by a shot -> meteor marker
	if RandomEvents.fx_root != null:
		SupplyCrate.reset()
		Game.crates_on = true
		SupplyCrate.spawn(1, "meteor", a.village_center + Vector3(40, 0, 0), "meteor", 1)
		TestBase.check(SupplyCrate.meteor_active(), "meteor crate spawns")
		var cr: Dictionary = SupplyCrate.crates[0]
		var h0: float = float(cr["height"])
		SupplyCrate.tick(2.0)
		TestBase.check(float(cr["height"]) < h0, "supply crate sinks")
		var m0: int = a.ammo_count("meteor")
		TestBase.check(not SupplyCrate.try_hit(Vector3(0, 500, 0), 0.5, src), "a shot far away misses the crate")
		TestBase.check(SupplyCrate.try_hit((cr["node"] as Node3D).position + Vector3(0, 0.7, 0), 0.5, src), "a shot hits the crate")
		TestBase.eq(a.ammo_count("meteor"), m0 + 1, "hitting the crate earns the meteor marker")
		TestBase.check(not SupplyCrate.meteor_active(), "the crate is gone after the hit")
		# small crate: 3 boulders / 5 logs
		var b0: int = a.ammo_count("boulder")
		SupplyCrate.spawn(2, "small", a.village_center + Vector3(-30, 0, 0), "boulder", 3)
		TestBase.eq(SupplyCrate.small_count(), 1, "small crate spawns")
		TestBase.check(SupplyCrate.try_hit((SupplyCrate.crates[0]["node"] as Node3D).position + Vector3(0, 0.5, 0), 0.5, src), "a shot hits the small crate")
		TestBase.eq(a.ammo_count("boulder"), b0 + 3, "a small crate holds 3 boulders")
		Game.rule_level = 2
		TestBase.check(SupplyCrate.small_target() >= int(Game.players.size() * 1.5) - 1, "chaos: 50% more small crates")
		Game.rule_level = 0
		SupplyCrate.reset()
	# three different trees
	var fake: Array[Structure] = []
	for i in 3:
		var s := Structure.new()
		s.kind = "tree"
		fake.append(s)
		Unlocks.on_tree_damaged(src, s)
		Unlocks.on_tree_damaged(src, s)
	TestBase.eq(a.ammo_count("log"), 1, "three damaged trees earn a log")
	a.use_ammo("cow")
	TestBase.eq(a.ammo_count("cow"), 0, "ammo is used up")

# ------------------------------------------------------------------ palisade posts (spec 2.3b)
static func _test_posts() -> void:
	TestBase.current = "posts"
	var me: PlayerData = Game.players[0]
	var rr := Rng.new(11)
	while Posts.count(me) > 0:
		Posts.remove_last(me)
	Game.palisades_per_player = 6
	var base: Vector3 = me.village_center + Vector3(Cfg.ZONE_RADIUS + 0.0 - 6.0, 0, 0)
	base.y = Terrain.h(base.x, base.z)
	var col: Dictionary = Posts.place_ground(me, base, rr)
	var near: Vector3 = Posts.snap_adjacent(me, base + Vector3(0.8, 0, 0.1))
	TestBase.near(Util.dist_xz(near, base), Posts.SPACING, 0.01, "a neighbouring post snaps to touching distance")
	Posts.place_stack(me, col, rr)
	Posts.place_stack(me, col, rr)
	# a fence is always three posts side by side; a stacked row adds three more on top
	while Posts.count(me) > 0:
		Posts.remove_last(me)
	col = Posts.place_ground(me, base, rr)
	Posts.place_stack(me, col, rr)
	Posts.place_stack(me, col, rr)
	var fc: Vector3 = base + Vector3(0, 0, 12.0)
	fc.y = Terrain.h(fc.x, fc.z)
	var parts0: int = 0
	for sx in Breakable.structures:
		if sx.kind == "palisadepost" and sx.owner_id == me.id:
			parts0 += 1
	var fence: Dictionary = Posts.place_fence(me, fc, 0.0, rr)
	var parts1: int = 0
	for sx2 in Breakable.structures:
		if sx2.kind == "palisadepost" and sx2.owner_id == me.id:
			parts1 += 1
	TestBase.eq(parts1 - parts0, 3, "one fence = three posts")
	TestBase.eq((fence["cols"] as Array).size(), 3, "three columns side by side")
	var c0: Vector3 = ((fence["cols"] as Array)[0] as Dictionary)["base"] as Vector3
	var c1: Vector3 = ((fence["cols"] as Array)[1] as Dictionary)["base"] as Vector3
	TestBase.near(Util.dist_xz(c0, c1), Posts.SPACING, 0.02, "the posts of a fence touch")
	TestBase.check(Posts.stack_fence(me, fence, rr), "a second row can be stacked on a fence")
	TestBase.eq(Posts.fence_layers(fence), 2, "two rows high")
	Posts.remove_last(me)
	TestBase.eq(Posts.fence_layers(fence), 1, "undo removes the whole row")
	Posts.remove_last(me)
	# rebuild the column test state
	while Posts.count(me) > 0:
		Posts.remove_last(me)
	col = Posts.place_ground(me, base, rr)
	Posts.place_stack(me, col, rr)
	Posts.place_stack(me, col, rr)
	var st: Array = col["structs"] as Array
	TestBase.eq(st.size(), 3, "three posts stacked")
	var top: Structure = st[2] as Structure
	TestBase.near(top.aabb.position.y, base.y + 2.0 * Posts.POST_H, 0.3, "the third post stands on the second")
	TestBase.near(Posts.POST_H * 2.0, 11.0, 0.01, "a post is half a tower high (5.5 m)")
	TestBase.check(not Posts.area_ok(me, Game.players[1].village_center), "no posts inside an enemy village")
	TestBase.check(Posts.area_ok(me, me.village_center), "posts inside the own village are fine")
	Posts.auto_place(me, rr)
	TestBase.eq(Posts.count(me), 6, "auto placement fills the post budget")
	# knocking out the bottom post brings the ones above down
	var low: Structure = st[0] as Structure
	var mid: Structure = st[1] as Structure
	for pp in low.parts.duplicate():
		Breakable.break_part(pp, {}, Vector3.UP, true)
	await tree.create_timer(0.3).timeout
	TestBase.check(mid.parts[0].state == Part.State.FREE, "the post above a destroyed post falls")
	while Posts.count(me) > 0:
		Posts.remove_last(me)
	TestBase.eq(me.posts.size(), 0, "undo removes every post")

## The stricter support rule (overhangs fall) must never tear down an intact building
static func _test_intact_buildings_stand() -> void:
	TestBase.current = "intact_buildings"
	var kinds: Array[String] = ["farmhouse", "barn", "tavern", "church", "watchtower", "well", "stall", "stable", "granary", "powderstore", "watertower", "windmill", "blacksmith", "outhouse", "palisade", "stonewall"]
	var bad: Array[String] = []
	for k in kinds:
		var st: Structure = build(k, lab_pos(), 0)
		Breakable.awaken(st)
		Breakable.support_check(st)
		var free_n: int = 0
		for part in st.parts:
			if part.state == Part.State.FREE:
				free_n += 1
		# a few loose pieces (signs, lanterns, a hay loft without glue links) were never attached - that was always so
		if free_n > maxi(3, st.parts.size() / 8):
			bad.append("%s:%d/%d" % [k, free_n, st.parts.size()])
	TestBase.check(bad.is_empty(), "intact buildings keep every part (released: %s)" % ", ".join(bad))

# ------------------------------------------------------------------ black powder (spec 6.4)
static func _test_powder() -> void:
	TestBase.current = "powder"
	Powder.reset()
	# a dry stretch of ground for the trail (the island has lakes and canyons now)
	var base: Vector3 = lab_pos() + Vector3(30, 0, 0)
	for tries in 40:
		var cand: Vector3 = lab_pos() + Vector3(20.0 + float(tries % 8) * 11.0, 0, float(tries / 8) * 14.0 - 28.0)
		var dry: bool = true
		for k0 in 12:
			var sx: float = cand.x + float(k0) * 1.6
			if Terrain.h(sx, cand.z) < Cfg.WATER_LEVEL + 1.0 or Terrain.slope_deg(sx, cand.z) > 25.0:
				dry = false
		if dry:
			base = cand
			break
	base.y = Terrain.h(base.x, base.z)
	for k in 12:
		Powder.drop(base + Vector3(float(k) * 1.6, 0, 0), {"player_id": 0, "ammo": "powdertrail"}, 1.0)
	TestBase.check(Powder.count() >= 10, "a trail of powder heaps lies on the ground (%d)" % Powder.count())
	for i in 100:
		Powder.tick(0.02)
	TestBase.check(Powder.count() >= 10, "unlit powder stays there for later turns")
	var idx_scorch_before: float = 0.0
	var data: MapData = Terrain.current.data
	var ix: int = int((base.x + 8.0 - data.origin) / data.cell)
	var iz: int = int((base.z - data.origin) / data.cell)
	idx_scorch_before = Terrain.current.scorch[iz * data.n + ix]
	Powder.ignite(base, 1.0, {"player_id": 1, "ammo": "stone"})
	for i in 200:
		Powder.tick(0.02)
	TestBase.eq(Powder.count(), 0, "one spark runs along the whole trail and burns all of it")
	TestBase.check(Terrain.current.scorch[iz * data.n + ix] > idx_scorch_before + 0.2, "the burnt trail leaves black marks on the ground")

# ------------------------------------------------------------------ landslides (spec 7.7)
static func _test_landslide() -> void:
	TestBase.current = "landslide"
	Landslide.reset()
	var t: Terrain = Terrain.current
	var data: MapData = t.data
	var c: Vector3 = lab_pos() + Vector3(-30, 0, 30)
	# an artificial very steep slope (about 50 degrees) over a 24 m patch
	var ix_c: int = int((c.x - data.origin) / data.cell)
	var iz_c: int = int((c.z - data.origin) / data.cell)
	var span: int = int(14.0 / data.cell)
	var base_h: float = Terrain.h(c.x, c.z)
	for iz in range(iz_c - span, iz_c + span + 1):
		for ix in range(ix_c - span, ix_c + span + 1):
			var rel: float = float(ix - ix_c) * data.cell
			data.heights[iz * data.n + ix] = base_h + 8.0 + clampf(-rel * 1.2, -8.0, 8.0)
	var pos := Vector3(c.x, Terrain.h(c.x, c.z), c.z)
	TestBase.check(Landslide.steepness(pos) >= Landslide.MIN_SLOPE, "the test slope is very steep (%.0f deg)" % Landslide.steepness(pos))
	TestBase.check(not Landslide.trigger(pos, 0.05, {}), "a tiny hit does not start a slide")
	var before: PackedFloat32Array = data.heights.duplicate()
	TestBase.check(Landslide.trigger(pos, 1.0, {"player_id": 0, "ammo": "boulder"}), "a strong hit on a steep slope starts a landslide")
	for i in 600:
		Landslide.tick(0.05)
	TestBase.check(not Landslide.active(), "the slide ends by itself")
	var moved: float = 0.0
	var max_slope_after: float = 0.0
	for k in before.size():
		moved += absf(data.heights[k] - before[k])
	var inner: int = int(7.0 / data.cell)
	for iz2 in range(iz_c - inner, iz_c + inner):
		for ix2 in range(ix_c - inner, ix_c + inner):
			var hh: float = data.heights[iz2 * data.n + ix2]
			var hx: float = data.heights[iz2 * data.n + ix2 + 1]
			max_slope_after = maxf(max_slope_after, rad_to_deg(atan(absf(hx - hh) / data.cell)))
	TestBase.check(moved > 5.0, "soil really moved (%.1f m summed)" % moved)
	TestBase.check(max_slope_after < 42.0, "the slope flattened out (%.0f deg at most inside the slide area)" % max_slope_after)
	# flat ground never slides
	var flat := Vector3(c.x + 60.0, Terrain.h(c.x + 60.0, c.z), c.z)
	if Landslide.steepness(flat) < Landslide.MIN_SLOPE:
		TestBase.check(not Landslide.trigger(flat, 5.0, {}), "gentle ground does not slide however hard it is hit")

## When the ground under a building is taken away (landslide / crater) the overhanging parts must fall
static func _test_ground_loss() -> void:
	TestBase.current = "ground_loss"
	var p: Vector3 = lab_pos() + Vector3(-60, 0, -30)
	p.y = Terrain.h(p.x, p.z)
	var st: Structure = build("farmhouse", p, 0)
	Breakable.awaken(st)
	var free_before: int = 0
	for part in st.parts:
		if part.state == Part.State.FREE:
			free_before += 1
	# dig a deep pit under the whole house (the ground it stood on is gone)
	Terrain.current.dig(Vector3(p.x, p.y, p.z), 7.0, 4.5, 0.0, 0.3)
	for i in 120:
		Breakable.tick(0.05)
	await tree.process_frame
	var free_after: int = 0
	for part2 in st.parts:
		if part2.state == Part.State.FREE:
			free_after += 1
	TestBase.check(free_after > free_before + 3, "parts above the vanished ground fall (%d -> %d released)" % [free_before, free_after])
