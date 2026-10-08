class_name Menu
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Main menu (spec 2.1): language, players (name / color / type), seed, options, START BATTLE.

signal start_requested
signal online_requested

const SEED_WORDS: Array[String] = ["cheese", "goose", "pitchfork", "turnip", "moat", "dragon", "haystack", "gravy", "kaboom", "ale", "gauntlet", "pumpernickel", "trebuchet", "wobble", "porridge", "yeet"]
const OPT_W := 230.0                  # width of every control in the options column
const TYPES: Array[String] = ["human", "peasant", "squire", "knight", "king"]

## Language flag button (drawn, no image files): Germany = black-red-gold, English = Union Jack
class FlagButton extends Control:
	signal pressed
	var kind: String = "de"
	var selected: bool = false
	var tile: bool = false          # drawn as a glass button tile with the flag inside (top right of the menu)
	var _hover: bool = false
	func _init(k: String = "de") -> void:
		kind = k
		custom_minimum_size = Vector2(46, 32)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		if tile:
			material = Glass.tinted(Color.WHITE, 0.24) if Glass.supported() else null
			if selected:
				# the chosen language looks pressed: flat (no shadow), a bit darker, the flag one pixel lower
				draw_style_box(Glass.fit(Glass.tile(12, 0.0, 1.0, 0), self), Rect2(Vector2.ZERO, size))
				var dark := StyleBoxFlat.new()
				dark.bg_color = Color(0.2, 0.12, 0.05, 0.16)
				dark.set_corner_radius_all(12)
				draw_style_box(dark, Rect2(Vector2.ZERO, size))
				r = Rect2(Vector2(10, 9), size - Vector2(20, 16))
			else:
				draw_style_box(Glass.fit(Glass.tile(12), self), Rect2(Vector2.ZERO, size))
				r = Rect2(Vector2(10, 8), size - Vector2(20, 16))
		if kind == "de":
			var h: float = r.size.y / 3.0
			draw_rect(Rect2(r.position, Vector2(r.size.x, h)), Color("#1a1a1a"))
			draw_rect(Rect2(r.position + Vector2(0, h), Vector2(r.size.x, h)), Color("#dd0000"))
			draw_rect(Rect2(r.position + Vector2(0, h * 2.0), Vector2(r.size.x, h)), Color("#ffce00"))
		else:
			var blue := Color("#012169")
			var red := Color("#c8102e")
			draw_rect(r, blue)
			var tl: Vector2 = r.position
			var br: Vector2 = r.position + r.size
			var tr: Vector2 = Vector2(br.x, tl.y)
			var bl: Vector2 = Vector2(tl.x, br.y)
			draw_line(tl, br, Color.WHITE, 5.0)
			draw_line(tr, bl, Color.WHITE, 5.0)
			draw_line(tl, br, red, 2.0)
			draw_line(tr, bl, red, 2.0)
			var c: Vector2 = r.get_center()
			draw_rect(Rect2(Vector2(r.position.x, c.y - 4.5), Vector2(r.size.x, 9.0)), Color.WHITE)
			draw_rect(Rect2(Vector2(c.x - 4.5, r.position.y), Vector2(9.0, r.size.y)), Color.WHITE)
			draw_rect(Rect2(Vector2(r.position.x, c.y - 2.5), Vector2(r.size.x, 5.0)), red)
			draw_rect(Rect2(Vector2(c.x - 2.5, r.position.y), Vector2(5.0, r.size.y)), red)
		if tile:
			draw_rect(r, Color(0.23, 0.16, 0.10, 0.55), false, 1.0)
			return
		var border: Color = Color("#ffd400") if selected else (Color("#8a6a3a") if _hover else Color("#3b2a1a"))
		draw_rect(r, border, false, 3.0 if selected else 2.0)
		if not selected:
			draw_rect(r, Color(0, 0, 0, 0.18))

