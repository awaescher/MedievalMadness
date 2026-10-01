class_name Weather
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Weather state machine (spec 11.4), evaluated at each turn start: clear / cloudy / rain / thunder / storm.

static var sky: SkyRig
static var cam: CameraRig
static var fx_root: Node3D
static var _rain: GPUParticles3D
static var _rain_cpu: CPUParticles3D
static var _bolt: MeshInstance3D
static var _bolt_mesh: ImmediateMesh
static var _bolt_t: float = 0.0
static var _light: OmniLight3D

static func reset() -> void:
	Game.weather = "clear"
	Game.weather_turns_left = 0
	Fire.raining = false
	if sky != null:
		sky.set_weather(0.0, 0.0)
	if _rain != null:
		_rain.emitting = false
	if _rain_cpu != null:
		_rain_cpu.emitting = false

## chance per turn: clear 55, cloudy 15, rain 12, thunderstorm 8, storm 10 (wind only)
static func turn_start() -> void:
	if not Game.weather_on:
		if Game.weather != "clear":
			set_weather("clear", 0, false)
		return
	if Game.weather_turns_left > 0:
		Game.weather_turns_left -= 1
		if Game.weather_turns_left > 0:
			# still going: thunderstorms strike at every turn start
			if Game.weather == "thunder":
				lightning_strike()
			return
		if Game.weather != "clear":
			set_weather("clear", 0, true)
		return
	var r: Rng = Game.rng_battle
	var k: int = r.pick_weighted([55.0, 15.0, 12.0, 8.0, 10.0])
	match k:
		1:
			set_weather("cloudy", r.range_i(1, 3), true)
		2:
			set_weather("rain", r.range_i(2, 3), true)
		3:
			set_weather("thunder", r.range_i(1, 2), true)
			lightning_strike()
		4:
			set_weather("storm", r.range_i(1, 2), true)
		_:
			pass

static func set_weather(kind: String, turns: int, announce: bool = true) -> void:
	Game.weather = kind
	Game.weather_turns_left = turns
	Fire.raining = kind == "rain" or kind == "thunder"
	var storm_mix: float = 0.0
	var fog: float = 0.0
	match kind:
		"cloudy":
			storm_mix = 0.45
		"rain":
			storm_mix = 0.7
			fog = 1.2
		"thunder":
			storm_mix = 1.0
			fog = 1.6
		"storm":
			storm_mix = 0.85
			fog = 0.4
	if sky != null:
		sky.set_weather(storm_mix, fog)
	_set_rain(kind == "rain" or kind == "thunder")
	if Fire.raining:
		# rain puts out the weakest fires right away and makes the ground wet
		pass
	if announce:
		var key: String = "banner.weather_" + kind if kind != "clear" else "banner.weather_clear"
		Events.banner.emit(I18n.t(key), "weather")
		Events.weather_change.emit(kind)

