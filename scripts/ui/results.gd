class_name Results
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## GAME_OVER screen (spec 2.6 / 13): winner with confetti and a silly crown, ranking, stats table, titles.

signal rematch
signal same_map
signal main_menu

var panel: PanelContainer
var _confetti_timer: float = 0.0
var _winner: int = -1
var has_replay: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.build()
	Glass.watch(self)
	visible = false

## Joke explanation of a title (looked up by its translated name)
func tip_for(title_text: String) -> String:
	for k in ["cow_launcher", "pyro", "pacifist", "sniper", "fisherman", "destroyer", "settler_bowler", "self_own", "firefighter", "cheesemaster", "longshot", "survivor", "loser"]:
		if I18n.t("title." + k) == title_text:
			return I18n.t("title_tip." + k)
	return ""

func show_results(winner: int, replay_available: bool) -> void:
	_winner = winner
	has_replay = replay_available
	for c in get_children():
		c.queue_free()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.03, 0.08, 0.34)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var vp_w: float = get_viewport_rect().size.x
	panel = PanelContainer.new()
	Glass.dialog(panel, 22, Vector2(22, 18))
	panel.custom_minimum_size = Vector2(minf(1480.0, vp_w - 40.0), 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	# header: dark banner with winner + crowns, crown title below
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _row_style(Color(0.16, 0.10, 0.20, 0.72), Color("#ffd400") if winner >= 0 else Color("#e74c3c"), 2, 16, 12))
	v.add_child(banner)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 16)
	banner.add_child(head)
	if winner >= 0:
		var wp: PlayerData = Game.player(winner)
		head.add_child(_crown(wp.color))
		var crew_names: Array[String] = []
		for tm in Game.team_members(wp.team):
			crew_names.append(tm.name)
		var wtxt: String = I18n.t("banner.team_win", {"names": " + ".join(crew_names)}) if crew_names.size() > 1 else I18n.t("banner.win", {"name": wp.name})
		var t: Label = UITheme.label(wtxt, 40 if wtxt.length() < 44 else 30, Color("#ffd400"), true, 10)
		t.add_theme_font_override("font", ComicText.comic_font())
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		head.add_child(_crown(wp.color))
		var crown_titles: Array = I18n.tr_list("title.crown")
		var ct: String = str(crown_titles[Rng.new(Rng.fnv1a(Game.seed_str)).range_i(0, crown_titles.size() - 1)]) if not crown_titles.is_empty() else ""
		var sub: Label = UITheme.label(ct, 24, UITheme.INK, true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sub)
	else:
		var t2: Label = UITheme.label(I18n.t("banner.everybody_loses"), 44, Color("#e74c3c"), true, 10)
		t2.add_theme_font_override("font", ComicText.comic_font())
		head.add_child(t2)
	# titles per player
	var titles: Array = Scoring.compute_titles(winner)
	var title_map: Dictionary = {}
	for tt in titles:
		var td: Dictionary = tt as Dictionary
		var pid: int = int(td["player_id"])
		if not title_map.has(pid):
			title_map[pid] = []
		(title_map[pid] as Array).append(I18n.t("title." + str(td["title_id"])))
	var ranking: Array[PlayerData] = _ranking(winner)
	# stats table: header row + one card per player, fixed column widths so numbers line up
	var cols: Array[Dictionary] = [
		{"k": "points", "w": 104}, {"k": "shots", "w": 66}, {"k": "hits", "w": 66}, {"k": "damage", "w": 96}, {"k": "launched", "w": 104},
		{"k": "killed", "w": 80}, {"k": "catapults", "w": 84}, {"k": "buildings", "w": 84}, {"k": "fires", "w": 62}, {"k": "longest", "w": 124}, {"k": "left", "w": 62}]
	var best: Array[float] = []
	for c in cols:
		best.append(0.0)
	var rows_vals: Array = []
	for p0 in ranking:
		var s0: PlayerData.Stats = p0.stats
		var vals: Array[float] = [float(p0.points), float(s0.shots), float(s0.hits), s0.damage_dealt, float(s0.settlers_launched), float(s0.settlers_killed),
			float(s0.catapults_destroyed), float(s0.buildings_destroyed), float(s0.fires_started), s0.longest_shot, float(p0.catapults_left())]
		rows_vals.append(vals)
		for ci in vals.size():
			best[ci] = maxf(best[ci], vals[ci])
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 12)
	hm.add_theme_constant_override("margin_right", 12)
	hm.add_child(hdr)
	v.add_child(hm)
	hdr.add_child(_cell(I18n.t("stats.rank"), 44, 14, Color("#7a5a36"), true, HORIZONTAL_ALIGNMENT_CENTER))
	var hn: Label = _cell(I18n.t("stats.player"), 0, 14, Color("#7a5a36"), true, HORIZONTAL_ALIGNMENT_LEFT)
	hn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hn.custom_minimum_size = Vector2(150, 0)
	hdr.add_child(hn)
	for c in cols:
		hdr.add_child(_cell(I18n.t("stats." + str(c["k"])), int(c["w"]), 13, Color("#7a5a36"), true, HORIZONTAL_ALIGNMENT_RIGHT))
	var wteam: int = Game.player(winner).team if Game.player(winner) != null else -1
	var count_labels: Array = []
	var row_nodes: Array[Control] = []
	for i in ranking.size():
		var p: PlayerData = ranking[i]
		var is_win: bool = winner >= 0 and p.team == wteam
		var card := PanelContainer.new()
		var bg: Color = Color(1.0, 0.86, 0.45, 0.55) if is_win else Color(1, 1, 1, 0.30 if i % 2 == 0 else 0.20)
		card.add_theme_stylebox_override("panel", _row_style(bg, Color(1, 1, 1, 0.55) if is_win else Color(0, 0, 0, 0), 1 if is_win else 0, 12, 7))
		v.add_child(card)
		row_nodes.append(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		card.add_child(cv)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 4)
		cv.add_child(r)
		r.add_child(_medal(i + 1, is_win))
		var nb := HBoxContainer.new()
		nb.add_theme_constant_override("separation", 8)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size = Vector2(150, 0)
		var sw := ColorRect.new()
		sw.color = p.color
		sw.custom_minimum_size = Vector2(10, 28)
		nb.add_child(sw)
		var nl: Label = UITheme.label(p.name, 20, p.color.darkened(0.45), true)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(nl)
		r.add_child(nb)
		var vals2: Array = rows_vals[i]
		for ci in cols.size():
			var val: float = vals2[ci]
			var is_best: bool = best[ci] > 0.0 and is_equal_approx(val, best[ci]) and ci != 1 and ci != 10
			var txt: String
			match ci:
				0: txt = Hud._fmt_points(int(val))
				3: txt = Util.format_int(int(val))
				9: txt = I18n.t("stats.unit_m", {"d": int(val)})
				_: txt = str(int(val))
			var cl: Label = _cell(txt, int(cols[ci]["w"]), 18 if ci == 0 else 16, Color("#b45f06") if is_best else UITheme.INK, is_best or ci == 0, HORIZONTAL_ALIGNMENT_RIGHT)
			if ci == 0:
				count_labels.append([cl, int(val)])
			r.add_child(cl)
		if title_map.has(p.id):
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 4)
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 48)
			pad.add_child(flow)
			cv.add_child(pad)
			for tn in (title_map[p.id] as Array):
				var chip := PanelContainer.new()
				chip.add_theme_stylebox_override("panel", _row_style(Color("#e8943a"), Color("#8a4b0a"), 2, 10, 3))
				var cl2: Label = UITheme.label("★ " + str(tn), 14, Color("#ffffff"), true, 4, Color("#6a3a05"))
				chip.add_child(cl2)
				chip.tooltip_text = tip_for(str(tn))
				chip.mouse_filter = Control.MOUSE_FILTER_STOP
				flow.add_child(chip)
		if not is_win and winner >= 0:
			card.modulate = Color(1, 1, 1, 0.92)
	# buttons
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	v.add_child(UITheme.vspacer(6))
	v.add_child(h)
	var b1: Button = UITheme.dialog_button(I18n.t("stats.rematch"), "GreenButton", 210.0)
	b1.pressed.connect(func() -> void: rematch.emit())
	b1.visible = not Net.active
	h.add_child(b1)
	var b2: Button = UITheme.dialog_button(I18n.t("stats.same_map"), "RedButton", 210.0)
	b2.pressed.connect(func() -> void: same_map.emit())
	b2.visible = not Net.active
	h.add_child(b2)
	var b3: Button = UITheme.dialog_button(I18n.t("stats.main_menu"), "ParchButton", 210.0)
	b3.pressed.connect(func() -> void: main_menu.emit())
	h.add_child(b3)
	if winner >= 0:
		_confetti_timer = 0.0
	_animate_in(row_nodes, count_labels)