var rows: Array[Dictionary] = []
var count: int = 4
var seed_edit: LineEdit
var count_label: Label
var map_label: Label
var players_box: VBoxContainer
var start_btn: Button
var online_btn: Button
var room_banner: PanelContainer
var _room_code_label: Label
var _room_count_label: Label
var status: Label
var title: Label
var _content: Control
var _sound_ready: bool = false
var _rng := Rng.new(int(Time.get_ticks_msec()))
var _rules_label: Label
var _settings_dlg: SettingsDialog
var _host_ctrls: Array[Control] = []     # controls only the host may change while a lobby is open
var _lobby_timer: float = 0.0
var _lobby_sent: String = ""
var _lobby_applied: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.build()
	Glass.watch(self)
	_load_state()
	_build()
	Events.language_changed.connect(_on_lang_changed)
	Net.roster_changed.connect(_on_net_changed)
	Net.joined.connect(func(_c: String) -> void: _on_net_changed())
	Sfx.synth_ready.connect(_on_synth_ready)
	if Sfx.is_ready:
		_on_synth_ready()

# ------------------------------------------------------------------ online lobby: who may change what, and keeping everybody in step
## The peer that owns seat `i` (-1 = a CPU seat / offline). Seat 0 is the host.
func _peer_of_seat(i: int) -> int:
	if not Net.active:
		return -1
	if Net.is_client():
		return int((rows[i] as Dictionary).get("peer", -1))
	var peers: Array = NetGame.seat_peers()
	return int(peers[i]) if i < peers.size() else -1

func _on_net_changed() -> void:
	_lobby_sent = ""
	_lobby_applied = ""
	if not Net.active and Settings.pop_lobby():
		_load_state()               # a guest that left gets its own settings back
	if Net.is_host:
		count = maxi(count, NetGame.seat_peers().size())
	_build()
	_refresh_start()

## Host: the complete menu state (seats with their peers, colours, bots and the match options)
func lobby_state() -> Dictionary:
	var peers: Array = NetGame.seat_peers()
	var out_rows: Array = []
	for i in count:
		var d: Dictionary = rows[i]
		var pid: int = int(peers[i]) if i < peers.size() else -1
		var tp: String = "human" if pid >= 0 else (str(d["type"]) if str(d["type"]) != "human" else "squire")
		out_rows.append({"name": Net.peer_name(pid) if pid >= 0 else str(d["name"]), "color": int(d["color"]), "type": tp, "peer": pid})
	return {"count": count, "rows": out_rows, "seed": seed_edit.text.strip_edges() if seed_edit != null else Settings.seed_text,
		"timer": Settings.timer, "cats": Settings.catapult_count, "posts": Settings.palisade_count, "hills": Settings.terrain_hills,
		"arsenal_preset": Settings.arsenal_preset, "rules": Settings.rules_level, "crates": Settings.crates_on, "autoplace": Settings.auto_place, "weather": Settings.weather_on, "wind": Settings.wind_level, "events": Settings.events_on, "arsenal": Settings.arsenal}

## Guest: show what the host has set up (a temporary overlay, see Settings.push_lobby)
func net_lobby_apply(d: Dictionary) -> void:
	if not Net.is_client():
		return
	var js: String = JSON.stringify(d)
	if js == _lobby_applied:
		return
	_lobby_applied = js
	Settings.push_lobby()
	count = clampi(int(d["count"]), Cfg.MIN_PLAYERS, Cfg.MAX_PLAYERS)
	var rr: Array = d["rows"] as Array
	for i in Cfg.MAX_PLAYERS:
		if i < rr.size():
			var r: Dictionary = rr[i] as Dictionary
			(rows[i] as Dictionary)["name"] = str(r["name"])
			(rows[i] as Dictionary)["color"] = int(r["color"])
			(rows[i] as Dictionary)["type"] = str(r["type"])
			(rows[i] as Dictionary)["peer"] = int(r["peer"])
	Settings.player_count = count
	Settings.seed_text = str(d["seed"])
	Settings.timer = int(d["timer"])
	Settings.catapult_count = int(d["cats"])
	Settings.palisade_count = int(d["posts"])
	Settings.terrain_hills = int(d["hills"])
	Settings.arsenal_preset = str(d["arsenal_preset"])
	Settings.rules_level = int(d.get("rules", 0))
	Settings.crates_on = bool(d.get("crates", true))
	Settings.auto_place = bool(d.get("autoplace", false))
	Settings.weather_on = bool(d.get("weather", Settings.weather_on))
	Settings.wind_level = clampi(int(d.get("wind", 1)), 0, 2)
	Settings.events_on = bool(d.get("events", Settings.events_on))
	Settings.arsenal_edit_preset = Settings.arsenal_preset
	Settings.arsenal_edit.clear()
	for k in (d["arsenal"] as Dictionary):
		Settings.arsenal_edit[str(k)] = int((d["arsenal"] as Dictionary)[k])
	_build()
	_refresh_start()

