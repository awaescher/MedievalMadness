class_name ComicText
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Floating comic words ("KRAWUMM!") as pooled Label3D billboards (spec 12.4 / 15.2):
## max 3 alive, bounce-in, float up + fade in 1.2 s, random tilt and color.

const COLORS: Array[String] = ["#ffd400", "#ff5b2e", "#ffffff", "#7cf0ff"]
const MAX_ALIVE := 3

class Word extends RefCounted:
	var label: Label3D
	var t: float = 0.0
	var dur: float = 1.2
	var tilt: float = 0.0
	var base: Vector3 = Vector3.ZERO
	var active: bool = false
	var size_mult: float = 1.0

static var inst: ComicText
static var _last_spawn_ms: int = 0
static var _font: SystemFont

var _pool: Array[Word] = []
var rng := Rng.new(99)

func _enter_tree() -> void:
	inst = self

func _exit_tree() -> void:
	if inst == self:
		inst = null

static func comic_font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Impact", "Arial Black", "Haettenschweiler", "DejaVu Sans Bold", "Arial"])
		_font.font_weight = 900
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font

func _ready() -> void:
	for i in MAX_ALIVE:
		var w := Word.new()
		var l := Label3D.new()
		l.font = comic_font()
		l.font_size = 110
		l.outline_size = 28
		l.outline_modulate = Color(0.05, 0.03, 0.08)
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.00075
		l.shaded = false
		l.double_sided = true
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		add_child(l)
		w.label = l
		_pool.append(w)

## Spawn a random word of a comic category (key in comic.<kind>)
static func spawn_kind(kind: String, pos: Vector3, size_mult: float = 1.0) -> void:
	if inst == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_spawn_ms < 250:
		return
	var lines: Array = I18n.tr_list("comic." + kind)
	if lines.is_empty():
		return
	inst.spawn(str(lines[inst.rng.range_i(0, lines.size() - 1)]), pos, size_mult)

static func spawn_text(text: String, pos: Vector3, size_mult: float = 1.0) -> void:
	if inst != null:
		inst.spawn(text, pos, size_mult)

func spawn(text: String, pos: Vector3, size_mult: float = 1.0) -> void:
	var w: Word = null
	for c in _pool:
		if not c.active:
			w = c
			break
	if w == null:
		# steal the oldest
		var oldest: Word = _pool[0]
		for c2 in _pool:
			if c2.t > oldest.t:
				oldest = c2
		w = oldest
	_last_spawn_ms = Time.get_ticks_msec()
	w.active = true
	w.t = 0.0
	w.dur = 1.2
	w.tilt = deg_to_rad(rng.range_f(-12.0, 12.0))
	w.base = pos
	w.size_mult = size_mult
	w.label.text = text
	w.label.modulate = Color.html(COLORS[rng.range_i(0, COLORS.size() - 1)])
	w.label.visible = true
	w.label.global_position = pos
	w.label.scale = Vector3.ONE * 0.01

func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	for w in _pool:
		if not w.active:
			continue
		w.t += delta
		var k: float = w.t / w.dur
		if k >= 1.0:
			w.active = false
			w.label.visible = false
			continue
		var s: float = Util.ease_out_back(minf(k * 4.0, 1.0)) * w.size_mult
		w.label.scale = Vector3.ONE * s
		var p: Vector3 = w.base + Vector3.UP * (k * 3.0)
		w.label.global_position = p
		var a: float = 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0)
		var col: Color = w.label.modulate
		col.a = a
		w.label.modulate = col
		var oc: Color = w.label.outline_modulate
		oc.a = a
		w.label.outline_modulate = oc
		# face the camera, then tilt
		var to_cam: Vector3 = (cp - p).normalized()
		var up: Vector3 = Vector3.UP if absf(to_cam.y) < 0.98 else Vector3.FORWARD
		# label front faces +Z: build a basis whose +Z points at the camera
		var bz: Vector3 = to_cam
		var bx: Vector3 = up.cross(bz).normalized()
		var by: Vector3 = bz.cross(bx).normalized()
		w.label.global_transform = Transform3D(Basis(bx, by, bz) * Basis(Vector3(0, 0, 1), w.tilt), p)
