extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Bootstrap + main loop glue (spec 1.3): builds everything in code, owns the state switching
## MENU -> GENERATING -> PLACEMENT -> BATTLE -> GAME_OVER -> MENU and the fixed-step system update order.

var world_root: Node3D
var phys: PhysWorld
var sky: SkyRig
var cam_rig: CameraRig
var world: GameWorld
var ui_layer: CanvasLayer
var ui_root: Control
var menu: Menu
var hud: Hud
var aiming: Aiming
var placement: Placement
var results: Results
var pause_menu: PauseMenu
var debug_overlay: DebugOverlay
var marker: MapMarker
var loading: Control
var loading_bar: ProgressBar
var loading_label: Label
var loading_title: Label
var vignette: ColorRect

var _args: PackedStringArray
var _autotest: String = ""
var _frames: int = 0
var _paused: bool = false
var _slowmo_until: float = 0.0
var _slowmo_scale: float = 1.0
var _fps_acc: float = 0.0
var _fps_time: float = 0.0
var _fps_low_time: float = 0.0
var _generating: bool = false
var _attract: bool = false
var _last_config: Array = []
var _last_seed: String = ""
var _feed_cool: Dictionary = {}
var _fast_forward: bool = false
var _overview: bool = false
var _menu_orbit_seed: String = "medieval-madness-menu"
var _test_ball_count: int = 0
var _wall_time: float = 0.0
var _debug_slowmo: bool = false
var _autotest_state: Dictionary = {}
var _focus_lost_pause: bool = false
var _autotest_seed: String = "autotest-cpu"
var _autotest_wall: float = 600.0
var _autotest_weather: bool = false
var _autotest_types: String = "peasant,squire,knight,king"
var _autotest_lang: String = ""
var _autotest_events_list: String = "dragon,cheese_meteor,cow_rain,earthquake,goose_army,tax_collector,fireworks_accident,bubble,flood"
var _autotest_events: bool = false
var _occluded: Array[Structure] = []   # buildings hidden because they stand between the aiming camera and the catapult
var _autotest_ammo: String = "firebarrel,boulder,powderkeg,scatter,cow,beehive,redkeg"

func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	for a in _args:
		if a.begins_with("--autotest"):
			_autotest = a.get_slice("=", 1) if "=" in a else "default"
		elif a.begins_with("--seed="):
			_autotest_seed = a.get_slice("=", 1)
		elif a.begins_with("--types="):
			_autotest_types = a.get_slice("=", 1)
		elif a.begins_with("--events="):
			_autotest_events_list = a.get_slice("=", 1)
		elif a.begins_with("--lang="):
			_autotest_lang = a.get_slice("=", 1)
		elif a == "--weather":
			_autotest_weather = true
		elif a == "--events":
			_autotest_events = true
		elif a.begins_with("--ammo="):
			_autotest_ammo = a.get_slice("=", 1)
		elif a.begins_with("--wall="):
			_autotest_wall = float(a.get_slice("=", 1))
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.apply_display()
	Settings.apply_volume()
	if _autotest_lang != "":
		Settings.language = _autotest_lang
	I18n.set_lang(Settings.language)
	get_window().min_size = Vector2i(1024, 600)
	# 3D root + systems
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	phys = PhysWorld.new()
	phys.name = "PhysRoot"
	add_child(phys)
	PhysWorld.init_physics(self)
	sky = SkyRig.new()
	sky.name = "Sky"
	world_root.add_child(sky)
	cam_rig = CameraRig.new()
	cam_rig.name = "CameraRig"
	world_root.add_child(cam_rig)
	cam_rig.shake_enabled = Settings.shake
	world = GameWorld.new()
	world.name = "GameWorld"
	world_root.add_child(world)
	world.setup_roots(sky)
	Game.world = world
	Turn.world = world
	Turn.cam = cam_rig
	Weather.sky = sky
	Weather.cam = cam_rig
	Weather.fx_root = world.fx_root
	RandomEvents.world = world
	RandomEvents.cam = cam_rig
	RandomEvents.fx_root = world.fx_root
	marker = MapMarker.new()
	marker.name = "MapMarker"
	marker.cam = cam_rig
	world.fx_root.add_child(marker)
	Quality.apply(Settings.quality, get_viewport(), sky)
	Sfx.begin_synthesis()
	_build_ui()
	_connect_events()
	if "--debug" in _args:
		Settings.debug = true
	await _show_menu(true)
	if _autotest != "":
		_run_autotest()

