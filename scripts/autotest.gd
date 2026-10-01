class_name AutoTest
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Scripted scenarios for `godot --path . -- --autotest=<name>` (spec 21): run headless-friendly checks,
## save screenshots to user://shot_*.png and quit. Used to verify rendering / feel without a human.

static var m: Node
static var tree: SceneTree
static var log_lines: PackedStringArray = []

static func frames(n: int) -> void:
	for i in n:
		await tree.process_frame

static func seconds(t: float) -> void:
	await tree.create_timer(t, true, false, false).timeout

static func say(text: String) -> void:
	print("[autotest] ", text)

static func wait_loaded() -> void:
	while m.get("loading").visible or m.get("_generating"):
		await tree.process_frame

static func shot(name: String) -> void:
	await frames(3)
	m.call("_save_shot", name)

static func start_match(seed_text: String, types: Array, timer: int = 0) -> void:
	Settings.seed_text = seed_text
	Settings.timer = timer
	Settings.weather_on = bool(m.get("_autotest_weather"))
	Settings.events_on = bool(m.get("_autotest_events"))
	var menu: Menu = m.get("menu") as Menu
	menu.count = types.size()
	for i in Cfg.MAX_PLAYERS:
		var row: Dictionary = menu.rows[i]
		row["type"] = str(types[i % types.size()]) if i < types.size() else "peasant"
		row["color"] = i
	m.set("_last_config", menu.players_config())
	await m.call("_start_game", seed_text)

static func auto_place_all() -> void:
	var pl: Placement = m.get("placement") as Placement
	var guard: int = 0
	while pl._active and guard < 40:
		guard += 1
		var p: PlayerData = Game.players[pl.player_idx] if pl.player_idx < Game.players.size() else null
		if p != null and p.is_human():
			pl._auto_place()
			pl._done()
		await tree.process_frame
		await tree.create_timer(0.02).timeout

static func wait_phase(phase: int, timeout: float = 30.0) -> bool:
	var t: float = 0.0
	while Turn.phase != phase and t < timeout:
		await tree.process_frame
		t += 1.0 / 60.0
	return Turn.phase == phase

## Solve the aim for `target` with the CPU solver and fire the current human catapult.
static func aim_and_fire(target: Vector3, ammo: String, elev: float = 45.0) -> Dictionary:
	CpuAI.shooter = Turn.sel
	Turn.set_ammo(ammo)
	Turn.aim_ammo = ammo
	var r: Dictionary = CpuAI.solve_sample(Callable(CpuAI, "_origin_fn"), Turn.sel.global_pos(), target, ammo, Game.wind, elev, 0.0)
	Turn.set_aim(float(r["yaw"]), float(r["elev"]), float(r["power"]))
	Turn.fire()
	return r