## Host: a guest changed its own colour
func net_lobby_set(seat: int, d: Dictionary) -> void:
	if seat < 0 or seat >= count or not d.has("color"):
		return
	(rows[seat] as Dictionary)["color"] = clampi(int(d["color"]), 0, Game.PLAYER_COLORS.size() - 1)
	_lobby_sent = ""
	_build()
	_refresh_start()

func _process(delta: float) -> void:
	if not Net.is_host or not visible:
		return
	_lobby_timer += delta
	if _lobby_timer < 0.4:
		return
	_lobby_timer = 0.0
	var js: String = JSON.stringify(lobby_state())
	if js != _lobby_sent:
		_lobby_sent = js
		NetGame.send_lobby(lobby_state())

static func _lock(c: Control) -> void:
	if c is LineEdit:
		(c as LineEdit).editable = false
	elif c is HSlider:
		(c as HSlider).editable = false
	elif c is BaseButton:
		(c as BaseButton).disabled = true

func _host_only(c: Control) -> void:
	_host_ctrls.append(c)

func _load_state() -> void:
	count = clampi(Settings.player_count, Cfg.MIN_PLAYERS, Cfg.MAX_PLAYERS)
	if Settings.seed_text == "":
		Settings.seed_text = _random_seed()
	var saved: Array = Settings.players
	rows.clear()
	var defaults: Array = Game.default_players(Cfg.MAX_PLAYERS, "")      # a new order at every program start
	for i in Cfg.MAX_PLAYERS:
		var d: Dictionary = (defaults[i] as Dictionary).duplicate()
		if i < saved.size() and saved[i] is Dictionary:
			var sd: Dictionary = saved[i] as Dictionary
			var sname: String = str(sd.get("name", d["name"]))
			if not Game.HUMAN_NAMES.has(sname):
				d["name"] = sname               # a name the player typed stays; the drawn ones are drawn anew
			d["color"] = int(sd.get("color", d["color"]))
			d["type"] = str(sd.get("type", d["type"]))
		rows.append(d)

func _random_seed() -> String:
	return "%s-%s-%d" % [SEED_WORDS[_rng.range_i(0, SEED_WORDS.size() - 1)], SEED_WORDS[_rng.range_i(0, SEED_WORDS.size() - 1)], _rng.range_i(10, 99)]

func _on_lang_changed() -> void:
	_collect()
	_build()
	_refresh_start()

func _on_synth_ready() -> void:
	_sound_ready = true
	_refresh_start()

func _refresh_start() -> void:
	var in_room: bool = Net.active
	if start_btn != null:
		start_btn.disabled = not _sound_ready or Net.is_client() or _team_count() < 2
		if in_room:
			start_btn.text = I18n.t("net.start_online") if Net.is_host else I18n.t("net.waiting_short")
		else:
			start_btn.text = I18n.t("menu.start")
	if online_btn != null:
		# in a room the second button ends it (red); otherwise it opens the online dialog (gold)
		online_btn.theme_type_variation = "RedButton" if in_room else "GoldButton"
		online_btn.text = (I18n.t("net.end_lobby") if Net.is_host else I18n.t("net.leave_lobby")) if in_room else I18n.t("net.open")
	if room_banner != null:
		room_banner.visible = in_room
		if in_room:
			_room_code_label.text = Net.code
			_room_count_label.text = "- " + I18n.t("net.players_n", {"n": Net.roster.size()})
	if status != null:
		if _sound_ready:
			status.text = ""
		if _team_count() < 2:
			status.text = I18n.t("menu.one_team")

## Different colours among the players = number of teams (same colour = same team)
func _team_count() -> int:
	var seen: Dictionary = {}
	for i in count:
		seen[int((rows[i] as Dictionary)["color"])] = true
	return seen.size()