# ------------------------------------------------------------------ UI construction
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UITheme.build()
	ui_layer.add_child(ui_root)
	# soft vignette (radial gradient shader on a ColorRect)
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nuniform float strength = 0.35;\nvoid fragment() { vec2 uv = UV - 0.5; float d = dot(uv, uv) * 1.6; COLOR = vec4(0.05, 0.02, 0.08, clamp(d * strength * 2.2, 0.0, 0.6)); }\n"
	vm.shader = vs
	vignette.material = vm
	ui_root.add_child(vignette)
	aiming = Aiming.new()
	aiming.name = "Aiming"
	aiming.cam = cam_rig
	ui_root.add_child(aiming)
	aiming.attach_preview(world_root)
	hud = Hud.new()
	hud.name = "Hud"
	ui_root.add_child(hud)
	placement = Placement.new()
	placement.name = "Placement"
	ui_root.add_child(placement)
	menu = Menu.new()
	menu.name = "Menu"
	ui_root.add_child(menu)
	results = Results.new()
	results.name = "Results"
	ui_root.add_child(results)
	pause_menu = PauseMenu.new()
	pause_menu.name = "Pause"
	ui_root.add_child(pause_menu)
	debug_overlay = DebugOverlay.new()
	ui_root.add_child(debug_overlay)
	debug_overlay.extra = Callable(self, "_debug_extra")
	_build_loading()
	# signals
	menu.start_requested.connect(_on_start_requested)
	hud.overview_pressed.connect(_toggle_overview)
	hud.fast_pressed.connect(_toggle_fast)
	hud.pause_pressed.connect(_open_pause)
	hud.skip_requested.connect(func() -> void: Turn.skip_turn())
	hud.ammo_clicked.connect(func(id: String) -> void: Turn.set_ammo(id))
	pause_menu.resume.connect(_close_pause)
	pause_menu.restart.connect(func() -> void:
		_close_pause()
		_restart_game(_last_seed, true))
	pause_menu.quit_to_menu.connect(func() -> void:
		_close_pause()
		_show_menu(false))
	results.rematch.connect(func() -> void:
		results.hide_results()
		_restart_game(menu._random_seed()))
	results.same_map.connect(func() -> void:
		results.hide_results()
		_restart_game(_last_seed, true))
	results.main_menu.connect(func() -> void:
		results.hide_results()
		_show_menu(false))
	placement.finished.connect(_on_placement_done)

func _build_loading() -> void:
	loading = Control.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.mouse_filter = Control.MOUSE_FILTER_STOP
	loading.visible = false
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#2b3a55")
	loading.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.offset_left = -300
	v.offset_right = 300
	v.offset_top = -80
	v.offset_bottom = 80
	v.add_theme_constant_override("separation", 14)
	loading.add_child(v)
	loading_title = UITheme.label(I18n.t("loading.title"), 44, Color("#ffd400"), true, 12)
	loading_title.add_theme_font_override("font", ComicText.comic_font())
	loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_title)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(0, 26)
	loading_bar.max_value = 1.0
	loading_bar.show_percentage = false
	v.add_child(loading_bar)
	loading_label = UITheme.label("", 22, Color.WHITE, true, 6)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)
	ui_root.add_child(loading)

func _debug_extra() -> String:
	return "state %d  phase %d  structs %d  settlers %d  fires %d  particles %d  debris %d" % [
		Game.state, Turn.phase, Breakable.structures.size(), Settler.all.size(), Fire.burning_count(),
		Fx.inst.live_particles if Fx.inst != null else 0, Debris.count()]

# ------------------------------------------------------------------ events -> feel
func _connect_events() -> void:
	Events.camera_shake.connect(func(a: float) -> void:
		cam_rig.shake_enabled = Settings.shake
		cam_rig.shake(a))
	Events.slowmo.connect(_on_slowmo)
	Events.quality_changed.connect(func(tier: String) -> void: Quality.apply(tier, get_viewport(), sky))
	Events.game_over.connect(_on_game_over)
	Events.settler_hit.connect(_on_settler_hit)
	Events.building_destroyed.connect(_on_building_destroyed)
	Events.catapult_destroyed.connect(_on_catapult_destroyed)
	Events.building_destroyed.connect(func(k: String, o: int, s: Dictionary) -> void: Scoring.on_building_destroyed(k, o, s))
	Events.turn_start.connect(func(_id: int) -> void:
		_overview = false
		hud.overview_on = false
		aiming.overview_active = false)

