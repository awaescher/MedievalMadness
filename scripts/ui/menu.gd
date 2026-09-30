class_name Menu
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Main menu (spec 2.1): language, players (name / color / type), seed, options, START BATTLE.

signal start_requested

const SEED_WORDS: Array[String] = ["cheese", "goose", "pitchfork", "turnip", "moat", "dragon", "haystack", "gravy", "kaboom", "ale", "gauntlet", "pumpernickel", "trebuchet", "wobble", "porridge", "yeet"]
const TYPES: Array[String] = ["human", "peasant", "squire", "knight", "king"]

var rows: Array[Dictionary] = []
var count: int = 4
var seed_edit: LineEdit
var count_label: Label
var map_label: Label
var players_box: VBoxContainer
var start_btn: Button
var status: Label
var title: Label
var _content: Control
var _sound_ready: bool = false
var _rng := Rng.new(int(Time.get_ticks_msec()))
var _volume_slider: HSlider

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.build()
	_load_state()
	_build()
	Events.language_changed.connect(_on_lang_changed)
	Sfx.synth_progress.connect(_on_synth_progress)
	Sfx.synth_ready.connect(_on_synth_ready)
	if Sfx.is_ready:
		_on_synth_ready()

func _load_state() -> void:
	count = clampi(Settings.player_count, Cfg.MIN_PLAYERS, Cfg.MAX_PLAYERS)
	if Settings.seed_text == "":
		Settings.seed_text = _random_seed()
	var saved: Array = Settings.players
	rows.clear()
	var defaults: Array = Game.default_players(Cfg.MAX_PLAYERS, Settings.seed_text)
	for i in Cfg.MAX_PLAYERS:
		var d: Dictionary = (defaults[i] as Dictionary).duplicate()
		if i < saved.size() and saved[i] is Dictionary:
			var sd: Dictionary = saved[i] as Dictionary
			d["name"] = str(sd.get("name", d["name"]))
			d["color"] = int(sd.get("color", d["color"]))
			d["type"] = str(sd.get("type", d["type"]))
		rows.append(d)

func _random_seed() -> String:
	return "%s-%s-%d" % [SEED_WORDS[_rng.range_i(0, SEED_WORDS.size() - 1)], SEED_WORDS[_rng.range_i(0, SEED_WORDS.size() - 1)], _rng.range_i(10, 99)]

func _on_lang_changed() -> void:
	_collect()
	_build()
	_refresh_start()

func _on_synth_progress(p: float) -> void:
	if not _sound_ready and status != null:
		status.text = I18n.t("menu.loading_audio", {"p": int(p * 100.0)})

func _on_synth_ready() -> void:
	_sound_ready = true
	_refresh_start()

func _refresh_start() -> void:
	if start_btn != null:
		start_btn.disabled = not _sound_ready
	if status != null:
		status.text = I18n.t("menu.ready") if _sound_ready else status.text

# ------------------------------------------------------------------ layout
func _build() -> void:
	if _content != null:
		_content.queue_free()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	# dim gradient at the sides for readability
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 30
	root.offset_right = -30
	root.offset_top = 14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 8)
	_content.add_child(root)
	# title
	title = UITheme.label(I18n.t("menu.title"), 68, Color("#ffd400"), true, 22)
	title.add_theme_font_override("font", ComicText.comic_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var sub: Label = UITheme.label(I18n.t("menu.subtitle"), 20, Color("#ffffff"), true, 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	# two columns
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 22)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(cols)
	cols.add_child(_players_panel())
	cols.add_child(_options_panel())
	# bottom bar
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 20)
	root.add_child(bottom)
	start_btn = UITheme.button(I18n.t("menu.start"), "RedButton", Vector2(380, 64), 30)
	start_btn.pressed.connect(_on_start)
	bottom.add_child(start_btn)
	var quit_btn: Button = UITheme.button(I18n.t("menu.quit"), "ParchButton", Vector2(140, 64), 20)
	quit_btn.pressed.connect(func() -> void: get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST); get_tree().quit())
	bottom.add_child(quit_btn)
	status = UITheme.label("", 15, Color.WHITE, false, 6)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status)
	var help: Label = UITheme.label(I18n.t("menu.help_line"), 15, Color.WHITE, false, 6)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(help)
	var cred: Label = UITheme.label(I18n.t("menu.credits") + "   -   v" + Cfg.game_version(), 13, Color(1, 1, 1, 0.8), false, 5)
	cred.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(cred)
	_refresh_start()

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	return p