# ------------------------------------------------------------------ layout
func _build() -> void:
	_host_ctrls.clear()
	if _content != null:
		_content.queue_free()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	if is_instance_valid(_settings_dlg):
		move_child(_settings_dlg, get_child_count() - 1)          # an open settings dialog stays in front of the rebuilt menu (language change)
	# dim gradient at the sides for readability
	# the menu scrolls when the screen is lower than the menu (phones in landscape, small browser windows)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 30
	scroll.offset_right = -30
	scroll.offset_top = 26
	scroll.offset_bottom = -16
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)
	# top right: language and the settings dialog as three glass buttons (graphics, display, sound: things of this computer)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tools.anchor_left = 1.0
	tools.anchor_right = 1.0
	tools.offset_right = -24
	tools.offset_top = 18
	tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	for lg in ["de", "en"]:
		var fb := FlagButton.new(lg)
		fb.tile = true
		fb.custom_minimum_size = Vector2(60, 42)
		fb.selected = I18n.get_lang() == lg
		fb.tooltip_text = "Deutsch" if lg == "de" else "English"
		var code: String = lg
		fb.pressed.connect(func() -> void:
			I18n.set_lang(code)
			Settings.save_settings())
		tools.add_child(fb)
	var gear := GearButton.new()
	gear.toggle_mode = false
	gear.custom_minimum_size = Vector2(60, 42)
	gear.tooltip_text = I18n.t("settings.title")
	Glass.button(gear)
	gear.pressed.connect(_open_settings)
	tools.add_child(gear)
	var quit_b := CloseButton.new()
	quit_b.quit_style = true
	quit_b.theme_type_variation = "RedButton"
	quit_b.tooltip_text = I18n.t("menu.quit")
	quit_b.custom_minimum_size = Vector2(60, 42)
	quit_b.pressed.connect(func() -> void: get_tree().quit())
	if not Cfg.is_web():
		tools.add_child(quit_b)       # a browser tab cannot be closed by the game
	else:
		quit_b.free()
	_content.add_child(tools)
	# title
	title = UITheme.label(I18n.t("menu.title"), 68, Color("#ffd400"), true, 22)
	title.add_theme_font_override("font", ComicText.comic_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var sub: Label = UITheme.label(I18n.t("menu.subtitle"), 20, Color("#ffffff"), true, 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	if Cfg.is_web() and TouchMode.on and int(JavaScriptBridge.eval("Math.min(window.innerWidth, window.innerHeight)", true)) < 600:
		var hint: Label = UITheme.label(I18n.t("menu.small_screen_hint"), 16, Color("#ffd400"), true, 6)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(hint)
	root.add_child(UITheme.vspacer(10))
	# two columns
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 22)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(cols)
	cols.add_child(_players_panel())
	cols.add_child(_options_panel())
	# room banner (only while in an online room): the code, big, above the buttons
	room_banner = PanelContainer.new()
	Glass.panel(room_banner)
	room_banner.visible = false
	var rb_box := HBoxContainer.new()
	rb_box.add_theme_constant_override("separation", 14)
	rb_box.alignment = BoxContainer.ALIGNMENT_CENTER
	room_banner.add_child(rb_box)
	rb_box.add_child(UITheme.label(I18n.t("net.room_label"), 20, UITheme.INK, true))
	_room_code_label = UITheme.label("", 40, Color("#a02818"), true)
	rb_box.add_child(_room_code_label)
	_room_count_label = UITheme.label("", 20, UITheme.INK, true)
	rb_box.add_child(_room_count_label)
	var copy_btn: Button = UITheme.option_button(I18n.t("net.copy"), "ParchButton", 100.0)
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Net.code)
		Sfx.play("ui_click", Vector3.INF, 0.6, 0))
	rb_box.add_child(copy_btn)
	var rb_center := CenterContainer.new()
	rb_center.add_child(room_banner)
	root.add_child(rb_center)
	# bottom bar: [start] [online / close lobby]
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 20)
	root.add_child(bottom)
	start_btn = UITheme.button(I18n.t("menu.start"), "GreenButton", Vector2(340, 68), 26)
	start_btn.pressed.connect(_on_start)
	bottom.add_child(start_btn)
	online_btn = UITheme.button(I18n.t("net.open"), "GoldButton", Vector2(340, 68), 26)
	online_btn.pressed.connect(func() -> void:
		if Net.active:
			Net.leave()          # host: closes the lobby for everybody, guest: leaves it
			_refresh_start()
		else:
			online_requested.emit())
	bottom.add_child(online_btn)
	# status line (online room, "needs two teams", rules reset): its space is always reserved; no help text
	status = UITheme.label("", 15, Color.WHITE, false, 6)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.custom_minimum_size = Vector2(0, 24)            # always takes its space: the buttons above never jump
	root.add_child(status)
	var cred: Label = UITheme.label(I18n.t("menu.credits") + "   -   v" + Cfg.game_version(), 13, Color(1, 1, 1, 0.8), false, 5)
	cred.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(cred)
	if Net.is_client():
		for hc in _host_ctrls:
			_lock(hc)
	_refresh_start()

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	Glass.dialog(p, 18, Vector2(18, 14))
	return p