func _feed_throttle(key: String, seconds: float = 0.5) -> bool:
	var now: float = Time.get_ticks_msec() * 0.001
	if _feed_cool.has(key) and now - float(_feed_cool[key]) < seconds:
		return false
	_feed_cool[key] = now
	return true

func _name_of(pid: int) -> String:
	var p: PlayerData = Game.player(pid)
	return p.name if p != null else "?"

func _on_settler_hit(settler_name: String, _owner_id: int, source: Dictionary, launched: bool) -> void:
	if not launched or source.is_empty() or not source.has("player_id"):
		return
	if not _feed_throttle("launch", 0.8):
		return
	Events.kill_feed.emit(I18n.pick("kill.launched", Game.rng_battle, {"attacker": _name_of(int(source["player_id"])), "victim": settler_name}))

func _on_building_destroyed(kind: String, owner_id: int, source: Dictionary) -> void:
	if kind == "tree":
		return
	Unlocks.on_building_destroyed(kind, owner_id, source)
	var b: String = I18n.t("building." + kind)
	if source.is_empty() or not source.has("player_id"):
		Events.kill_feed.emit(I18n.t("kill.misc.0"))
		return
	var ammo: String = I18n.t("ammo." + str(source.get("ammo", "stone")))
	Events.kill_feed.emit(I18n.pick("kill.flattened", Game.rng_battle, {"attacker": _name_of(int(source["player_id"])), "ammo": ammo, "building": b}))

func _on_catapult_destroyed(owner_id: int, source: Dictionary, reason: String) -> void:
	if reason != "fire" and not source.is_empty() and int(source.get("player_id", owner_id)) != owner_id:
		Events.slowmo.emit(0.2, 1.8)
	Unlocks.on_catapult_destroyed(owner_id, source, reason)
	var victim: String = _name_of(owner_id)
	if reason == "fire":
		Events.kill_feed.emit(I18n.pick("kill.lost_fire", Game.rng_battle, {"victim": victim}))
	elif source.is_empty() or not source.has("player_id"):
		Events.kill_feed.emit(I18n.pick("kill.lost_fire", Game.rng_battle, {"victim": victim}))
	elif int(source["player_id"]) == owner_id:
		Events.kill_feed.emit(I18n.pick("kill.self", Game.rng_battle, {"attacker": victim}))
		Events.banner.emit(I18n.pick("banner.self_hit", Game.rng_battle), "self")
	else:
		Events.kill_feed.emit(I18n.pick("kill.catapult", Game.rng_battle, {"attacker": _name_of(int(source["player_id"])), "victim": victim}))

func _on_slowmo(scale_value: float, duration: float) -> void:
	var now_t: float = Time.get_ticks_msec() * 0.001
	if now_t < _slowmo_until and scale_value > _slowmo_scale:
		return          # a deeper bullet time is already running
	_slowmo_scale = scale_value
	_slowmo_until = now_t + duration

func _on_game_over(winner: int) -> void:
	await get_tree().create_timer(2.8, true, false, true).timeout
	if Game.state != Game.State.GAME_OVER:
		return
	hud.visible = false
	results.show_results(winner, false)
	_fast_forward = false

# ------------------------------------------------------------------ state flow
func _clear_match() -> void:
	world.teardown()
	Weather.reset()
	RandomEvents.reset()
	Game.players.clear()
	_overview = false
	_occluded.clear()
	Turn.phase = Turn.Phase.NONE
	Turn.turn_count = 0
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_fast_forward = false
	Game.wind = Vector2.ZERO

