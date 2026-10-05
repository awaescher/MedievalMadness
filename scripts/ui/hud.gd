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
signal offer_toggled(id: String, on: bool)

# ------------------------------------------------------------------ small custom controls
class TimerRing extends Control:
	var frac: float = 1.0
	var seconds: int = 0
	var visible_ring: bool = true
	var urgent: bool = false          # the last 5 seconds: the ring flashes red
	var col: Color = Color("#2ecc71")
	func _init() -> void:
		custom_minimum_size = Vector2(54, 54)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if not visible_ring:
			return
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 4.0
		var flash: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.018) if urgent else 0.0
		draw_circle(c, r + 3.0 + flash * 2.0, Color("#e74c3c") if urgent else Color(0.15, 0.1, 0.06))
		draw_circle(c, r, Color("#fff6da").lerp(Color("#ff8a7a"), flash))
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
	var gift_from: String = ""         # a team mate offers this weapon for this turn
	var icon_only: bool = false        # draw only the icon (no frame, key or count): used in the menus
	signal clicked
	func _init() -> void:
		custom_minimum_size = Vector2(52, 52)
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
	## Compact tooltip: name, one line what it is, then short advantages (+) and drawbacks (-)
	func _make_custom_tooltip(for_text: String) -> Object:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var ink := Color("#3b2a1a")
		v.add_child(_tip_line(I18n.t("ammo." + for_text), 15, ink, true))
		var what: String = I18n.t("ammo_tip." + for_text + ".what")
		if what != "ammo_tip." + for_text + ".what":
			v.add_child(_tip_line(what, 12, Color("#6b4a2a"), false))
		for pro in I18n.tr_list("ammo_tip." + for_text + ".pro"):
			v.add_child(_tip_line("+ " + str(pro), 12, Color("#2e7d32"), true))
		for con in I18n.tr_list("ammo_tip." + for_text + ".con"):
			v.add_child(_tip_line("- " + str(con), 12, Color("#b03a2e"), true))
		# locked: how to earn it in THIS match (depends on the game mode's rules)
		if count == 0 and ammo != null and not ammo.is_action() and ammo.earnable:
			v.add_child(_tip_line("🔒 " + I18n.t("hud.unlock_how"), 12, Color("#8a5a00"), true))
			for ln in Unlocks.how(for_text):
				v.add_child(_tip_line("• " + ln, 12, Color("#8a5a00"), false))
		if gift_from != "":
			v.add_child(_tip_line("🎁 " + I18n.t("gift.badge", {"name": gift_from}), 12, Color("#1f6f3a"), true))
		return v
	func _tip_line(text: String, size_px: int, col: Color, bold: bool) -> Label:
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", size_px)
		l.add_theme_color_override("font_color", col)
		if bold:
			l.add_theme_font_override("font", UITheme.font_bold())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(230, 0)
		return l
	const ICON_SCALE := 0.6
	func _draw() -> void:
		if ammo == null:
			return
		if icon_only:
			# just the weapon icon, scaled to the control (menus)
			var isc: float = size.x / 52.0 * 0.85
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(isc, isc))
			_draw_icon(size * 0.5 / isc - Vector2(0, 2), true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		var action: bool = ammo.is_action()
		var bg: Color = Color("#f4e4bc") if enabled else Color("#b9a98a")
		# weapons: slightly reddish rim, turn actions (relocate / build): grey rim
		var border: Color = Color("#9a4535") if not action else Color("#8a8a94")
		if selected:
			border = Color("#e74c3c") if not action else Color("#4a4a58")
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(3 if selected else 2)
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(0, 0, 0, 0.3)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
		var off: float = -5.0 if selected else (-2.0 if hovered else 0.0)
		draw_style_box(sb, Rect2(Vector2(0, off), size))
		var c := Vector2(size.x * 0.5 + 1.0, 21.0 + off) if not action else Vector2(size.x * 0.5 + 1.0, 25.0 + off)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(ICON_SCALE, ICON_SCALE))
		_draw_icon(c / ICON_SCALE, enabled)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var f: Font = UITheme.font_bold()
		if not action:
			var cnt: String = "∞" if count < 0 else "x" + str(count)
			var w: float = f.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(f, Vector2(size.x * 0.5 - w * 0.5, 47.0 + off), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#3b2a1a"))
		var key: String = ammo.key_label()
		draw_circle(Vector2(9, 9 + off), 7.0, Color("#3b2a1a"))
		var kw: float = f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(9 - kw * 0.5, 13.0 + off), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f4e4bc"))
		if gift_from != "":
			# a gift ribbon: small green box with a red bow
			var gc := Vector2(size.x - 12.0, 11.0 + off)
			draw_rect(Rect2(gc + Vector2(-7, -5), Vector2(14, 12)), Color("#2e9e52"))
			draw_rect(Rect2(gc + Vector2(-7, -5), Vector2(14, 12)), Color("#1a1220"), false, 1.5)
			draw_rect(Rect2(gc + Vector2(-1.5, -5), Vector2(3, 12)), Color("#ffd400"))
			draw_circle(gc + Vector2(-2.5, -7), 2.5, Color("#e74c3c"))
			draw_circle(gc + Vector2(2.5, -7), 2.5, Color("#e74c3c"))
		elif count == 0 and not action:
			# locked: a padlock until the weapon has been earned
			var lc := Vector2(size.x - 11.0, 11.0 + off)
			draw_arc(lc + Vector2(0, -1), 5.0, PI, TAU, 10, Color("#3b2a1a"), 2.5, true)
			draw_rect(Rect2(lc + Vector2(-6.5, 0), Vector2(13, 10)), Color("#3b2a1a"))
			draw_circle(lc + Vector2(0, 5), 1.7, Color("#f4e4bc"))
	# ---- icon helpers (all drawn with primitives; `_on` dims everything of a locked weapon)
	var _on: bool = true
	func _k(col: Color) -> Color:
		return col if _on else col.darkened(0.42).lerp(Color("#8a8070"), 0.35)
	func _ball(p: Vector2, r: float, base: Color) -> void:
		draw_circle(p, r + 2.0, Color("#1a1220"))
		draw_circle(p, r, _k(base))
		draw_arc(p, r - 2.0, 0.15, 1.75, 14, _k(base.darkened(0.35)), 3.5, true)
		draw_circle(p + Vector2(-r * 0.32, -r * 0.34), r * 0.3, _k(base.lightened(0.38)))
		draw_circle(p + Vector2(-r * 0.4, -r * 0.42), r * 0.1, _k(Color(1, 1, 1, 0.9)))
	func _ellipse(p: Vector2, rx: float, ry: float, col: Color, rot: float = 0.0) -> void:
		var pts := PackedVector2Array()
		for q in 18:
			var a: float = TAU * float(q) / 18.0
			pts.append(p + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
		draw_colored_polygon(pts, col)
	func _poly(pts: PackedVector2Array, fill: Color, outline: Color = Color("#1a1220"), w: float = 2.0) -> void:
		draw_colored_polygon(pts, _k(fill))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, outline, w, true)
	func _barrel_pts(p: Vector2, w: float, h: float, bulge: float) -> PackedVector2Array:
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for q in 9:
			var t: float = float(q) / 8.0
			var half: float = w * 0.5 * (1.0 + bulge * sin(PI * t))
			left.append(p + Vector2(-half, -h * 0.5 + h * t))
			right.append(p + Vector2(half, -h * 0.5 + h * t))
		right.reverse()
		left.append_array(right)
		return left
	func _barrel(p: Vector2, w: float, h: float, wood: Color, band: Color) -> void:
		_poly(_barrel_pts(p, w, h, 0.14), wood)
		# staves
		for sx in [-0.5, -0.17, 0.17, 0.5]:
			draw_line(p + Vector2(w * float(sx) * 0.9, -h * 0.46), p + Vector2(w * float(sx) * 1.0, h * 0.46), _k(wood.darkened(0.3)), 1.2)
		# iron bands
		for by in [-0.27, 0.27]:
			var yy: float = h * float(by)
			var half: float = w * 0.5 * (1.0 + 0.14 * sin(PI * (0.5 + float(by))))
			draw_rect(Rect2(p + Vector2(-half - 1.0, yy - 2.5), Vector2(half * 2.0 + 2.0, 5.0)), Color("#1a1220"))
			draw_rect(Rect2(p + Vector2(-half, yy - 1.5), Vector2(half * 2.0, 3.0)), _k(band))
		# soft highlight on the left stave
		draw_line(p + Vector2(-w * 0.32, -h * 0.4), p + Vector2(-w * 0.36, h * 0.4), _k(wood.lightened(0.3)), 2.0)
	func _spark(p: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for q in 8:
			var a: float = TAU * float(q) / 8.0
			var rr: float = r if q % 2 == 0 else r * 0.42
			pts.append(p + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, _k(col))
	func _draw_icon(c: Vector2, on: bool) -> void:
		_on = on
		var dark := Color("#1a1220")
		match ammo.id:
			"stone":
				_ball(c, 18.0, Color("#9a9aa4"))
				draw_line(c + Vector2(2, -9), c + Vector2(6, -2), _k(Color("#6e6e78")), 1.6)
				draw_line(c + Vector2(6, -2), c + Vector2(3, 4), _k(Color("#6e6e78")), 1.6)
				draw_circle(c + Vector2(-5, 8), 2.2, _k(Color("#7c7c86")))
			"quad":
				for q in [Vector2(-10, -9), Vector2(10, -11), Vector2(-12, 11), Vector2(9, 9)]:
					_ball(c + (q as Vector2), 9.5, Color("#9a9aa4"))
				# speed streaks
				for sy in [-14, -2, 8]:
					draw_line(c + Vector2(-27, float(sy)), c + Vector2(-21, float(sy)), _k(Color("#6a5a48")), 1.5)
			"chain":
				# whirling: faint circular streaks behind the balls
				draw_arc(c, 21.0, -0.6, 1.0, 12, _k(Color("#a8a8b4")), 1.5, true)
				draw_arc(c, 21.0, PI - 0.6, PI + 1.0, 12, _k(Color("#a8a8b4")), 1.5, true)
				for lk in 5:
					var lx: float = (float(lk) - 2.0) * 6.2
					if lk % 2 == 0:
						_ellipse(c + Vector2(lx, 0), 4.2, 2.6, dark)
						_ellipse(c + Vector2(lx, 0), 3.2, 1.7, _k(Color("#b4b4c0")))
					else:
						_ellipse(c + Vector2(lx, 0), 2.6, 4.0, dark)
						_ellipse(c + Vector2(lx, 0), 1.7, 3.0, _k(Color("#8e8e9a")))
				_ball(c + Vector2(-20, 3), 10.5, Color("#33333c"))
				_ball(c + Vector2(20, -3), 10.5, Color("#33333c"))
			"boulder":
				var rr: Array[float] = [21.0, 18.5, 22.0, 19.0, 21.5, 17.5, 20.5, 22.5, 18.0, 20.0]
				var bp := PackedVector2Array()
				for q in rr.size():
					var a: float = TAU * float(q) / float(rr.size()) - 0.4
					bp.append(c + Vector2(cos(a), sin(a)) * rr[q])
				_poly(bp, Color("#87878f"), dark, 2.5)
				var shade := PackedVector2Array()
				for q in range(3, 8):
					shade.append(bp[q])
				shade.append(c + Vector2(2, 3))
				draw_colored_polygon(shade, _k(Color("#5d5d66")))
				var hl := PackedVector2Array([c + Vector2(-14, -8), c + Vector2(-6, -17), c + Vector2(3, -14), c + Vector2(-4, -6)])
				draw_colored_polygon(hl, _k(Color("#b4b4bc")))
				draw_line(c + Vector2(4, -4), c + Vector2(10, 4), _k(Color("#4a4a52")), 1.8)
				draw_line(c + Vector2(-8, 4), c + Vector2(-2, 11), _k(Color("#4a4a52")), 1.8)
				draw_circle(c + Vector2(8, 11), 2.5, _k(Color("#70707a")))
			"log":
				draw_set_transform(c * ICON_SCALE, -0.32, Vector2(ICON_SCALE, ICON_SCALE))
				var lg := PackedVector2Array([Vector2(-26, 0), Vector2(-19, -8), Vector2(18, -8), Vector2(26, 0), Vector2(18, 8), Vector2(-19, 8)])
				_poly(lg, Color("#8a5a2f"), dark, 2.5)
				draw_colored_polygon(PackedVector2Array([Vector2(-19, -8), Vector2(18, -8), Vector2(18, -4), Vector2(-19, -4)]), _k(Color("#a9763f")))
				for bx in [-12, -2, 9]:
					draw_line(Vector2(float(bx), -2), Vector2(float(bx) + 4, 6), _k(Color("#5a3a1c")), 1.6)
				_poly(PackedVector2Array([Vector2(-26, 0), Vector2(-22, -4), Vector2(-19, -8), Vector2(-19, 8), Vector2(-22, 4)]), Color("#e0bd84"), dark, 1.5)
				_poly(PackedVector2Array([Vector2(26, 0), Vector2(22, -4), Vector2(18, -8), Vector2(18, 8), Vector2(22, 4)]), Color("#e0bd84"), dark, 1.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(ICON_SCALE, ICON_SCALE))
				# rotation arrows
				draw_arc(c + Vector2(0, -2), 25.0, -2.3, -0.9, 10, _k(Color("#6a5a48")), 1.6, true)
				draw_arc(c + Vector2(0, 2), 25.0, 0.85, 2.25, 10, _k(Color("#6a5a48")), 1.6, true)
			"firebarrel":
				_barrel(c + Vector2(0, 7), 25.0, 30.0, Color("#8a5a2a"), Color("#4a4a56"))
				# flames
				_poly(PackedVector2Array([c + Vector2(-11, -6), c + Vector2(-13, -17), c + Vector2(-6, -11), c + Vector2(-4, -25), c + Vector2(2, -13), c + Vector2(8, -22), c + Vector2(10, -12), c + Vector2(13, -7)]), Color("#e8401c"), dark, 2.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -7), c + Vector2(-5, -15), c + Vector2(0, -10), c + Vector2(3, -17), c + Vector2(6, -8)]), _k(Color("#ff9a2a")))
				draw_colored_polygon(PackedVector2Array([c + Vector2(-3, -7), c + Vector2(0, -12), c + Vector2(3, -7)]), _k(Color("#ffe27a")))
			"powderkeg":
				_barrel(c + Vector2(0, 4), 26.0, 32.0, Color("#3c3c46"), Color("#8a95a3"))
				# skull on the barrel
				draw_circle(c + Vector2(0, 2), 6.0, _k(Color("#f4f0e4")))
				draw_rect(Rect2(c + Vector2(-3.5, 6), Vector2(7, 5)), _k(Color("#f4f0e4")))
				draw_circle(c + Vector2(-2.4, 1.5), 1.7, dark)
				draw_circle(c + Vector2(2.4, 1.5), 1.7, dark)
				# fuse with a spark
				draw_arc(c + Vector2(5, -14), 6.0, PI * 0.5, PI * 1.5, 8, _k(Color("#d8b25a")), 2.0, true)
				_spark(c + Vector2(5, -22), 5.5, Color("#ffcf3a"))
			"scatter":
				# a cloth sack tied at the neck, pellets bursting out of it
				var sack := PackedVector2Array([c + Vector2(-17, 18), c + Vector2(-21, 6), c + Vector2(-15, -4), c + Vector2(-9, -8), c + Vector2(-3, -4), c + Vector2(3, 6), c + Vector2(0, 18)])
				_poly(sack, Color("#cdaa68"), dark, 2.2)
				draw_line(c + Vector2(-17, 12), c + Vector2(-9, 4), _k(Color("#a8864a")), 1.5)
				draw_rect(Rect2(c + Vector2(-13, -8), Vector2(8, 4)), dark)
				draw_rect(Rect2(c + Vector2(-12, -7), Vector2(6, 2)), _k(Color("#8a5a2a")))
				for pe in [Vector2(6, -14), Vector2(14, -6), Vector2(19, -17), Vector2(12, -21), Vector2(22, 0), Vector2(8, -2)]:
					_ball(c + (pe as Vector2), 3.6, Color("#8d8d98"))
				draw_line(c + Vector2(4, -10), c + Vector2(0, -6), _k(Color("#6a5a48")), 1.4)
			"cow":
				# the cow's head, front view: curved horns, leaf ears with pink insides, a dark patch around one eye,
				# a big pink muzzle with nostrils and a straight mouth
				var cw := Color("#f4f1e8")
				var cp := Color("#f2b6b6")
				var ck := Color("#2b2b33")
				for sx in [-1.0, 1.0]:
					var sgn: float = sx as float
					var horn := PackedVector2Array([c + Vector2(10.0 * sgn, -16), c + Vector2(17.0 * sgn, -21), c + Vector2(23.0 * sgn, -23), c + Vector2(27.0 * sgn, -29)])
					draw_polyline(horn, dark, 7.5, true)
					draw_polyline(horn, _k(Color("#efe3bd")), 4.2, true)
					var ear: Vector2 = c + Vector2(23.0 * sgn, -7)
					_ellipse(ear, 12.0, 6.8, dark, 0.5 * sgn)
					_ellipse(ear, 10.0, 5.0, _k(ck if sgn < 0.0 else cw), 0.5 * sgn)
					_ellipse(ear + Vector2(-1.0 * sgn, 0.6), 5.8, 2.5, _k(cp), 0.5 * sgn)
				_ellipse(c + Vector2(0, -3), 17.8, 22.0, dark)
				_ellipse(c + Vector2(0, -3), 16.0, 20.2, _k(cw))
				_ellipse(c + Vector2(8, -9), 7.6, 8.8, _k(ck))
				_ellipse(c + Vector2(-9, -15), 4.5, 3.0, _k(ck), -0.4)
				_ellipse(c + Vector2(0, -20), 7.5, 3.4, _k(Color("#e4dfcf")))
				for ex in [-8.0, 8.0]:
					draw_circle(c + Vector2(ex as float, -8), 3.8, dark)
					draw_circle(c + Vector2((ex as float) - 1.0, -9.3), 1.2, Color(1, 1, 1, 0.92))
				_ellipse(c + Vector2(0, 13), 14.2, 10.6, dark)
				_ellipse(c + Vector2(0, 13), 12.6, 9.1, _k(cp))
				_ellipse(c + Vector2(-4.5, 8.5), 4.5, 2.0, _k(Color("#f9d6d6")))
				for nx in [-5.0, 5.0]:
					_ellipse(c + Vector2(nx as float, 11), 2.4, 3.2, dark)
				draw_line(c + Vector2(-7, 18.6), c + Vector2(7, 18.6), dark, 2.0, true)
			"powdertrail":
				# a row of three small kegs and the black trail they leave
				for kx in [-17, 0, 17]:
					_barrel(c + Vector2(float(kx), -3), 13.0, 19.0, Color("#5a4f44"), Color("#9aa2ad"))
				draw_polyline(PackedVector2Array([c + Vector2(-26, 15), c + Vector2(-16, 12), c + Vector2(-6, 16), c + Vector2(4, 12), c + Vector2(14, 16), c + Vector2(24, 12)]), dark, 4.5, true)
				for dx in [-22, -12, -1, 9, 19]:
					draw_circle(c + Vector2(float(dx), 14 + (dx % 3)), 2.3, _k(Color("#3a3a42")))
				_spark(c + Vector2(26, 9), 5.0, Color("#ffcf3a"))
			"drillbomb":
				# a round bomb with an amber band, a lit fuse and a steel drill below, boring into the ground
				_poly(PackedVector2Array([c + Vector2(-23, 25), c + Vector2(-12, 21), c + Vector2(0, 25), c + Vector2(12, 21), c + Vector2(23, 25), c + Vector2(23, 29), c + Vector2(-23, 29)]), Color("#7a5a3a"))
				_poly(PackedVector2Array([c + Vector2(-9, 4), c + Vector2(9, 4), c + Vector2(0, 25)]), Color("#aab2bc"))
				for ry in [8.0, 13.0, 18.0]:
					var hw: float = 9.0 * (25.0 - ry) / 21.0
					draw_line(c + Vector2(-hw, ry + 2.0), c + Vector2(hw, ry - 2.0), _k(Color("#5a626c")), 1.6)
				draw_rect(Rect2(c + Vector2(-11, 1), Vector2(22, 5)), Color("#1a1220"))
				draw_rect(Rect2(c + Vector2(-9.5, 2), Vector2(19, 3)), _k(Color("#6d7683")))
				_ball(c + Vector2(0, -9), 14.0, Color("#33333c"))
				draw_rect(Rect2(c + Vector2(-13, -11), Vector2(26, 5)), _k(Color("#c9962a")))
				draw_arc(c + Vector2(6, -27), 6.0, PI * 0.5, PI * 1.5, 8, _k(Color("#d8b25a")), 2.0, true)
				_spark(c + Vector2(6, -33), 5.0, Color("#ffcf3a"))
				# soil flying up
				for dp in [Vector2(-17, 18), Vector2(-21, 12), Vector2(18, 17), Vector2(22, 11)]:
					draw_circle(c + (dp as Vector2), 2.2, _k(Color("#8a6d4a")))
			"relocate":
				# catapult on wheels with drive arrows
				draw_rect(Rect2(c + Vector2(-17, 2), Vector2(34, 7)), dark)
				draw_rect(Rect2(c + Vector2(-15.5, 3.5), Vector2(31, 4)), _k(Color("#b5763a")))
				draw_line(c + Vector2(-3, 3), c + Vector2(11, -20), dark, 5.0)
				draw_line(c + Vector2(-3, 3), c + Vector2(11, -20), _k(Color("#c58a4a")), 2.6)
				_ellipse(c + Vector2(13, -22), 5.5, 3.0, _k(Color("#8a5a2a")))
				for wx in [-11, 11]:
					draw_circle(c + Vector2(float(wx), 11), 7.5, dark)
					draw_circle(c + Vector2(float(wx), 11), 5.5, _k(Color("#8a5a2a")))
					draw_circle(c + Vector2(float(wx), 11), 1.8, _k(Color("#7f8c9a")))
				_poly(PackedVector2Array([c + Vector2(-26, 24), c + Vector2(-17, 19), c + Vector2(-17, 29)]), Color("#6a6a76"))
				_poly(PackedVector2Array([c + Vector2(26, 24), c + Vector2(17, 19), c + Vector2(17, 29)]), Color("#6a6a76"))
			"wall":
				# stone wall with crenellations
				for mx in [-20, -4, 12]:
					_poly(PackedVector2Array([c + Vector2(float(mx), -4), c + Vector2(float(mx), -15), c + Vector2(float(mx) + 9, -15), c + Vector2(float(mx) + 9, -4)]), Color("#8a9096"), dark, 2.0)
				_poly(PackedVector2Array([c + Vector2(-23, -4), c + Vector2(23, -4), c + Vector2(23, 23), c + Vector2(-23, 23)]), Color("#9aa0a6"), dark, 2.5)
				for ry in [4, 13]:
					draw_line(c + Vector2(-23, float(ry)), c + Vector2(23, float(ry)), _k(Color("#6e747a")), 1.5)
				for bx in [-8, 8]:
					draw_line(c + Vector2(float(bx), -4), c + Vector2(float(bx), 4), _k(Color("#6e747a")), 1.5)
					draw_line(c + Vector2(float(bx) + 8, 4), c + Vector2(float(bx) + 8, 13), _k(Color("#6e747a")), 1.5)
					draw_line(c + Vector2(float(bx), 13), c + Vector2(float(bx), 23), _k(Color("#6e747a")), 1.5)
			"meteor":
				# green marker orb with a thin beam into the sky, a pulsing ring and a burning meteor on its way
				draw_rect(Rect2(c + Vector2(-3.5, -27), Vector2(7, 36)), _k(Color(0.45, 1.0, 0.7, 0.22)))
				draw_rect(Rect2(c + Vector2(-1.2, -27), Vector2(2.4, 36)), _k(Color(0.85, 1.0, 0.92, 0.9)))
				_ellipse(c + Vector2(0, 14), 18.0, 5.5, _k(Color(0.2, 1.0, 0.5, 0.35)))
				_ellipse(c + Vector2(0, 14), 12.0, 3.4, _k(Color(0.3, 1.0, 0.6, 0.45)))
				draw_circle(c + Vector2(0, 8), 12.0, _k(Color(0.2, 1.0, 0.5, 0.28)))
				_ball(c + Vector2(0, 8), 7.5, Color("#35ff86"))
				# the falling meteor
				draw_polyline(PackedVector2Array([c + Vector2(20, -22), c + Vector2(15, -15), c + Vector2(11, -9)]), _k(Color(1.0, 0.7, 0.25, 0.6)), 7.0, true)
				draw_circle(c + Vector2(21, -23), 5.0, dark)
				draw_circle(c + Vector2(21, -23), 3.6, _k(Color("#ff7a1a")))
				draw_circle(c + Vector2(20, -24), 1.5, _k(Color("#ffe27a")))

