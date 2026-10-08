class_name TouchPad
extends VBoxContainer
## Touch buttons for what the keyboard does in a turn (turn, elevation, to enemy / marker, driving, pause). Each button presses the
## key it stands for (`TouchMode.key`), so the game logic stays the same; turn / elevation / driving repeat while held.

## One button: an arrow (or none) above a short caption
class PadButton extends Button:
	var arrow: Vector2 = Vector2.ZERO
	var caption: String = ""
	var code: Key = KEY_NONE
	var hold: bool = false
	var _down_at: int = 0
	func _init() -> void:
		custom_minimum_size = Vector2(76, 58)
		focus_mode = Control.FOCUS_NONE
		theme_type_variation = "ParchButton"
		Glass.button(self)
		button_down.connect(func() -> void:
			_down_at = Time.get_ticks_msec()
			TouchMode.key(code, true)
			if not hold:
				TouchMode.key(code, false))
		button_up.connect(func() -> void:
			if hold:
				# a short tap must still move one step: the aim loops look at held keys 30 times a second
				var left: float = 0.15 - float(Time.get_ticks_msec() - _down_at) * 0.001
				if left > 0.0 and is_inside_tree():
					await get_tree().create_timer(left).timeout
				TouchMode.key(code, false))
	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and hold:
			TouchMode.key(code, false)           # never leave a key stuck down
	func _draw() -> void:
		var f: Font = UITheme.font_bold()
		var ink := Color("#3b2a1a")
		var cx: float = size.x * 0.5
		var ty: float = size.y * 0.36 if arrow != Vector2.ZERO else size.y * 0.5 - 2.0
		if arrow != Vector2.ZERO:
			var d: Vector2 = arrow.normalized()
			var n := Vector2(-d.y, d.x)
			var c := Vector2(cx, ty)
			draw_colored_polygon(PackedVector2Array([c + d * 11.0, c - d * 8.0 + n * 11.0, c - d * 8.0 - n * 11.0]), ink)
		var fs: int = 13
		var tw: float = f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y: float = size.y - 10.0 if arrow != Vector2.ZERO else size.y * 0.5 + 5.0
		draw_string(f, Vector2((size.x - tw) * 0.5, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

var _mode: String = ""
var _rows: Dictionary = {}          # mode -> Control

func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_rows["aim"] = _row([
		_btn(KEY_Q, Vector2(-1, 0), "hint.turn", true), _btn(KEY_E, Vector2(1, 0), "hint.turn", true),
		_btn(KEY_UP, Vector2(0, -1), "hint.elevation", true), _btn(KEY_DOWN, Vector2(0, 1), "hint.elevation", true),
		_btn(KEY_R, Vector2.ZERO, "hint.enemy"), _btn(KEY_X, Vector2.ZERO, "hint.marker_key"), _btn(KEY_ESCAPE, Vector2.ZERO, "hint.pause")])
	_rows["relocate"] = _row([
		_btn(KEY_A, Vector2(-1, 0), "hint.steer", true), _btn(KEY_D, Vector2(1, 0), "hint.steer", true),
		_btn(KEY_W, Vector2(0, -1), "hint.drive", true), _btn(KEY_S, Vector2(0, 1), "hint.drive", true),
		_btn(KEY_SPACE, Vector2.ZERO, "hint.t_done"), _btn(KEY_ESCAPE, Vector2.ZERO, "hint.pause")])
	_rows["wall"] = _row([
		_btn(KEY_Q, Vector2(-1, 0), "hint.turn", true), _btn(KEY_E, Vector2(1, 0), "hint.turn", true),
		_btn(KEY_ESCAPE, Vector2.ZERO, "hint.pause")])

func _btn(code: Key, arrow: Vector2, text_key: String, hold: bool = false) -> PadButton:
	var b := PadButton.new()
	b.code = code
	b.arrow = arrow
	b.hold = hold
	b.set_meta("text_key", text_key)
	return b

func _row(buttons: Array) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.visible = false
	for b in buttons:
		h.add_child(b as Node)
	add_child(h)
	return h

## "aim" | "relocate" | "wall" | "" (nothing shown)
func set_mode(mode: String) -> void:
	if mode == _mode:
		return
	_mode = mode
	visible = mode != ""
	for k in _rows:
		(_rows[k] as Control).visible = (k == mode)
	refresh_texts()

func refresh_texts() -> void:
	for k in _rows:
		for b in (_rows[k] as Control).get_children():
			var pb: PadButton = b as PadButton
			pb.caption = I18n.t(str(pb.get_meta("text_key")))
			pb.queue_redraw()