func _show_menu(first: bool) -> void:
	_attract = true
	Game.set_state(Game.State.MENU)
	results.hide_results()
	hud.visible = false
	placement.visible = false
	placement._active = false
	if not first:
		_clear_match()
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# attract world behind the menu (two villages, settlers wander, chimneys smoke)
	var dummy: Array[PlayerData] = []
	for i in 2:
		var p := PlayerData.new()
		p.id = i
		p.name = "Attract %d" % i
		p.color = Game.color_of(i)
		p.type = "peasant"
		dummy.append(p)
	Game.players = dummy
	Game.seed_str = _menu_orbit_seed
	Game.weather_on = false
	Game.events_on = false
	loading.visible = true
	loading_bar.value = 0.0
	loading_label.text = ""
	loading_title.text = I18n.t("loading.title")
	await world.generate(_menu_orbit_seed, dummy, Callable(self, "_on_progress"))
	loading.visible = false
	var focus: Vector3 = Vector3(0, 0, 0)
	if dummy.size() >= 2:
		focus = (dummy[0].village_center + dummy[1].village_center) * 0.5
	cam_rig.map_limit = world.map.map_radius + 20.0
	cam_rig.max_dist = world.map.map_radius * 3.2
	cam_rig.start_orbit(focus, world.map.map_radius * 0.75, 30.0)
	cam_rig.yaw = 0.4
	cam_rig.snap()
	menu.visible = true

func _on_progress(p: float, msg_idx: int) -> void:
	loading_bar.value = p
	var lines: Array = I18n.tr_list("loading.lines")
	if not lines.is_empty():
		loading_label.text = str(lines[msg_idx % lines.size()])

func _on_start_requested() -> void:
	_start_game(Settings.seed_text)

func _build_players(cfg: Array) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var used: Array = []
	var name_rng := Rng.from_string(Settings.seed_text + "-cpu")
	for i in cfg.size():
		var c: Dictionary = cfg[i] as Dictionary
		var p := PlayerData.new()
		p.id = i
		p.type = str(c["type"])
		p.color = Game.color_of(int(c["color"]))
		var nm: String = str(c["name"]).strip_edges()
		if p.type != "human" and (Game.HUMAN_NAMES.has(nm) or nm == ""):
			nm = Game.cpu_name(p.type, used, name_rng)
		if nm == "":
			nm = "Player %d" % (i + 1)
		used.append(nm)
		p.name = nm
		p.reset_ammo(Settings.arsenal)
		out.append(p)
	return out

func _start_game(seed_text: String, keep_layout: bool = false) -> void:
	if _generating:
		return
	# the seed decides the terrain; the village layout gets a fresh nonce for every new match (kept for "same map")
	if not keep_layout:
		Game.layout_nonce = "" if _autotest != "" else str(randi())
	_generating = true
	_attract = false
	_last_seed = seed_text
	_last_config = menu.players_config()
	menu.visible = false
	_clear_match()
	Game.seed_str = seed_text
	Game.turn_timer = Settings.timer
	Game.catapults_per_player = Settings.catapult_count
	Game.palisades_per_player = Settings.palisade_count
	Game.terrain_hills = Settings.terrain_hills
	Game.arsenal = Settings.arsenal.duplicate()
	Game.weather_on = Settings.weather_on
	Game.events_on = Settings.events_on
	Game.players = _build_players(_last_config)
	Game.set_state(Game.State.GENERATING)
	cam_rig.shake_enabled = Settings.shake
	loading.visible = true
	loading_bar.value = 0.0
	Sfx.play("stinger_event", Vector3.INF, 0.6, 5)
	await world.generate(seed_text, Game.players, Callable(self, "_on_progress"))
	loading.visible = false
	_generating = false
	cam_rig.map_limit = world.map.map_radius + 20.0
	cam_rig.max_dist = world.map.map_radius * 3.2
	Weather.reset()
	Game.wind = Vector2.ZERO
	Game.set_state(Game.State.PLACEMENT)
	Turn.phase = Turn.Phase.PLACEMENT
	hud.visible = false
	placement.start(world, cam_rig)
	if _autotest == "":
		pass

func _restart_game(seed_text: String, keep_layout: bool = false) -> void:
	# same players/settings, given seed
	if _last_config.is_empty():
		_last_config = menu.players_config()
	menu.rows = menu.rows   # keep
	Settings.seed_text = seed_text
	_start_game(seed_text, keep_layout)

func _on_placement_done() -> void:
	Game.set_state(Game.State.BATTLE)
	hud.visible = true
	Fire.build_grid()
	Turn.start_battle(Game.players)

# ------------------------------------------------------------------ pause / overview
func _open_pause() -> void:
	if Game.state != Game.State.BATTLE and Game.state != Game.State.PLACEMENT:
		return
	_paused = true
	get_tree().paused = true
	PhysicsServer3D.set_active(false)
	pause_menu.open()

