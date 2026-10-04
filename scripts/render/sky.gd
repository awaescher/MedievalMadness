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
var _rich: bool = false
var _fog_col: Color = Color("#ffe9b8")       # base colours of fog / ambient light / sun, set by the graphics style
var _amb_col: Color = Color("#9fd8ff")
var _sun_k: float = 1.0
var _dof: CameraAttributesPractical     # distance blur of the natural style (off in the overview)

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

## Lighting presets. basic = the old flat look; enhanced = filmic tonemap, SSAO, bloom, soft sun shadows;
## rt = additionally ray-marched global illumination (SDFGI) and volumetric light shafts. The last two need the Forward+ renderer.
func apply_lighting(mode: String) -> void:
	var fp: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	if not fp and mode == "rt":
		mode = "enhanced"
	var rich: bool = mode != "basic"
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if rich else Environment.TONE_MAPPER_LINEAR
	env.tonemap_white = 6.0
	env.adjustment_enabled = rich
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	env.glow_enabled = false          # (bloom was behind the blocky yellow squares around flames: no glow at all)
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	# only the fine glow levels: the coarse ones (1/32, 1/64 resolution) are what showed up as big pixel blocks around flames
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.7)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.5)
	env.set_glow_level(4, 0.0)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = rich and fp
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.35
	# (no SSIL: it paints blocky yellow halos around bright flames; SSAO stays)
	env.ssil_enabled = false
	env.ssil_intensity = 0.8
	env.sdfgi_enabled = mode == "rt" and fp
	env.sdfgi_cascades = 5
	env.sdfgi_min_cell_size = 0.6
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.2
	env.sdfgi_energy = 0.85
	env.volumetric_fog_enabled = mode == "rt" and fp
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color("#fff0cf")
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_gi_inject = 0.0
	sun.light_angular_distance = 0.6 if rich else sun.light_angular_distance
	_rich = rich
	_base_fog = 0.0028 * (0.5 if rich else 1.0)

## Graphics style overrides on top of apply_lighting() (see GfxStyle for the table): colours, exposure, post effects.
func apply_style(st: GfxStyle.Style) -> void:
	var fp: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	_fog_col = st.fog_color
	_amb_col = st.ambient_color
	_sun_k = st.sun_k
	_base_fog = 0.0028 * (0.5 if _rich else 1.0) * st.fog_k
	sun.light_color = st.sun_color
	env.ambient_light_energy = st.ambient_energy
	env.tonemap_mode = st.tonemap if _rich or st.force_tonemap else env.tonemap_mode
	env.tonemap_exposure = st.exposure
	env.adjustment_enabled = st.id != "toon" or _rich
	env.adjustment_saturation = st.saturation if st.id != "toon" or _rich else 1.0
	env.adjustment_contrast = st.contrast if st.id != "toon" or _rich else 1.0
	env.ssr_enabled = st.ssr and fp
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	if st.glow > 0.0:
		env.glow_enabled = true
		env.glow_intensity = st.glow
		env.glow_bloom = st.bloom
		env.glow_hdr_threshold = st.glow_threshold
		env.set_glow_level(4, 0.6)
		env.set_glow_level(5, 0.3)
	if st.ssao_k > 0.0:
		env.ssao_enabled = fp
		env.ssao_intensity *= st.ssao_k
	if st.id != "toon" and st.ssil and fp:
		env.ssil_enabled = true
		env.ssil_intensity = 0.6
	if st.id != "toon" and st.sdfgi_off:
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
	if st.id == "photo" and fp:
		env.sdfgi_energy = 1.0
	sun.light_angular_distance = st.sun_soft if st.sun_soft >= 0.0 else sun.light_angular_distance
	env.fog_sun_scatter = st.fog_scatter
	env.fog_aerial_perspective = st.aerial
	if st.vol_density >= 0.0 and env.volumetric_fog_enabled:
		env.volumetric_fog_density = st.vol_density
		env.volumetric_fog_anisotropy = 0.75
	if st.dof_far > 0.0:
		var ca := CameraAttributesPractical.new()
		ca.dof_blur_far_enabled = true
		ca.dof_blur_far_distance = st.dof_far
		ca.dof_blur_far_transition = 90.0
		ca.dof_blur_amount = 0.04
		world_env.camera_attributes = ca
		_dof = ca
	else:
		world_env.camera_attributes = null
		_dof = null
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if st.ambient_sky else Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 1.0
	var rad: int = Sky.RADIANCE_SIZE_128 if st.ambient_sky else Sky.RADIANCE_SIZE_32
	if env.sky.radiance_size != rad:
		env.sky.radiance_size = rad
	sun.rotation_degrees.x = st.sun_pitch
	sun.shadow_opacity = st.shadow_opacity
	if st.ssao_radius > 0.0:
		env.ssao_radius = st.ssao_radius
		env.ssao_detail = 1.0
	# shadows: the fine style spends more cascades and atlas on them; everything else keeps the cheap 2-cascade setup
	var ultra: bool = Quality.current_id == "ultra"
	if st.fine_shadows and sun.shadow_enabled:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_split_1 = 0.04
		sun.directional_shadow_split_2 = 0.14
		sun.directional_shadow_split_3 = 0.4
		sun.directional_shadow_blend_splits = true
		sun.shadow_bias = 0.06
		sun.shadow_normal_bias = 0.3
		if ultra:
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if ultra else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, not ultra, 0.5, 2, 50.0, 300.0)
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.1
		sun.directional_shadow_blend_splits = false
		sun.shadow_bias = 0.05
		sun.shadow_normal_bias = 1.0
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)

func lightning_flash() -> void:
	flash = 1.0

func update(dt: float, wind: Vector2) -> void:
	_storm = move_toward(_storm, _storm_target, dt * 0.5)
	if _dof != null:
		_dof.dof_blur_far_enabled = not high_view
	_rain_fog = lerpf(_rain_fog, _rain_fog_target, Util.damp(1.0, dt))
	sky_mat.set_shader_parameter("storm_mix", _storm)
	_fog_k = lerpf(_fog_k, 0.22 if high_view else 1.0, Util.damp(3.0, dt))
	env.fog_density = _base_fog * (1.0 + _rain_fog) * _fog_k
	for cl in _clouds:
		cl.visible = not high_view
	env.fog_light_color = _fog_col.lerp(Color("#8a8f99"), _storm)
	env.ambient_light_color = _amb_col.lerp(Color("#7f8fa3"), _storm * 0.8)
	sun.light_energy = lerpf(1.25, 0.7, _storm) * (1.12 if _rich else 1.0) * _sun_k + flash * 2.5
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
