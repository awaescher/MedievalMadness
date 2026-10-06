class_name UITheme
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Chunky rounded parchment UI theme built once in code (spec 16.1): parchment panels, bright buttons,
## hover wobble via Tween. Fonts are SystemFonts with fallback chains (no bundled fonts).

const PARCH := Color("#f4e4bc")
const PARCH_DARK := Color("#e6d0a0")
const INK := Color("#3b2a1a")
const RED := Color("#e74c3c")
const YELLOW := Color("#f1c40f")
const GREEN := Color("#2ecc71")
const BLUE := Color("#3498db")

static var _theme: Theme
static var _font: SystemFont
static var _font_bold: SystemFont

static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Trebuchet MS", "Comic Sans MS", "Verdana", "DejaVu Sans", "Arial"])
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font

static func font_bold() -> SystemFont:
	if _font_bold == null:
		_font_bold = SystemFont.new()
		_font_bold.font_names = PackedStringArray(["Trebuchet MS", "Comic Sans MS", "Verdana", "DejaVu Sans", "Arial"])
		_font_bold.font_weight = 800
		_font_bold.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font_bold

static func box(bg: Color, border: Color = INK, bw: int = 3, radius: int = 14, shadow: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Modern, quiet surface: a translucent fill, a hair-line light edge, no heavy frame (buttons, inputs, popups)
static func soft(fill: Color, edge: Color = Color(1, 1, 1, 0.38), radius: int = 12, edge_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(edge_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb

## Button variation: only a light tint of `col` over the glass behind it (the tint amount `a` stays small), dark text
static func _btn(theme: Theme, type: String, base: String, col: Color, txt: Color, a: float = 0.30) -> void:
	if type != base:
		theme.add_type(type)
		theme.set_type_variation(type, base)
	theme.set_stylebox("normal", type, soft(Color(col.r, col.g, col.b, a)))
	theme.set_stylebox("hover", type, soft(Color(col.r, col.g, col.b, minf(a + 0.16, 0.9)), Color(1, 1, 1, 0.6)))
	theme.set_stylebox("pressed", type, soft(Color(col.r, col.g, col.b, maxf(a - 0.1, 0.12)), Color(1, 1, 1, 0.25)))
	theme.set_stylebox("disabled", type, soft(Color(0.5, 0.5, 0.5, 0.14), Color(1, 1, 1, 0.15)))
	theme.set_stylebox("focus", type, soft(Color(0, 0, 0, 0), Color(1, 1, 1, 0.7), 12, 2))
	theme.set_color("font_color", type, txt)
	theme.set_color("font_hover_color", type, txt)
	theme.set_color("font_pressed_color", type, txt)
	theme.set_color("font_disabled_color", type, Color(0.3, 0.25, 0.2, 0.5))
	theme.set_color("font_outline_color", type, Color(0.1, 0.05, 0.02))
	theme.set_constant("outline_size", type, 0)

static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	# tooltips: parchment panel with ONE border (custom tooltip content has no frame of its own)
	var tip := box(Color(0.97, 0.94, 0.86, 0.97), Color(0, 0, 0, 0.0), 0, 10, 4)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.content_margin_top = 6
	tip.content_margin_bottom = 7
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 13)
	# labels
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color(1, 1, 1, 0.0))
	# panels
	# (menus and dialogs put the frosted glass on their panels, see Glass.dialog; this is the plain fallback)
	t.set_stylebox("panel", "PanelContainer", box(Color(0.97, 0.94, 0.86, 0.80), Color(1, 1, 1, 0.0), 0, 16, 8))
	t.set_stylebox("panel", "Panel", box(Color(0.97, 0.94, 0.86, 0.80), Color(1, 1, 1, 0.0), 0, 16, 8))
	# buttons (default bright red variants, with title/gold variations)
	_btn(t, "Button", "Button", Color("#e9c46a"), INK, 0.34)
	_btn(t, "RedButton", "Button", Color("#d9605a"), Color("#4a1410"), 0.40)
	_btn(t, "GreenButton", "Button", Color("#4fa65f"), Color("#0f2f17"), 0.62)
	_btn(t, "GoldButton", "Button", Color("#dcae3c"), INK, 0.62)
	_btn(t, "ParchButton", "Button", Color("#ffffff"), INK, 0.32)
	t.set_font("font", "RedButton", font_bold())
	t.set_font("font", "GreenButton", font_bold())
	# line edit / option button / check
	var le := soft(Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.55), 10)
	le.content_margin_top = 4
	le.content_margin_bottom = 4
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", soft(Color(1, 1, 1, 0.62), Color("#c9962a"), 10, 2))
	t.set_stylebox("read_only", "LineEdit", soft(Color(0.5, 0.5, 0.5, 0.16), Color(1, 1, 1, 0.2), 10))
	t.set_color("font_uneditable_color", "LineEdit", Color(0.3, 0.25, 0.2, 0.55))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.4, 0.3, 0.2, 0.6))
	var ob := soft(Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.55), 10)
	ob.content_margin_top = 4
	ob.content_margin_bottom = 4
	t.set_stylebox("normal", "OptionButton", ob)
	t.set_stylebox("hover", "OptionButton", soft(Color(1, 1, 1, 0.60), Color(1, 1, 1, 0.7), 10))
	t.set_stylebox("pressed", "OptionButton", soft(Color(1, 1, 1, 0.32), Color(1, 1, 1, 0.4), 10))
	t.set_stylebox("disabled", "OptionButton", soft(Color(0.5, 0.5, 0.5, 0.14), Color(1, 1, 1, 0.15), 10))
	t.set_stylebox("focus", "OptionButton", soft(Color(0, 0, 0, 0), Color("#c9962a"), 10, 2))
	t.set_color("font_color", "OptionButton", INK)
	t.set_color("font_hover_color", "OptionButton", INK)
	t.set_color("font_pressed_color", "OptionButton", INK)
	t.set_color("font_focus_color", "OptionButton", INK)
	t.set_color("font_disabled_color", "OptionButton", Color(0.3, 0.25, 0.2, 0.5))
	var pm := box(Color(0.98, 0.96, 0.90, 1.0), Color(1, 1, 1, 0.65), 1, 12, 10)
	pm.content_margin_left = 6
	pm.content_margin_right = 6
	pm.content_margin_top = 6
	pm.content_margin_bottom = 6
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", box(Color(0.91, 0.77, 0.42, 0.55), Color(0, 0, 0, 0), 0, 6, 0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", Color(0.5, 0.4, 0.3))
	t.set_stylebox("panel", "PopupPanel", pm)
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(1, 1, 1, 0.0 if st != "hover" else 0.25)
		flat.set_corner_radius_all(8)
		flat.content_margin_left = 0
		flat.content_margin_top = 4
		flat.content_margin_bottom = 4
		t.set_stylebox(st, "CheckButton", flat)
		t.set_stylebox(st, "CheckBox", flat)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_focus_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", INK)
	t.set_color("font_color", "CheckBox", INK)
	# sliders
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.23, 0.16, 0.10, 0.22)
	groove.set_corner_radius_all(6)
	groove.content_margin_top = 5
	groove.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#d9a441")
	fill.set_corner_radius_all(6)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# scroll
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t

