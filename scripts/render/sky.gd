class_name SkyRig
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Environment, sun light, gradient sky shader and procedural puffy clouds (spec 16.1).

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var _clouds: Array[Node3D] = []
var _cloud_speed: Array[float] = []
var _storm: float = 0.0
var _storm_target: float = 0.0
var _rain_fog: float = 0.0
var _rain_fog_target: float = 0.0
var _map_radius: float = 120.0
var _base_fog: float = 0.0028
var flash: float = 0.0
var high_view: bool = false          # overview camera: thin fog, no clouds in the way
var _fog_k: float = 1.0

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://scripts/render/shaders/sky.gdshader") as Shader
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9fd8ff")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("#ffe9b8")
	env.fog_density = _base_fog
	env.fog_sky_affect = 0.0
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#fff1d0")
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.0
	add_child(sun)

func build_clouds(map_radius: float, rng: Rng) -> void:
	_map_radius = map_radius
	for c in _clouds:
		c.queue_free()
	_clouds.clear()
	_cloud_speed.clear()
	var count: int = rng.range_i(8, 14)
	var mat: ShaderMaterial = Toon.colored(Color(1, 1, 1), false)
	for i in count:
		var buf := MeshGen.Buf.new()
		var parts: int = rng.range_i(4, 7)
		var spread: float = rng.range_f(10.0, 16.0)
		for k in parts:
			var r: float = rng.range_f(5.0, 9.0) * (1.0 - 0.4 * absf(float(k) / float(parts) - 0.5))
			var pos := Vector3(float(k) / float(parts) * spread * 2.0 - spread, rng.range_f(-1.0, 2.0), rng.range_f(-4.0, 4.0))
			MeshGen.add_sphere(buf, r, Transform3D(Basis(), pos), Color.WHITE, 0.0, 6, 10)
		var mi := MeshInstance3D.new()
		mi.mesh = buf.to_mesh()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.add_child(mi)
		var a: float = rng.range_f(0.0, TAU)
		var rad: float = rng.range_f(0.1, 1.3) * map_radius
		holder.position = Vector3(cos(a) * rad, rng.range_f(150.0, 210.0), sin(a) * rad)
		holder.rotation.y = rng.range_f(0.0, TAU)
		holder.scale = Vector3.ONE * rng.range_f(1.2, 2.2)
		add_child(holder)
		_clouds.append(holder)
		_cloud_speed.append(rng.range_f(0.6, 1.4))

func set_weather(storm: float, fog_mult: float) -> void:
	_storm_target = clampf(storm, 0.0, 1.0)
	_rain_fog_target = fog_mult

func apply_quality(shadows: bool, atlas: int, soft: bool) -> void:
	sun.shadow_enabled = shadows
	if shadows:
		RenderingServer.directional_shadow_atlas_set_size(atlas, true)
		sun.light_angular_distance = 1.0 if soft else 0.0
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if soft else RenderingServer.SHADOW_QUALITY_SOFT_LOW)

func lightning_flash() -> void:
	flash = 1.0

func update(dt: float, wind: Vector2) -> void:
	_storm = move_toward(_storm, _storm_target, dt * 0.5)
	_rain_fog = lerpf(_rain_fog, _rain_fog_target, Util.damp(1.0, dt))
	sky_mat.set_shader_parameter("storm_mix", _storm)
	_fog_k = lerpf(_fog_k, 0.22 if high_view else 1.0, Util.damp(3.0, dt))
	env.fog_density = _base_fog * (1.0 + _rain_fog) * _fog_k
	for cl in _clouds:
		cl.visible = not high_view
	env.fog_light_color = Color("#ffe9b8").lerp(Color("#8a8f99"), _storm)
	env.ambient_light_color = Color("#9fd8ff").lerp(Color("#7f8fa3"), _storm * 0.8)
	sun.light_energy = lerpf(1.25, 0.7, _storm) + flash * 2.5
	flash = maxf(0.0, flash - dt * 3.5)
	var drift := Vector3(wind.x, 0.0, wind.y) * 0.25
	for i in _clouds.size():
		var c: Node3D = _clouds[i]
		c.position += (Vector3(1.2, 0, 0.4) + drift) * dt * _cloud_speed[i]
		var lim: float = _map_radius * 1.6
		if c.position.x > lim:
			c.position.x = -lim
		elif c.position.x < -lim:
			c.position.x = lim
		if c.position.z > lim:
			c.position.z = -lim
		elif c.position.z < -lim:
			c.position.z = lim
