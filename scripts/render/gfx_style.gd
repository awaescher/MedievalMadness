class_name GfxStyle
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Graphics styles: the same game in another look. One global shader parameter (gfx_style, see project.godot) switches the
## toon / outline / water / sky shaders, a full-screen post shader adds grain / pixelation / halftone, and the
## environment gets its own colours and effects. Applies live from Quality.apply().

class Style extends RefCounted:
	var id: String
	var index: int
	var outlines: bool = true
	var post: bool = false
	var fog_color: Color = Color("#ffe9b8")
	var ambient_color: Color = Color("#9fd8ff")
	var ambient_energy: float = 0.7
	var sun_color: Color = Color("#fff1d0")
	var sun_k: float = 1.0
	var sun_soft: float = -1.0
	var fog_k: float = 1.0
	var tonemap: int = Environment.TONE_MAPPER_FILMIC
	var force_tonemap: bool = false
	var exposure: float = 1.0
	var saturation: float = 1.18
	var contrast: float = 1.06
	var glow: float = 0.0
	var bloom: float = 0.05
	var glow_threshold: float = 1.2
	var ssao_k: float = 0.0
	var ssil: bool = false
	var ssr: bool = false
	var sdfgi_off: bool = false
	var lighting: String = ""         # forces a lighting preset ("" = the player's choice)
	var scale: float = 0.0            # > 0: render resolution scale
	var no_msaa: bool = false
	var ambient_sky: bool = false     # ambient light comes from the sky (blue from above, ground bounce below) instead of one flat colour
	var sun_pitch: float = -52.0      # sun elevation in degrees (lower = longer, more dramatic shadows)
	var fine_shadows: bool = false    # 4 shadow cascades, finer atlas, softer penumbra (see SkyRig.apply_style)
	var ssao_radius: float = -1.0
	var fog_scatter: float = 0.0      # fog glows towards the sun (golden haze)
	var aerial: float = 0.0           # distant fog takes on the sky colour (atmospheric perspective)
	var vol_density: float = -1.0     # volumetric fog (light shafts), only with the "rt" lighting preset; < 0: keep the preset
	var dof_far: float = 0.0          # > 0: distant things go slightly soft (distance in m where it starts)
	var shadow_opacity: float = 1.0   # < 1: shadows let some sun through, so nothing in them turns black

static var styles: Dictionary = {}
static var current: Style
static var post_layer: CanvasLayer
static var post_rect: ColorRect

