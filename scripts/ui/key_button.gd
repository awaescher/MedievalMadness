class_name KeyButton
extends Button
## A parchment button whose key is shown as a key cap chip (same look as the hint strip): [F] Fast-forward

var key_text: String = ""
var label_text: String = ""

func _init() -> void:
	theme_type_variation = "ParchButton"
	custom_minimum_size = Vector2(0, 32)
	focus_mode = Control.FOCUS_NONE

func set_content(key: String, label: String) -> void:
	key_text = key
	label_text = label
	queue_redraw()

func _draw() -> void:
	var f: Font = UITheme.font_bold()
	var kw: float = maxf(f.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0, 22.0)
	var lw: float = f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var total: float = kw + 8.0 + lw
	var x: float = (size.x - total) * 0.5
	var cy: float = size.y * 0.5
	var cap := StyleBoxFlat.new()
	cap.bg_color = Color("#3b2a1a")
	cap.set_corner_radius_all(6)
	draw_style_box(cap, Rect2(Vector2(x, cy - 10.0), Vector2(kw, 20.0)))
	var tw: float = f.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(f, Vector2(x + (kw - tw) * 0.5, cy + 4.5), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f4e4bc"))
	draw_string(f, Vector2(x + kw + 8.0, cy + 5.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#3b2a1a"))