func _players_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	# language row
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vb.add_child(lang_row)
	lang_row.add_child(UITheme.label(I18n.t("menu.language"), 18, UITheme.INK, true))
	var en: Button = UITheme.button("EN", "GoldButton" if I18n.get_lang() == "en" else "ParchButton", Vector2(56, 34), 16)
	en.pressed.connect(func() -> void: I18n.set_lang("en"); Settings.save_settings())
	lang_row.add_child(en)
	var de: Button = UITheme.button("DE", "GoldButton" if I18n.get_lang() == "de" else "ParchButton", Vector2(56, 34), 16)
	de.pressed.connect(func() -> void: I18n.set_lang("de"); Settings.save_settings())
	lang_row.add_child(de)
	lang_row.add_child(Control.new())
	(lang_row.get_child(lang_row.get_child_count() - 1) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rn: Button = UITheme.button(I18n.t("menu.random_names"), "ParchButton", Vector2(0, 34), 15)
	rn.pressed.connect(_randomize_names)
	lang_row.add_child(rn)
	# count
	var cnt_row := HBoxContainer.new()
	cnt_row.add_theme_constant_override("separation", 10)
	vb.add_child(cnt_row)
	count_label = UITheme.label("", 18, UITheme.INK, true)
	count_label.custom_minimum_size = Vector2(150, 0)
	cnt_row.add_child(count_label)
	var sl := HSlider.new()
	sl.min_value = Cfg.MIN_PLAYERS
	sl.max_value = Cfg.MAX_PLAYERS
	sl.step = 1
	sl.value = count
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(240, 26)
	sl.value_changed.connect(func(v: float) -> void:
		count = int(v)
		_update_count()
		Sfx.play("ui_hover", Vector3.INF, 0.4, 0))
	cnt_row.add_child(sl)
	# rows
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 6)
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(players_box)
	for i in Cfg.MAX_PLAYERS:
		players_box.add_child(_player_row(i))
	# seed row
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	vb.add_child(seed_row)
	seed_row.add_child(UITheme.label(I18n.t("menu.seed"), 18, UITheme.INK, true))
	seed_edit = LineEdit.new()
	seed_edit.text = Settings.seed_text
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_edit)
	var rb: Button = UITheme.button(I18n.t("menu.random"), "GoldButton", Vector2(110, 34), 16)
	rb.pressed.connect(func() -> void: seed_edit.text = _random_seed())
	seed_row.add_child(rb)
	map_label = UITheme.label("", 15, Color("#6b4a2a"))
	vb.add_child(map_label)
	_update_count()
	return panel

func _player_row(i: int) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var num: Label = UITheme.label(str(i + 1), 18, UITheme.INK, true)
	num.custom_minimum_size = Vector2(22, 0)
	hb.add_child(num)
	var d: Dictionary = rows[i]
	var name_edit := LineEdit.new()
	name_edit.text = str(d["name"])
	name_edit.max_length = 32
	name_edit.custom_minimum_size = Vector2(280, 34)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t: String) -> void: (rows[i] as Dictionary)["name"] = t)
	hb.add_child(name_edit)
	var swatch := Button.new()
	swatch.custom_minimum_size = Vector2(38, 34)
	swatch.focus_mode = Control.FOCUS_NONE
	_style_swatch(swatch, int(d["color"]))
	swatch.pressed.connect(func() -> void:
		var used: Array[int] = []
		for k in count:
			if k != i:
				used.append(int((rows[k] as Dictionary)["color"]))
		var c: int = int((rows[i] as Dictionary)["color"])
		for step in Game.PLAYER_COLORS.size():
			c = (c + 1) % Game.PLAYER_COLORS.size()
			if not used.has(c):
				break
		(rows[i] as Dictionary)["color"] = c
		_style_swatch(swatch, c)
		Sfx.play("ui_click", Vector3.INF, 0.6, 0))
	hb.add_child(swatch)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(160, 34)
	for t in TYPES:
		opt.add_item(I18n.t("menu.type_" + t))
	opt.select(TYPES.find(str(d["type"])))
	opt.item_selected.connect(func(idx: int) -> void:
		(rows[i] as Dictionary)["type"] = TYPES[idx]
		Sfx.play("ui_click", Vector3.INF, 0.6, 0))
	hb.add_child(opt)
	hb.set_meta("row", i)
	rows[i]["_node"] = hb
	return hb

