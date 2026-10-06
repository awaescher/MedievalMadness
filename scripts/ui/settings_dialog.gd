class_name SettingsDialog
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## The technical settings in one tidy dialog: Graphics, Display, Sound and Language. They belong to this machine and never to a match;
## the match rules (timer, catapults, wind ...) live in the menu next to the players. Used by the main menu and the pause menu.

signal closed

const ROW_W := 230.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.build()
	Glass.watch(self)
	_build()
	Events.language_changed.connect(_build)

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.30)
	add_child(dim)
	var panel := PanelContainer.new()
	Glass.dialog(panel, 22, Vector2(26, 20))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	# header
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title: Label = UITheme.label(I18n.t("settings.title"), 26, UITheme.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := CloseButton.new()
	close.pressed.connect(_close)
	head.add_child(close)
	var sub: Label = UITheme.label(I18n.t("settings.sub"), 14, Color("#6b4a2a"))
	vb.add_child(sub)
	# two columns: what the picture looks like | how the game is shown and heard
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	vb.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	# ---- graphics
	left.add_child(_section(I18n.t("settings.graphics")))
	var ql := OptionButton.new()
	for q in Settings.QUALITY_TIERS:
		ql.add_item(I18n.t("menu.q_" + q))
	ql.select(Settings.QUALITY_TIERS.find(Settings.quality))
	ql.item_selected.connect(func(idx: int) -> void:
		Settings.quality = Settings.QUALITY_TIERS[idx]
		Events.quality_changed.emit(Settings.quality))
	left.add_child(_row(I18n.t("menu.quality"), ql))
	var lt := OptionButton.new()
	for lm in Settings.LIGHTING_MODES:
		lt.add_item(I18n.t("menu.l_" + lm))
	lt.select(Settings.LIGHTING_MODES.find(Settings.lighting))
	lt.item_selected.connect(func(idx: int) -> void:
		Settings.lighting = Settings.LIGHTING_MODES[idx]
		Events.quality_changed.emit(Settings.quality))
	left.add_child(_row(I18n.t("menu.lighting"), lt))
	left.add_child(_row(I18n.t("menu.gfx_style"), GfxStyle.make_style_button()))
	left.add_child(_check(I18n.t("menu.autoquality"), Settings.auto_quality, func(v: bool) -> void: Settings.auto_quality = v))
	left.add_child(_note(I18n.t("settings.graphics_note")))
	# ---- display
	right.add_child(_section(I18n.t("settings.display")))
	right.add_child(_check(I18n.t("menu.fullscreen"), Settings.fullscreen, func(v: bool) -> void: Settings.set_fullscreen(v)))
	right.add_child(_check(I18n.t("menu.vsync"), Settings.vsync, func(v: bool) -> void:
		Settings.vsync = v
		Settings.apply_display()))
	right.add_child(_check(I18n.t("settings.glass"), Settings.glass, func(v: bool) -> void:
		Settings.glass = v
		Glass.reset()
		Events.quality_changed.emit(Settings.quality)
		Settings.save_settings()))
	right.add_child(_check(I18n.t("menu.shake"), Settings.shake, func(v: bool) -> void: Settings.shake = v))
	# ---- sound
	right.add_child(_section(I18n.t("settings.sound")))
	var vs := HSlider.new()
	vs.min_value = 0.0
	vs.max_value = 1.0
	vs.step = 0.05
	vs.value = Settings.volume
	vs.value_changed.connect(func(x: float) -> void:
		Settings.volume = x
		Settings.apply_volume())
	vs.drag_ended.connect(func(_ch: bool) -> void: Sfx.play("ui_click", Vector3.INF, 0.7, 0))
	right.add_child(_row(I18n.t("menu.volume"), vs))
	var ms := HSlider.new()
	ms.min_value = 0.0
	ms.max_value = 1.0
	ms.step = 0.05
	ms.value = Settings.music_volume
	ms.value_changed.connect(func(x: float) -> void:
		Settings.music_volume = x
		Music.apply_volume())
	right.add_child(_row(I18n.t("settings.music"), ms))
	# ---- language
	right.add_child(_section(I18n.t("menu.language")))
	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 10)
	for lg in ["de", "en"]:
		var fb := Menu.FlagButton.new(lg)
		fb.tile = true
		fb.custom_minimum_size = Vector2(60, 42)
		fb.selected = I18n.get_lang() == lg
		fb.tooltip_text = "Deutsch" if lg == "de" else "English"
		var code: String = lg
		fb.pressed.connect(func() -> void:
			I18n.set_lang(code)
			Settings.save_settings())
		flags.add_child(fb)
	right.add_child(flags)
	# ---- footer
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(foot)
	var reset: Button = UITheme.dialog_button(I18n.t("settings.reset"), "ParchButton", 190.0)
	reset.pressed.connect(func() -> void:
		Settings.reset_display_options()
		Events.quality_changed.emit(Settings.quality)
		Sfx.play("ui_click", Vector3.INF, 0.7, 0)
		_build())
	foot.add_child(reset)
	var done: Button = UITheme.dialog_button(I18n.t("menu.ok"), "GreenButton", 150.0)
	done.pressed.connect(_close)
	foot.add_child(done)

func _close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		_close()

## Section heading: small, muted, spaced capitals with a hair line under it
func _section(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var l: Label = UITheme.label(text.to_upper(), 13, Color("#7a5a36"), true)
	v.add_child(l)
	var line := ColorRect.new()
	line.color = Color(0.23, 0.16, 0.10, 0.18)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	return v

func _row(text: String, ctl: Control) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var l: Label = UITheme.label(text, 17, UITheme.INK, false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	if ctl is OptionButton:
		(ctl as OptionButton).fit_to_longest_item = false
		(ctl as OptionButton).clip_text = true
	ctl.custom_minimum_size.x = ROW_W
	ctl.size_flags_horizontal = Control.SIZE_SHRINK_END
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ctl)
	return hb

func _check(text: String, value: bool, cb: Callable) -> Control:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 17)
	c.toggled.connect(func(v: bool) -> void:
		cb.call(v)
		Sfx.play("ui_click", Vector3.INF, 0.5, 0))
	return c

func _note(text: String) -> Control:
	var l: Label = UITheme.label(text, 13, Color("#6b4a2a"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(ROW_W + 150.0, 0)
	return l