func _panel_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = UITheme.box(UITheme.PARCH, UITheme.INK, 4, 20, 16)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	return sb

func _row_style(bg: Color, border: Color, bw: int, radius: int, vpad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = vpad
	sb.content_margin_bottom = vpad
	return sb

func _cell(text: String, w: int, size: int, col: Color, bold: bool, align: HorizontalAlignment) -> Label:
	var l: Label = UITheme.label(text, size, col, bold)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(w, 0)
	return l

## Round rank badge: gold / silver / bronze for the first three, plain number below.
func _medal(rank: int, is_win: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(44, 40)
	c.draw.connect(func() -> void:
		var cols: Array[Color] = [Color("#ffd700"), Color("#c9d1d9"), Color("#cd7f32")]
		var ctr := Vector2(22, 20)
		if rank <= 3:
			c.draw_circle(ctr, 17.0, cols[rank - 1])
			c.draw_arc(ctr, 17.0, 0.0, TAU, 28, Color("#1a1220"), 3.0, true)
		var f: Font = UITheme.font_bold()
		var s: String = str(rank)
		var sz: Vector2 = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		c.draw_string(f, ctr + Vector2(-sz.x * 0.5, 7.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.INK if rank <= 3 or is_win else Color(UITheme.INK, 0.7)))
	return c

## Pop the panel in, fade the rows in one after another and count the points up.
func _animate_in(rows: Array[Control], counts: Array) -> void:
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size * 0.5)
	panel.pivot_offset = panel.size * 0.5
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in rows.size():
		var r: Control = rows[i]
		var target: float = r.modulate.a
		r.modulate.a = 0.0
		var rt: Tween = create_tween()
		rt.tween_interval(0.25 + 0.12 * i)
		rt.tween_property(r, "modulate:a", target, 0.25)
	for entry in counts:
		var lbl: Label = (entry as Array)[0]
		var total: int = int((entry as Array)[1])
		lbl.text = Hud._fmt_points(0)
		var ct: Tween = create_tween()
		ct.tween_interval(0.35)
		ct.tween_method(func(x: float) -> void: lbl.text = Hud._fmt_points(int(x)), 0.0, float(total), 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func hide_results() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in get_children():
		c.queue_free()

func _ranking(winner: int) -> Array[PlayerData]:
	var arr: Array[PlayerData] = Game.players.duplicate()
	var wteam: int = Game.player(winner).team if Game.player(winner) != null else -1
	arr.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var aw: bool = a.team == wteam
		var bw: bool = b.team == wteam
		if aw != bw:
			return aw
		if a.eliminated != b.eliminated:
			return not a.eliminated
		if a.eliminated and b.eliminated:
			return a.eliminated_order > b.eliminated_order
		return a.catapults_left() > b.catapults_left())
	return arr

func _crown(col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(70, 60)
	c.draw.connect(func() -> void:
		var gold := Color("#ffd700")
		var dark := Color("#1a1220")
		var pts := PackedVector2Array([Vector2(6, 52), Vector2(6, 20), Vector2(22, 34), Vector2(35, 8), Vector2(48, 34), Vector2(64, 20), Vector2(64, 52)])
		c.draw_colored_polygon(pts, gold)
		c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[5], pts[6], pts[0]]), dark, 3.0, true)
		c.draw_rect(Rect2(6, 46, 58, 8), col)
		c.draw_rect(Rect2(6, 46, 58, 8), dark, false, 2.0)
		for p in [Vector2(6, 20), Vector2(35, 8), Vector2(64, 20)]:
			c.draw_circle(p as Vector2, 5.0, Color("#e74c3c"))
			c.draw_arc(p as Vector2, 5.0, 0.0, TAU, 12, dark, 2.0))
	return c

func _process(delta: float) -> void:
	if not visible or _winner < 0:
		return
	_confetti_timer -= delta
	if _confetti_timer <= 0.0:
		_confetti_timer = 1.4
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			var f: Vector3 = -cam.global_transform.basis.z
			Fx.burst("confetti", cam.global_position + f * 12.0 + Vector3(0, 6, 0) + cam.global_transform.basis.x * randf_range(-6, 6), Color(0, 0, 0, -1), 1.0, Vector3.UP)
