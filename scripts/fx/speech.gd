class_name Speech
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Speech bubbles as pooled Label3D (spec 12.8 / 15.2): max 6 alive, 2.2 s, at most one per speaker.

const MAX_ALIVE := 6
const LIFETIME := 2.2

class Bubble extends RefCounted:
	var label: Label3D
	var t: float = 0.0
	var life: float = LIFETIME
	var follow: Node3D = null
	var speaker: Object = null
	var pos: Vector3 = Vector3.ZERO
	var offset: float = 2.4
	var active: bool = false

static var inst: Speech
static var _font: SystemFont

var _pool: Array[Bubble] = []

func _enter_tree() -> void:
	inst = self

func _exit_tree() -> void:
	if inst == self:
		inst = null

static func ui_font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Trebuchet MS", "Comic Sans MS", "Verdana", "DejaVu Sans", "Arial"])
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font

func _ready() -> void:
	for i in MAX_ALIVE:
		var b := Bubble.new()
		var l := Label3D.new()
		l.font = ui_font()
		l.font_size = 34
		l.outline_size = 9
		l.modulate = Color(1, 1, 1)
		l.outline_modulate = Color(0.1, 0.06, 0.12)
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0008
		l.shaded = false
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.render_priority = 8
		l.outline_render_priority = 7
		l.width = 420.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.visible = false
		add_child(l)
		b.label = l
		_pool.append(b)

## Show a bubble above `follow` (or a world position). `speaker` prevents duplicates.
static func say(text: String, follow: Node3D, speaker: Object = null, life: float = LIFETIME, offset: float = 2.4, pos: Vector3 = Vector3.ZERO, color: Color = Color.WHITE) -> void:
	if inst != null:
		inst._say(text, follow, speaker, life, offset, pos, color)

func _say(text: String, follow: Node3D, speaker: Object, life: float, offset: float, pos: Vector3, color: Color) -> void:
	var b: Bubble = null
	if speaker != null:
		for c in _pool:
			if c.active and c.speaker == speaker:
				b = c
				break
	if b == null:
		for c2 in _pool:
			if not c2.active:
				b = c2
				break
	if b == null:
		var oldest: Bubble = _pool[0]
		for c3 in _pool:
			if c3.t > oldest.t:
				oldest = c3
		b = oldest
	b.active = true
	b.t = 0.0
	b.life = life
	b.follow = follow
	b.speaker = speaker
	b.pos = pos
	b.offset = offset
	b.label.text = text
	b.label.modulate = color
	b.label.visible = true

## Per category: the least number of seconds between two lines (bubbles are fun, so they stay rare)
const COOLDOWNS := {"speech.idle": 9.0, "speech.panic": 2.5, "speech.hit": 1.5, "speech.fire": 4.0, "speech.landed": 3.0, "speech.bump": 2.5, "speech.bucket": 8.0}
static var _last_said: Dictionary = {}

static func say_random(key: String, follow: Node3D, speaker: Object = null, rng: Rng = null, offset: float = 2.4) -> void:
	var lines: Array = I18n.tr_list(key)
	if lines.is_empty():
		return
	# the line is drawn BEFORE any throttling so the RNG stream is the same on every machine (online play)
	var r: Rng = rng if rng != null else Game.rng_battle
	var text: String = str(lines[r.range_i(0, lines.size() - 1)])
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - float(_last_said.get(key, -999.0)) < float(COOLDOWNS.get(key, 3.0)):
		return
	if alive_count() >= (2 if key == "speech.idle" else 4):
		return
	_last_said[key] = now
	say(text, follow, speaker, LIFETIME, offset)

static func alive_count() -> int:
	if inst == null:
		return 0
	var n: int = 0
	for b in inst._pool:
		if b.active:
			n += 1
	return n

func _process(delta: float) -> void:
	for b in _pool:
		if not b.active:
			continue
		b.t += delta
		if b.t >= b.life or (b.follow != null and not is_instance_valid(b.follow)):
			b.active = false
			b.label.visible = false
			continue
		var p: Vector3 = b.pos
		if b.follow != null:
			p = b.follow.global_position
		b.label.global_position = p + Vector3.UP * (b.offset + minf(b.t, 0.4) * 0.5)
		var a: float = 1.0 - clampf((b.t - (b.life - 0.4)) / 0.4, 0.0, 1.0)
		var c: Color = b.label.modulate
		c.a = a
		b.label.modulate = c
		var oc: Color = b.label.outline_modulate
		oc.a = a
		b.label.outline_modulate = oc
		b.label.scale = Vector3.ONE * Util.ease_out_back(minf(b.t * 5.0, 1.0))