func _style_swatch(b: Button, color_idx: int) -> void:
	var c: Color = Game.color_of(color_idx)
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = UITheme.box(c if st != "hover" else c.lightened(0.2), UITheme.INK, 3, 10, 2)
		b.add_theme_stylebox_override(st, sb)

func _update_count() -> void:
	if count_label != null:
		count_label.text = "%s: %d" % [I18n.t("menu.players"), count]
	for i in Cfg.MAX_PLAYERS:
		var n: Control = (rows[i] as Dictionary).get("_node") as Control
		if n != null:
			n.visible = i < count
	if map_label != null:
		map_label.text = I18n.t("menu.map_size", {"r": int(MapGen.map_radius_for(count) * 1.3), "r2": int(minf(MapGen.map_radius_for(count) * 3.0, 300.0))})

func _randomize_names() -> void:
	var defaults: Array = Game.default_players(Cfg.MAX_PLAYERS, _random_seed())
	for i in Cfg.MAX_PLAYERS:
		var d: Dictionary = rows[i]
		d["name"] = str((defaults[i] as Dictionary)["name"])
		var n: Control = d.get("_node") as Control
		if n != null:
			((n.get_child(1)) as LineEdit).text = str(d["name"])

func _options_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(430, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	panel.add_child(vb)
	vb.add_child(UITheme.label(I18n.t("menu.options"), 22, UITheme.RED, true))
	# timer
	var timers: Array[int] = [0, 20, 30, 45, 60]
	var tr := OptionButton.new()
	for t in timers:
		tr.add_item(I18n.t("menu.timer_off") if t == 0 else I18n.t("menu.timer_s", {"s": t}))
	tr.select(timers.find(Settings.timer))
	tr.item_selected.connect(func(idx: int) -> void: Settings.timer = timers[idx])
	vb.add_child(_opt_row(I18n.t("menu.timer"), tr))
	vb.add_child(_slider_row("menu.catapults", 1, Cfg.CATAPULTS_PER_PLAYER, Settings.catapult_count, func(v: int) -> void: Settings.catapult_count = v))
	vb.add_child(_slider_row("menu.palisades", 1, 10, Settings.palisade_count, func(v: int) -> void: Settings.palisade_count = v))
	var hills := OptionButton.new()
	for hl in 5:
		hills.add_item(I18n.t("menu.hills_" + str(hl)))
	hills.select(Settings.terrain_hills)
	hills.item_selected.connect(func(idx: int) -> void: Settings.terrain_hills = idx)
	vb.add_child(_opt_row(I18n.t("menu.terrain"), hills))
	var ars: Button = UITheme.button(I18n.t("menu.arsenal_btn"), "GoldButton", Vector2(0, 36), 16)
	ars.pressed.connect(_open_arsenal)
	vb.add_child(ars)
	var ql := OptionButton.new()
	for q in Settings.QUALITY_TIERS:
		ql.add_item(I18n.t("menu.q_" + q))
	ql.select(Settings.QUALITY_TIERS.find(Settings.quality))
	ql.item_selected.connect(func(idx: int) -> void:
		Settings.quality = Settings.QUALITY_TIERS[idx]
		Events.quality_changed.emit(Settings.quality))
	vb.add_child(_opt_row(I18n.t("menu.quality"), ql))
	vb.add_child(_check(I18n.t("menu.weather"), Settings.weather_on, func(v: bool) -> void: Settings.weather_on = v))
	vb.add_child(_check(I18n.t("menu.events"), Settings.events_on, func(v: bool) -> void: Settings.events_on = v))
	vb.add_child(_check(I18n.t("menu.shake"), Settings.shake, func(v: bool) -> void: Settings.shake = v))
	vb.add_child(_check(I18n.t("menu.autoquality"), Settings.auto_quality, func(v: bool) -> void: Settings.auto_quality = v))
	vb.add_child(_check(I18n.t("menu.vsync"), Settings.vsync, func(v: bool) -> void:
		Settings.vsync = v
		Settings.apply_display()))
	vb.add_child(_check(I18n.t("menu.fullscreen"), Settings.fullscreen, func(v: bool) -> void: Settings.set_fullscreen(v)))
	var vs := HSlider.new()
	vs.min_value = 0.0
	vs.max_value = 1.0
	vs.step = 0.05
	vs.value = Settings.volume
	vs.custom_minimum_size = Vector2(180, 26)
	vs.value_changed.connect(func(v: float) -> void:
		Settings.volume = v
		Settings.apply_volume())
	vs.drag_ended.connect(func(_ch: bool) -> void: Sfx.play("ui_click", Vector3.INF, 0.7, 0))
	_volume_slider = vs
	vb.add_child(_opt_row(I18n.t("menu.volume"), vs))
	return panel

## Integer slider with a live label ("Catapults per player: 4")
func _slider_row(key: String, lo: int, hi: int, value: int, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l: Label = UITheme.label(I18n.t(key, {"n": value}), 17, UITheme.INK, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 1
	sl.value = value
	sl.custom_minimum_size = Vector2(150, 26)
	sl.value_changed.connect(func(v: float) -> void:
		l.text = I18n.t(key, {"n": int(v)})
		cb.call(int(v))
		Sfx.play("ui_hover", Vector3.INF, 0.4, 0))
	hb.add_child(sl)
	return hb

## "Starting arsenal": pre-grant weapons (they are normally earned during the match)
func _open_arsenal() -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -290
	panel.offset_right = 290
	panel.offset_top = -270
	panel.offset_bottom = 270
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(UITheme.label(I18n.t("menu.arsenal"), 22, UITheme.RED, true))
	var hint: Label = UITheme.label(I18n.t("menu.arsenal_hint"), 15, Color("#6b4a2a"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(540, 0)
	vb.add_child(hint)
	for a in AmmoDef.all():
		var ammo: AmmoDef = a
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.color = ammo.color
		hb.add_child(dot)
		var nm: Label = UITheme.label(I18n.t("ammo." + ammo.id), 17, UITheme.INK, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(nm)
		if ammo.earnable:
			var sp := SpinBox.new()
			sp.min_value = 0
			sp.max_value = 9
			sp.step = 1
			sp.value = int(Settings.arsenal.get(ammo.id, 0))
			sp.custom_minimum_size = Vector2(110, 32)
			var aid: String = ammo.id
			sp.value_changed.connect(func(v: float) -> void:
				if int(v) <= 0:
					Settings.arsenal.erase(aid)
				else:
					Settings.arsenal[aid] = int(v)
				Sfx.play("ui_hover", Vector3.INF, 0.4, 0))
			hb.add_child(sp)
		else:
			hb.add_child(UITheme.label(I18n.t("menu.always"), 16, Color("#2e7d32"), true))
		vb.add_child(hb)
	var ok: Button = UITheme.button(I18n.t("menu.ok"), "GreenButton", Vector2(0, 44), 20)
	ok.pressed.connect(func() -> void:
		Settings.save_settings()
		overlay.queue_free())
	vb.add_child(ok)
	_content.add_child(overlay)

func _opt_row(text: String, ctl: Control) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l: Label = UITheme.label(text, 17, UITheme.INK, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, 170.0)
	hb.add_child(ctl)
	return hb

func _check(text: String, value: bool, cb: Callable) -> Control:
	var cb_btn := CheckButton.new()
	cb_btn.text = text
	cb_btn.button_pressed = value
	cb_btn.focus_mode = Control.FOCUS_NONE
	cb_btn.add_theme_font_size_override("font_size", 17)
	cb_btn.toggled.connect(func(v: bool) -> void:
		cb.call(v)
		Sfx.play("ui_click", Vector3.INF, 0.5, 0))
	return cb_btn

func _collect() -> void:
	if seed_edit != null:
		Settings.seed_text = seed_edit.text.strip_edges()
	Settings.player_count = count
	var out: Array = []
	for i in Cfg.MAX_PLAYERS:
		var d: Dictionary = rows[i]
		out.append({"name": str(d["name"]), "color": int(d["color"]), "type": str(d["type"])})
	Settings.players = out

func _on_start() -> void:
	_collect()
	if Settings.seed_text == "":
		Settings.seed_text = _random_seed()
	Settings.save_settings()
	Sfx.play("ui_click", Vector3.INF, 0.8, 0)
	start_requested.emit()

func players_config() -> Array:
	var out: Array = []
	for i in count:
		var d: Dictionary = rows[i]
		out.append({"name": str(d["name"]), "color": int(d["color"]), "type": str(d["type"])})
	return out