func _players_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
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
	if Net.is_host:
		sl.min_value = maxi(Cfg.MIN_PLAYERS, NetGame.seat_peers().size())     # every connected player keeps a seat
	cnt_row.add_child(sl)
	_host_only(sl)
	var rn: Button = UITheme.option_button(I18n.t("menu.random_names"), "ParchButton", 0.0)
	rn.pressed.connect(_randomize_names)
	cnt_row.add_child(rn)
	_host_only(rn)
	# rows
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 6)
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pp := MarginContainer.new()              # room for the shadows of the fields
	pp.add_theme_constant_override("margin_right", 6)
	pp.add_theme_constant_override("margin_bottom", 6)
	pp.add_theme_constant_override("margin_top", 2)
	scroll.add_child(pp)
	pp.add_child(players_box)
	for i in Cfg.MAX_PLAYERS:
		players_box.add_child(_player_row(i))
	# match setup as one aligned grid: label | field | button (same columns in every row)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	_arsenal_cells(grid)
	grid.add_child(UITheme.label(I18n.t("menu.seed"), 18, UITheme.INK, true))
	seed_edit = LineEdit.new()
	seed_edit.text = Settings.seed_text
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.custom_minimum_size = Vector2(0, 36)
	grid.add_child(seed_edit)
	_host_only(seed_edit)
	var rb: Button = UITheme.option_button(I18n.t("menu.random"), "GoldButton", 100.0)
	rb.pressed.connect(func() -> void: seed_edit.text = _random_seed())
	grid.add_child(rb)
	_host_only(rb)
	grid.add_child(Control.new())
	map_label = UITheme.label("", 14, Color("#6b4a2a"))
	grid.add_child(map_label)
	grid.add_child(Control.new())
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
	# online: seats of connected players show their (net) name and are fixed humans; only the host defines bots / their names
	var peer: int = _peer_of_seat(i)
	var in_lobby: bool = Net.active
	if peer >= 0:
		name_edit.text = Net.peer_name(peer) if not Net.is_client() else str(d["name"])
	if in_lobby and (peer >= 0 or Net.is_client()):
		name_edit.editable = false
	# team = colour: a dropdown of colour swatches (several players may share one colour = one team)
	var team_dd := OptionButton.new()
	team_dd.custom_minimum_size = Vector2(150, 34)
	team_dd.focus_mode = Control.FOCUS_NONE
	team_dd.tooltip_text = I18n.t("menu.team_hint")
	for ci in Game.PLAYER_COLORS.size():
		team_dd.add_icon_item(_swatch_icon(ci), I18n.t("menu.color_" + str(ci)))
	team_dd.select(int(d["color"]) % Game.PLAYER_COLORS.size())
	team_dd.item_selected.connect(func(idx: int) -> void:
		(rows[i] as Dictionary)["color"] = idx
		if Net.is_client():
			NetGame.send_lobby_set({"color": idx})          # the host takes it over and tells everybody
		_refresh_start()
		Sfx.play("ui_click", Vector3.INF, 0.6, 0))
	hb.add_child(team_dd)
	# a guest may only change its own colour, the host everybody's
	if Net.is_client() and peer != Net.my_id:
		team_dd.disabled = true
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(160, 34)
	for t in TYPES:
		opt.add_item(I18n.t("menu.type_" + t))
	opt.select(TYPES.find(str(d["type"])))
	opt.item_selected.connect(func(idx: int) -> void:
		(rows[i] as Dictionary)["type"] = TYPES[idx]
		Sfx.play("ui_click", Vector3.INF, 0.6, 0))
	hb.add_child(opt)
	if in_lobby:
		if Net.is_client() or peer >= 0:
			opt.disabled = true
		else:
			# a free seat can only be a CPU
			opt.set_item_disabled(TYPES.find("human"), true)
			if str(d["type"]) == "human":
				(rows[i] as Dictionary)["type"] = "squire"
				opt.select(TYPES.find("squire"))
	hb.set_meta("row", i)
	rows[i]["_node"] = hb
	return hb

