class_name RotateHint
extends Control
## A touch screen held upright (higher than wide): a full-screen note "please rotate your device" covers the game, which is made for
## landscape. Nothing of the game can be seen or touched until the screen is turned.

## The picture: a phone upright, an arrow, a phone lying down
class Icon extends Control:
	const SCALE := 3.0                     # a portrait screen is 1600 virtual px wide: draw big so it reads on a phone
	func _init() -> void:
		custom_minimum_size = Vector2(340, 220) * SCALE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
		var ink := Color("#ffd400")
		var up := Rect2(Vector2(40, 40), Vector2(80, 140))
		var down := Rect2(Vector2(200, 80), Vector2(140, 80))
		for r in [up, down]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.08)
			sb.border_color = ink
			sb.set_border_width_all(5)
			sb.set_corner_radius_all(14)
			draw_style_box(sb, r as Rect2)
		draw_circle(Vector2(80, 164), 5.0, ink)
		draw_circle(Vector2(324, 120), 5.0, ink)
		draw_arc(Vector2(170, 100), 62.0, deg_to_rad(215.0), deg_to_rad(325.0), 24, ink, 5.0, true)
		var tip := Vector2(170, 100) + Vector2(62.0, 0.0).rotated(deg_to_rad(325.0))
		draw_colored_polygon(PackedVector2Array([tip + Vector2(14, -2), tip + Vector2(-8, -14), tip + Vector2(-10, 10)]), ink)

var _label: Label
var _text_lang: String = ""

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	visible = false
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#2b3a55")
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 60)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var icon := Icon.new()
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	_label = UITheme.label("", 96, Color("#ffd400"), true, 22)
	_label.add_theme_font_override("font", ComicText.comic_font())
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(1300, 0)
	v.add_child(_label)

func _process(_delta: float) -> void:
	var vs: Vector2 = get_viewport_rect().size
	var on: bool = TouchMode.on and vs.y > vs.x
	if on != visible:
		visible = on
	if on and _text_lang != I18n.get_lang():
		_text_lang = I18n.get_lang()
		_label.text = I18n.t("hint.rotate")
