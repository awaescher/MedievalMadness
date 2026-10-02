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
	visible = false

func show_results(winner: int, replay_available: bool) -> void:
	_winner = winner
	has_replay = replay_available
	for c in get_children():
		c.queue_free()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.03, 0.08, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1060, 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	# header: winner + crown
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	if winner >= 0:
		var wp: PlayerData = Game.player(winner)
		head.add_child(_crown(wp.color))
		var col := VBoxContainer.new()
		head.add_child(col)
		var crew_names: Array[String] = []
		for tm in Game.team_members(wp.team):
			crew_names.append(tm.name)
		var t: Label = UITheme.label(I18n.t("banner.team_win", {"names": " + ".join(crew_names)}) if crew_names.size() > 1 else I18n.t("banner.win", {"name": wp.name}), 40, Color("#ffd400"), true, 10)
		t.add_theme_font_override("font", ComicText.comic_font())
		col.add_child(t)
		var crown_titles: Array = I18n.tr_list("title.crown")
		var ct: String = str(crown_titles[Rng.new(Rng.fnv1a(Game.seed_str)).range_i(0, crown_titles.size() - 1)]) if not crown_titles.is_empty() else ""
		var sub: Label = UITheme.label(ct, 22, UITheme.INK, true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
		head.add_child(_crown(wp.color))
	else:
		var t2: Label = UITheme.label(I18n.t("banner.everybody_loses"), 44, Color("#e74c3c"), true, 10)
		t2.add_theme_font_override("font", ComicText.comic_font())
		head.add_child(t2)
	# stats table
	var titles: Array = Scoring.compute_titles(winner)
	var title_map: Dictionary = {}
	for tt in titles:
		var td: Dictionary = tt as Dictionary
		var pid: int = int(td["player_id"])
		if not title_map.has(pid):
			title_map[pid] = []
		(title_map[pid] as Array).append(I18n.t("title." + str(td["title_id"])))
	var ranking: Array[PlayerData] = _ranking(winner)
	var grid := GridContainer.new()
	grid.columns = 13
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var heads: Array[String] = ["rank", "player", "points", "shots", "hits", "damage", "launched", "killed", "catapults", "buildings", "fires", "longest", "left"]
	for hd in heads:
		var hl: Label = UITheme.label(I18n.t("stats." + hd), 14, UITheme.RED, true)
		grid.add_child(hl)
	for i in ranking.size():
		var p: PlayerData = ranking[i]
		var st: PlayerData.Stats = p.stats
		var cells: Array = [str(i + 1), p.name, Hud._fmt_points(p.points), str(st.shots), str(st.hits), Util.format_int(int(st.damage_dealt)), str(st.settlers_launched), str(st.settlers_killed),
			str(st.catapults_destroyed), str(st.buildings_destroyed), str(st.fires_started), I18n.t("stats.unit_m", {"d": int(st.longest_shot)}), str(p.catapults_left())]
		for ci in cells.size():
			var l: Label = UITheme.label(str(cells[ci]), 16, p.color.darkened(0.3) if ci == 1 else UITheme.INK, ci == 1 or p.id == winner)
			if ci == 1:
				l.custom_minimum_size = Vector2(230, 0)
				l.clip_text = true
			grid.add_child(l)
	# titles
	if not title_map.is_empty():
		v.add_child(UITheme.label(I18n.t("stats.titles"), 20, UITheme.RED, true))
		for p2 in ranking:
			if title_map.has(p2.id):
				var tl: Label = UITheme.label("%s: %s" % [p2.name, " / ".join(PackedStringArray(title_map[p2.id] as Array))], 16, UITheme.INK, false)
				v.add_child(tl)
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
