class_name Toon
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Toon + outline material factory (spec 16.1). One shader, many materials.

static var _toon_shader: Shader
static var _outline_shader: Shader
static var _main: ShaderMaterial
static var _outline: ShaderMaterial
static var _terrain: ShaderMaterial
static var _unlit_shader: Shader
static var _cache: Dictionary = {}
static var outlines_on: bool = true

static func toon_shader() -> Shader:
	if _toon_shader == null:
		_toon_shader = load("res://scripts/render/shaders/toon.gdshader") as Shader
		if not use_instance_params():
			# every instance with an instance uniform costs one of the 4096 slots of the OpenGL renderer: use a copy of the
			# shader whose per-instance values are constants (colour comes from the material instead, see set_tint)
			var src: String = _toon_shader.code
			src = src.replace("instance uniform vec4 tint : source_color = vec4(1.0);", "const vec4 tint = vec4(1.0);")
			src = src.replace("instance uniform float glow = 0.0;", "const float glow = 0.0;")
			src = src.replace("instance uniform float wet = 0.0;", "const float wet = 0.0;")
			var sh := Shader.new()
			sh.code = src
			_toon_shader = sh
	return _toon_shader

static func outline_shader() -> Shader:
	if _outline_shader == null:
		_outline_shader = load("res://scripts/render/shaders/outline.gdshader") as Shader
	return _outline_shader

static func outline_material() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = outline_shader()
	return _outline

## Per-instance shader parameters (tint / glow / wet) are cheap in Forward+ / Mobile, but the OpenGL (Compatibility) renderer
## only has room for 4096 instances using them: beyond that colours turn into garbage (orange / purple). There the colour of a
## part is a cached material per (quantised) colour instead, and glow / wet are skipped.
static var _inst: int = -1

static func use_instance_params() -> bool:
	if _inst < 0:
		_inst = 0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1
	return _inst == 1

## Colour a mesh instance of a part (absolute colour, white = the plain vertex colours)
static func set_tint(mi: MeshInstance3D, col: Color) -> void:
	if use_instance_params():
		mi.set_instance_shader_parameter("tint", col)
	elif col.is_equal_approx(Color.WHITE):
		mi.material_override = main()
	else:
		var q := Color(roundf(col.r * 24.0) / 24.0, roundf(col.g * 24.0) / 24.0, roundf(col.b * 24.0) / 24.0, 1.0)
		mi.material_override = colored(q)

static func set_glow(mi: MeshInstance3D, v: float) -> void:
	if use_instance_params():
		mi.set_instance_shader_parameter("glow", v)

static func set_wet(mi: MeshInstance3D, v: float) -> void:
	if use_instance_params():
		mi.set_instance_shader_parameter("wet", v)

## Main shared material (vertex color x instance tint) with outline pass.
static func main() -> ShaderMaterial:
	if _main == null:
		_main = ShaderMaterial.new()
		_main.shader = toon_shader()
		if outlines_on:
			_main.next_pass = outline_material()
	return _main

## Toon material without outline (particles-adjacent stuff, big flat things)
static func plain() -> ShaderMaterial:
	if _cache.has("plain"):
		return _cache["plain"] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = toon_shader()
	_cache["plain"] = m
	return m

static func terrain() -> ShaderMaterial:
	if _terrain == null:
		_terrain = ShaderMaterial.new()
		_terrain.shader = toon_shader()
		_terrain.set_shader_parameter("terrain_noise", 1.0)
	return _terrain

static func set_outlines(on: bool) -> void:
	outlines_on = on
	if _main != null:
		_main.next_pass = outline_material() if on else null
	for k in _cache:
		var m: ShaderMaterial = _cache[k] as ShaderMaterial
		if m != null and bool(m.get_meta("outlined", false)):
			m.next_pass = outline_material() if on else null

## Glowing toon material (emission), cached per color+strength; with outline.
static func emissive(color: Color, strength: float = 1.0, outlined: bool = true) -> ShaderMaterial:
	var key: String = "em:%s:%.2f:%s" % [color.to_html(), strength, str(outlined)]
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = toon_shader()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission_strength", strength)
	m.set_shader_parameter("emission_color", color)
	if outlined:
		m.set_meta("outlined", true)
		if outlines_on:
			m.next_pass = outline_material()
	_cache[key] = m
	return m

## Toon material tinted by a fixed albedo color (cached), with outline.
static func colored(color: Color, outlined: bool = true) -> ShaderMaterial:
	var key: String = "col:%s:%s" % [color.to_html(), str(outlined)]
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = toon_shader()
	m.set_shader_parameter("albedo", color)
	if outlined:
		m.set_meta("outlined", true)
		if outlines_on:
			m.next_pass = outline_material()
	_cache[key] = m
	return m

## Unshaded alpha material (rings, marker discs, glow blobs, bubbles). Cached.
static func unlit(color: Color, additive: bool = false, no_depth: bool = false) -> StandardMaterial3D:
	var key: String = "ul:%s:%s:%s" % [color.to_html(true), str(additive), str(no_depth)]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	if color.a < 0.999 or additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = no_depth
	_cache[key] = m
	return m

static func clear() -> void:
	_cache.clear()
	_main = null
	_outline = null
	_terrain = null