static func _ensure() -> void:
	if not styles.is_empty():
		return
	var toon := Style.new()
	toon.id = "toon"
	styles["toon"] = toon

	var photo := Style.new()
	photo.id = "photo"
	photo.index = 1
	photo.outlines = false
	photo.post = true
	photo.fog_color = Color("#e8cba2")
	photo.ambient_color = Color("#a3bbdc")
	photo.ambient_energy = 1.1
	photo.ambient_sky = true
	photo.sun_color = Color("#ffd6a0")
	photo.sun_k = 1.55
	photo.sun_pitch = -25.0
	photo.fine_shadows = true
	photo.shadow_opacity = 0.85
	photo.ssao_radius = 1.3
	photo.sun_soft = 0.3
	photo.fog_k = 0.9
	photo.fog_scatter = 0.55
	photo.aerial = 0.4
	photo.vol_density = 0.005
	photo.dof_far = 90.0
	photo.tonemap = Environment.TONE_MAPPER_AGX
	photo.force_tonemap = true
	photo.exposure = 1.08
	photo.saturation = 1.12
	photo.contrast = 1.12
	photo.glow = 0.9
	photo.bloom = 0.09
	photo.glow_threshold = 0.85
	photo.ssao_k = 0.75
	photo.ssil = true
	photo.ssr = true
	photo.lighting = "rt"
	styles["photo"] = photo

	var retro := Style.new()
	retro.id = "retro"
	retro.index = 3
	retro.post = true
	retro.outlines = false
	retro.fog_color = Color("#c9bd98")
	retro.ambient_color = Color("#ffffff")
	retro.ambient_energy = 0.6
	retro.fog_k = 1.4
	retro.tonemap = Environment.TONE_MAPPER_LINEAR
	retro.force_tonemap = true
	retro.saturation = 1.0
	retro.contrast = 1.0
	retro.sdfgi_off = true
	retro.lighting = "basic"
	retro.no_msaa = true
	styles["retro"] = retro

	var noir := Style.new()
	noir.id = "noir"
	noir.index = 4
	noir.post = true
	noir.fog_color = Color("#c8c8c8")
	noir.ambient_color = Color("#bcbcbc")
	noir.ambient_energy = 0.6
	noir.sun_color = Color("#ffffff")
	noir.sun_k = 1.15
	noir.saturation = 0.0
	noir.contrast = 1.25
	noir.lighting = "enhanced"
	styles["noir"] = noir

	var neon := Style.new()
	neon.id = "neon"
	neon.index = 5
	neon.post = true
	neon.fog_color = Color("#2a0a4a")
	neon.ambient_color = Color("#4a24a0")
	neon.ambient_energy = 0.4
	neon.sun_color = Color("#ff80e0")
	neon.sun_k = 0.6
	neon.fog_k = 0.9
	neon.saturation = 1.2
	neon.contrast = 1.18
	neon.glow = 0.85
	neon.bloom = 0.18
	neon.glow_threshold = 0.9
	neon.lighting = "enhanced"
	styles["neon"] = neon

	var wc := Style.new()
	wc.id = "watercolor"
	wc.index = 6
	wc.outlines = false
	wc.post = true
	wc.fog_color = Color("#fff6ea")
	wc.ambient_color = Color("#f0f0ff")
	wc.ambient_energy = 1.0
	wc.sun_soft = 0.9
	wc.fog_k = 0.7
	wc.saturation = 0.9
	wc.contrast = 0.95
	wc.lighting = "basic"
	styles["watercolor"] = wc

	var comic := Style.new()
	comic.id = "comic"
	comic.index = 7
	comic.post = true
	comic.saturation = 1.08
	comic.contrast = 1.1
	comic.lighting = "basic"
	styles["comic"] = comic
	current = toon

static func get_style(id: String) -> Style:
	_ensure()
	return (styles[id] if styles.has(id) else styles["toon"]) as Style

## The lighting preset a tier / style combination uses
static func lighting_for(tier_id: String) -> String:
	var st: Style = get_style(Settings.gfx_style)
	if tier_id == "low" and st.lighting != "basic":
		return "basic"
	return st.lighting if st.lighting != "" else Settings.lighting

## Apply the chosen style: shader switch, post layer, resolution. Environment / light colours are set by SkyRig.apply_style().
static func apply(viewport: Viewport, host: Node) -> Style:
	var st: Style = get_style(Settings.gfx_style)
	current = st
	if st.id == "photo":
		GfxTextures.load_all()
	RenderingServer.global_shader_parameter_set("gfx_style", float(st.index))
	if host != null:
		_ensure_post(host)
		post_layer.visible = st.post
	if viewport != null:
		if st.no_msaa:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		if st.scale > 0.0:
			viewport.scaling_3d_scale = st.scale
	return st

static func _ensure_post(host: Node) -> void:
	if post_layer != null and is_instance_valid(post_layer):
		return
	post_layer = CanvasLayer.new()
	post_layer.name = "StylePost"
	post_layer.layer = -1                 # above the 3D view, below all UI
	post_rect = ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/render/shaders/post.gdshader") as Shader
	post_rect.material = mat
	post_layer.add_child(post_rect)
	host.add_child(post_layer)

## The graphics style dropdown (changes apply live through Events.quality_changed)
static func make_style_button() -> OptionButton:
	var ob := OptionButton.new()
	for gs in Settings.GFX_STYLES:
		ob.add_item(I18n.t("menu.s_" + gs))
	ob.select(Settings.GFX_STYLES.find(Settings.gfx_style))
	ob.item_selected.connect(func(idx: int) -> void:
		Settings.gfx_style = Settings.GFX_STYLES[idx]
		Events.quality_changed.emit(Settings.quality))
	return ob
