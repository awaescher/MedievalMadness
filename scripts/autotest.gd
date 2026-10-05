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

static func cam_focus_wall(rig: CameraRig, w: Dictionary) -> void:
	rig.focus_on(w["center"] as Vector3 + Vector3.UP * 3.0, 22.0, 25.0, float(w["yaw"]) + 0.6)
	rig.snap()

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
	Settings.arsenal_preset = "custom"
	Settings.arsenal_custom = {"firebarrel": 2}
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
	while pl._active and guard < 3000:
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

static func uarg(name: String, default_value: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.get_slice("=", 1)
	return default_value

## Online test player: place automatically, then fire a stone at an enemy every time it is this peer's turn
static func net_play(max_turns: int, max_wall: float) -> void:
	var wall: float = 0.0
	var last_turn: int = -1
	var logged: int = -1
	while Game.state != Game.State.GAME_OVER and wall < max_wall and Game.turn_number < max_turns + 1:
		await tree.process_frame
		wall += 1.0 / maxf(Engine.get_frames_per_second(), 20.0)
		var pl: Node = m.get("placement") as Node
		if Game.state == Game.State.PLACEMENT and pl != null and bool(pl.get("_active")):
			var pidx: int = int(pl.get("player_idx"))
			if pidx >= 0 and pidx < Game.players.size() and Game.players[pidx].is_human():
				pl.call("_auto_place")
				await frames(3)
				pl.call("_done")
		if Game.state == Game.State.BATTLE and Game.turn_number != logged and Turn.phase == Turn.Phase.TURN_START:
			logged = Game.turn_number
			var cats: Array = Game.players.map(func(x: PlayerData) -> int: return x.catapults_left())
			say("NETLOG turn=%d cur=%d wind=(%.2f,%.2f) hash=%d dead=%d fixed=%d missing=%d impact=%s cats=%s" % [Game.turn_number, Game.current_player, Game.wind.x, Game.wind.y, NetGame.live_hash(), NetGame.dead_total(), NetGame.fixed_parts, NetGame.missing_parts, str(Projectile.last_impact_pos), str(cats)])
		if Game.state == Game.State.BATTLE and Turn.phase == Turn.Phase.AIMING and Game.cur().is_human() and last_turn != Game.turn_number and Turn.sel == null:
			pass
		if Game.state == Game.State.BATTLE and Turn.phase == Turn.Phase.AIMING and Game.cur().is_human() and last_turn != Game.turn_number:
			last_turn = Game.turn_number
			await seconds(0.6)
			var me: PlayerData = Game.cur()
			var tgt: PlayerData = null
			for o in Game.players:
				if o.id != me.id and not o.eliminated and o.catapults_left() > 0:
					tgt = o
					break
			if tgt != null and not me.living_catapults().is_empty():
				Turn.select_catapult(me.living_catapults()[0] as Catapult)
				aim_and_fire((tgt.living_catapults()[0] as Catapult).global_pos(), "stone", 45.0)
	var cats2: Array = Game.players.map(func(x: PlayerData) -> int: return x.catapults_left())
	say("NETDONE state=%d turn=%d hash=%d cats=%s mismatches=%d fixed_parts=%d missing_parts=%d winner=%d bytes_out=%d bytes_in=%d" % [Game.state, Game.turn_number, NetGame.live_hash(), str(cats2), NetGame.hash_mismatches, NetGame.fixed_parts, NetGame.missing_parts, Game.last_winner, Net.bytes_out, Net.bytes_in])

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
			Events.banner.emit(I18n.t("banner.placement") + " - " + Game.players[0].name + " has a really long banner text, Sir", "info")
			Events.reward.emit(Game.players[0].id, "cow", 2, Game.players[0].village_center)
			Events.reward.emit(Game.players[1].id, "boulder", 1, Game.players[0].village_center)
			await frames(30)
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
		"crate":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await auto_place_all()
			await wait_phase(Turn.Phase.AIMING)
			var spot: Vector3 = SupplyCrate._pick_meteor_spot()
			say("crate spot %s" % str(spot))
			SupplyCrate.spawn(1, "meteor", spot, "meteor", 1)
			SupplyCrate.crates[0]["height"] = 14.0
			SupplyCrate.tick(0.01)
			var cm: Node = tree.root.get_node_or_null("Main")
			var cam: CameraRig = (cm.get("cam_rig") as CameraRig) if cm != null else null
			if cam != null:
				cam.focus_on(spot + Vector3(0, 6, 0), 28.0, 30.0)
			await frames(90)
			await shot("crate_sinking")
			SupplyCrate.crates[0]["height"] = 0.05
			await frames(60)
			await shot("crate_landed")
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
		"results_ui":
			# fills the stats with made-up numbers and shows the results screen (layout check, shots "results_ui_*")
			await wait_loaded()
			var rt: Array = str(m.get("_autotest_types")).split(",")
			await start_match(str(m.get("_autotest_seed")), rt)
			for ri in Game.players.size():
				var rp: PlayerData = Game.players[ri]
				rp.points = [25589, 5180, 12475, 1963, 887][ri % 5]
				rp.stats.shots = 31 - ri
				rp.stats.hits = [21, 5, 24, 1, 0][ri % 5]
				rp.stats.damage_dealt = [176658.0, 10677.0, 131550.0, 664.0, 0.0][ri % 5]
				rp.stats.longest_shot = [413.0, 416.0, 237.0, 542.0, 642.0][ri % 5]
			(m.get("results") as Results).show_results(0, false)
			await seconds(2.5)
			await shot("results_ui")
		"restart":
			# plays CPU games and restarts the same map several times (the results screen button "same map")
			await wait_loaded()
			for round_i in 4:
				if round_i == 0:
					await start_match("autotest-r", ["squire", "knight", "king"])
				else:
					m.call("_restart_game", "autotest-r", true)
					await frames(30)
				await wait_loaded()
				await auto_place_all()
				m.set("_fast_forward", true)
				var wall2: float = 0.0
				while Game.state != Game.State.GAME_OVER and wall2 < 60.0:
					await tree.process_frame
					wall2 += 1.0 / maxf(Engine.get_frames_per_second(), 20.0)
				say("round %d: state=%d turn=%d wall=%.0f" % [round_i, Game.state, Game.turn_number, wall2])
				m.set("_fast_forward", false)
			say("restart test survived")
		"styles":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await auto_place_all()
			await wait_phase(Turn.Phase.AIMING)
			await seconds(2.0)
			(m.get("ui_layer") as CanvasLayer).visible = false
			var rig_s: CameraRig = m.get("cam_rig") as CameraRig
			Settings.quality = "ultra"
			Events.quality_changed.emit("ultra")
			var vc: Vector3 = Game.players[0].village_center
			for gs in Settings.GFX_STYLES:
				Settings.gfx_style = gs
				Events.quality_changed.emit(Settings.quality)
				rig_s.focus_on(vc + Vector3.UP * 2.0, 40.0, 24.0, 0.5)
				rig_s.snap()
				await frames(90)
				await shot("style_" + gs + "_a")
				rig_s.focus_on(vc + Vector3.UP * 2.0, 14.0, 16.0, 1.6)
				rig_s.snap()
				await frames(30)
				await shot("style_" + gs + "_b")
			await seconds(2.0)
			Events.quality_changed.emit(Settings.quality)
			var tree_pos: Vector3 = Vector3.INF
			for st in Breakable.structures:
				if st.kind == "tree" and not st.parts.is_empty():
					var tp: Vector3 = (st.parts[0] as Part).xf.origin
					if tree_pos == Vector3.INF or tp.distance_to(vc) < tree_pos.distance_to(vc):
						tree_pos = tp
			say("tree at %s (village %s)" % [str(tree_pos), str(vc)])
			if tree_pos != Vector3.INF:
				rig_s.focus_on(tree_pos + Vector3.UP * 3.0, 11.0, 14.0, 0.9)
				rig_s.snap()
				await frames(60)
				await shot("style_photo_tree")
				Settings.gfx_style = "toon"
				Events.quality_changed.emit(Settings.quality)
				await frames(40)
				await shot("style_toon_tree")
		"water":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await auto_place_all()
			await wait_phase(Turn.Phase.AIMING)
			await seconds(1.5)
			(m.get("ui_layer") as CanvasLayer).visible = false
			Settings.quality = "ultra"
			var mp: MapData = (m.get("world") as GameWorld).map
			var best: Vector2 = Vector2.INF
			var depth_best: float = 0.0
			for xi in range(-100, 101, 6):
				for zi in range(-100, 101, 6):
					var cnt: int = 0
					for dx in range(-12, 13, 6):
						for dz in range(-12, 13, 6):
							if mp.in_bounds(float(xi + dx), float(zi + dz)) and mp.height_at(float(xi + dx), float(zi + dz)) < Cfg.WATER_LEVEL - 0.3:
								cnt += 1
					if cnt > depth_best:
						depth_best = cnt
						best = Vector2(xi, zi)
			say("water spot %s (%d wet samples)" % [str(best), int(depth_best)])
			var cam_w := Camera3D.new()
			m.add_child(cam_w)
			cam_w.fov = 55.0
			for gs in ["photo", "toon"]:
				Settings.gfx_style = gs
				Events.quality_changed.emit("ultra")
				cam_w.global_position = Vector3(best.x + 18.0, Cfg.WATER_LEVEL + 22.0, best.y + 26.0)
				cam_w.look_at(Vector3(best.x, Cfg.WATER_LEVEL, best.y))
				cam_w.make_current()
				await frames(60)
				await shot("water_" + gs)
		"trees":
			await wait_loaded()
			await start_match("autotest-a", ["human", "peasant"])
			await auto_place_all()
			await wait_phase(Turn.Phase.AIMING)
			await seconds(2.0)
			(m.get("ui_layer") as CanvasLayer).visible = false
			var rig_t: CameraRig = m.get("cam_rig") as CameraRig
			Settings.quality = "ultra"
			var tpos: Vector3 = Vector3.INF
			for st in Breakable.structures:
				if st.kind == "tree" and not st.parts.is_empty():
					var tp: Vector3 = (st.parts[0] as Part).xf.origin
					if tpos == Vector3.INF or tp.distance_to(Game.players[0].village_center) < tpos.distance_to(Game.players[0].village_center):
						tpos = tp
			for gs in ["photo", "toon"]:
				Settings.gfx_style = gs
				Events.quality_changed.emit("ultra")
				Events.quality_changed.emit("ultra")
				for k in 3:
					var ang: float = 0.9 + float(k) * 1.4
					var rad: float = 8.0 + float(k) * 5.0
					var cam_t := Camera3D.new()
					m.add_child(cam_t)
					cam_t.fov = 55.0
					cam_t.global_position = tpos + Vector3(cos(ang) * rad, 2.5 + float(k) * 2.0, sin(ang) * rad)
					cam_t.look_at(tpos + Vector3.UP * 2.2)
					cam_t.make_current()
					await frames(60)
					await shot("tree_%s_%d" % [gs, k])
					cam_t.queue_free()
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
				await seconds(12.0 if a == "meteor" else 2.5)
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
		"menu_arsenal":
			await wait_loaded()
			await seconds(2.5)
			var mn: Menu = m.get("menu") as Menu
			Settings.arsenal_preset = "quarry"
			await shot("menu_row")
			var lob: Lobby = m.get("lobby") as Lobby
			lob.open()
			await seconds(0.6)
			await shot("lobby_start")
			lob._relay_open = true
			lob._build()
			await seconds(0.3)
			await shot("lobby_relay")
			lob._step = "help"
			lob._build()
			await seconds(0.3)
			await shot("lobby_help")
			lob._relay_open = false
			lob._step = "join"
			lob._build()
			await seconds(0.3)
			await shot("lobby_join")
			Net.active = true
			Net.is_host = true
			Net.code = "FZCA"
			Net.my_id = 1
			Net.roster = {1: "Lord Percival Pickle", 2: "Anna"}
			lob._build()
			await seconds(0.3)
			await shot("lobby_room")
			lob._dismiss()
			mn.call("_refresh_start")
			await seconds(0.3)
			await shot("menu_room")
			Net.active = false
			Net.is_host = false
			Net.roster = {}
			mn.call("_refresh_start")
			mn.call("_open_arsenal")
			await seconds(0.8)
			await shot("menu_custom")
			say("relay help files: spec %d, template %d, check %d chars" % [FileAccess.get_file_as_string("res://assets/relay_help/spec.txt").length(), FileAccess.get_file_as_string("res://assets/relay_help/relay_node.txt").length(), FileAccess.get_file_as_string("res://assets/relay_help/check.txt").length()])
			say("arsenals: powerplay=%s chaos=%d keys quarry=%s" % [str(Arsenal.counts("powerplay", {})), Arsenal.counts("chaos", {}).size(), str(Arsenal.counts("quarry", {}))])
			var pa: PlayerData = PlayerData.new()
			pa.reset_ammo(Arsenal.counts("powerplay", {}))
			say("powerplay: stone %d quad %d boulder %d log %d firebarrel %d" % [pa.ammo_count("stone"), pa.ammo_count("quad"), pa.ammo_count("boulder"), pa.ammo_count("log"), pa.ammo_count("firebarrel")])
		"ram":
			await wait_loaded()
			Settings.palisade_count = 1
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var g10: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g10 < 60.0:
				await tree.process_frame
				g10 += 1.0 / 60.0
			await seconds(1.0)
			var me10: PlayerData = Game.players[0]
			var house: Structure = null
			var hd: float = 1e9
			for sx10 in Breakable.structures:
				if sx10.owner_id == 0 and sx10.kind == "farmhouse" and Util.dist_xz(sx10.center, Turn.sel.global_pos()) < hd:
					hd = Util.dist_xz(sx10.center, Turn.sel.global_pos())
					house = sx10
			Turn.set_ammo("relocate")
			await frames(5)
			var cat10: Catapult = Turn.sel
			var dir10: Vector3 = Util.flat(house.center - cat10.global_pos()).normalized()
			cat10.place_at(house.center - dir10 * (house.radius + 4.0), Util.dir_to_yaw(dir10))
			await frames(5)
			var cam10: CameraRig = m.get("cam_rig") as CameraRig
			cam10.aim_at(cat10.global_pos(), cat10.yaw, 0.5)
			var live0: int = house.live_count
			say("house %s parts before: %d" % [house.kind, live0])
			var kd := InputEventKey.new()
			kd.keycode = KEY_W
			kd.pressed = true
			for i in 90:
				Input.parse_input_event(kd)
				await frames(2)
			var ku := InputEventKey.new()
			ku.keycode = KEY_W
			ku.pressed = false
			Input.parse_input_event(ku)
			await seconds(0.5)
			say("rammed: parts %d -> %d, driven %.1f m, bubbles %d" % [live0, house.live_count, Turn.move_used, Speech.alive_count()])
			var nset: int = 0
			for st10 in Settler.all:
				if is_instance_valid(st10) and st10.global_position.distance_to(house.center) < 18.0:
					nset += 1
			say("settlers within 18 m: %d, speech inst %s, bump lines %d" % [nset, str(Speech.inst != null), I18n.tr_list("speech.bump").size()])
			(m.get("actions") as Actions)._bump_cool = 0.0
			(m.get("actions") as Actions)._react(house.center)
			await frames(10)
			say("after forced reaction: bubbles %d" % Speech.alive_count())
			await shot("ram")
			(m.get("actions") as Actions).confirm_move()
			await seconds(1.0)
		"powderfire":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			await seconds(1.0)
			var hs: Structure = null
			for sx11 in Breakable.structures:
				if sx11.owner_id == 1 and sx11.kind == "farmhouse":
					hs = sx11
			Fire.ignite_in_radius(hs.center, 5.0, 1.0, {})
			await seconds(2.0)
			say("burning parts: %d" % Fire.burning_count())
			var before_d: int = Powder.count()
			var spot2: Vector3 = Vector3.INF
			for bp in Fire.burning_list:
				if spot2 == Vector3.INF:
					spot2 = Vector3(bp.xf.origin.x, Terrain.h(bp.xf.origin.x, bp.xf.origin.z), bp.xf.origin.z)
			say("dropping at %s" % str(spot2))
			Powder.drop(spot2, {}, 1.0)
			say("heap dropped next to a fire: lit=%s" % str(Powder.active()))
			await seconds(1.0)
			say("heaps before %d, after %d (the heap must have flashed away)" % [before_d + 1, Powder.count()])
			var far: Vector3 = hs.center + Vector3(60, 0, 60)
			far.y = Terrain.h(far.x, far.z)
			Powder.drop(far, {}, 1.0)
			await seconds(1.0)
			say("heap far from any fire stays: count %d" % Powder.count())
		"logroof":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			await seconds(1.0)
			var tgt: Structure = null
			for sx12 in Breakable.structures:
				if sx12.owner_id == 1 and (sx12.kind == "barn" or sx12.kind == "farmhouse"):
					tgt = sx12
			var base12: Vector3 = tgt.center
			var launched12: int = 0
			for k12 in 12:
				var ang12: float = float(k12) * 0.5
				var from12: Vector3 = base12 + Vector3(cos(ang12), 0, sin(ang12)) * 34.0 + Vector3(0, 16.0, 0)
				var aim12: Vector3 = (base12 + Vector3(0, tgt.height * 0.8, 0) - from12).normalized()
				Projectile.launch("log", from12, aim12 * 30.0, 0, null)
				launched12 += 1
				await seconds(0.3)
			await seconds(10.0)
			say("LOGROOF stuck %d of %d (thrown at a house)" % [Projectile.stuck_logs.size(), launched12])
			var persist_n: int = 0
			for it12 in Debris.items:
				if it12.persistent:
					persist_n += 1
			say("lying logs (persistent): %d" % persist_n)
			await seconds(40.0)
			var persist2: int = 0
			for it13 in Debris.items:
				if it13.persistent and it13.fading < 0.0:
					persist2 += 1
			say("lying logs after 40 more seconds: %d (must be unchanged)" % persist2)
		"cows":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant", "peasant"])
			await auto_place_all()
			await seconds(1.5)
			for pl14 in Game.players:
				var n14: int = 0
				for an in Animal.all:
					if is_instance_valid(an) and an.kind == "cow" and an.owner_id == pl14.id:
						n14 += 1
				say("village %d has %d cows" % [pl14.id, n14])
			var g14: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g14 < 60.0:
				await tree.process_frame
				g14 += 1.0 / 60.0
			await seconds(1.0)
			var cat14: Catapult = Turn.sel
			var fwd14: Vector3 = Util.yaw_to_dir(cat14.yaw)
			var cow14: Animal = Animal.spawn("cow", cat14.global_pos() + fwd14 * 6.0, 0, 0.1, Rng.new(3))
			cow14.rotation.y = cat14.yaw + PI * 0.5
			cow14._timer = 999.0
			Turn.phase = Turn.Phase.NONE
			var rig14: CameraRig = m.get("cam_rig") as CameraRig
			var cp14: Vector3 = cow14.global_position
			rig14.cinema(cp14 + Vector3(3.2, 1.8, 3.2), cp14 + Vector3(0, 1.0, 0), 50.0)
			rig14.snap()
			await seconds(1.2)
			await shot("cow_close")
			rig14.cinema(cp14 + Vector3(-1.5, 1.6, 3.4), cp14 + Vector3(0, 1.2, 0.6), 50.0)
			rig14.snap()
			await seconds(0.8)
			await shot("cow_close2")
			var big: Hud.AmmoSlot = Hud.AmmoSlot.new()
			big.ammo = AmmoDef.get_def("cow")
			big.count = 3
			big.position = Vector2(300, 100)
			big.scale = Vector2(7, 7)
			(m.get("hud") as Hud).add_child(big)
			var big2: Hud.AmmoSlot = Hud.AmmoSlot.new()
			big2.ammo = AmmoDef.get_def("log")
			big2.count = 3
			big2.position = Vector2(700, 100)
			big2.scale = Vector2(7, 7)
			(m.get("hud") as Hud).add_child(big2)
			await seconds(0.5)
			await shot("cow_icon")
			var me14: PlayerData = Game.players[0]
			me14.ammo["cow"] = 3
		"boulderroll":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var total_d: float = 0.0
			var n_d: int = 0
			for k15 in 8:
				var sp15 := Vector3(-150.0 + float(k15) * 5.0, 0.0, -110.0 + float(k15) * 20.0)
				if Terrain.is_water(sp15.x, sp15.z):
					continue
				sp15.y = Terrain.h(sp15.x, sp15.z)
				var ang15: float = deg_to_rad(Rng.new(k15 * 5 + 1).range_f(35.0, 50.0))
				var spd15: float = Rng.new(k15 * 9 + 2).range_f(28.0, 38.0)
				var pr15: Projectile = Projectile.launch("boulder", sp15 + Vector3(0, 3.0, 0), Vector3(cos(ang15) * spd15, sin(ang15) * spd15, 0.0), 0, null)
				var hit15: Vector3 = Vector3.INF
				var last15: Vector3 = Vector3.INF
				var t15: float = 0.0
				while pr15.alive and t15 < 20.0:
					await tree.process_frame
					t15 += 1.0 / 60.0
					if pr15.first_impact_pos != Vector3.INF and hit15 == Vector3.INF:
						hit15 = pr15.first_impact_pos
					var pp15: Vector3 = pr15.position()
					if pp15 != Vector3.INF:
						last15 = pp15
				if hit15 != Vector3.INF and last15 != Vector3.INF:
					total_d += Util.dist_xz(hit15, last15)
					n_d += 1
					say("boulder %d: rolled %.1f m in %.1f s" % [k15, Util.dist_xz(hit15, last15), t15])
			say("BOULDERROLL average %.1f m over %d" % [total_d / maxf(float(n_d), 1.0), n_d])
		"smooth":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			await seconds(2.0)
			var samples: Array = []
			for stt in Settler.all:
				if stt.state == Settler.State.WANDER and samples.size() < 4:
					samples.append(stt)
			var ans: Array = []
			for an3 in Animal.all:
				if an3.state == Animal.State.WANDER and ans.size() < 2:
					ans.append(an3)
			say("walking settlers %d, animals %d" % [samples.size(), ans.size()])
			var prev: Dictionary = {}
			var steps: Array = []
			var fr: int = 0
			while fr < 360:
				await tree.process_frame
				fr += 1
				for ent in samples + ans:
					if is_instance_valid(ent):
						var cur: Vector3 = ent.global_position
						if prev.has(ent):
							var d: float = Util.dist_xz(cur, prev[ent] as Vector3)
							if d > 0.0:
								steps.append(d)
						prev[ent] = cur
			steps.sort()
			var med: float = steps[steps.size() / 2] if not steps.is_empty() else 0.0
			var mx: float = steps[steps.size() - 1] if not steps.is_empty() else 0.0
			say("SMOOTH per-frame steps: n=%d median %.4f max %.4f (max/median %.1f), fps %d" % [steps.size(), med, mx, mx / maxf(med, 0.0001), Engine.get_frames_per_second()])
		"placeview":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant", "peasant", "peasant"])
			Game.players[1].team = Game.players[0].team
			await seconds(2.0)
			await shot("placement_markers")
			await auto_place_all()
		"repair":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var g16: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g16 < 60.0:
				await tree.process_frame
				g16 += 1.0 / 60.0
			var hs16: Structure = null
			for sx16 in Breakable.structures:
				if sx16.owner_id == 0 and sx16.kind == "farmhouse":
					hs16 = sx16
			var before16: int = hs16.live_count
			Explosion.explode(hs16.center + Vector3(0, 2, 0), 5.0, 900.0, {"source": {"player_id": 1, "ammo": "stone"}, "no_crater": true})
			await seconds(5.0)
			var hurt16: int = hs16.live_count
			say("farmhouse parts: %d intact, after the blast %d (initial %d)" % [before16, hurt16, hs16.initial_count])
			var hammering: bool = false
			var tool_seen: bool = false
			var live_prev: int = hs16.live_count
			for tick16 in 90:
				await seconds(1.0)
				for st16 in Settler.all:
					if st16.owner_id == 0 and st16._repair != null:
						hammering = true
						if st16.state == Settler.State.WORK and st16._tool.visible and not tool_seen:
							tool_seen = true
							var cam16: CameraRig = m.get("cam_rig") as CameraRig
							cam16.overview(st16.global_position + Vector3(0, 1.0, 0), 7.0, 25.0)
							cam16.yaw = 0.8
							cam16.snap()
							await seconds(0.3)
							await shot("repair_hammer")
				if tick16 % 6 == 0:
					var info16: String = ""
					for st17 in Settler.all:
						if st17.owner_id == 0 and st17._repair != null:
							info16 += " [st=%d d=%.2f left=%.1f]" % [st17.state, st17.global_position.distance_to(st17._target), st17._repair_left]
					say("t=%d parts %d builders:%s" % [tick16, hs16.live_count, info16])
				if hs16.live_count != live_prev:
					live_prev = hs16.live_count
			say("REPAIR after 90 s: parts %d -> %d -> %d (builders seen %s, hammer visible %s)" % [before16, hurt16, hs16.live_count, str(hammering), str(tool_seen)])
		"hanging":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			await seconds(1.0)
			var c18: Vector3 = Game.players[1].village_center
			# the soil under half of the village sinks away (like after a big landslide)
			for k18 in 6:
				Terrain.current.dig(c18 + Vector3(float(k18) * 5.0 - 12.0, 0, 0), 9.0, 3.0, 0.0, 0.3)
			for k20 in 60 * 12:
				await tree.physics_frame
			var hov18: Array[String] = []
			for s19 in Breakable.structures:
				if s19.destroyed or Util.dist_xz(s19.center, c18) > 45.0:
					continue
				for p19 in s19.parts:
					if p19.state == Part.State.DEAD or p19.state == Part.State.DORMANT and s19.awake:
						continue
					var o19: Vector3 = p19.xf.origin
					if p19.state == Part.State.FREE and PhysWorld.bodies.has(p19.body_id):
						o19 = PhysWorld.get_transform(p19.body_id).origin
					var bot19: float = o19.y - p19.size.y * 0.5
					if bot19 - Terrain.h(o19.x, o19.z) < 0.8:
						continue
					var ex19: Array[RID] = []
					if PhysWorld.bodies.has(p19.body_id):
						ex19.append(PhysWorld.body_rid(p19.body_id))
					if s19.dormant_body != 0 and PhysWorld.bodies.has(s19.dormant_body):
						ex19.append(PhysWorld.body_rid(s19.dormant_body))
					var hit19: Dictionary = PhysWorld.raycast(Vector3(o19.x, bot19 + 0.05, o19.z), Vector3.DOWN, 0.4, Cfg.LAYER_ALL, ex19)
					if hit19.is_empty() and s19.dormant_body == 0:
						hov18.append("%s/%s st=%d gap=%.1f" % [s19.kind, p19.tag, p19.state, bot19 - Terrain.h(o19.x, o19.z)])
			say("HANGING unsupported parts: %s" % str(hov18))
			var floating18: int = 0
			for s18 in Breakable.structures:
				if s18.destroyed or s18.kind == "tree":
					continue
				for p18 in s18.parts:
					if p18.state == Part.State.DEAD:
						continue
					var o18: Vector3 = p18.xf.origin
					if Util.dist_xz(o18, c18) < 30.0 and (p18.state == Part.State.FROZEN or p18.state == Part.State.DORMANT) and p18.xf.origin.y - p18.size.y * 0.5 > Terrain.h(o18.x, o18.z) + 1.5 and p18.anchor:
						floating18 += 1
			say("HANGING anchored parts still floating: %d" % floating18)
		"kegburst":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			await seconds(1.0)
			var c17: Vector3 = Game.players[1].village_center + Vector3(0, 0, 8)
			c17.y = Terrain.h(c17.x, c17.z)
			var before17: int = Powder.count()
			var pr17: Projectile = Projectile.launch("powdertrail", c17 + Vector3(-10, 6, 0), Vector3(14, -8, 0), 0, null)
			var rig17: CameraRig = m.get("cam_rig") as CameraRig
			rig17.overview(c17, 30.0, 35.0)
			rig17.snap()
			var shots17: int = 0
			var t17: float = 0.0
			while t17 < 14.0:
				await tree.process_frame
				t17 += 1.0 / 60.0
				if not pr17.alive and shots17 == 0:
					shots17 = 1
					await seconds(0.25)
					await shot("keg_burst_a")
					await seconds(0.35)
					await shot("keg_burst_b")
			say("KEGBURST powder heaps %d -> %d" % [before17, Powder.count()])
		"fireglow":
			await wait_loaded()
			Settings.lighting = "enhanced"
			Events.quality_changed.emit(Settings.quality)
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var g18: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g18 < 60.0:
				await tree.process_frame
				g18 += 1.0 / 60.0
			var hs18: Structure = null
			var hd18: float = 1e9
			for sx18 in Breakable.structures:
				if sx18.owner_id == 0 and (sx18.kind == "farmhouse" or sx18.kind == "barn") and Util.dist_xz(sx18.center, Turn.sel.global_pos()) < hd18:
					hd18 = Util.dist_xz(sx18.center, Turn.sel.global_pos())
					hs18 = sx18
			Fire.ignite_in_radius(hs18.center, 6.0, 1.0, {})
			await seconds(7.0)
			say("lighting %s quality %s" % [Settings.lighting, Settings.quality])
			await shot("fireglow")
			var sky18: SkyRig = m.get("sky") as SkyRig
			sky18.env.glow_enabled = false
			await seconds(0.6)
			await shot("fireglow_noglow")
			sky18.env.volumetric_fog_enabled = false
			await seconds(0.6)
			await shot("fireglow_novol")
			sky18.env.sdfgi_enabled = false
			await seconds(0.6)
			await shot("fireglow_nosdfgi")
		"teams":
			await wait_loaded()
			Settings.palisade_count = 1
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant", "peasant", "peasant"])
			await auto_place_all()
			var t0: PlayerData = Game.players[0]
			var t1: PlayerData = Game.players[1]
			t1.team = t0.team
			t1.color = t0.color
			say("teams alive: %s (0 and 1 allied: %s, 0 vs 2 enemy: %s)" % [str(Game.living_teams()), str(t0.is_ally(t1)), str(t0.is_enemy(Game.players[2]))])
			t1.marker = t1.village_center + Vector3(10, 0, 0)
			say("marker for 0 comes from the ally: %s" % str(Game.marker_for(t0) == t1.marker))
			var pole_count: int = 0
			for sx in Breakable.structures:
				if sx.kind == "flagpole":
					pole_count += 1
			say("flagpoles: %d (one per village = %d)" % [pole_count, Game.players.size()])
			var fp: Structure = null
			for sx2 in Breakable.structures:
				if sx2.kind == "flagpole" and sx2.owner_id == 0:
					fp = sx2
			var rig9: CameraRig = m.get("cam_rig") as CameraRig
			if fp != null:
				rig9.focus_on(fp.center + Vector3(0, 4, 0), 24.0, 22.0, 0.5)
				rig9.snap()
				await seconds(1.5)
				await shot("flagpole")
			var g9: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g9 < 60.0:
				await tree.process_frame
				g9 += 1.0 / 60.0
			await seconds(1.0)
			await shot("team_hud")
			# the rival team loses everything: the allied pair wins together
			for pl9 in [Game.players[2], Game.players[3]]:
				for c9 in (pl9 as PlayerData).catapults.duplicate():
					if is_instance_valid(c9):
						(c9 as Catapult).destroy("debug")
			Turn.skip_turn()
			g9 = 0.0
			while Game.state != Game.State.GAME_OVER and g9 < 30.0:
				await tree.process_frame
				g9 += 1.0 / 60.0
			say("phase=%d cur=%d teams=%s elim=%s" % [Turn.phase, Game.current_player, str(Game.living_teams()), str(Game.players.map(func(q: PlayerData) -> bool: return q.eliminated))])
			say("game over: %s, winner seat %d, allies both winners: %s %s" % [str(Game.state == Game.State.GAME_OVER), Game.last_winner, str(Game.is_winner(t0)), str(Game.is_winner(t1))])
			await seconds(2.0)
			await shot("team_win")
		"actions":
			await wait_loaded()
			Settings.palisade_count = 1
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var me2: PlayerData = Game.players[0]
			var rig8: CameraRig = m.get("cam_rig") as CameraRig
			var g8: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g8 < 60.0:
				await tree.process_frame
				g8 += 1.0 / 60.0
			await seconds(1.0)
			await shot("hud_aim")
			var hud9: Hud = m.get("hud") as Hud
			var slot_c: Vector2 = hud9.ammo_slots[4].global_position + hud9.ammo_slots[4].size * 0.5
			var mm_ev := InputEventMouseMotion.new()
			mm_ev.position = slot_c
			mm_ev.global_position = slot_c
			Input.parse_input_event(mm_ev)
			await seconds(0.3)
			mm_ev = InputEventMouseMotion.new()
			mm_ev.position = slot_c + Vector2(2, 1)
			mm_ev.global_position = slot_c + Vector2(2, 1)
			Input.parse_input_event(mm_ev)
			await seconds(1.6)
			await shot("tooltips")
			# a house between camera and catapult must turn almost transparent, not vanish
			var cam_occ: CameraRig = m.get("cam_rig") as CameraRig
			var fade_n: int = 0
			for _i in 60:
				await tree.process_frame
			for k_s in (m.get("_fade") as Dictionary).keys():
				fade_n += 1
			say("faded structures: %d" % fade_n)
			var near_s: Structure = null
			var nd: float = 1e9
			for sx9 in Breakable.structures:
				if sx9.owner_id == 0 and sx9.kind == "farmhouse" and Util.dist_xz(sx9.center, Turn.sel.global_pos()) < nd:
					nd = Util.dist_xz(sx9.center, Turn.sel.global_pos())
					near_s = sx9
			var cam_r: CameraRig = m.get("cam_rig") as CameraRig
			cam_r.focus_on(near_s.center + Vector3(0, 2, 0), 16.0, 25.0, 0.4)
			cam_r.snap()
			await seconds(0.8)
			await shot("fade_off")
			for gn in m.call("_geoms", near_s.root):
				(gn as GeometryInstance3D).transparency = 0.88
			await seconds(0.3)
			await shot("fade_on")
			for gn2 in m.call("_geoms", near_s.root):
				(gn2 as GeometryInstance3D).transparency = 0.0
			# stone vs. wood (material table)
			say("stone hp/m3 %.0f break %.0f | wood hp/m3 %.0f break %.0f" % [Materials.get_def("stone").hp_per_m3, Materials.get_def("stone").break_force, Materials.get_def("wood").hp_per_m3, Materials.get_def("wood").break_force])
			# 1) build a wall
			var spot: Vector3 = Vector3.INF
			var wyaw: float = Util.dir_to_yaw(Util.flat(Game.players[1].village_center - me2.village_center))
			for ring_i in 12:
				for a_i in 16:
					var ang: float = TAU * float(a_i) / 16.0
					var cand: Vector3 = me2.village_center + Vector3(cos(ang), 0, sin(ang)) * (6.0 + float(ring_i) * 1.5)
					cand.y = Terrain.h(cand.x, cand.z)
					if spot == Vector3.INF and Walls.footprint_valid(me2, cand, wyaw):
						spot = cand
			say("wall spot: %s" % str(spot))
			Turn.set_ammo("wall")
			await seconds(1.5)
			await shot("hud_wall")
			Turn.do_action({"t": "wall", "c": [spot.x, spot.y, spot.z], "y": wyaw, "stack": false})
			await frames(5)
			var w0: Dictionary = me2.walls[0] as Dictionary
			var l0: Structure = (w0["layers"] as Array)[0] as Structure
			var cren: int = 0
			for pt in l0.parts:
				if pt.tag == "crenel":
					cren += 1
			say("wall built: layers=%d parts=%d crenellations=%d size=%.1f x %.1f m (palisade fence 1.56 x 5.5) phase=%d" % [Walls.layer_count(w0), l0.parts.size(), cren, l0.aabb.size.x, l0.aabb.size.y, Turn.phase])
			var rig_f: float = 0.0
			cam_focus_wall(rig8, w0)
			await seconds(1.0)
			await shot("wall1")
			# next own turn: stack a second layer
			Turn.skip_aftermath()
			g8 = 0.0
			m.set("_fast_forward", true)
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g8 < 120.0:
				await tree.process_frame
				g8 += 1.0 / 60.0
			m.set("_fast_forward", false)
			Turn.set_ammo("wall")
			var wc: Vector3 = w0["center"] as Vector3
			Turn.do_action({"t": "wall", "c": [wc.x, wc.y, wc.z], "y": float(w0["yaw"]), "stack": true})
			await frames(5)
			var dead_cren: int = 0
			for pt2 in l0.parts:
				if pt2.tag == "crenel" and pt2.state == Part.State.DEAD:
					dead_cren += 1
			var l1: Structure = (w0["layers"] as Array)[1] as Structure
			var cren1: int = 0
			for pt3 in l1.parts:
				if pt3.tag == "crenel":
					cren1 += 1
			say("stacked: layers=%d, lower crenellations removed=%d, top crenellations=%d, top y=%.1f" % [Walls.layer_count(w0), dead_cren, cren1, l1.aabb.end.y - Terrain.h(wc.x, wc.z)])
			cam_focus_wall(rig8, w0)
			await seconds(1.0)
			await shot("wall2")
			# blow a hole into the bottom layer: what stands above must come down
			Explosion.explode(wc + Vector3(0, 1.5, 0), 4.0, 900.0, {"source": {}, "no_crater": true})
			await seconds(3.0)
			say("after a blast: lower layer %d/%d parts, top layer %d/%d parts" % [l0.live_count, l0.initial_count, l1.live_count, l1.initial_count])
			await shot("wall3")
			# 2) relocate
			Turn.skip_aftermath()
			g8 = 0.0
			m.set("_fast_forward", true)
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g8 < 120.0:
				await tree.process_frame
				g8 += 1.0 / 60.0
			m.set("_fast_forward", false)
			Turn.set_ammo("relocate")
			await seconds(1.0)
			await shot("hud_move")
			var cat8: Catapult = Turn.sel
			var from8: Vector3 = cat8.global_pos()
			for i in 40:
				var key := InputEventKey.new()
				key.keycode = KEY_W
				key.pressed = true
				Input.parse_input_event(key)
				Input.action_press("ui_up")
				await frames(3)
			var kr := InputEventKey.new()
			kr.keycode = KEY_W
			kr.pressed = false
			Input.parse_input_event(kr)
			say("relocate (driven %.1f m): moved %.1f m" % [Turn.move_used, Util.dist_xz(from8, cat8.global_pos())])
			var np: Vector3 = from8 + Util.yaw_to_dir(cat8.yaw) * 6.0
			cat8.place_at(np, cat8.yaw + 0.5)
			(m.get("actions") as Actions)._moved = true
			(m.get("actions") as Actions).confirm_move()
			await seconds(1.0)
			say("after relocate: moved %.1f m, phase=%d (must be AFTERMATH=%d)" % [Util.dist_xz(from8, cat8.global_pos()), Turn.phase, Turn.Phase.AFTERMATH])
			await shot("relocate")
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
		"meteor":
			await wait_loaded()
			Settings.palisade_count = 1
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			Game.players[0].add_ammo("meteor", 2)
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
			var rk: Dictionary = await aim_and_fire(tgt, "meteor", 45.0)
			say("solver err %.1f m, power %.2f" % [float(rk["err"]), float(rk["power"])])
			await wait_phase(Turn.Phase.AFTERMATH, 60.0)
			var mt0: float = Time.get_ticks_msec() * 0.001
			var ground0: float = Terrain.h(Meteor.strikes[0].target.x, Meteor.strikes[0].target.z) if not Meteor.strikes.is_empty() else 0.0
			var tp: Vector3 = Meteor.strikes[0].target if not Meteor.strikes.is_empty() else tgt
			say("marker down at %s (aimed %s), beam up" % [str(tp), str(tgt)])
			await seconds(2.0)
			await shot("meteor_1_beam")
			await seconds(2.6)
			await shot("meteor_2_fall")
			var slow_seen: bool = false
			while Meteor.pending() and Time.get_ticks_msec() * 0.001 - mt0 < 20.0:
				if Engine.time_scale < 0.99:
					slow_seen = true
				await tree.process_frame
			await seconds(0.4)
			await shot("meteor_3_boom")
			await seconds(2.0)
			await shot("meteor_4_crater")
			await seconds(4.0)
			var hp1: float = Breakable.village_hp(1)
			say("meteor: village HP %.0f -> %.0f (%.0f%% destroyed), crater depth at the point %.1f m, bullet time seen: %s, time scale %.2f" % [hp0, hp1, 100.0 * (1.0 - hp1 / maxf(hp0, 1.0)), ground0 - Terrain.h(tp.x, tp.z), str(slow_seen), Engine.time_scale])
			await shot("meteor_5_after")
		"arsenal":
			await wait_loaded()
			await seconds(1.0)
			(m.get("menu") as Menu).call("_open_arsenal")
			await seconds(0.6)
			await shot("arsenal_dialog")
		"gif":
			# README animation: a boulder (or drill bomb) is thrown into the enemy village from a fixed camera; every n-th frame
			# is written to user://gif/ as a small PNG (assembled to a GIF outside the game)
			await wait_loaded()
			I18n.set_lang("en")
			Settings.palisade_count = 1
			await start_match(uarg("seed", "trebuchet-haystack-42"), ["human", "peasant"])
			await auto_place_all()
			var gammo: String = uarg("ammo", "boulder")
			var gg: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and gg < 60.0:
				await tree.process_frame
				gg += 1.0 / 60.0
			await seconds(1.0)
			(m.get("ui_root") as Control).visible = false
			var grig: CameraRig = m.get("cam_rig") as CameraRig
			var gv: Vector3 = Game.players[1].village_center
			var gang: float = deg_to_rad(float(uarg("ang", "200")))
			var gdir := Vector3(cos(gang), 0.0, sin(gang))
			var gperp := Vector3(-gdir.z, 0.0, gdir.x)
			var gdist: float = float(uarg("dist", "38"))
			var gspeed: float = float(uarg("speed", "20"))
			var gstart: Vector3 = gv + gdir * gdist
			gstart.y = Terrain.h(gstart.x, gstart.z) + float(uarg("height", "8"))
			var gtgt: Vector3 = gv + gperp * float(uarg("side", "0"))
			gtgt.y = Terrain.h(gtgt.x, gtgt.z) + 0.5
			# aim at the biggest building of the village (most parts) so the boulder smashes through it
			var gbest: Structure = null
			for gs in Breakable.structures:
				if gs.owner_id == 1 and not gs.destroyed and ["farmhouse", "barn", "tavern", "church", "granary", "stable", "windmill", "watchtower"].has(gs.kind) and (gbest == null or gs.parts.size() > gbest.parts.size()):
					gbest = gs
			if gbest != null and uarg("bld", "1") == "1":
				say("gif target: %s with %d parts" % [gbest.kind, gbest.parts.size()])
				gv = gbest.center
				gtgt = gbest.center
				gtgt.y = maxf(Terrain.h(gtgt.x, gtgt.z) + 1.0, gbest.center.y - 1.0)
				gstart = gv + gdir * gdist
				gstart.y = Terrain.h(gstart.x, gstart.z) + float(uarg("height", "8"))
			var gtime: float = Util.dist_xz(gstart, gtgt) / gspeed
			var gvel: Vector3 = (gtgt - gstart) / gtime
			gvel.y = (gtgt.y - gstart.y + 0.5 * 19.62 * gtime * gtime) / gtime
			var gcam_p: Vector3 = gv + gperp * float(uarg("camside", "22")) + gdir * float(uarg("camback", "0"))
			gcam_p.y = Terrain.h(gcam_p.x, gcam_p.z) + float(uarg("camh", "10"))
			var gcam_t: Vector3 = gv + Vector3.UP * 1.5
			grig.cinema(gcam_p, gcam_t, float(uarg("fov", "60")))
			grig.snap()
			await frames(20)
			DirAccess.make_dir_recursive_absolute("user://gif")
			var gstep: int = int(uarg("step", "5"))
			var gdur: float = float(uarg("dur", "9"))
			var gw: int = int(uarg("w", "560"))
			var gn: int = 0
			var gfr: int = 0
			if gammo == "drillbomb":
				Game.players[0].add_ammo("drillbomb", 2)
			Projectile.launch(gammo, gstart, gvel, 0, null)
			var gt0: float = Time.get_ticks_msec() * 0.001
			while Time.get_ticks_msec() * 0.001 - gt0 < gdur:
				await tree.process_frame
				grig.cinema(gcam_p, gcam_t, float(uarg("fov", "60")))
				gfr += 1
				if gfr % gstep == 0:
					var gimg: Image = m.get_viewport().get_texture().get_image()
					gimg.resize(gw, int(float(gw) * float(gimg.get_height()) / float(gimg.get_width())), Image.INTERPOLATE_LANCZOS)
					gimg.save_png("user://gif/f%04d.png" % gn)
					gn += 1
			say("gif: %d frames in %s" % [gn, ProjectSettings.globalize_path("user://gif")])
		"readmeshot":
			# README screenshot: English UI, the aiming view of the first player (own catapults in front, enemy village behind)
			await wait_loaded()
			I18n.set_lang("en")
			await start_match(uarg("seed", "trebuchet-haystack-42"), ["human", "peasant"])
			await auto_place_all()
			var rg: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and rg < 60.0:
				await tree.process_frame
				rg += 1.0 / 60.0
			await seconds(float(uarg("wait", "6")))
			Turn.select_catapult(Game.cur().living_catapults()[int(uarg("cat", "1"))] as Catapult)
			await seconds(2.0)
			await shot("readme_aim")
			var rv: Vector3 = (Game.players[0].village_center + Game.players[1].village_center) * 0.5
			(m.get("cam_rig") as CameraRig).overview(rv, float(uarg("odist", "150")), float(uarg("opitch", "48")))
			if Speech.inst != null:
				Speech.inst.visible = false          # no speech bubble over the picture
			await seconds(2.5)
			await shot("readme_overview")
		"drillbomb":
			await wait_loaded()
			Settings.palisade_count = 1
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			Game.players[0].add_ammo("drillbomb", 2)
			var guardd: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and guardd < 60.0:
				await tree.process_frame
				guardd += 1.0 / 60.0
			await seconds(1.0)
			var vc: Vector3 = Game.players[1].village_center
			var bestd: Catapult = Game.cur().living_catapults()[0] as Catapult
			Turn.select_catapult(bestd)
			var hpd0: float = Breakable.village_hp(1)
			var gd0: float = Terrain.h(vc.x, vc.z)
			var rd: Dictionary = await aim_and_fire(vc, "drillbomb", 45.0)
			say("drill bomb: solver err %.1f m, village ground %.1f m" % [float(rd["err"]), gd0])
			await wait_phase(Turn.Phase.AFTERMATH, 60.0)
			var t0d: float = Time.get_ticks_msec() * 0.001
			while not DrillBomb.active() and Time.get_ticks_msec() * 0.001 - t0d < 5.0:
				await tree.process_frame
			var bp: DrillBomb = DrillBomb.bombs[0] if not DrillBomb.bombs.is_empty() else null
			say("bomb started: %s" % str(bp != null))
			await seconds(0.3)
			await shot("drill_1_landed")
			await seconds(1.0)
			await shot("drill_2_drilling")
			var tb: float = Time.get_ticks_msec() * 0.001
			while DrillBomb.active() and Time.get_ticks_msec() * 0.001 - tb < 15.0:
				await tree.process_frame
			say("drilling + sinking took %.1f s, ground at the bomb %.1f -> %.1f m" % [Time.get_ticks_msec() * 0.001 - tb, gd0, Terrain.h(bp.x, bp.z) if bp != null else 0.0])
			await seconds(1.0)
			await shot("drill_3_cavein")
			await seconds(6.0)
			var hpd1: float = Breakable.village_hp(1)
			say("drill bomb: village HP %.0f -> %.0f (%.0f%% destroyed), landslide still active: %s" % [hpd0, hpd1, 100.0 * (1.0 - hpd1 / maxf(hpd0, 1.0)), str(Landslide.active())])
			await shot("drill_4_after")
		"nethost":
			await wait_loaded()
			Settings.seed_text = uarg("seed", "net-test")
			Settings.timer = 0
			Settings.catapult_count = 2
			Settings.palisade_count = 1
			Settings.player_count = int(uarg("players", "4"))
			Net.host_game(uarg("relay", "ws://127.0.0.1:9080"), "Host")
			var g0: float = 0.0
			while not Net.active and g0 < 15.0:
				await tree.process_frame
				g0 += 1.0 / 60.0
			say("NETCODE " + Net.code)
			var f: FileAccess = FileAccess.open("/tmp/mm_netcode.txt", FileAccess.WRITE)
			f.store_string(Net.code)
			f.close()
			var want: int = 1 + int(uarg("peers", "1"))
			g0 = 0.0
			while Net.roster.size() < want and g0 < 60.0:
				await tree.process_frame
				g0 += 1.0 / 60.0
			say("roster: %s" % str(Net.roster))
			var menu0: Menu = m.get("menu") as Menu
			menu0.count = int(uarg("players", "4"))
			NetGame.host_start(NetGame.make_cfg(menu0.players_config(), menu0.count))
			await net_play(int(uarg("turns", "6")), 400.0)
			await seconds(1.0)
		"lobbyhost":
			await wait_loaded()
			var mh: Menu = m.get("menu") as Menu
			Net.host_game(uarg("relay", "ws://127.0.0.1:9080"), "Hosty")
			var gl: float = 0.0
			while not Net.active and gl < 15.0:
				await tree.process_frame
				gl += 1.0 / 60.0
			var f2: FileAccess = FileAccess.open("/tmp/mm_netcode.txt", FileAccess.WRITE)
			f2.store_string(Net.code)
			f2.close()
			gl = 0.0
			while Net.roster.size() < 2 and gl < 60.0:
				await tree.process_frame
				gl += 1.0 / 60.0
			await seconds(1.0)
			mh.count = 4
			(mh.rows[0] as Dictionary)["color"] = 3
			(mh.rows[2] as Dictionary)["color"] = 5
			(mh.rows[3] as Dictionary)["type"] = "king"
			Settings.timer = 45
			Settings.seed_text = "lobby-seed"
			mh.call("_build")
			say("host set: count 4, colours 3/?/5, seat 4 king, timer 45")
			gl = 0.0
			while int((mh.rows[1] as Dictionary)["color"]) != 6 and gl < 20.0:
				await tree.process_frame
				gl += 1.0 / 60.0
			say("LOBBYHOST guest colour arrived at the host: seat 2 colour = %d (want 6), rows names %s" % [int((mh.rows[1] as Dictionary)["color"]), str([(mh.rows[0] as Dictionary)["name"], (mh.rows[1] as Dictionary)["name"]])])
			NetGame.send_lobby(mh.lobby_state())
			(mh.rows[1] as Dictionary)["color"] = 2
			mh.call("_build")
			await seconds(2.0)
			say("host changed the guest's colour to 2; seats: %s" % str(NetGame.seat_peers()))
			await seconds(2.0)
		"lobbyjoin":
			await wait_loaded()
			var mg: Menu = m.get("menu") as Menu
			Settings.timer = 20
			Net.join_game(uarg("relay", "ws://127.0.0.1:9080"), uarg("code", ""), "Guesty")
			var gj: float = 0.0
			while not Net.active and gj < 15.0:
				await tree.process_frame
				gj += 1.0 / 60.0
			gj = 0.0
			while Settings.timer != 45 and gj < 20.0:
				await tree.process_frame
				gj += 1.0 / 60.0
			say("LOBBYJOIN host state arrived: timer %d seed %s count %d colours %d/%d/%d seat4 type %s peers %s" % [Settings.timer, Settings.seed_text, mg.count, int((mg.rows[0] as Dictionary)["color"]), int((mg.rows[1] as Dictionary)["color"]), int((mg.rows[2] as Dictionary)["color"]), str((mg.rows[3] as Dictionary)["type"]), str([(mg.rows[0] as Dictionary)["peer"], (mg.rows[1] as Dictionary)["peer"]])])
			NetGame.send_lobby_set({"color": 6})
			gj = 0.0
			while int((mg.rows[1] as Dictionary)["color"]) != 2 and gj < 20.0:
				await tree.process_frame
				gj += 1.0 / 60.0
			say("guest colour after the host changed it: %d (want 2)" % int((mg.rows[1] as Dictionary)["color"]))
			Net.leave()
			await seconds(1.0)
			say("LOBBYJOIN after leaving: timer back to %d (want 20)" % Settings.timer)
		"overviewhold":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var g19: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g19 < 60.0:
				await tree.process_frame
				g19 += 1.0 / 60.0
			Turn.skip_turn()
			g19 = 0.0
			while (Game.current_player != 1 or Turn.phase == Turn.Phase.TURN_START or Turn.phase == Turn.Phase.TURN_END) and g19 < 30.0:
				await tree.process_frame
				g19 += 1.0 / 60.0
			m.call("_toggle_overview")
			var rig19: CameraRig = m.get("cam_rig") as CameraRig
			var frames_ov: int = 0
			var frames_all: int = 0
			var t19: float = 0.0
			while t19 < 14.0:
				await tree.process_frame
				t19 += 1.0 / 60.0
				frames_all += 1
				if rig19.mode == CameraRig.Mode.OVERVIEW:
					frames_ov += 1
			say("OVERVIEWHOLD during the CPU turn (aim, flight, aftermath): overview kept in %d of %d frames (cur=%d phase=%d)" % [frames_ov, frames_all, Game.current_player, Turn.phase])
		"countdown":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"], 30)
			await auto_place_all()
			var g20: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and g20 < 60.0:
				await tree.process_frame
				g20 += 1.0 / 60.0
			Turn.time_left = 3.6
			await seconds(0.5)
			await shot("countdown")
			say("timer on %s, left %.1f" % [str(Turn.timer_on), Turn.time_left])
		"netjoin":
			await wait_loaded()
			Settings.timer = 0
			Net.join_game(uarg("relay", "ws://127.0.0.1:9080"), uarg("code", ""), uarg("name", "Guest"))
			var g1: float = 0.0
			while not Net.active and g1 < 15.0:
				await tree.process_frame
				g1 += 1.0 / 60.0
			say("joined=%s as %d, roster %s" % [str(Net.active), Net.my_id, str(Net.roster)])
			await net_play(int(uarg("turns", "6")), 400.0)
			await seconds(1.0)
		"quickstart":
			await wait_loaded()
			Settings.palisade_count = 2
			await start_match(str(m.get("_autotest_seed")), ["human", "human", "squire"])
			await frames(30)
			(m.get("placement") as Node).call("_quick_start")
			await frames(10)
			var ok: bool = true
			for qp in Game.players:
				say("%s: catapults %d, posts %d" % [qp.name, qp.catapults.size(), Posts.count(qp)])
				ok = ok and qp.catapults.size() == Game.catapults_per_player and Posts.count(qp) > 0
			say("QUICKSTART ok=%s state=%d" % [str(ok), Game.state])
		"bucket":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			for eid in AmmoDef.earnable_ids():
				Game.players[0].add_ammo(eid, 3)
			var gb: float = 0.0
			while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and gb < 60.0:
				await tree.process_frame
				gb += 1.0 / 60.0
			await seconds(1.0)
			Turn.select_catapult(Game.cur().living_catapults()[0] as Catapult)
			Turn.set_aim(Turn.aim_yaw, 40.0, 0.5)
			for bid in ["stone", "quad", "chain", "boulder", "log", "firebarrel", "powderkeg", "scatter", "cow", "powdertrail", "meteor"]:
				Turn.set_ammo(bid)
				Turn.sel.set_ammo_visual(bid)
				await seconds(0.5)
				await shot("bucket_" + bid)
		"lobby":
			await wait_loaded()
			await seconds(1.0)
			(m.get("lobby") as Lobby).open()
			await seconds(0.5)
			await shot("lobby_idle")
		"logstick":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var spot := Vector3(0, 0, 0)
			spot.y = Terrain.h(spot.x, spot.z)
			var lvel := Vector3(14, -22, 0)
			var lpr: Projectile = Projectile.launch("log", spot + Vector3(-14, 32, 0), lvel, 0, null)
			# nose first: the pointed end (local Y) along the flight direction, no tumbling
			var ly: Vector3 = lvel.normalized()
			var lx: Vector3 = ly.cross(Vector3.FORWARD).normalized()
			PhysWorld.set_transform(lpr.body_id, Transform3D(Basis(lx, ly, lx.cross(ly)), spot + Vector3(-14, 32, 0)))
			PhysWorld.set_velocity(lpr.body_id, lvel, Vector3.ZERO)
			await seconds(4.0)
			say("stuck logs: %d (ground y %.1f)" % [Projectile.stuck_logs.size(), spot.y])
			if not Projectile.stuck_logs.is_empty():
				var sid: int = int((Projectile.stuck_logs[0] as Dictionary)["id"])
				say("log mode static: %s, pos %s" % [str(PhysicsServer3D.body_get_mode(PhysWorld.body_rid(sid)) == PhysicsServer3D.BODY_MODE_STATIC), str(PhysWorld.get_transform(sid).origin)])
				await shot("log_stuck")
				await seconds(5.0)
				say("still stuck after 5 s: %d" % Projectile.stuck_logs.size())
				Projectile.release_stuck_logs(spot, 20.0)
				say("after a blast: stuck logs %d" % Projectile.stuck_logs.size())
		"lograte":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var total: int = 0
			var stuck_n: int = 0
			for batch in 8:
				var before: int = Projectile.stuck_logs.size()
				var launched: int = 0
				for k in 10:
					var sp := Vector3(-150.0 + float(k) * 6.0, 0.0, -100.0 + float(batch) * 60.0)
					if Terrain.is_water(sp.x, sp.z):
						continue
					sp.y = Terrain.h(sp.x, sp.z)
					var spd: float = Rng.new(batch * 100 + k).range_f(26.0, 40.0)
					var ang: float = deg_to_rad(Rng.new(batch * 7 + k * 3).range_f(35.0, 55.0))
					var v := Vector3(cos(ang) * spd, sin(ang) * spd, 0.0)
					Projectile.launch("log", sp + Vector3(0, 3.0, 0), v, 0, null)
					launched += 1
				await seconds(14.0)
				total += launched
				stuck_n += Projectile.stuck_logs.size() - before
			say("LOGRATE stuck %d of %d (%.0f%%)" % [stuck_n, total, 100.0 * float(stuck_n) / float(maxi(total, 1))])
		"wind":
			await wait_loaded()
			await start_match(str(m.get("_autotest_seed")), ["human", "peasant"])
			await auto_place_all()
			var landings: Array = []
			var winds: Array = [Vector2.ZERO, Vector2(14.0, 0.0), Vector2.ZERO, Vector2(14.0, 0.0)]
			var aim_yaw0: float = 0.0
			var aim_pow0: float = 0.0
			for wi in winds.size():
				var gd: float = 0.0
				while (Turn.phase != Turn.Phase.AIMING or Game.cur().id != 0) and gd < 120.0:
					await tree.process_frame
					gd += 1.0 / 60.0
				await seconds(0.5)
				var sel0: Catapult = Game.cur().living_catapults()[0] as Catapult
				Turn.select_catapult(sel0)
				Game.wind = winds[wi] as Vector2
				if wi == 0:
					aim_yaw0 = sel0.yaw
					aim_pow0 = 0.6
				Turn.aim_ammo = "stone"
				Turn.set_aim(aim_yaw0, 40.0, aim_pow0)
				var org: Vector3 = Turn.launch_origin(sel0, 40.0, aim_yaw0)
				var pred: Vector3 = Ballistics.landing(org, aim_yaw0, 40.0, aim_pow0, "stone", winds[wi] as Vector2)
				Turn.fire()
				await wait_phase(Turn.Phase.AFTERMATH, 40.0)
				landings.append(Projectile.last_impact_pos)
				say("shot %d wind %s: landed %s, predicted %s" % [wi, str(winds[wi]), str(Projectile.last_impact_pos), str(pred)])
				await wait_phase(Turn.Phase.TURN_START, 60.0)
			var d1: Vector3 = (landings[1] as Vector3) - (landings[0] as Vector3)
			var d2: Vector3 = (landings[3] as Vector3) - (landings[2] as Vector3)
			say("WIND shift of the landing point: %.1f m and %.1f m along the wind (+X)" % [d1.x, d2.x])
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