static func run(main: Node, name: String) -> void:
	m = main
	tree = main.get_tree()
	say("scenario " + name)
	match name:
		"sound":
			while not Sfx.is_ready:
				await tree.process_frame
			say("synthesis took %.2f s, %d sounds" % [Sfx.synth_seconds, Sfx.streams.size()])
			for n in SoundRecipes.NAMES:
				if not Sfx.has_sound(n):
					say("MISSING sound " + n)
			Sfx.play("boom")
			await seconds(1.0)
		"menu":
			await wait_loaded()
			await frames(120)
			await shot("menu")
		"placement":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await frames(60)
			await shot("placement_1")
			await auto_place_all()
			await frames(30)
			await shot("battle_start")
		"hud":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await auto_place_all()
			await frames(90)
			var hud: Hud = m.get("hud") as Hud
			say("hud rect=%s size=%s visible=%s" % [str(hud.get_global_rect()), str(hud.size), str(hud.visible)])
			for c in hud.get_children():
				if c is Control:
					say("  %s rect=%s" % [c.name, str((c as Control).get_global_rect())])
			var uir: Control = m.get("ui_root") as Control
			say("ui_root size=%s" % str(uir.size))
			for c2 in uir.get_children():
				if c2 is Control:
					say("  ui child %s size=%s pos=%s vis=%s" % [c2.name, str((c2 as Control).size), str((c2 as Control).position), str((c2 as Control).visible)])
			var vp: Vector2 = m.get_viewport().get_visible_rect().size
			say("viewport %s" % str(vp))
			await shot("hud")
		"shoot":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await auto_place_all()
			await wait_phase(Turn.Phase.AIMING)
			var enemy: PlayerData = Game.players[1]
			var tgt: Vector3 = enemy.living_catapults()[0].global_pos()
			var best_c: Catapult = null
			var best_cover: int = 1 << 30
			for c in Game.cur().living_catapults():
				var cv: int = CpuAI.cover_along((c as Catapult).global_pos() + Vector3(0, 2, 0), tgt + Vector3(0, 1, 0))
				if cv < best_cover:
					best_cover = cv
					best_c = c as Catapult
			Turn.select_catapult(best_c)
			say("shooter cover=%d" % best_cover)
			var r: Dictionary = await aim_and_fire(tgt, "stone")
			say("solve err=%.2f yaw=%.1f elev=%.1f power=%.2f" % [float(r["err"]), rad_to_deg(float(r["yaw"])), float(r["elev"]), float(r["power"])])
			var t0: float = 0.0
			var shots: int = 0
			while Turn.phase != Turn.Phase.TURN_END and Turn.phase != Turn.Phase.TURN_START and t0 < 40.0:
				await tree.process_frame
				t0 += 1.0 / 60.0
				if Turn.phase == Turn.Phase.FLIGHT and shots == 0 and t0 > 0.6:
					shots = 1
					await shot("shoot_flight")
				if Turn.phase == Turn.Phase.AFTERMATH and shots == 1:
					shots = 2
					await frames(20)
					await shot("shoot_impact")
			for li in Projectile.impact_log:
				say("impact: %s" % str(li))
			say("stats: cats_destroyed=%d dmg=%d hits=%d shots=%d" % [Game.players[0].stats.catapults_destroyed, int(Game.players[0].stats.damage_dealt), Game.players[0].stats.hits, Game.players[0].stats.shots])
			say("turn ended after %.1f s, phase=%d, impact points=%s, cat hp=%s" % [t0, Turn.phase, str(Turn.impact_points), str(enemy.living_catapults().map(func(c: Variant) -> float: return (c as Catapult).hp))])
			await shot("shoot_after")
		"cpugame":
			await wait_loaded()
			var types: Array = str(m.get("_autotest_types")).split(",")
			await start_match(str(m.get("_autotest_seed")), types)
			await auto_place_all()
			m.set("_fast_forward", true)
			var last_turn: int = -1
			var wall: float = 0.0
			var max_wall: float = float(m.get("_autotest_wall"))
			while Game.state != Game.State.GAME_OVER and wall < max_wall:
				await tree.process_frame
				wall += 1.0 / maxf(Engine.get_frames_per_second(), 20.0)
				if Game.turn_number != last_turn and Turn.phase == Turn.Phase.TURN_START:
					last_turn = Game.turn_number
					var pl: PlayerData = Game.cur()
					say("turn %d: %s (%s) cats=%s" % [Game.turn_number, pl.name, pl.type, str(Game.players.map(func(x: PlayerData) -> int: return x.catapults_left()))])
					if Game.turn_number % 12 == 0:
						await shot("cpugame_%d" % Game.turn_number)
			say("state=%d turn=%d wall=%.0f s winner=%d" % [Game.state, Game.turn_number, wall, Game.last_winner])
			for pl2 in Game.players:
				say("  %s (%s): shots=%d hits=%d dmg=%d launched=%d killed=%d cats_destroyed=%d bldg=%d fires=%d" % [pl2.name, pl2.type, pl2.stats.shots, pl2.stats.hits, int(pl2.stats.damage_dealt), pl2.stats.settlers_launched, pl2.stats.settlers_killed, pl2.stats.catapults_destroyed, pl2.stats.buildings_destroyed, pl2.stats.fires_started])
			await frames(200)
			await shot("cpugame_end")
			await seconds(3.5)
			await shot("cpugame_results")
		"perf":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["squire", "squire", "squire"])
			await auto_place_all()
			if OS.get_environment("MM_PERF_W") != "":
				DisplayServer.window_set_size(Vector2i(int(OS.get_environment("MM_PERF_W")), int(OS.get_environment("MM_PERF_H"))))
			if OS.get_environment("MM_PERF_Q") != "":
				Events.quality_changed.emit(OS.get_environment("MM_PERF_Q"))
			if OS.get_environment("MM_PERF_L") != "":
				Settings.lighting = OS.get_environment("MM_PERF_L")
				Events.quality_changed.emit(Settings.quality)
				await frames(240)
				await shot("light_" + Settings.lighting)
				await frames(600)
				await shot("light_" + Settings.lighting + "_b")
			var census: Dictionary = {}
			var verts: int = 0
			var stack: Array = [tree.root]
			while not stack.is_empty():
				var nd: Node = stack.pop_back() as Node
				stack.append_array(nd.get_children())
				census[nd.get_class()] = int(census.get(nd.get_class(), 0)) + 1
				if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
					var mesh: Mesh = (nd as MeshInstance3D).mesh
					for si in mesh.get_surface_count():
						var arr: Array = mesh.surface_get_arrays(si)
						if arr.size() > 0 and arr[0] != null:
							verts += (arr[0] as PackedVector3Array).size()
			say("nodes: %s" % str(census))
			say("mesh vertices total: %d" % verts)
			var vp_rid: RID = tree.root.get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vp_rid, true)
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			var t_end: float = Time.get_ticks_msec() * 0.001 + float(OS.get_environment("MM_PERF_SECS") if OS.get_environment("MM_PERF_SECS") != "" else "40")
			var n: int = 0
			var sp: float = 0.0
			var sf: float = 0.0
			var worst: float = 0.0
			var last_us: int = Time.get_ticks_usec()
			var spikes: Array = []
			while Time.get_ticks_msec() * 0.001 < t_end:
				await tree.process_frame
				var nowu: int = Time.get_ticks_usec()
				var ft: float = float(nowu - last_us) / 1000.0
				last_us = nowu
				if ft > 20.0 and n > 300:
					spikes.append([snappedf(ft, 0.1), "turn%d ph%d" % [Game.turn_number, Turn.phase]])
				var tp: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				var tf: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				sp += tp
				sf += tf
				worst = maxf(worst, tp + tf)
				n += 1
				if n % 120 == 0:
					say("render: fps=%d gpu=%.2f ms cpu=%.2f ms draws=%d prims=%d objs=%d win=%s q=%s" % [int(Engine.get_frames_per_second()), RenderingServer.viewport_get_measured_render_time_gpu(vp_rid), RenderingServer.viewport_get_measured_render_time_cpu(vp_rid), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)), str(DisplayServer.window_get_size()), Quality.current_id])
					say("frames=%d avg process=%.2f ms physics=%.2f ms worst=%.1f objs=%d" % [n, sp / n, sf / n, worst, int(Performance.get_monitor(Performance.OBJECT_COUNT))])
			say("SPIKES(>20ms) n=%d: %s" % [spikes.size(), str(spikes.slice(0, 40))])
			say("PROF us/total %s" % str(GameWorld.prof))
			say("PERF avg process=%.2f ms avg physics=%.2f ms worst=%.1f ms frames=%d" % [sp / n, sf / n, worst, n])
		"physics":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await auto_place_all()
			await frames(30)
			# build a church in an empty spot near the map center and drop everything
			var ctx := BuildContext.new()
			var rr := Rng.new(5)
			var res: BuildResult = Buildings.build("church", ctx, rr)
			var pos := Vector3(-20, 0, 60)
			pos.y = Terrain.h(pos.x, pos.z)
			var st: Structure = Breakable.create("church", 0, res, Transform3D(Basis(), pos))
			say("church parts=%d anchors=%d ground=%.2f" % [st.parts.size(), st.parts.filter(func(p: Part) -> bool: return p.anchor).size(), pos.y])
			Breakable.awaken(st)
			var bell: Part = null
			for p in st.parts:
				if p.tag == "bell":
					bell = p
			say("bell y=%.2f state=%d" % [bell.xf.origin.y, bell.state])
			# break the foundation: everything should be released
			for p in st.parts.duplicate():
				if p.anchor:
					Breakable.break_part(p, {}, Vector3.ZERO, true)
			Breakable.support_check(st)
			var free_n: int = 0
			for p in st.parts:
				if p.state == Part.State.FREE:
					free_n += 1
			say("after foundation removed: free=%d of live=%d" % [free_n, st.live_count])
			for i in 8:
				await seconds(0.5)
				if bell.state != Part.State.DEAD:
					say("t=%.1f bell y=%.2f vel=%s" % [float(i) * 0.5, PhysWorld.get_transform(bell.body_id).origin.y, str(PhysWorld.get_velocity(bell.body_id))])
			await shot("physics_church")
		"physics2":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			await frames(30)
			var ch: Structure = null
			for sx in Breakable.structures:
				if sx.kind == "church" and sx.owner_id == 0:
					ch = sx
			if ch == null:
				say("no church in village 0")
			else:
				say("church center=%s ground=%.2f" % [str(ch.center), Terrain.h(ch.center.x, ch.center.z)])
				Breakable.awaken(ch)
				var bell2: Part = null
				for p in ch.parts:
					if p.tag == "bell":
						bell2 = p
				for p in ch.parts.duplicate():
					if p.anchor:
						Breakable.break_part(p, {}, Vector3.ZERO, true)
				Breakable.support_check(ch)
				for i in 8:
					await seconds(0.5)
					if bell2.state != Part.State.DEAD:
						say("t=%.1f bell y=%.2f vel=%s" % [float(i) * 0.5, PhysWorld.get_transform(bell2.body_id).origin.y, str(PhysWorld.get_velocity(bell2.body_id))])
				await shot("physics2")
		"ammo":
			await wait_loaded()
			Settings.palisade_count = 1
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			for eid in AmmoDef.earnable_ids():
				Game.players[0].add_ammo(eid, 3)
			var ammos: Array = str(m.get("_autotest_ammo")).split(",")
			var enemy2: PlayerData = Game.players[1]
			for a in ammos:
				var guard2: float = 0.0
				while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and guard2 < 120.0:
					await tree.process_frame
					guard2 += 1.0 / 60.0
				if Turn.phase != Turn.Phase.AIMING:
					say("no aiming phase for " + str(a))
					break
				var kind_target: String = "tavern" if a != "boulder" else "barn"
				var tstruct: Structure = null
				for sx in Breakable.structures:
					if sx.owner_id == 1 and sx.kind == kind_target and not sx.destroyed:
						tstruct = sx
				var target: Vector3 = tstruct.center if tstruct != null else enemy2.village_center
				var best2: Catapult = null
				var bc2: int = 1 << 30
				for c in Game.cur().living_catapults():
					var cv2: int = CpuAI.cover_along((c as Catapult).global_pos() + Vector3(0, 2, 0), target + Vector3(0, 1, 0))
					if cv2 < bc2:
						bc2 = cv2
						best2 = c as Catapult
				Turn.select_catapult(best2)
				var fires0: int = Fire.burning_count()
				var settlers0: int = Settler.all.filter(func(x: Settler) -> bool: return x.state != Settler.State.DEAD).size()
				var res2: Dictionary = await aim_and_fire(target, str(a), 45.0 if a != "cow" else 50.0)
				say("%s -> %s err=%.1f" % [str(a), kind_target, float(res2["err"])])
				await wait_phase(Turn.Phase.AFTERMATH, 20.0)
				await frames(45)
				await shot("ammo_" + str(a))
				await seconds(10.0 if a == "beehive" else 2.5)
				await shot("ammo_" + str(a) + "_later")
				var settlers1: int = Settler.all.filter(func(x: Settler) -> bool: return x.state != Settler.State.DEAD).size()
				say("  powder heaps now: %d, landslides: %d" % [Powder.count(), Landslide.slides.size()])
				say("  fires %d -> %d, settlers alive %d -> %d, target destroyed_frac=%.2f" % [fires0, Fire.burning_count(), settlers0, settlers1, tstruct.destroyed_fraction() if tstruct != null else -1.0])
				await wait_phase(Turn.Phase.TURN_START, 60.0)
		"events":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant", "squire"])
			await auto_place_all()
			await wait_phase(Turn.Phase.AIMING, 60.0)
			var cam4: CameraRig = m.get("cam_rig") as CameraRig
			var ids: Array = str(m.get("_autotest_events_list")).split(",")
			for id in ids:
				var mm: MapData = (m.get("world") as GameWorld).map
				cam4.overview(Vector3.ZERO, mm.map_radius * 1.15, 52.0)
				cam4.snap()
				m.set("_overview", true)
				RandomEvents.trigger(str(id))
				say("event " + str(id) + " started")
				await seconds(3.0)
				await shot("event_" + str(id))
				var guard4: float = 0.0
				while RandomEvents.busy() and guard4 < 40.0:
					await seconds(0.5)
					guard4 += 0.5
				say("event " + str(id) + " finished after %.1f s (water y=%.2f)" % [3.0 + guard4, Terrain.current.water_y])
				await seconds(1.0)
		"windmill":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant", "squire", "knight"])
			await auto_place_all()
			await frames(120)
			var wm: Structure = null
			for sx in Breakable.structures:
				if sx.kind == "windmill":
					wm = sx
					break
			if wm == null:
				say("no windmill in this seed")
			else:
				var beh: Specials.Windmill = wm.behavior as Specials.Windmill
				say("windmill rotor body=%d attached=%s" % [beh.rotor_id, str(beh.attached)])
				var a0: Basis = PhysWorld.get_transform(beh.rotor_id).basis
				await seconds(1.0)
				var a1: Basis = PhysWorld.get_transform(beh.rotor_id).basis
				var ang: float = a0.get_rotation_quaternion().angle_to(a1.get_rotation_quaternion())
				say("rotor turned %.1f deg in 1 s (expected about 40)" % rad_to_deg(ang))
				var cam5: CameraRig = m.get("cam_rig") as CameraRig
				cam5.focus_on(wm.center, 22.0, 20.0, 0.0)
				cam5.snap()
				await frames(20)
				await shot("windmill_a")
				# hit the windmill: the sails must fall off
				Explosion.explode(wm.center + Vector3(0, 6, 4), 3.0, 200.0, {"source": {}, "no_crater": true})
				await seconds(2.0)
				say("after a hit: attached=%s" % str(beh.attached))
				await shot("windmill_b")
		"marker":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant", "peasant"])
			await auto_place_all()
			var guard5: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and guard5 < 60.0:
				await tree.process_frame
				guard5 += 1.0 / 60.0
			await seconds(2.0)
			var rig5: CameraRig = m.get("cam_rig") as CameraRig
			var me: PlayerData = Game.players[0]
			# 1) overview must show the whole map, at a useful height
			m.call("_toggle_overview")
			await seconds(2.5)
			say("overview: camera y=%.0f, distance to focus=%.0f, map radius=%.0f" % [rig5.cam.global_position.y, rig5.cam.global_position.distance_to(rig5.focus), (m.get("world") as GameWorld).map.map_radius])
			var vis_sites: int = 0
			var vp: Vector2 = (m.get("get_viewport") as Callable).call().get_visible_rect().size if false else Vector2(1600, 900)
			for pl in Game.players:
				var sp: Vector2 = rig5.project(pl.village_center)
				if sp.x > 0 and sp.x < vp.x and sp.y > 0 and sp.y < vp.y and not rig5.is_behind(pl.village_center):
					vis_sites += 1
			say("overview shows %d of %d villages" % [vis_sites, Game.players.size()])
			await shot("overview")
			# 2) a left click on the enemy village sets the marker
			var target: Vector3 = Game.players[1].village_center
			var click_at: Vector2 = rig5.project(target)
			var cl := InputEventMouseButton.new()
			cl.button_index = MOUSE_BUTTON_LEFT
			cl.pressed = true
			cl.position = click_at
			Input.parse_input_event(cl)
			await frames(5)
			say("marker after click: %s (enemy village at %s, error %.1f m)" % [str(me.marker), str(target), Util.dist_xz(me.marker, target) if me.marker != Vector3.INF else -1.0])
			# 3) a second click elsewhere replaces it
			var t2: Vector3 = Game.players[2].village_center
			cl.position = rig5.project(t2)
			Input.parse_input_event(cl)
			await frames(5)
			say("second click moves it (only one marker): now %.1f m from village 3, %.1f m from village 2" % [Util.dist_xz(me.marker, t2), Util.dist_xz(me.marker, target)])
			await seconds(0.6)
			await shot("overview_marker")
			# 4) back to the aim camera: the compass shows the direction, M faces it
			m.call("_toggle_overview")
			await seconds(2.0)
			var aim5: Aiming = m.get("aiming") as Aiming
			aim5._face_marker()
			await seconds(1.5)
			say("after M: aim yaw %.1f deg, marker heading %.1f deg" % [rad_to_deg(Turn.aim_yaw), rad_to_deg(Util.dir_to_yaw(Util.flat(me.marker - Turn.sel.global_pos())))])
			Turn.set_aim(Turn.aim_yaw, Turn.aim_elev, 0.6)
			await seconds(0.5)
			say(Aiming.marker_text(Turn.sel.global_pos(), me.marker, Turn.aim_yaw, 100.0))
			await shot("aim_marker")
			# 5) fire; the marker must survive the other players' turns
			Turn.set_ammo("firebarrel")
			Turn.fire()
			var mk_before: Vector3 = me.marker
			var guard7: float = 0.0
			while not (Game.cur().id == 1 and Turn.phase == Turn.Phase.AIMING) and guard7 < 120.0:
				await tree.process_frame
				guard7 += 1.0 / 60.0
			say("next player's ammo: %s (must be stone, player 0 chose firebarrel, stored %s)" % [Turn.aim_ammo, me.ammo_sel])
			(m.set as Callable).call("_fast_forward", true) if false else m.set("_fast_forward", true)
			var guard6: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0 or Turn.turn_count < 4) and guard6 < 240.0:
				await tree.process_frame
				guard6 += 1.0 / 60.0
				if Game.cur().id == 0 and Turn.phase == Turn.Phase.AIMING and Turn.turn_count >= 4:
					break
			await frames(4)
			say("turn %d, marker kept across turns: %s" % [Turn.turn_count, str(me.marker == mk_before)])
			say("fast-forward auto-off at the human's aiming phase: %s" % str(not m.get("_fast_forward")))
			await seconds(2.0)
			await shot("aim_marker_turn2")
		"redkeg":
			await wait_loaded()
			Settings.palisade_count = 1
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			Game.players[0].add_ammo("redkeg", 2)
			var guard9: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and guard9 < 60.0:
				await tree.process_frame
				guard9 += 1.0 / 60.0
			await seconds(1.0)
			var tav: Structure = null
			for sx2 in Breakable.structures:
				if sx2.owner_id == 1 and sx2.kind == "tavern":
					tav = sx2
			var tgt: Vector3 = tav.center if tav != null else Game.players[1].village_center
			var best9: Catapult = null
			var bc9: int = 1 << 30
			for c9 in Game.cur().living_catapults():
				var cv9: int = CpuAI.cover_along((c9 as Catapult).global_pos() + Vector3(0, 2, 0), tgt + Vector3(0, 1, 0))
				if cv9 < bc9:
					bc9 = cv9
					best9 = c9 as Catapult
			Turn.select_catapult(best9)
			var hp0: float = Breakable.village_hp(1)
			var rk: Dictionary = await aim_and_fire(tgt, "redkeg", 45.0)
			say("solver err %.1f m, power %.2f" % [float(rk["err"]), float(rk["power"])])
			await wait_phase(Turn.Phase.AFTERMATH, 60.0)
			await seconds(3.0)
			var hp1: float = Breakable.village_hp(1)
			say("red keg: village HP %.0f -> %.0f (%.0f%% destroyed)" % [hp0, hp1, 100.0 * (1.0 - hp1 / maxf(hp0, 1.0))])
			await shot("redkeg_impact")
		"tab":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var guard8: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and guard8 < 60.0:
				await tree.process_frame
				guard8 += 1.0 / 60.0
			await seconds(1.0)
			var before: int = Turn.sel.index
			for k in 3:
				var kev := InputEventKey.new()
				kev.keycode = KEY_TAB
				kev.physical_keycode = KEY_TAB
				kev.pressed = true
				Input.parse_input_event(kev)
				await frames(6)
				kev.pressed = false
				Input.parse_input_event(kev)
				await frames(6)
				say("Tab %d: selected catapult index %d (was %d)" % [k + 1, Turn.sel.index, before])
		"aiminput":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var guard3: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and guard3 < 60.0:
				await tree.process_frame
				guard3 += 1.0 / 60.0
			await seconds(2.5)
			var yaw0: float = Turn.aim_yaw
			var ok_all: bool = true
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = Vector2(800, 450)
			Input.parse_input_event(press)
			await frames(2)
			var mv := InputEventMouseMotion.new()
			var rig: CameraRig = m.get("cam_rig") as CameraRig
			# the on-screen direction of the real launch heading must equal the opposite of the pull, for every direction
			var worst_err: float = 0.0
			for k in 12:
				var ang: float = TAU * float(k) / 12.0
				var pull: Vector2 = Vector2.from_angle(ang) * 110.0
				mv.position = Vector2(800, 450) + pull
				mv.relative = pull
				mv.button_mask = MOUSE_BUTTON_MASK_LEFT
				Input.parse_input_event(mv)
				await seconds(0.6)
				var cat: Catapult = Turn.sel
				var base: Vector3 = cat.global_pos()
				var s0: Vector2 = rig.project(base)
				var s1: Vector2 = rig.project(base + Util.yaw_to_dir(Turn.aim_yaw) * 4.0)
				var want: Vector2 = -pull.normalized()
				var got: Vector2 = (s1 - s0).normalized()
				var err: float = rad_to_deg(absf(want.angle_to(got)))
				worst_err = maxf(worst_err, err)
			say("screen-true aiming: worst angle error over 12 pull directions = %.2f deg (power %.2f, elevation %.1f)" % [worst_err, Turn.aim_power, Turn.aim_elev])
			var pw_ok: bool = worst_err < 3.0 and absf(Turn.aim_power - 0.5) < 0.02 and absf(Turn.aim_elev - Cfg.DEFAULT_ELEVATION) < 0.01
			say("mapping %s (expected error < 3 deg, power 0.50, elevation unchanged)" % ("OK" if pw_ok else "WRONG"))
			mv.position = Vector2(700, 550)
			mv.relative = Vector2(-100, 100)
			Input.parse_input_event(mv)
			await frames(6)
			await shot("aim_drag")
			var prev_vis: bool = false
			for c3 in m.get("aiming").get_parent().get_children():
				pass
			var aim_node: Aiming = m.get("aiming") as Aiming
			say("preview visible=%s dragging=%s" % [str(aim_node._preview.visible), str(aim_node.dragging)])
			# release: must fire
			var rel := InputEventMouseButton.new()
			rel.button_index = MOUSE_BUTTON_LEFT
			rel.pressed = false
			rel.position = Vector2(700, 550)
			Input.parse_input_event(rel)
			await frames(20)
			say("after release: phase=%d (FIRING=4 / FLIGHT=5) ammo stone shots=%d" % [Turn.phase, Game.players[0].stats.shots])
			await wait_phase(Turn.Phase.TURN_END, 60.0)
			say("turn ended, hits=%d" % Game.players[0].stats.hits)
			# a tiny pull (< 10 px) must cancel without firing
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and guard3 < 200.0:
				await tree.process_frame
				guard3 += 1.0 / 60.0
			await frames(30)
			var shots_before: int = Game.players[0].stats.shots
			press.position = Vector2(800, 450)
			Input.parse_input_event(press)
			await frames(2)
			mv.position = Vector2(804, 453)
			mv.relative = Vector2(4, 3)
			Input.parse_input_event(mv)
			await frames(2)
			rel.position = Vector2(804, 453)
			Input.parse_input_event(rel)
			await frames(10)
			say("tiny pull: fired=%s (must be false)" % str(Game.players[0].stats.shots != shots_before))
		"units":
			await wait_loaded()
			while not Sfx.is_ready:
				await tree.process_frame
			await start_match("unit-tests", ["human", "peasant"])
			await auto_place_all()
			await frames(30)
			SceneUnits.main = m
			SceneUnits.tree = tree
			SceneUnits.world = m.get("world") as GameWorld
			await SceneUnits.run_all()
			tree.quit(1 if TestBase.failed > 0 else 0)
			return
		"perf":
			Settings.vsync = false
			Settings.apply_display()
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["knight", "king", "squire", "king"])
			await auto_place_all()
			var t_total: float = 0.0
			var samples: int = 0
			var fps_sum: float = 0.0
			var fps_min: float = 1e9
			var last_report: float = 0.0
			var max_t: float = float(m.get("_autotest_wall"))
			while t_total < max_t and Game.state != Game.State.GAME_OVER:
				await tree.process_frame
				var dt: float = 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
				t_total += dt
				var f: float = Engine.get_frames_per_second()
				if f > 0.0:
					fps_sum += f
					samples += 1
					fps_min = minf(fps_min, f)
				if t_total - last_report > 5.0:
					last_report = t_total
					say("t=%.0f fps=%.0f (min %.0f) process=%.1fms physics=%.1fms bodies=%d awake=%d active_phys=%d draw=%d objs=%d nodes=%d turn=%d" % [t_total, fps_sum / float(maxi(samples, 1)), fps_min,
						Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
						PhysWorld.bodies.size(), PhysWorld.awake_count(), int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
						int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), Game.turn_number])
					fps_sum = 0.0
					samples = 0
					fps_min = 1e9
		"village":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant", "squire", "knight"])
			await frames(60)
			var world: GameWorld = m.get("world") as GameWorld
			var cam: CameraRig = m.get("cam_rig") as CameraRig
			for i in 4:
				var p: PlayerData = Game.players[i]
				cam.focus_on(p.village_center, 40.0, 38.0, float(i) * 1.3)
				cam.snap()
				await frames(30)
				await shot("village_%d" % i)
			say("structures=%d awake=%d bodies=%d settlers=%d" % [Breakable.structures.size(), Breakable.awake_list.size(), PhysWorld.bodies.size(), Settler.all.size()])
		_:
			say("unknown scenario")
	say("done")
	tree.quit()
