class_name Glass
extends RefCounted
## Frosted "liquid glass" look of the HUD: translucent panels without frames that show a blurred copy of the scene behind them.
##
## How it works: a glass surface is an ordinary stylebox filled with the marker colour (magenta, no border). One shared shader sits on the
## control; it replaces exactly the marker pixels by a blurred copy of the screen behind them (screen texture, 12 taps on a mip level)
## mixed with a light warm tint, and leaves every other pixel (text, icons, key caps) as it was drawn. Alpha is kept, so `modulate`
## still fades a glass element. The OpenGL (Compatibility) renderer gets a plain translucent fill instead of the blur.

const MARK := Color(1.0, 0.0, 1.0, 1.0)
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod = 3.6;
uniform float blur_px = 9.0;
uniform vec4 tint : source_color = vec4(0.984, 0.953, 0.878, 1.0);
uniform float tint_amount = 0.30;
uniform float saturation = 1.35;
uniform float brightness = 0.05;
void fragment() {
	// how much of this pixel is the marker colour (magenta) - 1 inside a glass fill, a fraction on anti-aliased edges and under text
	float c = clamp(min(COLOR.r, COLOR.b) - COLOR.g, 0.0, 1.0);
	if (c > 0.12 && COLOR.g < 0.6) {
		vec2 texel = 1.0 / vec2(textureSize(screen_tex, 0));
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 2.399963;
			float r = sqrt((float(i) + 0.5) / 12.0) * blur_px;
			acc += textureLod(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r * texel, blur_lod).rgb;
		}
		vec3 bg = acc / 12.0;
		float l = dot(bg, vec3(0.299, 0.587, 0.114));
		bg = mix(vec3(l), bg, saturation) + brightness;
		vec3 glass = mix(bg, tint.rgb, tint_amount);
		// take the marker out of the pixel (what was drawn on top of it: an edge, a glyph) and put the glass under it
		vec3 base = clamp((COLOR.rgb - c * vec3(1.0, 0.0, 1.0)) / max(1.0 - c, 0.001), 0.0, 1.0);
		COLOR = vec4(mix(base, glass, c), COLOR.a);
	}
}
"""

static var _mat: ShaderMaterial
static var _forced_off: bool = false

## Dev switch: MM_GLASS=0 turns the glass look off (plain translucent parchment instead of the blur)
static func supported() -> bool:
	if OS.get_environment("MM_GLASS") == "0" or _forced_off or not Settings.glass:
		return false
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat

static func reset() -> void:
	_mat = null

## The fill colour to draw glass with: the marker (blurred by the shader) or a translucent parchment where the shader is not used
static func fill_color() -> Color:
	return MARK if supported() else PLAIN

const PLAIN := Color(0.98, 0.94, 0.84, 0.93)

## For controls that draw glass fills but have no glass material (no shader): a plain translucent fill instead of the magenta marker
static func fit(sb: StyleBoxFlat, c: CanvasItem) -> StyleBoxFlat:
	if c.material == null and sb.bg_color.r > 0.97 and sb.bg_color.g < 0.03:
		sb.bg_color = Color(PLAIN.r, PLAIN.g, PLAIN.b, PLAIN.a * sb.bg_color.a)
	return sb

## A frameless glass stylebox (corner radius, soft shadow, margins like `UITheme.box`)
static func box(radius: int = 14, shadow: int = 8, accent: Color = Color(0, 0, 0, 0), accent_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill_color()
	sb.set_corner_radius_all(radius)
	if accent.a > 0.0 and accent_w > 0:
		sb.border_color = accent
		sb.set_border_width_all(accent_w)
	sb.shadow_color = Color(0, 0, 0, 0.26)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Put the glass look on a control that draws glass stylebox fills itself
static func apply(c: CanvasItem) -> void:
	if supported():
		c.material = material()

static func panel(pc: PanelContainer, radius: int = 16) -> void:
	pc.add_theme_stylebox_override("panel", box(radius, 8))
	apply(pc)

## A dialog / menu panel: frosted glass with generous margins
static func dialog(pc: PanelContainer, radius: int = 20, pad: Vector2 = Vector2(20, 16)) -> void:
	var sb: StyleBoxFlat = box(radius, 14)
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	pc.add_theme_stylebox_override("panel", sb)
	apply(pc)

## THE button look of the whole game: a glass tile with a hair-line light edge and a soft shadow (`edge` brighter on hover)
## The edge of a glass tile: variants to choose from (env MM_EDGE while experimenting): "none", "soft" (faint, 2 px), "dark" (faint dark line)
static var edge_mode: String = OS.get_environment("MM_EDGE") if OS.get_environment("MM_EDGE") != "" else "none"

static func edge_of(a: float) -> Array:
	match edge_mode:
		"soft":
			return [Color(1, 1, 1, a * 0.4), 2]
		"dark":
			return [Color(0.2, 0.12, 0.05, a * 0.22), 1]
		"none":
			return [Color(1, 1, 1, 0.0), 0]       # no edge at all: the 1 px light line frayed (pink / white pixels) at the rounded corners
	return [Color(1, 1, 1, a), 1]

static func tile(radius: int = 12, edge: float = 0.38, fill_a: float = 1.0, shadow: int = 4) -> StyleBoxFlat:
	var ed: Array = edge_of(edge)
	var sb: StyleBoxFlat = box(radius, shadow, ed[0] as Color, int(ed[1]))
	sb.bg_color.a = fill_a if supported() else PLAIN.a * fill_a
	sb.shadow_color = Color(0, 0, 0, 0.22)
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

static func button(b: Button, radius: int = 12) -> void:
	b.add_theme_stylebox_override("normal", tile(radius))
	b.add_theme_stylebox_override("hover", tile(radius, 0.85))
	b.add_theme_stylebox_override("pressed", tile(radius, 0.25, 0.7, 1))
	b.add_theme_stylebox_override("focus", tile(radius, 0.9, 0.0, 0))
	b.add_theme_stylebox_override("disabled", tile(radius, 0.15, 0.45, 0))
	apply(b)

# ------------------------------------------------------------------ glass for buttons and inputs of the menus
## Tint per button variation: [colour, amount]. The button is glass like the panel it sits on, only a light tint colours it.
const TINTS := {
	"GreenButton": [Color("#4fa65f"), 0.42],
	"GoldButton": [Color("#dcae3c"), 0.36],
	"RedButton": [Color("#d9382f"), 0.66],
	"ParchButton": [Color("#ffffff"), 0.24],
	"Button": [Color("#dcae3c"), 0.34],
	"input": [Color("#ffffff"), 0.30],
}
static var _tinted: Dictionary = {}
static var _watching: bool = false

static func tinted(tint: Color, amount: float) -> ShaderMaterial:
	var key: String = "%s_%.2f" % [tint.to_html(false), amount]
	if _tinted.has(key):
		return _tinted[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = material().shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tint_amount", amount)
	m.set_shader_parameter("blur_px", 6.0)
	m.set_shader_parameter("saturation", 1.15)
	m.set_shader_parameter("brightness", 0.03)
	_tinted[key] = m
	return m

## Everything below `root` that is created later (and a button / input of it) gets the glass look automatically
static func watch(root: Node) -> void:
	if not supported():
		return
	root.set_meta("glass_root", true)
	if not _watching:
		_watching = true
		root.get_tree().node_added.connect(_on_node_added)

static func _on_node_added(n: Node) -> void:
	if not (n is Control):
		return
	if not (n is Button or n is LineEdit or n is SpinBox):
		return
	var p: Node = n.get_parent()
	while p != null:
		if p.has_meta("glass_root"):
			_skin.call_deferred(n)
			return
		p = p.get_parent()

static func _skin(n: Node) -> void:
	if not is_instance_valid(n) or not supported():
		return
	if n is CheckBox or n is CheckButton or n is MenuButton:
		return
	if n is SpinBox:
		(n as SpinBox).material = tinted(Color.WHITE, 0.30)          # its line edit draws with the material of the spin box
		return
	if n.get_script() != null and not (n is CloseButton):
		return                                       # self-drawn buttons (flags, icons, key caps) keep their own look
	if n is OptionButton:
		_skin_surface(n as Control, ["normal", "hover", "pressed", "disabled", "focus"], "input", 10, 4)
	elif n is LineEdit:
		_skin_surface(n as Control, ["normal", "focus", "read_only"], "input", 10, 4)
		if n.get_parent() is SpinBox:
			(n as Control).material = null                  # (use_parent_material: the SpinBox carries the glass)
	elif n is Button:
		var b: Button = n as Button
		var v: String = b.theme_type_variation if b.theme_type_variation != "" else "Button"
		_skin_surface(b, ["normal", "hover", "pressed", "disabled", "focus"], v if TINTS.has(v) else "ParchButton", 12, 7)

static func _skin_surface(c: Control, states: Array, tint_key: String, radius: int, pad_v: int) -> void:
	for st in states:
		var edge: float = 0.38
		var fill_a: float = 1.0
		var w: int = 1
		match str(st):
			"hover":
				edge = 0.85
			"pressed":
				fill_a = 0.7
				edge = 0.25
			"disabled":
				fill_a = 0.45
				edge = 0.15
			"focus":
				fill_a = 0.0
				edge = 0.9
				w = 2
		var ed: Array = edge_of(edge)
		var sb: StyleBoxFlat = UITheme.soft(Color(1, 0, 1, fill_a), (ed[0] as Color) if str(st) != "focus" else Color("#c9962a"), radius, int(ed[1]) if str(st) != "focus" else w)
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
		if str(st) in ["normal", "hover"] and c is Button:
			sb.shadow_color = Color(0, 0, 0, 0.16)          # all buttons cast the same soft, small shadow
			sb.shadow_size = 2
			sb.shadow_offset = Vector2(0, 1)
			if c is CloseButton:
				sb.shadow_color = Color(0, 0, 0, 0.22)      # like the flag / cog buttons next to it (top right of the menu)
				sb.shadow_size = 4
				sb.shadow_offset = Vector2(0, 2)
		c.add_theme_stylebox_override(str(st), sb)
	var t: Array = TINTS[tint_key] as Array
	c.material = tinted(t[0] as Color, float(t[1]))
