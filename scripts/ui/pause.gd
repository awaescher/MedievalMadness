class_name PauseMenu
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Pause menu (Esc): Resume, Restart (same seed), Quit to menu, Options.

signal resume
signal restart
signal quit_to_menu

var panel: PanelContainer
var _options: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.build()
	visible = false
	Events.language_changed.connect(func() -> void:
		if visible:
			_build())

func open() -> void:
	_options = false
	visible = true
	_build()

func close() -> void:
	visible = false

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.03, 0.08, 0.6)
	add_child(dim)
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t: Label = UITheme.label(I18n.t("pause.title"), 34, UITheme.RED, true)
	t.add_theme_font_override("font", ComicText.comic_font())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if not _options:
		var b1: Button = UITheme.dialog_button(I18n.t("pause.resume"), "GreenButton")
		b1.pressed.connect(func() -> void: resume.emit())
		v.add_child(b1)
		var b2: Button = UITheme.dialog_button(I18n.t("pause.options"), "GoldButton")
		b2.pressed.connect(func() -> void:
			_options = true
			_build())
		v.add_child(b2)
		var b3: Button = UITheme.dialog_button(I18n.t("pause.restart"), "ParchButton")
		b3.pressed.connect(func() -> void: restart.emit())
		b3.visible = not Net.active
		v.add_child(b3)
		var b4: Button = UITheme.dialog_button(I18n.t("pause.quit"), "RedButton")
		b4.pressed.connect(func() -> void: quit_to_menu.emit())
		v.add_child(b4)
	else:
		var vs := HSlider.new()
		vs.min_value = 0.0
		vs.max_value = 1.0
		vs.step = 0.05
		vs.value = Settings.volume
		vs.custom_minimum_size = Vector2(0, 26)
		vs.value_changed.connect(func(x: float) -> void:
			Settings.volume = x
			Settings.apply_volume())
		v.add_child(UITheme.label(I18n.t("menu.volume"), 17, UITheme.INK, true))
		v.add_child(vs)
		var ql := OptionButton.new()
		for q in Settings.QUALITY_TIERS:
			ql.add_item(I18n.t("menu.q_" + q))
		ql.select(Settings.QUALITY_TIERS.find(Settings.quality))
		ql.item_selected.connect(func(idx: int) -> void:
			Settings.quality = Settings.QUALITY_TIERS[idx]
			Events.quality_changed.emit(Settings.quality))
		v.add_child(UITheme.label(I18n.t("menu.quality"), 17, UITheme.INK, true))
		v.add_child(ql)
		var lt := OptionButton.new()
		for lm in Settings.LIGHTING_MODES:
			lt.add_item(I18n.t("menu.l_" + lm))
		lt.select(Settings.LIGHTING_MODES.find(Settings.lighting))
		lt.item_selected.connect(func(idx: int) -> void:
			Settings.lighting = Settings.LIGHTING_MODES[idx]
			Events.quality_changed.emit(Settings.quality))
		v.add_child(UITheme.label(I18n.t("menu.lighting"), 17, UITheme.INK, true))
		v.add_child(lt)
		var gst: OptionButton = GfxStyle.make_style_button()
		v.add_child(UITheme.label(I18n.t("menu.gfx_style"), 17, UITheme.INK, true))
		v.add_child(gst)
		var shake := CheckButton.new()
		shake.text = I18n.t("menu.shake")
		shake.button_pressed = Settings.shake
		shake.toggled.connect(func(on: bool) -> void: Settings.shake = on)
		v.add_child(shake)
		var fs := CheckButton.new()
		fs.text = I18n.t("menu.fullscreen")
		fs.button_pressed = Settings.fullscreen
		fs.toggled.connect(func(on: bool) -> void: Settings.set_fullscreen(on))
		v.add_child(fs)
		var lang_row := HBoxContainer.new()
		lang_row.add_theme_constant_override("separation", 8)
		lang_row.add_child(UITheme.label(I18n.t("menu.language"), 17, UITheme.INK, true))
		for lg in ["de", "en"]:
			var fb := Menu.FlagButton.new(lg)
			fb.selected = I18n.get_lang() == lg
			var code: String = lg
			fb.pressed.connect(func() -> void: I18n.set_lang(code))
			lang_row.add_child(fb)
		v.add_child(lang_row)
		var back: Button = UITheme.dialog_button(I18n.t("pause.back"), "ParchButton")
		back.pressed.connect(func() -> void:
			Settings.save_settings()
			_options = false
			_build())
		v.add_child(back)