## One compact line of "what can I do now": [key cap] label  [key cap] label ... on a parchment strip
class KeyHints extends Control:
	signal chip_pressed(id: String)
	var items: Array = []          # [[key, label, optional click id], ...]; key "" = plain note
	var _sig: String = ""
	var _hits: Array = []          # [[Rect2, id]] of the clickable chips (only those catch the mouse)
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _has_point(point: Vector2) -> bool:
		for h in _hits:
			if ((h as Array)[0] as Rect2).has_point(point):
				return true
		return false
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			for h in _hits:
				if ((h as Array)[0] as Rect2).has_point((ev as InputEventMouseButton).position):
					chip_pressed.emit(str((h as Array)[1]))
					accept_event()
					return
		custom_minimum_size = Vector2(0, 34)
	func set_items(list: Array) -> void:
		var sig: String = str(list)
		if sig == _sig:
			return
		_sig = sig
		items = list
		queue_redraw()
	func _draw() -> void:
		if items.is_empty():
			return
		var f: Font = UITheme.font_bold()
		var fs: int = 14
		var total: float = 8.0
		for it in items:
			var key: String = str((it as Array)[0])
			var lab: String = str((it as Array)[1])
			var kw: float = (maxf(f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0, 22.0)) if key != "" else 0.0
			total += kw + (6.0 if key != "" else 0.0) + f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
		var x0: float = (size.x - total) * 0.5
		var strip := StyleBoxFlat.new()
		strip.bg_color = Color("#f4e4bc")
		strip.border_color = Color("#3b2a1a")
		strip.set_border_width_all(2)
		strip.set_corner_radius_all(10)
		strip.shadow_color = Color(0, 0, 0, 0.3)
		strip.shadow_size = 3
		draw_style_box(strip, Rect2(Vector2(x0, 2), Vector2(total, size.y - 6)))
		var x: float = x0 + 12.0
		var cy: float = 2.0 + (size.y - 6.0) * 0.5
		_hits.clear()
		for i in items.size():
			var key2: String = str((items[i] as Array)[0])
			var lab2: String = str((items[i] as Array)[1])
			if key2 != "":
				var tw: float = f.get_string_size(key2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				var kw2: float = maxf(tw + 14.0, 22.0)
				var cap := StyleBoxFlat.new()
				cap.bg_color = Color("#3b2a1a")
				cap.set_corner_radius_all(6)
				draw_style_box(cap, Rect2(Vector2(x, cy - 10.0), Vector2(kw2, 20.0)))
				draw_string(f, Vector2(x + (kw2 - tw) * 0.5, cy + 4.5), key2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f4e4bc"))
				x += kw2 + 6.0
			draw_string(f, Vector2(x, cy + 5.0), lab2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#3b2a1a"))
			var lw: float = f.get_string_size(lab2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if (items[i] as Array).size() > 2:
				_hits.append([Rect2(Vector2(x - (maxf(f.get_string_size(key2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0, 22.0) + 6.0 if key2 != "" else 0.0) - 3.0, cy - 13.0), Vector2(lw + 12.0 + (maxf(f.get_string_size(key2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0, 22.0) + 6.0 if key2 != "" else 0.0), 26.0)), str((items[i] as Array)[2])])
			x += lw + 16.0

## Clickable catapult selector (also reachable with Tab / Shift+Tab)
class CatSelect extends Control:
	signal picked(cat: Catapult)
	var cats: Array = []
	var sel: Catapult = null
	func _init() -> void:
		custom_minimum_size = Vector2(260, 46)
		mouse_filter = Control.MOUSE_FILTER_STOP
	## right-aligned with the buttons below
	func _x0() -> float:
		return size.x - float(cats.size()) * 50.0 + 2.0
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				var i: int = int(floor((mb.position.x - _x0()) / 50.0))
				if i >= 0 and i < cats.size() and is_instance_valid(cats[i]) and not (cats[i] as Catapult).destroyed:
					picked.emit(cats[i] as Catapult)
					accept_event()
	func _draw() -> void:
		var f: Font = UITheme.font_bold()
		for i in cats.size():
			var valid: bool = is_instance_valid(cats[i])
			var c: Catapult = (cats[i] as Catapult) if valid else null
			var alive: bool = valid and not c.destroyed
			var x: float = _x0() + float(i) * 50.0
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
var offer_box: PanelContainer
var offer_slots: Array[AmmoSlot] = []
var offer_label: Label
var aim_panel: PanelContainer
var aim_labels: Dictionary = {}
const BANNER_TOP := 128.0
var banner: Label
var banner_panel: PanelContainer
var feed_box: VBoxContainer
var toast_label: Label
var btn_overview: Button
var btn_skip: KeyButton
var btn_sound: Button
var skip_bar: ProgressBar
var _banner_tween: Tween
var _feed_items: Array[Dictionary] = []
var _skip_hold: float = 0.0
var _toast_t: float = 0.0
var _dirty_players: bool = true
var _players_sig: String = ""
var hint_label: Label
var countdown: Label
var _last_tick: int = -1
var hints: KeyHints
var _distance_label: Label
var btn_fast: KeyButton
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
	Events.points_awarded.connect(_on_points)
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
	ab.offset_top = -76
	ab.offset_bottom = -10
	ab.offset_left = -330
	ab.offset_right = 330
	ab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ab.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(ab)
	ammo_box = HBoxContainer.new()
	ammo_box.add_theme_constant_override("separation", 4)
	ammo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ab.add_child(ammo_box)
	for a in AmmoDef.all():
		var slot := AmmoSlot.new()
		slot.ammo = a
		var aid: String = a.id
		slot.clicked.connect(func() -> void: ammo_clicked.emit(aid))
		slot.tooltip_text = a.id          # the real text is built in AmmoSlot._make_custom_tooltip
		ammo_box.add_child(slot)
		ammo_slots.append(slot)
	# ---- bottom left: offer weapons to a team mate who is on turn
	offer_box = PanelContainer.new()
	offer_box.anchor_top = 1.0
	offer_box.anchor_bottom = 1.0
	offer_box.offset_left = 12
	offer_box.offset_top = -214
	offer_box.offset_bottom = -140
	offer_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	offer_box.visible = false
	add_child(offer_box)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 2)
	offer_box.add_child(ov)
	offer_label = UITheme.label("", 14, UITheme.INK, true)
	ov.add_child(offer_label)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 4)
	ov.add_child(orow)
	for oa in AmmoDef.all():
		if oa.is_action() or oa.id == "stone":
			continue
		var os := AmmoSlot.new()
		os.ammo = oa
		os.custom_minimum_size = Vector2(44, 52)
		var oid: String = oa.id
		os.clicked.connect(func() -> void: offer_toggled.emit(oid, not (Turn.gifts.get(oid, -1) == (Game.viewer().id if Game.viewer() != null else -2))))
		os.tooltip_text = oa.id
		orow.add_child(os)
		offer_slots.append(os)
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
	br.offset_left = -188
	br.offset_right = -10
	br.offset_top = -150
	br.offset_bottom = -8
	br.alignment = BoxContainer.ALIGNMENT_END
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.add_theme_constant_override("separation", 6)
	add_child(br)
	btn_fast = KeyButton.new()
	btn_fast.pressed.connect(func() -> void: fast_pressed.emit())
	br.add_child(btn_fast)
	cat_select = CatSelect.new()
	cat_select.anchor_left = 1.0
	cat_select.anchor_right = 1.0
	cat_select.anchor_top = 1.0
	cat_select.anchor_bottom = 1.0
	cat_select.offset_left = -272
	cat_select.offset_right = -12
	cat_select.offset_top = -204
	cat_select.offset_bottom = -158
	cat_select.picked.connect(func(c: Catapult) -> void:
		if Turn.phase == Turn.Phase.AIMING and Game.cur() != null and Game.cur().is_human():
			Turn.select_catapult(c)
			Sfx.play("ui_click", Vector3.INF, 0.7, 0))
	add_child(cat_select)
	btn_overview = UITheme.button("", "ParchButton", Vector2(0, 32), 14)
	btn_overview.pressed.connect(func() -> void: overview_pressed.emit())
	# (the overview lives as a clickable chip in the hint strip; this button only keeps the text helper alive)
	btn_skip = KeyButton.new()
	btn_skip.button_down.connect(func() -> void: _skip_hold = 0.001)
	btn_skip.button_up.connect(func() -> void: _skip_hold = 0.0)
	br.add_child(btn_skip)
	skip_bar = ProgressBar.new()
	skip_bar.custom_minimum_size = Vector2(0, 8)
	skip_bar.show_percentage = false
	skip_bar.max_value = 1.0
	skip_bar.visible = false
	br.add_child(skip_bar)
	btn_sound = UITheme.button("", "ParchButton", Vector2(0, 32), 14)
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
	banner_panel.offset_top = BANNER_TOP
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
	hint_label.visible = false
	# the last 5 seconds of a turn: a big red number in the middle of the screen
	countdown = UITheme.label("", 150, Color("#ff3b2e"), true, 16)
	countdown.add_theme_font_override("font", ComicText.comic_font())
	countdown.set_anchors_preset(Control.PRESET_CENTER_TOP)
	countdown.anchor_left = 0.5
	countdown.anchor_right = 0.5
	countdown.offset_left = -120
	countdown.offset_right = 120
	countdown.offset_top = 150
	countdown.offset_bottom = 340
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown.pivot_offset = Vector2(120, 95)
	countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown.visible = false
	add_child(countdown)
	hints = KeyHints.new()
	hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hints.anchor_left = 0.5
	hints.anchor_right = 0.5
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = -520
	hints.offset_right = 520
	hints.offset_top = -118
	hints.offset_bottom = -84
	hints.visible = false
	hints.chip_pressed.connect(func(id: String) -> void:
		if id == "overview":
			overview_pressed.emit()
		elif id == "skip":
			Turn.skip_aftermath())
	add_child(hints)
	_rebuild_texts()

func _rebuild_texts() -> void:
	if btn_overview == null:
		return
	btn_overview.text = I18n.t("hud.overview")
	btn_fast.set_content(I18n.t("hud.key_fast"), I18n.t("hud.fast_btn"))
	btn_skip.set_content(I18n.t("hud.key_skip"), I18n.t("hud.skip"))
	btn_sound.text = I18n.t("hud.sound_off") if Settings.volume <= 0.01 else I18n.t("hud.sound_on")
	_dirty_players = true

# ------------------------------------------------------------------ events
## The offer strip: shown to a team mate while the player whose turn it is could use one of their weapons
func _update_gifts(cur: PlayerData) -> void:
	var v: PlayerData = Game.viewer()
	var show: bool = Net.active and v != null and v.id != cur.id and v.is_ally(cur) and not v.eliminated and Turn.phase == Turn.Phase.AIMING
	offer_box.visible = show
	if not show:
		return
	offer_label.text = I18n.t("gift.title", {"name": cur.name})
	for s in offer_slots:
		var c: int = v.ammo_count(s.ammo.id)
		var mine: bool = int(Turn.gifts.get(s.ammo.id, -1)) == v.id
		s.count = c
		s.selected = mine
		s.visible = c > 0
		s.enabled = c > 0 and (mine or not Turn.gifts.has(s.ammo.id))
		s.queue_redraw()

func _on_banner(text: String, kind: String) -> void:
	if not visible and kind != "win":
		pass
	banner.text = text
	banner_panel.visible = true
	banner_panel.modulate = Color(1, 1, 1, 1)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	var start_y: float = BANNER_TOP          # (always the same: a banner arriving mid-animation must not drift upwards)
	banner_panel.offset_top = start_y - 60.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_panel, "offset_top", start_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(2.1)
	_banner_tween.tween_property(banner_panel, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(func() -> void:
		banner_panel.visible = false
		banner_panel.offset_top = start_y)

static func _fmt_points(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += "."
		out += s[i]
	return ("-" if n < 0 else "") + out

func _on_points(pid: int, pts: int, text: String) -> void:
	var p: PlayerData = Game.player(pid)
	if p == null:
		return
	var l: Label = UITheme.label("%s%d  %s  (%s)" % ["+" if pts > 0 else "", pts, text, p.name], 16, Color("#ffe27a") if pts > 0 else Color("#ff8a7a"), true, 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.add_child(l)
	_feed_items.append({"node": l, "t": 5.0})
	while _feed_items.size() > 6:
		var old: Dictionary = _feed_items.pop_front()
		(old["node"] as Node).queue_free()

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
		var pts: Label = UITheme.label(_fmt_points(p.points), 15, Color("#8a5a00"), true)
		pts.custom_minimum_size = Vector2(62, 0)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pts)
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
		sig += "%d%s%d,%d|" % [pl.catapults_left(), "x" if pl.eliminated else "o", 1 if pl.id == Game.current_player else 0, pl.points]
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
		var warn: bool = show_timer and Turn.time_left <= 5.0 and Turn.time_left > 0.0 and p.is_human()
		timer_ring.urgent = warn
		countdown.visible = warn
		if warn:
			var sec: int = int(ceil(Turn.time_left))
			var into: float = 1.0 - (Turn.time_left - floor(Turn.time_left))      # 0..1 within the current second
			countdown.text = str(sec)
			countdown.scale = Vector2.ONE * (1.0 + 0.5 * (1.0 - into) * (1.0 - into))
			countdown.modulate.a = 1.0 - 0.5 * into
			if sec != _last_tick:
				_last_tick = sec
				Sfx.play("clack", Vector3.INF, 0.9, 3)
		else:
			_last_tick = -1
		timer_ring.queue_redraw()
		# ammo bar
		var human_turn: bool = p.is_human()
		for s in ammo_slots:
			var c: int = p.ammo_count(s.ammo.id)
			var giver: PlayerData = Game.player(int(Turn.gifts.get(s.ammo.id, -1)))
			s.gift_from = giver.name if giver != null else ""
			if giver != null and c >= 0:
				c += 1                       # the offered unit counts for this turn
			s.count = c
			s.enabled = c != 0 and human_turn
			s.selected = s.ammo.id == Turn.aim_ammo and Turn.phase != Turn.Phase.TURN_START
			s.modulate.a = 1.0 if c != 0 else 0.6
			s.queue_redraw()
		_update_gifts(p)
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
			if Game.marker_for(p) != Vector3.INF:
				txt += ("\n" if txt != "" else "") + Aiming.marker_text(Turn.sel.global_pos(), Game.marker_for(p), Turn.aim_yaw, d if Turn.aim_power > 0.05 else -1.0)
			_distance_label.text = txt
		else:
			_distance_label.text = ""
		var aiming_human: bool = Turn.phase == Turn.Phase.AIMING and not p.is_cpu()
		aim_panel.visible = (aiming_human or p.is_human()) and Turn.action_mode() == ""
		var aftermath: bool = Turn.phase == Turn.Phase.AFTERMATH and not overview_on
		var list: Array = _hint_items(aiming_human, aftermath)
		hints.visible = not list.is_empty()
		hints.set_items(list)
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

## What the player can do right now (short, same key-cap style everywhere)
func _hint_items(aiming_human: bool, aftermath: bool) -> Array:
	if aftermath:
		return [[I18n.t("hint.k_click_space"), I18n.t("hint.next_turn"), "skip"], ["V", I18n.t("hint.overview"), "overview"]]
	if overview_on:
		return [[I18n.t("hint.k_click"), I18n.t("hint.marker")], [I18n.t("hint.k_rmb"), I18n.t("hint.camera")], ["V", I18n.t("hint.back"), "overview"]]
	if not aiming_human:
		return [["V", I18n.t("hint.overview"), "overview"]] if Game.state == Game.State.BATTLE else []
	match Turn.action_mode():
		"relocate":
			return [["W/S", I18n.t("hint.drive")], ["A/D", I18n.t("hint.steer")], [I18n.t("hint.k_space"), I18n.t("hint.done")], ["", I18n.t("hint.driven", {"u": int(round(Turn.move_used))})], ["1-9", I18n.t("hint.weapon")], ["V", I18n.t("hint.overview"), "overview"]]
		"wall":
			return [[I18n.t("hint.k_click"), I18n.t("hint.build")], ["Q/E", I18n.t("hint.turn")], [I18n.t("hint.k_on_wall"), I18n.t("hint.stack")], ["1-9", I18n.t("hint.weapon")], ["V", I18n.t("hint.overview"), "overview"]]
	return [[I18n.t("hint.k_drag"), I18n.t("hint.fire")], ["Q/E", I18n.t("hint.turn")], ["↑↓", I18n.t("hint.elevation")], ["Tab", I18n.t("hint.catapult")], ["R", I18n.t("hint.enemy")], ["M", I18n.t("hint.marker_key")], ["V", I18n.t("hint.overview"), "overview"]]

func _cam_yaw() -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var f: Vector3 = -cam.global_transform.basis.z
	return atan2(f.x, -f.z)

func show_state(state: int) -> void:
	visible = state == Game.State.BATTLE
	_dirty_players = true
