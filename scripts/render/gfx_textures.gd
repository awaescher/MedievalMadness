class_name GfxTextures
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Real material textures for the photo graphics style (CC0 scans, see assets/textures/README.md). The meshes have no UVs: the toon
## shader projects them triplanar. Colour+roughness and the normal maps live in two texture arrays (one layer per material) that are
## bound as global shader parameters; the layer of a surface comes from the material of its part (vertex UV.x, see MeshGen.Buf.mat).

const LAYERS: Array[String] = ["wood", "plank", "stone", "brick", "thatch", "cloth", "metal", "grass", "ground", "leaf", "shingle", "cobble"]
const SIZE := 512

static var _globals: bool = false
static var _loaded: bool = false

## physics material id -> texture layer (-1: stays untextured)
static func layer(material: String, tag: String = "") -> int:
	if tag == "roof" and material != "thatch" and material != "hay" and material != "cloth":
		return 10
	match material:
		"leaf":
			return 9
		"wood", "barrel_wood":
			return 0
		"plank":
			return 1
		"stone":
			return 2
		"brick":
			return 3
		"thatch", "hay":
			return 4
		"cloth":
			return 5
		"metal":
			return 6
	return -1

static func _placeholder_array() -> Texture2DArray:
	var imgs: Array[Image] = []
	for i in LAYERS.size():
		var im := Image.create(4, 4, true, Image.FORMAT_RGBA8)
		im.fill(Color(0.5, 0.5, 0.5, 0.8))
		im.generate_mipmaps()
		imgs.append(im)
	var t := Texture2DArray.new()
	t.create_from_images(imgs)
	return t

## The shaders reference the globals, so they must exist before the first toon shader compiles.
static func ensure_globals() -> void:
	if _globals:
		return
	_globals = true
	RenderingServer.global_shader_parameter_add("gfx_tex_c", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2DARRAY, _placeholder_array())
	var nrm_imgs: Array[Image] = []
	for i in LAYERS.size():
		var im := Image.create(4, 4, true, Image.FORMAT_RGBA8)
		im.fill(Color(0.5, 0.5, 1.0, 1.0))
		im.generate_mipmaps()
		nrm_imgs.append(im)
	var nt := Texture2DArray.new()
	nt.create_from_images(nrm_imgs)
	RenderingServer.global_shader_parameter_add("gfx_tex_n", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2DARRAY, nt)
	var avg := Image.create(LAYERS.size(), 1, false, Image.FORMAT_RGBA8)
	avg.fill(Color(0.5, 0.5, 0.5, 1.0))
	RenderingServer.global_shader_parameter_add("gfx_tex_avg", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, ImageTexture.create_from_image(avg))

static func _img(path: String) -> Image:
	var tex: Texture2D = load(path) as Texture2D
	var im: Image = tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.clear_mipmaps()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != SIZE or im.get_height() != SIZE:
		im.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return im

## Loads the real textures (first time the photo style is used).
static func load_all() -> void:
	ensure_globals()
	if _loaded:
		return
	_loaded = true
	var cs: Array[Image] = []
	var ns: Array[Image] = []
	var avg := Image.create(LAYERS.size(), 1, false, Image.FORMAT_RGBA8)
	for i in LAYERS.size():
		var name: String = LAYERS[i]
		var c: Image = _img("res://assets/textures/%s_c.jpg" % name)
		var r: Image = _img("res://assets/textures/%s_r.jpg" % name)
		var n: Image = _img("res://assets/textures/%s_n.jpg" % name)
		var sum := Vector3.ZERO
		var samples: int = 0
		for y in range(4, SIZE, 32):
			for x in range(4, SIZE, 32):
				var px: Color = c.get_pixel(x, y)
				sum += Vector3(px.r, px.g, px.b)
				samples += 1
		sum /= float(samples)
		avg.set_pixel(i, 0, Color(sum.x, sum.y, sum.z, 1.0))
		# roughness rides in the alpha channel of the colour map
		var data: PackedByteArray = c.get_data()
		var rd: PackedByteArray = r.get_data()
		for k in range(3, data.size(), 4):
			data[k] = rd[k - 3]
		var packed: Image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
		packed.generate_mipmaps()
		cs.append(packed)
		n.generate_mipmaps()
		ns.append(n)
	var ct := Texture2DArray.new()
	ct.create_from_images(cs)
	var nt := Texture2DArray.new()
	nt.create_from_images(ns)
	RenderingServer.global_shader_parameter_set("gfx_tex_c", ct)
	RenderingServer.global_shader_parameter_set("gfx_tex_n", nt)
	RenderingServer.global_shader_parameter_set("gfx_tex_avg", ImageTexture.create_from_image(avg))