static var _swatch_cache: Dictionary = {}

static func _swatch_icon(color_idx: int) -> Texture2D:
	if _swatch_cache.has(color_idx):
		return _swatch_cache[color_idx] as Texture2D
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	var c: Color = Game.color_of(color_idx)
	for y in 22:
		for x in 22:
			var edge: bool = x < 2 or y < 2 or x > 19 or y > 19
			img.set_pixel(x, y, Color("#3b2a1a") if edge else c)
	var tex: Texture2D = ImageTexture.create_from_image(img)
	_swatch_cache[color_idx] = tex
	return tex

## Starting arsenal: preset dropdown + one line that says what is in it
func _arsenal_cells(grid: GridContainer) -> void:
	grid.add_child(UITheme.label(I18n.t("menu.arsenal_short"), 18, UITheme.INK, true))
	var dd := OptionButton.new()
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dd.custom_minimum_size = Vector2(0, 36)
	dd.focus_mode = Control.FOCUS_NONE
	for pid in Arsenal.PRESETS:
		dd.add_item(I18n.t("menu.ars_" + pid))
	dd.select(Arsenal.PRESETS.find(Settings.arsenal_preset))
	grid.add_child(dd)
	_host_only(dd)
	# the button always opens the list of weapons (look at what a preset contains; tweaks of a preset are for this session only)
	var edit: Button = UITheme.option_button(I18n.t("menu.ars_edit"), "GoldButton", 100.0)
	edit.pressed.connect(_open_arsenal)
	grid.add_child(edit)
	# unlock rules: given by the mode (the tier of a Custom arsenal is chosen in the Edit dialog); always readable right here
	grid.add_child(UITheme.label(I18n.t("menu.rules"), 18, UITheme.INK, true))
	_rules_label = UITheme.label(_rules_text(), 17, UITheme.INK)
	_rules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_label.clip_text = true
	grid.add_child(_rules_label)
	var rq: Button = UITheme.option_button(I18n.t("menu.show_rules"), "ParchButton", 100.0)
	rq.pressed.connect(_open_rules)
	grid.add_child(rq)
	dd.item_selected.connect(func(idx: int) -> void:
		Settings.arsenal_preset = Arsenal.PRESETS[idx]
		Settings.arsenal_edit_preset = ""
		Settings.arsenal_edit.clear()
		_rules_label.text = _rules_text()
		Settings.save_settings()
		Sfx.play("ui_click", Vector3.INF, 0.6, 0))

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
	panel.custom_minimum_size = Vector2(450, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# the options scroll when the window is too low, so the buttons at the bottom of the menu never slip out of view
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 160)
	panel.add_child(scroll)
	var pad := MarginContainer.new()               # room around the controls so that their shadows are not clipped by the scroll area
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 3)
	pad.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(pad)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 9)
	pad.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var ot: Label = UITheme.label(I18n.t("menu.match_rules"), 22, UITheme.INK, true)
	ot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ot)
	vb.add_child(head)
	# timer
	var timers: Array[int] = [0, 20, 30, 45, 60]
	var tr := OptionButton.new()
	for t in timers:
		tr.add_item(I18n.t("menu.timer_off") if t == 0 else I18n.t("menu.timer_s", {"s": t}))
	tr.select(timers.find(Settings.timer))
	tr.item_selected.connect(func(idx: int) -> void: Settings.timer = timers[idx])
	vb.add_child(_opt_row(I18n.t("menu.timer"), tr))
	_host_only(tr)
	var cat_row: Control = _slider_row("menu.catapults", 1, Cfg.CATAPULTS_PER_PLAYER, Settings.catapult_count, func(v: int) -> void: Settings.catapult_count = v)
	vb.add_child(cat_row)
	_host_only(cat_row.get_child(1) as Control)
	var pal_row: Control = _slider_row("menu.palisades", 1, 10, Settings.palisade_count, func(v: int) -> void: Settings.palisade_count = v)
	vb.add_child(pal_row)
	_host_only(pal_row.get_child(1) as Control)
	var hills := OptionButton.new()
	for hl in 5:
		hills.add_item(I18n.t("menu.hills_" + str(hl)))
	hills.select(Settings.terrain_hills)
	hills.item_selected.connect(func(idx: int) -> void: Settings.terrain_hills = idx)
	vb.add_child(_opt_row(I18n.t("menu.terrain"), hills))
	_host_only(hills)
	var wind_opt := OptionButton.new()
	for wl in 3:
		wind_opt.add_item(I18n.t("menu.wind_" + str(wl)))
	wind_opt.select(Settings.wind_level)
	wind_opt.item_selected.connect(func(idx: int) -> void: Settings.wind_level = idx)
	vb.add_child(_opt_row(I18n.t("menu.wind"), wind_opt))
	_host_only(wind_opt)          # match rule: online only the host decides
	var chk_weather: Control = _check(I18n.t("menu.weather"), Settings.weather_on, func(v: bool) -> void: Settings.weather_on = v)
	_host_only(chk_weather)          # match rule: online only the host decides
	vb.add_child(chk_weather)
	var chk_events: Control = _check(I18n.t("menu.events"), Settings.events_on, func(v: bool) -> void: Settings.events_on = v)
	_host_only(chk_events)          # match rule: online only the host decides
	vb.add_child(chk_events)
	var chk_crates: Control = _check(I18n.t("menu.crates"), Settings.crates_on, func(v: bool) -> void: Settings.crates_on = v)
	_host_only(chk_crates)          # match rule: online only the host decides
	vb.add_child(chk_crates)
	var chk_auto: Control = _check(I18n.t("menu.autoplace"), Settings.auto_place, func(v: bool) -> void: Settings.auto_place = v)
	_host_only(chk_auto)          # match rule: online only the host decides
	vb.add_child(chk_auto)
	# back to the first-start state of the match rules
	var reset: Button = UITheme.option_button(I18n.t("menu.reset_rules"), "ParchButton", 0.0)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset.pressed.connect(func() -> void:
		Settings.reset_match_options(Net.is_client())
		Sfx.play("ui_click", Vector3.INF, 0.7, 0)
		_build()
		status.text = I18n.t("menu.rules_reset"))
	vb.add_child(reset)
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
	sl.custom_minimum_size = Vector2(OPT_W, 26)
	sl.size_flags_horizontal = Control.SIZE_SHRINK_END
	sl.value_changed.connect(func(v: float) -> void:
		l.text = I18n.t(key, {"n": int(v)})
		cb.call(int(v))
		Sfx.play("ui_hover", Vector3.INF, 0.4, 0))
	hb.add_child(sl)
	return hb