func _close_pause() -> void:
	_paused = false
	get_tree().paused = false
	PhysicsServer3D.set_active(true)
	pause_menu.close()

## Fast-forward is allowed whenever it is not a human's aiming phase (CPU turns, flight, aftermath)
func _can_fast() -> bool:
	if Game.state != Game.State.BATTLE:
		return false
	var p: PlayerData = Game.cur()
	return not (p != null and p.is_human() and Turn.phase == Turn.Phase.AIMING)

func _toggle_fast() -> void:
	if not _fast_forward and not _can_fast():
		return
	_fast_forward = not _fast_forward
	Events.toast.emit(I18n.t("hud.fast") if _fast_forward else "")

## Left click in the overview: set / move / remove the player's single map marker (spec 6.7)
func _place_marker(pos: Vector2, remove: bool) -> void:
	var p: PlayerData = Game.viewer()
	if p == null:
		return
	var org: Vector3 = cam_rig.cam.project_ray_origin(pos)
	var dir: Vector3 = cam_rig.cam.project_ray_normal(pos)
	var hit: Vector3 = Terrain.pick(org, dir, 1200.0)
	if hit == Vector3.INF:
		return
	if remove or (p.marker != Vector3.INF and Util.dist_xz(p.marker, hit) < 4.0):
		if p.marker != Vector3.INF:
			p.marker = Vector3.INF
			Events.toast.emit(I18n.t("marker.cleared"))
			Sfx.play("ui_click", Vector3.INF, 0.5, 0)
		return
	p.marker = hit
	Events.toast.emit(I18n.t("marker.set"))
	Sfx.play("ui_click", Vector3.INF, 0.9, 0)

func _toggle_overview() -> void:
	if Game.state != Game.State.BATTLE:
		return
	_overview = not _overview
	aiming.overview_active = _overview
	hud.overview_on = _overview
	if _overview:
		# the whole playfield: map center, far enough out to see every village (spec 18.2)
		var r: float = world.map.map_radius
		cam_rig.overview(Vector3.ZERO, r * 1.9, 58.0)
		Events.toast.emit(I18n.t("hud.overview"))
	else:
		if Turn.phase == Turn.Phase.AIMING and Turn.sel != null and Game.cur().is_human():
			cam_rig.aim_at(Turn.sel.global_pos(), Turn.aim_yaw, deg_to_rad(Turn.aim_elev))
		elif Game.cur() != null:
			cam_rig.focus_on(Game.cur().village_center, 46.0, 40.0)

# ------------------------------------------------------------------ main loop
func _physics_process(dt: float) -> void:
	if _paused:
		return
	_wall_time += dt
	if world == null or world.map == null:
		return
	var st: int = Game.state
	if st == Game.State.MENU or st == Game.State.PLACEMENT or st == Game.State.BATTLE or st == Game.State.GAME_OVER:
		world.physics_tick(dt, cam_rig.camera_position())
		if st != Game.State.MENU:
			RandomEvents.tick(dt)
			Weather.update(dt)
	if st == Game.State.BATTLE or st == Game.State.GAME_OVER:
		Turn.update(dt)
	if st == Game.State.GAME_OVER:
		pass

func _process(delta: float) -> void:
	_frames += 1
	delta = minf(delta, 1.0 / 20.0)
	# slow motion (real-time timers)
	var now: float = Time.get_ticks_msec() * 0.001
	var target_scale: float = 1.0
	if now < _slowmo_until:
		target_scale = _slowmo_scale
	elif _fast_forward:
		target_scale = 3.0
	elif _debug_slowmo:
		target_scale = Cfg.SLOWMO_SCALE
	if _fast_forward and not _can_fast():
		_fast_forward = false
	hud.fast_on = _fast_forward
	if not _paused:
		_apply_speed(target_scale, delta)
		# bullet time stretches the sound as well (pitch and speed follow the time scale)
		AudioServer.playback_speed_scale = clampf(Engine.time_scale, 0.1, 1.0)
	if world == null or world.map == null:
		return
	sky.high_view = _overview and Game.state == Game.State.BATTLE
	sky.update(delta, Game.wind)
	if not _paused:
		world.frame_tick(delta)
		_update_nameplates()
		_camera_controls(delta)
		cam_rig.update(delta)
		_update_occluders()
		_auto_quality(delta)
	hud.visible = Game.state == Game.State.BATTLE and not results.visible
	vignette.visible = Game.state != Game.State.MENU