## Attach a hover wobble (scale/rotation) to any Control, plus click/hover sounds
static func wobble(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	c.mouse_entered.connect(func() -> void:
		var tw: Tween = c.create_tween()
		tw.tween_property(c, "scale", Vector2(1.015, 1.015), 0.08)
		Sfx.play("ui_hover", Vector3.INF, 0.25, 0))
	c.mouse_exited.connect(func() -> void:
		var tw2: Tween = c.create_tween()
		tw2.tween_property(c, "scale", Vector2.ONE, 0.08))
	if c is BaseButton:
		(c as BaseButton).pressed.connect(func() -> void: Sfx.play("ui_click", Vector3.INF, 0.6, 0))

## A player colour that reads on dark and light text backgrounds: very dark colours (blue, black) are lifted a bit
static func name_color(c: Color) -> Color:
	var lum: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return c.lerp(Color.WHITE, clampf((0.55 - lum) * 1.1, 0.0, 0.5))

## BBCode: every player name in `text` written in that player's colour (names of the current match; `[` is escaped)
static func tint_names(text: String) -> String:
	var out: String = text.replace("[", "[lb]")
	var ps: Array = Game.players.duplicate()
	ps.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.name.length() > b.name.length())
	var tags: Array[String] = []
	for p in ps:
		var pl: PlayerData = p as PlayerData
		if pl.name.length() < 2:
			continue
		var plain: String = pl.name.replace("[", "[lb]")
		if not out.contains(plain):
			continue
		var token: String = "\u0001%d\u0002" % tags.size()
		tags.append("[color=#%s]%s[/color]" % [name_color(pl.color).to_html(false), plain])
		out = out.replace(plain, token)
	for k in tags.size():
		out = out.replace("\u0001%d\u0002" % k, tags[k])
	return out

## Label with BBCode (player names in colour). Same look as `label()`; `centered` wraps the text in [center].
static func rich_label(text: String, size: int = 17, color: Color = INK, bold: bool = false, outline: int = 0, centered: bool = false) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size)
	l.add_theme_font_override("normal_font", font_bold() if bold else font())
	l.add_theme_font_override("bold_font", font_bold())
	l.add_theme_color_override("default_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	set_rich(l, text, centered)
	return l

static func set_rich(l: RichTextLabel, text: String, centered: bool = false) -> void:
	var t: String = tint_names(text)
	l.text = "[center]%s[/center]" % t if centered else t

static func label(text: String, size: int = 17, color: Color = INK, bold: bool = false, outline: int = 0, outline_col: Color = Color(0.1, 0.05, 0.02)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold())
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_col)
	return l

## One size for the buttons of every dialog, a smaller one for buttons inside option rows; only the two buttons that start
## a game (menu) are bigger.
const DIALOG_H := 44.0
const DIALOG_FONT := 18
const OPTION_H := 32.0
const OPTION_FONT := 15

static func dialog_button(text: String, variation: String = "ParchButton", width: float = 0.0) -> Button:
	return button(text, variation, Vector2(width, DIALOG_H), DIALOG_FONT)

static func option_button(text: String, variation: String = "ParchButton", width: float = 100.0) -> Button:
	return button(text, variation, Vector2(width, OPTION_H), OPTION_FONT)

static func button(text: String, variation: String = "", min_size: Vector2 = Vector2(0, 0), font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	wobble(b)
	return b

static func hspacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c

static func vspacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
