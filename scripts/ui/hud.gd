class_name Hud
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## In-battle HUD (spec 18.1): turn banner + timer, player list, wind/weather, ammo bar, aim info,
## buttons, announcer banner, kill feed, toasts. No emoji: all icons are drawn with _draw().

signal overview_pressed
signal fast_pressed
signal pause_pressed
signal skip_requested
signal ammo_clicked(id: String)

# ------------------------------------------------------------------ small custom controls
class TimerRing extends Control:
	var frac: float = 1.0
	var seconds: int = 0
	var visible_ring: bool = true
	var col: Color = Color("#2ecc71")
	func _init() -> void:
		custom_minimum_size = Vector2(54, 54)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if not visible_ring:
			return
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, r + 3.0, Color(0.15, 0.1, 0.06))
		draw_circle(c, r, Color("#fff6da"))
		var a: Color = col if frac > 0.33 else Color("#e74c3c")
		draw_arc(c, r - 3.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, a, 6.0, true)
		var f: Font = UITheme.font_bold()
		var s: String = str(seconds)
		var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(f, Vector2(c.x - w * 0.5, c.y + 7.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#3b2a1a"))

class WindWidget extends Control:
	var wind: Vector2 = Vector2.ZERO
	var cam_yaw: float = 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(70, 70)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 3.0
		draw_circle(c, r + 2.0, Color(0.15, 0.1, 0.06))
		draw_circle(c, r, Color("#fff6da"))
		var sp: float = wind.length()
		# world wind (x, z) -> screen: rotate by camera yaw so "up" on screen is the view direction
		var ang: float = atan2(wind.x, -wind.y) - cam_yaw
		var dir := Vector2(sin(ang), -cos(ang)) if sp > 0.05 else Vector2.ZERO
		var len: float = r * clampf(0.35 + sp / Cfg.WIND_MAX / 1.8 * 0.65, 0.35, 0.95)
		if sp > 0.05:
			var tip: Vector2 = c + dir * len
			var tail: Vector2 = c - dir * len * 0.7
			var side := Vector2(-dir.y, dir.x)
			var col: Color = Color("#3498db").lerp(Color("#e74c3c"), clampf(sp / (Cfg.WIND_MAX * 1.2), 0.0, 1.0))
			draw_line(tail, tip, col, 6.0, true)
			var poly := PackedVector2Array([tip + dir * 4.0, tip - dir * 10.0 + side * 8.0, tip - dir * 10.0 - side * 8.0])
			draw_colored_polygon(poly, col)
		else:
			draw_circle(c, 5.0, Color("#3498db"))

class AmmoSlot extends Control:
	var ammo: AmmoDef
	var count: int = 0
	var selected: bool = false
	var hovered: bool = false
	var enabled: bool = true
	signal clicked
	func _init() -> void:
		custom_minimum_size = Vector2(74, 90)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and enabled:
				clicked.emit()
				accept_event()
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			hovered = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			hovered = false
			queue_redraw()
	func _draw() -> void:
		if ammo == null:
			return
		var r := Rect2(Vector2.ZERO, size)
		var bg: Color = Color("#f4e4bc") if enabled else Color("#b9a98a")
		var border: Color = Color("#e74c3c") if selected else Color("#3b2a1a")
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(4 if selected else 3)
		sb.set_corner_radius_all(12)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 2)
		draw_style_box(sb, Rect2(Vector2(0, -6.0 if selected else (-2.0 if hovered else 0.0)), size))
		var off: float = -6.0 if selected else (-2.0 if hovered else 0.0)
		var c := Vector2(size.x * 0.5, 36.0 + off)
		_draw_icon(c, enabled)
		var f: Font = UITheme.font_bold()
		var cnt: String = "inf" if count < 0 else "x" + str(count)
		if count < 0:
			cnt = "∞"
		var w: float = f.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(f, Vector2(size.x * 0.5 - w * 0.5, 76.0 + off), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#3b2a1a"))
		var key: String = str(ammo.slot)
		draw_circle(Vector2(12, 12 + off), 9.0, Color("#3b2a1a"))
		var kw: float = f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(f, Vector2(12 - kw * 0.5, 17 + off), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f4e4bc"))
		if count == 0:
			# locked: a padlock until the weapon has been earned
			var lc := Vector2(size.x - 16.0, 16.0 + off)
			draw_arc(lc + Vector2(0, -1), 6.0, PI, TAU, 10, Color("#3b2a1a"), 3.0, true)
			draw_rect(Rect2(lc + Vector2(-8, 0), Vector2(16, 12)), Color("#3b2a1a"))
			draw_circle(lc + Vector2(0, 6), 2.0, Color("#f4e4bc"))
	func _draw_icon(c: Vector2, on: bool) -> void:
		var col: Color = ammo.color if on else ammo.color.darkened(0.5)
		var dark := Color("#1a1220")
		match ammo.id:
			"stone":
				draw_circle(c, 19.0, dark)
				draw_circle(c, 16.0, col)
				draw_circle(c + Vector2(-5, -5), 4.0, col.lightened(0.3))
			"boulder":
				draw_circle(c, 23.0, dark)
				draw_circle(c, 20.0, col)
				draw_circle(c + Vector2(-7, -7), 6.0, col.lightened(0.25))
				draw_circle(c + Vector2(7, 6), 4.5, col.darkened(0.25))
				draw_circle(c + Vector2(-5, 9), 3.0, col.darkened(0.2))
			"powderkeg":
				draw_rect(Rect2(c + Vector2(-15, -19), Vector2(30, 38)), dark)
				draw_rect(Rect2(c + Vector2(-12, -16), Vector2(24, 32)), col)
				draw_rect(Rect2(c + Vector2(-12, -8), Vector2(24, 4)), Color("#7f8c9a"))
				draw_rect(Rect2(c + Vector2(-12, 6), Vector2(24, 4)), Color("#7f8c9a"))
			"firebarrel":
				draw_rect(Rect2(c + Vector2(-14, -16), Vector2(28, 34)), dark)
				draw_rect(Rect2(c + Vector2(-11, -13), Vector2(22, 28)), Color("#8a5a2a") if on else Color("#4a3a2a"))
				draw_rect(Rect2(c + Vector2(-11, -6), Vector2(22, 4)), Color("#3a3a44"))
				draw_rect(Rect2(c + Vector2(-11, 6), Vector2(22, 4)), Color("#3a3a44"))
				var fl2 := PackedVector2Array([c + Vector2(-8, -14), c + Vector2(-2, -30), c + Vector2(2, -20), c + Vector2(6, -28), c + Vector2(9, -14)])
				draw_colored_polygon(fl2, col)
			"scatter":
				draw_circle(c, 18.0, dark)
				draw_circle(c, 15.0, col)
				for p in [Vector2(-6, -4), Vector2(5, -6), Vector2(0, 5), Vector2(-7, 7), Vector2(8, 4)]:
					draw_circle(c + (p as Vector2), 3.5, Color("#5a4a30"))
			"cow":
				draw_rect(Rect2(c + Vector2(-17, -12), Vector2(34, 24)), dark)
				draw_rect(Rect2(c + Vector2(-15, -10), Vector2(30, 20)), col)
				draw_rect(Rect2(c + Vector2(-9, -8), Vector2(9, 8)), Color("#2b2b33"))
				draw_rect(Rect2(c + Vector2(4, 0), Vector2(8, 7)), Color("#2b2b33"))
			"beehive":
				for i in 4:
					var w2: float = 30.0 - abs(float(i) - 1.5) * 6.0
					draw_rect(Rect2(c + Vector2(-w2 * 0.5 - 1, -20 + float(i) * 10 - 1), Vector2(w2 + 2, 12)), dark)
					draw_rect(Rect2(c + Vector2(-w2 * 0.5, -20 + float(i) * 10), Vector2(w2, 10)), col if i % 2 == 0 else col.darkened(0.15))
			"powdertrail":
				for kx in [-13, 0, 13]:
					draw_rect(Rect2(c + Vector2(float(kx) - 6, -12), Vector2(12, 18)), dark)
					draw_rect(Rect2(c + Vector2(float(kx) - 4.5, -10.5), Vector2(9, 15)), Color("#5a4f44") if on else Color("#3a3a3a"))
					draw_rect(Rect2(c + Vector2(float(kx) - 4.5, -5), Vector2(9, 2.5)), Color("#9aa2ad"))
				for dx in [-16, -7, 4, 14]:
					draw_circle(c + Vector2(float(dx), 12 + (dx % 3)), 3.0, Color("#1a1a1e"))
			"redkeg":
				draw_rect(Rect2(c + Vector2(-17, -20), Vector2(34, 42)), dark)
				draw_rect(Rect2(c + Vector2(-14, -17), Vector2(28, 36)), col)
				draw_rect(Rect2(c + Vector2(-14, -9), Vector2(28, 5)), Color("#2b2b33"))
				draw_rect(Rect2(c + Vector2(-14, 8), Vector2(28, 5)), Color("#2b2b33"))
				draw_circle(c + Vector2(0, 0), 5.0, Color("#f7f0e0"))
				draw_rect(Rect2(c + Vector2(-3, 3), Vector2(6, 4)), Color("#f7f0e0"))
		var f: Font = UITheme.font_bold()
		var w: float = f.get_string_size(ammo.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, c + Vector2(-w * 0.5, 30), ammo.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#3b2a1a"))

## Clickable catapult selector (also reachable with Tab / Shift+Tab)
class CatSelect extends Control:
	signal picked(cat: Catapult)
	var cats: Array = []
	var sel: Catapult = null
	func _init() -> void:
		custom_minimum_size = Vector2(260, 46)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				var i: int = int((mb.position.x - 4.0) / 50.0)
				if i >= 0 and i < cats.size() and is_instance_valid(cats[i]) and not (cats[i] as Catapult).destroyed:
					picked.emit(cats[i] as Catapult)
					accept_event()
	func _draw() -> void:
		var f: Font = UITheme.font_bold()
		for i in cats.size():
			var valid: bool = is_instance_valid(cats[i])
			var c: Catapult = (cats[i] as Catapult) if valid else null
			var alive: bool = valid and not c.destroyed
			var x: float = 4.0 + float(i) * 50.0
			var r := Rect2(x, 2, 44, 38)
			var chosen: bool = alive and c == sel
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("#f4e4bc") if alive else Color("#7a6a55")
			sb.border_color = Color("#e74c3c") if chosen else Color("#3b2a1a")
			sb.set_border_width_all(4 if chosen else 2)
			sb.set_corner_radius_all(8)
			draw_style_box(sb, r)
			var col: Color = Color("#2ecc71") if alive else Color("#c0392b")
			draw_rect(Rect2(x + 12, 14, 20, 10), Color("#1a1220"))
			draw_rect(Rect2(x + 13, 15, 18, 8), col)
			draw_circle(Vector2(x + 16, 26), 3.0, Color("#1a1220"))
			draw_circle(Vector2(x + 28, 26), 3.0, Color("#1a1220"))
			var t: String = str(i + 1)
			draw_string(f, Vector2(x + 18, 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#3b2a1a"))

class CatIcons extends Control:
	var alive: int = 0
	var total: int = 5
	func _init() -> void:
		custom_minimum_size = Vector2(88, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for i in total:
			var x: float = 2.0 + float(i) * 17.0
			var col: Color = Color("#2ecc71") if i < alive else Color("#e74c3c")
			draw_rect(Rect2(x, 4, 13, 8), Color("#1a1220"))
			draw_rect(Rect2(x + 1, 5, 11, 6), col)
			draw_circle(Vector2(x + 3, 13), 2.2, Color("#1a1220"))
			draw_circle(Vector2(x + 10, 13), 2.2, Color("#1a1220"))

# ------------------------------------------------------------------ state
var turn_panel: PanelContainer
var turn_chip: ColorRect
var turn_name: Label
var timer_ring: TimerRing
var players_panel: PanelContainer
var players_box: VBoxContainer
var wind_widget: WindWidget
var wind_label: Label
var weather_label: Label
var ammo_box: HBoxContainer
var ammo_slots: Array[AmmoSlot] = []
var aim_panel: PanelContainer
var aim_labels: Dictionary = {}
var banner: Label
var banner_panel: PanelContainer
var feed_box: VBoxContainer
var toast_label: Label
var btn_overview: Button
var btn_skip: Button
var btn_sound: Button
var skip_bar: ProgressBar
var _banner_tween: Tween
var _feed_items: Array[Dictionary] = []
var _skip_hold: float = 0.0
var _toast_t: float = 0.0
var _dirty_players: bool = true
var _players_sig: String = ""
var hint_label: Label
var _distance_label: Label
var btn_fast: Button
var cat_select: CatSelect
var overview_on: bool = false
var fast_on: bool = false
var last_tab_pressed: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.build()
	_build()
	Events.banner.connect(_on_banner)
	Events.toast.connect(_on_toast)
	Events.kill_feed.connect(_on_feed)
	Events.turn_start.connect(func(_id: int) -> void: _dirty_players = true)
	Events.turn_end.connect(func(_id: int) -> void: _dirty_players = true)
	Events.catapult_destroyed.connect(func(_id: int, _s: Dictionary, _r: String) -> void: _dirty_players = true)
	Events.player_eliminated.connect(func(_id: int) -> void: _dirty_players = true)
	Events.language_changed.connect(func() -> void: _rebuild_texts())
	visible = false

func _build() -> void:
	# ---- top center: turn panel
	turn_panel = PanelContainer.new()
	turn_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_panel.anchor_left = 0.5
	turn_panel.anchor_right = 0.5
	turn_panel.offset_left = -270
	turn_panel.offset_right = 270
	turn_panel.offset_top = 10
	turn_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(turn_panel)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_panel.add_child(th)
	turn_chip = ColorRect.new()
	turn_chip.custom_minimum_size = Vector2(22, 34)
	th.add_child(turn_chip)
	turn_name = UITheme.label("", 26, UITheme.INK, true)
	turn_name.custom_minimum_size = Vector2(420, 0)
	turn_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	th.add_child(turn_name)
	timer_ring = TimerRing.new()
	th.add_child(timer_ring)
	# ---- top left: players
	players_panel = PanelContainer.new()
	players_panel.position = Vector2(12, 10)
	add_child(players_panel)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 3)
	players_panel.add_child(players_box)
	# ---- top right: wind + weather + pause
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -238
	right.offset_right = -12
	right.offset_top = 10
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(right)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 10)
	right.add_child(rh)
	wind_widget = WindWidget.new()
	rh.add_child(wind_widget)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(rv)
	wind_label = UITheme.label("", 18, UITheme.INK, true)
	rv.add_child(wind_label)
	weather_label = UITheme.label("", 15, Color("#6b4a2a"))
	rv.add_child(weather_label)
	var pb: Button = UITheme.button("II", "ParchButton", Vector2(40, 32), 16)
	pb.pressed.connect(func() -> void: pause_pressed.emit())
	rh.add_child(pb)
	# ---- bottom center: ammo bar
	var ab := PanelContainer.new()
	ab.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ab.anchor_left = 0.5
	ab.anchor_right = 0.5
	ab.anchor_top = 1.0
	ab.anchor_bottom = 1.0
	ab.offset_top = -132
	ab.offset_bottom = -10
	ab.offset_left = -330
	ab.offset_right = 330
	ab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ab.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(ab)
	ammo_box = HBoxContainer.new()
	ammo_box.add_theme_constant_override("separation", 6)
	ammo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ab.add_child(ammo_box)
	for a in AmmoDef.all():
		var slot := AmmoSlot.new()
		slot.ammo = a
		var aid: String = a.id
		slot.clicked.connect(func() -> void: ammo_clicked.emit(aid))
		slot.tooltip_text = I18n.t("ammo." + a.id) + "\n" + I18n.t("ammo_desc." + a.id)
		ammo_box.add_child(slot)
		ammo_slots.append(slot)
	# ---- bottom left: aim info
	aim_panel = PanelContainer.new()
	aim_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	aim_panel.anchor_top = 1.0
	aim_panel.anchor_bottom = 1.0
	aim_panel.offset_left = 12
	aim_panel.offset_top = -132
	aim_panel.offset_bottom = -10
	aim_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(aim_panel)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 2)
	aim_panel.add_child(av)
	for key in ["power", "elevation", "azimuth"]:
		var l: Label = UITheme.label("", 18, UITheme.INK, true)
		l.custom_minimum_size = Vector2(200, 0)
		av.add_child(l)
		aim_labels[key] = l
	_distance_label = UITheme.label("", 15, Color("#6b4a2a"))
	av.add_child(_distance_label)
	# ---- bottom right: buttons
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.anchor_left = 1.0
	br.anchor_right = 1.0
	br.anchor_top = 1.0
	br.anchor_bottom = 1.0
	br.offset_left = -240
	br.offset_right = -12
	br.offset_top = -176
	br.offset_bottom = -10
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.add_theme_constant_override("separation", 6)
	add_child(br)
	btn_fast = UITheme.button("", "ParchButton", Vector2(0, 36), 15)
	btn_fast.pressed.connect(func() -> void: fast_pressed.emit())
	br.add_child(btn_fast)
	cat_select = CatSelect.new()
	cat_select.anchor_left = 1.0
	cat_select.anchor_right = 1.0
	cat_select.anchor_top = 1.0
	cat_select.anchor_bottom = 1.0
	cat_select.offset_left = -272
	cat_select.offset_right = -12
	cat_select.offset_top = -228
	cat_select.offset_bottom = -182
	cat_select.picked.connect(func(c: Catapult) -> void:
		if Turn.phase == Turn.Phase.AIMING and Game.cur() != null and Game.cur().is_human():
			Turn.select_catapult(c)
			Sfx.play("ui_click", Vector3.INF, 0.7, 0))
	add_child(cat_select)
	btn_overview = UITheme.button("", "GoldButton", Vector2(0, 36), 15)
	btn_overview.pressed.connect(func() -> void: overview_pressed.emit())
	br.add_child(btn_overview)
	btn_skip = UITheme.button("", "ParchButton", Vector2(0, 36), 15)
	btn_skip.button_down.connect(func() -> void: _skip_hold = 0.001)
	btn_skip.button_up.connect(func() -> void: _skip_hold = 0.0)
	br.add_child(btn_skip)
	skip_bar = ProgressBar.new()
	skip_bar.custom_minimum_size = Vector2(0, 8)
	skip_bar.show_percentage = false
	skip_bar.max_value = 1.0
	skip_bar.visible = false
	br.add_child(skip_bar)
	btn_sound = UITheme.button("", "ParchButton", Vector2(0, 36), 15)
	btn_sound.pressed.connect(func() -> void:
		Settings.volume = 0.0 if Settings.volume > 0.01 else 0.8
		Settings.apply_volume()
		_rebuild_texts())
	br.add_child(btn_sound)
	# ---- announcer banner (center)
	banner_panel = PanelContainer.new()
	banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_panel.anchor_left = 0.5
	banner_panel.anchor_right = 0.5
	banner_panel.offset_top = 128
	banner_panel.z_index = 20
	banner_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_panel.visible = false
	banner_panel.add_theme_stylebox_override("panel", UITheme.box(Color("#3b2a1a"), Color("#ffd400"), 3, 16, 8))
	add_child(banner_panel)
	banner = UITheme.label("", 44, Color("#ffd400"), true, 10)
	banner.custom_minimum_size = Vector2(900, 0)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_theme_font_override("font", ComicText.comic_font())
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_panel.add_child(banner)
	# ---- kill feed (left)
	feed_box = VBoxContainer.new()
	feed_box.position = Vector2(12, 190)
	feed_box.add_theme_constant_override("separation", 3)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed_box)
	# ---- toast + hint
	toast_label = UITheme.label("", 18, Color.WHITE, true, 8)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_top = -172
	toast_label.offset_bottom = -140
	toast_label.offset_left = -400
	toast_label.offset_right = 400
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_label)
	hint_label = UITheme.label("", 15, Color(1, 1, 1, 0.9), false, 6)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_top = -224
	hint_label.offset_bottom = -176
	hint_label.offset_left = -480
	hint_label.offset_right = 480
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)
	_rebuild_texts()

func _rebuild_texts() -> void:
	if btn_overview == null:
		return
	btn_overview.text = I18n.t("hud.overview")
	btn_fast.text = I18n.t("hud.fast_btn")
	btn_skip.text = I18n.t("hud.skip")
	btn_sound.text = I18n.t("hud.sound_off") if Settings.volume <= 0.01 else I18n.t("hud.sound_on")
	for s in ammo_slots:
		s.tooltip_text = I18n.t("ammo." + s.ammo.id) + "\n" + I18n.t("ammo_desc." + s.ammo.id)
	_dirty_players = true

# ------------------------------------------------------------------ events
func _on_banner(text: String, kind: String) -> void:
	if not visible and kind != "win":
		pass
	banner.text = text
	banner_panel.visible = true
	banner_panel.modulate = Color(1, 1, 1, 1)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	var start_y: float = banner_panel.offset_top
	banner_panel.offset_top = start_y - 60.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_panel, "offset_top", start_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(2.1)
	_banner_tween.tween_property(banner_panel, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(func() -> void:
		banner_panel.visible = false
		banner_panel.offset_top = start_y)

func _on_toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 4.0

func _on_feed(text: String) -> void:
	var l: Label = UITheme.label(text, 15, Color.WHITE, false, 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.add_child(l)
	_feed_items.append({"node": l, "t": 4.0})
	while _feed_items.size() > 5:
		var old: Dictionary = _feed_items.pop_front()
		(old["node"] as Node).queue_free()

# ------------------------------------------------------------------ per-frame
func _update_players() -> void:
	for c in players_box.get_children():
		c.queue_free()
	for p in Game.players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var cur := Label.new()
		cur.custom_minimum_size = Vector2(14, 0)
		cur.text = ">" if p.id == Game.current_player and not p.eliminated else ""
		cur.add_theme_color_override("font_color", UITheme.RED)
		cur.add_theme_font_override("font", UITheme.font_bold())
		row.add_child(cur)
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(14, 20)
		chip.color = p.color
		row.add_child(chip)
		var n: Label = UITheme.label(p.name, 15, UITheme.INK if not p.eliminated else Color(0.5, 0.4, 0.3), p.id == Game.current_player)
		n.custom_minimum_size = Vector2(190, 0)
		n.clip_text = true
		if p.eliminated:
			n.text = p.name + "  (" + I18n.t("hud.eliminated") + ")"
		row.add_child(n)
		var ic := CatIcons.new()
		ic.alive = p.catapults_left()
		ic.total = Game.catapults_per_player
		row.add_child(ic)
		players_box.add_child(row)

func _process(delta: float) -> void:
	if not visible:
		return
	# rebuild the player list whenever a catapult count / elimination changes (never trust a single event)
	var sig: String = ""
	for pl in Game.players:
		sig += "%d%s%d|" % [pl.catapults_left(), "x" if pl.eliminated else "o", 1 if pl.id == Game.current_player else 0]
	if sig != _players_sig:
		_players_sig = sig
		_dirty_players = true
	if _dirty_players:
		_dirty_players = false
		_update_players()
	var p: PlayerData = Game.cur()
	if p != null:
		turn_chip.color = p.color
		turn_name.text = I18n.t("hud.turn", {"name": p.name})
		# timer
		var show_timer: bool = Turn.timer_on and Turn.phase == Turn.Phase.AIMING
		timer_ring.visible_ring = show_timer
		timer_ring.modulate.a = 1.0 if show_timer else 0.0
		if show_timer:
			timer_ring.frac = clampf(Turn.time_left / maxf(float(Game.turn_timer), 1.0), 0.0, 1.0)
			timer_ring.seconds = int(ceil(maxf(Turn.time_left, 0.0)))
		timer_ring.queue_redraw()
		# ammo bar
		var human_turn: bool = p.is_human()
		for s in ammo_slots:
			var c: int = p.ammo_count(s.ammo.id)
			s.count = c
			s.enabled = c != 0 and human_turn
			s.selected = s.ammo.id == Turn.aim_ammo and Turn.phase != Turn.Phase.TURN_START
			s.modulate.a = 1.0 if c != 0 else 0.6
			s.queue_redraw()
		# aim info
		(aim_labels["power"] as Label).text = "%s: %d%%" % [I18n.t("hud.power"), int(round(Turn.aim_power * 100.0))]
		(aim_labels["elevation"] as Label).text = "%s: %d°" % [I18n.t("hud.elevation"), int(round(Turn.aim_elev))]
		var az: float = fposmod(rad_to_deg(Turn.aim_yaw), 360.0)
		(aim_labels["azimuth"] as Label).text = "%s: %d°" % [I18n.t("hud.azimuth"), int(round(az))]
		if Turn.phase == Turn.Phase.AIMING and Turn.sel != null and not p.is_cpu():
			var v: Vector3 = Turn.current_velocity()
			var tr: Dictionary = Turn.predict_trajectory(Turn.launch_origin(Turn.sel, Turn.aim_elev, Turn.aim_yaw), v, Turn.aim_ammo, Game.wind, 12.0)
			var txt: String = ""
			var d: float = 0.0
			if Turn.aim_power > 0.05:
				d = Util.dist_xz(Turn.sel.global_pos(), tr["landing"] as Vector3)
				txt = I18n.t("hud.distance", {"d": int(round(d))})
			if p.marker != Vector3.INF:
				txt += ("\n" if txt != "" else "") + Aiming.marker_text(Turn.sel.global_pos(), p.marker, Turn.aim_yaw, d if Turn.aim_power > 0.05 else -1.0)
			_distance_label.text = txt
		else:
			_distance_label.text = ""
		var aiming_human: bool = Turn.phase == Turn.Phase.AIMING and not p.is_cpu()
		aim_panel.visible = aiming_human or p.is_human()
		var aftermath: bool = Turn.phase == Turn.Phase.AFTERMATH and not overview_on
		hint_label.visible = aiming_human or overview_on or aftermath
		if aftermath:
			hint_label.text = I18n.t("hud.skip_hint")
		elif overview_on:
			hint_label.text = I18n.t("hud.overview_hint")
		elif aiming_human:
			hint_label.text = I18n.t("hud.aim_hint") + "   |   " + I18n.t("hud.aim_hint_keys")
	btn_fast.modulate = Color(1, 0.85, 0.3) if fast_on else Color.WHITE
	var cs_p: PlayerData = Game.cur()
	cat_select.visible = cs_p != null and cs_p.is_human() and Turn.phase == Turn.Phase.AIMING and cs_p.catapults.size() > 1
	if cat_select.visible:
		cat_select.cats = cs_p.catapults
		cat_select.sel = Turn.sel
		cat_select.queue_redraw()
	# wind + weather
	wind_widget.wind = Game.wind
	wind_widget.cam_yaw = _cam_yaw()
	wind_widget.queue_redraw()
	wind_label.text = "%s %.1f m/s" % [I18n.t("hud.wind"), Game.wind.length()]
	weather_label.text = I18n.t("hud.weather_" + Game.weather)
	# skip button (hold X)
	if Input.is_key_pressed(KEY_X) and Turn.phase == Turn.Phase.AIMING and p != null and p.is_human():
		_skip_hold = maxf(_skip_hold, 0.001) + delta
	elif not btn_skip.button_pressed:
		_skip_hold = 0.0
	skip_bar.visible = _skip_hold > 0.0
	skip_bar.value = clampf(_skip_hold / 2.0, 0.0, 1.0)
	if _skip_hold >= 2.0:
		_skip_hold = 0.0
		skip_requested.emit()
	# toast / feed timers
	if _toast_t > 0.0:
		_toast_t -= delta
		toast_label.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
	else:
		toast_label.text = ""
	var i: int = _feed_items.size() - 1
	while i >= 0:
		var it: Dictionary = _feed_items[i]
		it["t"] = float(it["t"]) - delta
		var lab: Label = it["node"] as Label
		if float(it["t"]) <= 0.0:
			lab.queue_free()
			_feed_items.remove_at(i)
		else:
			lab.modulate.a = clampf(float(it["t"]) / 0.6, 0.0, 1.0)
		i -= 1

func _cam_yaw() -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var f: Vector3 = -cam.global_transform.basis.z
	return atan2(f.x, -f.z)

func show_state(state: int) -> void:
	visible = state == Game.State.BATTLE
	_dirty_players = true