## Slow motion scales time down (small physics steps). Fast-forward raises the tick rate instead of the step
## length (180 ticks x time_scale 3 = fixed 1/60 s steps), because long physics steps make bodies tunnel.
func _apply_speed(target_scale: float, delta: float) -> void:
	if target_scale > 1.05:
		var ticks: int = int(round(60.0 * target_scale))
		if Engine.physics_ticks_per_second != ticks:
			Engine.physics_ticks_per_second = ticks
		Engine.time_scale = target_scale
	else:
		if Engine.physics_ticks_per_second != 60:
			Engine.physics_ticks_per_second = 60
			Engine.time_scale = 1.0
		Engine.time_scale = lerpf(Engine.time_scale, target_scale, minf(delta * 20.0 / maxf(Engine.time_scale, 0.1), 1.0))

func _update_nameplates() -> void:
	# owner nameplates: the current player's catapults during their turn, every catapult in the overview camera
	var battle: bool = Game.state == Game.State.BATTLE
	for p in Game.players:
		var first_alive: Catapult = null
		for c0 in p.catapults:
			if not is_instance_valid(c0):
				continue
			var c1: Catapult = c0 as Catapult
			if c1 != null and not c1.destroyed:
				first_alive = c1
				break
		for c in p.catapults:
			if not is_instance_valid(c):
				continue
			var cat: Catapult = c as Catapult
			if cat == null:
				continue
			var visible_ok: bool = battle and not p.eliminated and Turn.phase != Turn.Phase.FLIGHT and Turn.phase != Turn.Phase.AFTERMATH
			# own turn: every catapult of the current player; overview camera: one plate per village
			var own_turn: bool = p.id == Game.current_player and not _overview and Turn.sel != null and cat == Turn.sel
			var show: bool = visible_ok and (own_turn or (_overview and cat == first_alive))
			cat.set_nameplate_visible(show)

## While a catapult aims / fires, buildings (trees, posts) between the chase camera and the catapult are hidden
## so the shot is never blocked from view. They come back as soon as the catapult has shot.
func _update_occluders() -> void:
	var want: Array[Structure] = []
	var active: bool = Game.state == Game.State.BATTLE and Turn.sel != null and is_instance_valid(Turn.sel) \
		and (Turn.phase == Turn.Phase.AIMING or Turn.phase == Turn.Phase.FIRING) and cam_rig.mode == CameraRig.Mode.AIM
	if active:
		var from: Vector3 = cam_rig.camera_position()
		var to: Vector3 = Turn.sel.global_pos() + Vector3(0, 1.8, 0)
		var probe := AABB()
		for s in Breakable.structures:
			if s.free_parts or s.root == null or not is_instance_valid(s.root) or s.live_count <= 0:
				continue
			probe = s.aabb.grow(0.4)
			# the catapult's own surroundings (props, carts) stay visible: only big things behind it are hidden
			if probe.intersects_segment(from, to) and to.distance_to(s.center) > 1.0:
				want.append(s)
	for s2 in _occluded:
		if is_instance_valid(s2.root) and not want.has(s2):
			s2.root.visible = true
	for s3 in want:
		s3.root.visible = false
	_occluded = want

func _camera_controls(delta: float) -> void:
	# WASD pans the overview camera, Home recenters
	if cam_rig.mode == CameraRig.Mode.OVERVIEW:
		var v := Vector3.ZERO
		var yaw: float = cam_rig.yaw
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		if Input.is_key_pressed(KEY_W):
			v += fwd
		if Input.is_key_pressed(KEY_S):
			v -= fwd
		if Input.is_key_pressed(KEY_D):
			v += right
		if Input.is_key_pressed(KEY_A):
			v -= right
		if v != Vector3.ZERO:
			cam_rig.pan_world(v.normalized() * cam_rig.dist * 0.7 * delta)
	elif cam_rig.mode == CameraRig.Mode.ORBIT:
		pass

func _auto_quality(delta: float) -> void:
	if not Settings.auto_quality or Game.state != Game.State.BATTLE or _paused:
		_fps_low_time = 0.0
		return
	var fps: float = Engine.get_frames_per_second()
	if fps > 0.0 and fps < 40.0 and Engine.time_scale >= 0.99:
		_fps_low_time += delta
	else:
		_fps_low_time = maxf(_fps_low_time - delta, 0.0)
	if _fps_low_time > 5.0:
		_fps_low_time = 0.0
		var lower: String = Quality.lower(Quality.current_id)
		if lower != Quality.current_id:
			Settings.quality = lower
			Quality.apply(lower, get_viewport(), sky)
			Events.toast.emit(I18n.t("hud.quality_dropped", {"q": I18n.t("menu.q_" + lower)}))

# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	# a click, Space or Esc ends bullet time first (and does nothing else)
	if Time.get_ticks_msec() * 0.001 < _slowmo_until and _slowmo_scale < 0.5 and Game.state == Game.State.BATTLE:
		var cancel: bool = false
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			cancel = true
		elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and ((event as InputEventKey).keycode == KEY_SPACE or (event as InputEventKey).keycode == KEY_ESCAPE):
			cancel = true
		if cancel:
			_slowmo_until = 0.0
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		match k.keycode:
			KEY_F11:
				Settings.toggle_fullscreen()
			KEY_F3:
				if Settings.debug:
					debug_overlay.visible = not debug_overlay.visible
			KEY_ESCAPE:
				if _paused:
					_close_pause()
				elif Game.state == Game.State.BATTLE or Game.state == Game.State.PLACEMENT:
					if aiming.dragging:
						aiming.cancel_drag()
					else:
						_open_pause()
			KEY_V:
				_toggle_overview()
			KEY_HOME:
				if Game.cur() != null:
					cam_rig.recenter(Game.cur().village_center)
			KEY_F:
				_toggle_fast()
			KEY_SPACE:
				if Game.state == Game.State.BATTLE:
					if Turn.phase == Turn.Phase.AFTERMATH and not _overview:
						Turn.skip_aftermath()
					elif _can_fast() or _fast_forward:
						_toggle_fast()
		if Settings.debug:
			_debug_key(k)
	# mouse camera controls in the other modes (aiming handles its own)
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if cam_rig.mode == CameraRig.Mode.OVERVIEW or cam_rig.mode == CameraRig.Mode.FOCUS or cam_rig.mode == CameraRig.Mode.IMPACT:
			if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				cam_rig.orbit_drag(mm.relative.x, mm.relative.y)
			elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT and mm.shift_pressed):
				cam_rig.pan(mm.relative.x, mm.relative.y)
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and Game.state == Game.State.BATTLE and Turn.phase == Turn.Phase.AFTERMATH and not _overview:
			Turn.skip_aftermath()
			get_viewport().set_input_as_handled()
			return
		if _overview and Game.state == Game.State.BATTLE and mb.button_index == MOUSE_BUTTON_LEFT:
			_place_marker(mb.position, mb.shift_pressed)
			get_viewport().set_input_as_handled()
			return
		if Game.state != Game.State.PLACEMENT and Game.state != Game.State.BATTLE:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				cam_rig.zoom(1.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cam_rig.zoom(-1.0)
		elif Game.state == Game.State.BATTLE and Game.cur() != null and Game.cur().is_cpu():
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				cam_rig.zoom(1.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cam_rig.zoom(-1.0)

func _debug_key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_B:
			_spawn_test_ball()
		KEY_E:
			RandomEvents.debug_next()
		KEY_W:
			if not (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)) and cam_rig.mode != CameraRig.Mode.OVERVIEW:
				var kinds: Array[String] = ["clear", "cloudy", "rain", "thunder", "storm"]
				var i: int = (kinds.find(Game.weather) + 1) % kinds.size()
				Weather.set_weather(kinds[i], 2, true)
		KEY_K:
			if Turn.sel != null:
				Turn.sel.destroy("debug")
		KEY_F:
			var hit: Vector3 = Terrain.pick(cam_rig.cam.project_ray_origin(get_viewport().get_mouse_position()), cam_rig.cam.project_ray_normal(get_viewport().get_mouse_position()))
			if hit != Vector3.INF:
				Fire.ignite_in_radius(hit, 2.5, 1.0, {})
		KEY_X:
			var hit2: Vector3 = Terrain.pick(cam_rig.cam.project_ray_origin(get_viewport().get_mouse_position()), cam_rig.cam.project_ray_normal(get_viewport().get_mouse_position()))
			if hit2 != Vector3.INF:
				Explosion.explode(hit2, 6.0, 700.0, {"source": {}})
		KEY_C:
			get_tree().debug_collisions_hint = not get_tree().debug_collisions_hint
		KEY_H:
			for p in Game.players:
				for c in p.catapults:
					if is_instance_valid(c):
						(c as Catapult).hp = Cfg.CATAPULT_HP
		KEY_T:
			_debug_slowmo = not _debug_slowmo
		KEY_O:
			Toon.set_outlines(not Toon.outlines_on)

func _spawn_test_ball() -> void:
	var mp: Vector2 = get_viewport().get_mouse_position()
	var org: Vector3 = cam_rig.cam.project_ray_origin(mp)
	var dir: Vector3 = cam_rig.cam.project_ray_normal(mp)
	var hit: Vector3 = Terrain.pick(org, dir)
	var pos: Vector3 = (hit + Vector3(0, 8, 0)) if hit != Vector3.INF else org + dir * 30.0
	var d := PhysWorld.BodyDesc.new()
	d.shapes.append(PhysWorld.sphere_desc(0.6))
	d.xf = Transform3D(Basis(), pos)
	d.mass = 30.0
	d.friction = 0.6
	d.bounce = 0.35
	d.layer = Cfg.LAYER_DEBRIS
	d.mask = Cfg.LAYER_ALL
	d.kind = "shard"
	var mi := MeshInstance3D.new()
	mi.mesh = MeshGen.sphere_mesh(0.6)
	mi.material_override = Toon.colored(Color("#ff5b5b"))
	world.fx_root.add_child(mi)
	d.visual = mi
	var id: int = PhysWorld.add_body(d)
	var pb: PhysWorld.PBody = PhysWorld.body(id)
	pb.buoy = 0.6
	pb.radius = 0.6
	Debris.register_shard(id, mi)
	_test_ball_count += 1

# ------------------------------------------------------------------ window
func _exit_tree() -> void:
	# free every RID we own so quitting is clean (bodies, joints, shapes)
	if world != null and is_instance_valid(world):
		world.teardown()
	PhysWorld.shutdown()
	_release_statics()

## Drop every static reference to a Resource/Node so the engine can free them cleanly on exit
func _release_statics() -> void:
	MeshGen.clear_caches()
	Toon.clear()
	Toon._toon_shader = null
	Toon._outline_shader = null
	Toon._unlit_shader = null
	Settler._torso_cache.clear()
	Settler._head_cache.clear()
	Settler._limb_cache.clear()
	Settler._ghost_tex = null
	Settler.all.clear()
	Animal._mesh_cache.clear()
	Animal.all.clear()
	Catapult._bar_shader = null
	Catapult._ring_mesh = null
	Catapult._quad = null
	Flag._mesh = null
	Flag._shader = null
	Flag.all.clear()
	ComicText._font = null
	ComicText.inst = null
	Speech._font = null
	Speech.inst = null
	UITheme._theme = null
	UITheme._font = null
	UITheme._font_bold = null
	Fx.inst = null
	Weather._rain = null
	Weather._rain_cpu = null
	Weather._bolt = null
	Weather._bolt_mesh = null
	Weather._light = null
	Weather.sky = null
	Weather.cam = null
	Weather.fx_root = null
	WaterSys._disc = null
	WaterSys.root = null
	Breakable.world_root = null
	Breakable.structures.clear()
	Breakable.awake_list.clear()
	Fire.light_root = null
	Fire.grid.clear()
	Projectile.world_root = null
	Projectile.all_live.clear()
	Settler.world_root = null
	Animal.world_root = null
	Flag.world_root = null
	Trail.reset_statics()
	RandomEvents.world = null
	RandomEvents.cam = null
	RandomEvents.fx_root = null
	Turn.world = null
	Turn.cam = null
	Turn.sel = null
	Game.world = null
	Game.players.clear()
	Quality.tiers.clear()
	Quality.current = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Settings.win_size = get_window().size if get_window().mode == Window.MODE_WINDOWED else Settings.win_size
		Settings.save_settings()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# pause during a human turn without a timer jump
		if Game.state == Game.State.BATTLE and Game.cur() != null and Game.cur().is_human() and not _paused and _autotest == "":
			_open_pause()
			Events.toast.emit(I18n.t("hud.paused_focus"))

# ------------------------------------------------------------------ autotest hooks
func _save_shot(shot_name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://shot_%s.png" % shot_name
	img.save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func _run_autotest() -> void:
	await AutoTest.run(self, _autotest)
