class_name KeyButton
extends Button
## A glass button with a key cap on the left and the label next to it; keys and labels of stacked buttons line up
## (fixed key column). With `hold_time` > 0 the button has to be held: a progress fill runs from left to right inside it
## and `held` fires when it is full, so it cannot be triggered by accident.

signal held

const KEY_COL := 38.0

var key_text: String = ""
var label_text: String = ""
var hold_time: float = 0.0
var progress: float = 0.0           # 0..1, also driven from outside (the key is held)
var _mouse_hold: bool = false
var active: bool = false:          # switched on (fast-forward): a soft light fill, never a colour change
	set(v):
		active = v
		queue_redraw()

func _init() -> void:
	theme_type_variation = "ParchButton"
	custom_minimum_size = Vector2(0, 26)
	focus_mode = Control.FOCUS_NONE

func set_content(key: String, label: String) -> void:
	key_text = key
	label_text = label
	queue_redraw()

func set_progress(v: float) -> void:
	if absf(v - progress) > 0.001:
		progress = v
		queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if hold_time <= 0.0:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_mouse_hold = (ev as InputEventMouseButton).pressed
		accept_event()                  # a plain click never triggers `pressed`: only a full hold does
		if not _mouse_hold:
			set_progress(0.0)

func _process(delta: float) -> void:
	if hold_time > 0.0 and _mouse_hold:
		set_progress(minf(progress + delta / hold_time, 1.0))
		if progress >= 1.0:
			_mouse_hold = false
			set_progress(0.0)
			held.emit()

func _draw() -> void:
	var f: Font = UITheme.font_bold()
	if active:
		var lit := StyleBoxFlat.new()
		lit.bg_color = Color(1, 1, 1, 0.38)
		lit.set_corner_radius_all(12)
		draw_style_box(lit, Rect2(Vector2.ZERO, size))
	if progress > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.85, 0.45, 0.25, 0.55)
		fill.set_corner_radius_all(12)
		var w: float = maxf(size.x * progress, 24.0)
		draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(w, size.y)))
	var cy: float = size.y * 0.5
	var kw: float = minf(maxf(f.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0, 20.0), KEY_COL - 4.0)
	var x: float = 10.0
	var cap := StyleBoxFlat.new()
	cap.bg_color = Color("#3b2a1a")
	cap.set_corner_radius_all(6)
	draw_style_box(cap, Rect2(Vector2(x, cy - 8.5), Vector2(kw, 17.0)))
	var tw: float = f.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(f, Vector2(x + (kw - tw) * 0.5, cy + 4.0), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f4e4bc"))
	draw_string(f, Vector2(x + KEY_COL, cy + 4.5), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#3b2a1a"))