## The unlock rules that are active in the chosen mode, per weapon
func _open_settings() -> void:
	Sfx.play("ui_click", Vector3.INF, 0.6, 0)
	if is_instance_valid(_settings_dlg):
		return
	_settings_dlg = SettingsDialog.new()          # a child of the menu itself (not of the content): a language change rebuilds the content
	add_child(_settings_dlg)

func _rules_text() -> String:
	var lvl: int = Settings.effective_rule_level()
	return I18n.t("menu.rules_%d" % lvl) + ("  +  " + I18n.t("menu.rules_quarry") if Settings.arsenal_preset == "quarry" else "")

func _open_rules() -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.30)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	Glass.dialog(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -280
	panel.offset_bottom = 280
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var lvl: int = Settings.effective_rule_level()
	var title: Label = UITheme.label(I18n.t("menu.rules") + ": " + I18n.t("menu.rules_%d" % lvl), 22, UITheme.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := CloseButton.new()
	head.add_child(close)
	var intro: Label = UITheme.label(I18n.t("menu.rules_intro"), 15, Color("#6b4a2a"))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(560, 0)
	vb.add_child(intro)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 380)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for entry in Unlocks.rules_of_mode(lvl, Settings.arsenal_preset == "quarry"):
		var nm: Label = UITheme.label(I18n.t("ammo." + str(entry[0])), 17, UITheme.INK, true)
		list.add_child(nm)
		for line in (entry[1] as Array):
			var l: Label = UITheme.label("• " + str(line), 14, Color("#4a3320"))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(540, 0)
			list.add_child(l)
	var ok: Button = UITheme.dialog_button(I18n.t("menu.ok"), "GreenButton")
	ok.pressed.connect(func() -> void: overlay.queue_free())
	close.pressed.connect(func() -> void: overlay.queue_free())
	vb.add_child(ok)
	_content.add_child(overlay)

## "Starting arsenal": pre-grant weapons (they are normally earned during the match)
func _open_arsenal() -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.30)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	Glass.dialog(panel)
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
	var work: Dictionary = Settings.arsenal.duplicate()
	var ahead := HBoxContainer.new()
	vb.add_child(ahead)
	var at: Label = UITheme.label(I18n.t("menu.arsenal") + ": " + I18n.t("menu.ars_" + Settings.arsenal_preset), 22, UITheme.INK, true)
	at.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ahead.add_child(at)
	var aclose := CloseButton.new()
	ahead.add_child(aclose)
	if Settings.arsenal_preset == "custom":
		# the tier of the unlock rules of a Custom arsenal is chosen here (the other modes bring their own)
		var rd := OptionButton.new()
		rd.focus_mode = Control.FOCUS_NONE
		for lv in 3:
			rd.add_item(I18n.t("menu.rules_%d" % lv))
		rd.select(Settings.rules_level)
		rd.disabled = Net.is_client()
		rd.item_selected.connect(func(idx: int) -> void:
			Settings.rules_level = idx
			Sfx.play("ui_click", Vector3.INF, 0.6, 0))
		vb.add_child(_opt_row(I18n.t("menu.rules"), rd))
	var hint: Label = UITheme.label(I18n.t("menu.arsenal_hint"), 15, Color("#6b4a2a"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(540, 0)
	vb.add_child(hint)
	# the weapon rows scroll when the window is too small for all of them
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, clampf(get_viewport_rect().size.y - 230.0, 200.0, 560.0))
	vb.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rp := MarginContainer.new()
	rp.add_theme_constant_override("margin_right", 8)
	rp.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(rp)
	rp.add_child(rows)
	for a in AmmoDef.all():
		var ammo: AmmoDef = a
		if ammo.is_action():
			continue
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		var icon := Hud.AmmoSlot.new()
		icon.ammo = ammo
		icon.icon_only = true
		icon.custom_minimum_size = Vector2(44, 44)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)
		var nm: Label = UITheme.label(I18n.t("ammo." + ammo.id), 17, UITheme.INK, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(nm)
		if ammo.earnable:
			var aid: String = ammo.id
			var cur: int = int(work.get(aid, 0))
			var sp := SpinBox.new()
			sp.min_value = 0
			sp.max_value = 9
			sp.step = 1
			sp.value = maxi(cur, 0)
			sp.editable = cur >= 0
			sp.custom_minimum_size = Vector2(110, 32)
			var inf := CheckBox.new()
			inf.text = "∞"
			inf.add_theme_font_size_override("font_size", 24)
			inf.button_pressed = cur < 0
			inf.focus_mode = Control.FOCUS_NONE
			sp.value_changed.connect(func(v: float) -> void:
				if int(v) <= 0:
					work.erase(aid)
				else:
					work[aid] = int(v)
				Sfx.play("ui_hover", Vector3.INF, 0.4, 0))
			inf.toggled.connect(func(on: bool) -> void:
				sp.editable = not on
				if on:
					work[aid] = -1
				elif int(sp.value) > 0:
					work[aid] = int(sp.value)
				else:
					work.erase(aid)
				Sfx.play("ui_click", Vector3.INF, 0.5, 0))
			hb.add_child(sp)
			hb.add_child(inf)
		else:
			hb.add_child(UITheme.label(I18n.t("menu.always"), 16, Color("#2e7d32"), true))
		rows.add_child(hb)
	var ok: Button = UITheme.dialog_button(I18n.t("menu.ok"), "GreenButton")
	var commit := func() -> void:
		if Settings.arsenal_preset == "custom":
			Settings.arsenal_custom = work          # the only thing that is remembered for the next session
		else:
			Settings.arsenal_edit = work
			Settings.arsenal_edit_preset = Settings.arsenal_preset
		Settings.save_settings()
		if _rules_label != null:
			_rules_label.text = _rules_text()
		overlay.queue_free()
	ok.pressed.connect(commit)
	aclose.pressed.connect(commit)
	vb.add_child(ok)
	_content.add_child(overlay)

func _opt_row(text: String, ctl: Control) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l: Label = UITheme.label(text, 17, UITheme.INK, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	if ctl is OptionButton:
		(ctl as OptionButton).fit_to_longest_item = false
		(ctl as OptionButton).clip_text = true
	ctl.custom_minimum_size.x = OPT_W          # one common width: all controls start at the same x
	ctl.size_flags_horizontal = Control.SIZE_SHRINK_END
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
	if Net.is_client():
		return                         # a guest only shows the host's setup
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