static func _set_rain(on: bool) -> void:
	if fx_root == null:
		return
	if _rain == null and _rain_cpu == null:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.05, 0.9)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.albedo_color = Color(0.7, 0.85, 1.0, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var count: int = mini(800, Quality.particle_cap / 2)
		if Settings.cpu_particles:
			_rain_cpu = CPUParticles3D.new()
			_rain_cpu.amount = count
			_rain_cpu.lifetime = 1.0
			_rain_cpu.local_coords = false
			_rain_cpu.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			_rain_cpu.emission_box_extents = Vector3(30, 0.5, 30)
			_rain_cpu.direction = Vector3.DOWN
			_rain_cpu.spread = 3.0
			_rain_cpu.initial_velocity_min = 24.0
			_rain_cpu.initial_velocity_max = 28.0
			_rain_cpu.gravity = Vector3.ZERO
			_rain_cpu.mesh = quad
			_rain_cpu.material_override = m
			_rain_cpu.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
			fx_root.add_child(_rain_cpu)
		else:
			_rain = GPUParticles3D.new()
			_rain.amount = count
			_rain.lifetime = 1.0
			_rain.local_coords = false
			_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
			var pm := ParticleProcessMaterial.new()
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(30, 0.5, 30)
			pm.direction = Vector3.DOWN
			pm.spread = 3.0
			pm.initial_velocity_min = 24.0
			pm.initial_velocity_max = 28.0
			pm.gravity = Vector3.ZERO
			_rain.process_material = pm
			_rain.draw_pass_1 = quad
			_rain.material_override = m
			_rain.draw_passes = 1
			fx_root.add_child(_rain)
	if _rain != null:
		_rain.emitting = on
	if _rain_cpu != null:
		_rain_cpu.emitting = on

static func update(dt: float) -> void:
	if cam != null:
		var p: Vector3 = cam.camera_position() + Vector3(0, 18, 0)
		if _rain != null:
			_rain.global_position = p
		if _rain_cpu != null:
			_rain_cpu.global_position = p
	# lightning bolt fade
	if _bolt_t > 0.0:
		_bolt_t -= dt
		if _bolt_t <= 0.0 and _bolt != null:
			_bolt.visible = false
			if _light != null:
				_light.visible = false

## Lightning bolt at a tall structure of a living village (spec 11.4)
static func lightning_strike() -> void:
	var living: Array[PlayerData] = Game.living_players()
	if living.is_empty():
		return
	var r: Rng = Game.rng_battle
	var target_p: PlayerData = null
	if r.chance(0.6):
		var best: int = -1
		for p in living:
			if p.catapults_left() > best:
				best = p.catapults_left()
				target_p = p
	if target_p == null:
		target_p = living[r.range_i(0, living.size() - 1)]
	# weighted by tallest structure: church, tower, windmill weight 3
	var cands: Array[Structure] = []
	var weights: Array = []
	for s in Breakable.structures:
		if s.owner_id != target_p.id or s.free_parts or s.destroyed or s.kind == "tree":
			continue
		cands.append(s)
		var w: float = 1.0 + s.height * 0.1
		if s.kind in ["church", "watchtower", "windmill"]:
			w *= 3.0
		weights.append(w)
	var pos: Vector3 = target_p.village_center
	if not cands.is_empty():
		var s2: Structure = cands[r.pick_weighted(weights)]
		pos = s2.top_pos()
	strike_at(pos)

static func strike_at(pos: Vector3) -> void:
	var src: Dictionary = {}
	Fire.ignite_in_radius(pos, 3.0, 0.8, src)
	Explosion.explode(pos, 3.0, 120.0, {"source": src, "sound": "zap", "no_crater": false, "color": Color("#bfefff")})
	Fx.comic_kind("lightning", pos + Vector3.UP * 2.0)
	if sky != null:
		sky.lightning_flash()
	_draw_bolt(pos)
	var cp: Vector3 = cam.camera_position() if cam != null else pos
	var delay: float = clampf(cp.distance_to(pos) / 150.0, 0.2, 2.5)
	Sfx.play("zap", pos, 1.0, 5)
	Sfx.play_delayed("thunder", delay, pos, 1.0)
	Events.camera_shake.emit(0.5)

static func _draw_bolt(pos: Vector3) -> void:
	if fx_root == null:
		return
	if _bolt == null:
		_bolt_mesh = ImmediateMesh.new()
		_bolt = MeshInstance3D.new()
		_bolt.mesh = _bolt_mesh
		_bolt.material_override = Toon.unlit(Color(0.85, 0.95, 1.0, 1.0), true, true)
		_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bolt.extra_cull_margin = 500.0
		fx_root.add_child(_bolt)
		_light = OmniLight3D.new()
		_light.light_color = Color(0.8, 0.9, 1.0)
		_light.light_energy = 8.0
		_light.omni_range = 40.0
		fx_root.add_child(_light)
	_bolt_mesh.clear_surfaces()
	var r: Rng = Rng.new(int(Time.get_ticks_msec()))
	var top: Vector3 = pos + Vector3(r.range_f(-8, 8), 90.0, r.range_f(-8, 8))
	var pts: Array[Vector3] = [top]
	var n: int = 14
	for i in range(1, n):
		var t: float = float(i) / float(n)
		var p: Vector3 = top.lerp(pos, t) + Vector3(r.range_f(-3.0, 3.0), 0, r.range_f(-3.0, 3.0)) * (1.0 - t)
		pts.append(p)
	pts.append(pos)
	var cp: Vector3 = cam.camera_position() if cam != null else pos + Vector3(0, 10, 30)
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var d: Vector3 = (pts[minf(i + 1, pts.size() - 1) as int] - pts[maxi(i - 1, 0)])
		var side: Vector3 = d.cross(cp - pts[i]).normalized() * 0.35
		_bolt_mesh.surface_set_color(Color(1, 1, 1, 1))
		_bolt_mesh.surface_add_vertex(pts[i] + side)
		_bolt_mesh.surface_set_color(Color(1, 1, 1, 1))
		_bolt_mesh.surface_add_vertex(pts[i] - side)
	_bolt_mesh.surface_end()
	_bolt.visible = true
	_bolt_t = 0.22
	_light.global_position = pos + Vector3.UP * 4.0
	_light.visible = true
