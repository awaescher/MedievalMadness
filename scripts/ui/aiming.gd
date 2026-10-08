class_name Aiming
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Human aiming (spec 6.1): slingshot drag anywhere. The launch heading is the *screen-true* direction opposite to the pull
## (the chase camera is frozen while pulling), elevation is separate (arrows / Shift+wheel). Trajectory preview, rubber-band
## overlay, map marker compass (6.7). Also camera orbit / zoom in AIM mode.

signal fired

var cam: CameraRig
var world_root: Node3D
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_cur: Vector2 = Vector2.ZERO
var _preview: MultiMeshInstance3D
var _preview_mm: MultiMesh
var _ring: MeshInstance3D
var _key_acc: float = 0.0
var _click_start: Vector2 = Vector2.ZERO
var _orbiting: bool = false
var _last_power: float = 0.0
var _release_flash: float = 0.0
var overview_active: bool = false
var enabled_for_input: bool = true
var _overlay_on: bool = false
var _trim: float = 0.0              # Q/E correction added to the screen-true heading while a pull is in progress

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_preview()

func _build_preview() -> void:
	_preview_mm = MultiMesh.new()
	_preview_mm.transform_format = MultiMesh.TRANSFORM_3D
	_preview_mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	sphere.radial_segments = 8
	sphere.rings = 4
	_preview_mm.mesh = sphere
	_preview_mm.instance_count = 40
	_preview_mm.visible_instance_count = 0
	_preview = MultiMeshInstance3D.new()
	_preview.multimesh = _preview_mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	_preview.material_override = m
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.extra_cull_margin = 300.0
	_preview.visible = false

func attach_preview(root: Node3D) -> void:
	world_root = root
	if _preview.get_parent() == null:
		root.add_child(_preview)

func _scale() -> float:
	return maxf(get_viewport().get_visible_rect().size.y / 900.0, 0.5)

func _human_aiming() -> bool:
	if Game.state != Game.State.BATTLE or Turn.phase != Turn.Phase.AIMING:
		return false
	var p: PlayerData = Game.cur()
	return p != null and p.is_human() and enabled_for_input and not overview_active

func cancel_drag() -> void:
	if dragging:
		dragging = false
		cam.aim_hold = false
		Turn.set_aim(Turn.aim_yaw, Turn.aim_elev, 0.0)
		queue_redraw()

## World heading (yaw) that the screen direction `dir2` (normalized, y down) points to when seen from the catapult.
func _yaw_from_screen(dir2: Vector2) -> float:
	var base: Vector3 = Turn.sel.global_pos()
	var sp: Vector2 = cam.project(base)
	var flat: Vector3 = Vector3.ZERO
	# shorter and shorter probes until the ray reaches the ground plane (a straight line on screen is a straight line on the ground)
	for px in [140.0, 70.0, 35.0, 16.0, 8.0]:
		var q: Vector2 = sp + dir2 * float(px) * _scale()
		var ray: Dictionary = cam.ray_from_screen(q)
		var o: Vector3 = ray["origin"] as Vector3
		var d: Vector3 = ray["dir"] as Vector3
		if d.y < -0.004:
			var t: float = (base.y - o.y) / d.y
			flat = Util.flat(o + d * t - base)
			if flat.length() > 0.05 and t > 0.0:
				break
			flat = Vector3.ZERO
	if flat.length() < 0.05:
		var cb: Basis = cam.cam.global_transform.basis
		var f: Vector3 = Util.flat(-cb.z).normalized()
		var r: Vector3 = Util.flat(cb.x).normalized()
		flat = f * (-dir2.y) + r * dir2.x
	return Util.dir_to_yaw(flat)

## Screen position of a point `meters` away from the catapult along `yaw` (for the faithful direction arrow)
func _yaw_tip(yaw: float, pixels: float) -> Vector2:
	var base: Vector3 = Turn.sel.global_pos() + Vector3(0, 0.6, 0)
	var dir: Vector3 = Util.yaw_to_dir(yaw)
	var sp: Vector2 = cam.project(base)
	var k: float = 10.0
	for i in 4:
		var tip: Vector2 = cam.project(base + dir * k)
		var l: float = tip.distance_to(sp)
		if l >= pixels * 0.5 or k > 160.0:
			break
		k *= maxf(pixels / maxf(l, 4.0), 1.6)
	return cam.project(base + dir * k)

## "Marker 142 m - 12° right - 8 m short"
static func marker_text(from: Vector3, marker: Vector3, yaw: float, landing_dist: float) -> String:
	var d: float = Util.dist_xz(from, marker)
	var h: float = Util.dir_to_yaw(Util.flat(marker - from))
	var diff: float = rad_to_deg(Util.angle_diff(h, yaw))
	var dir_s: String
	if absf(diff) < 0.6:
		dir_s = I18n.t("marker.straight")
	elif diff > 0.0:
		dir_s = I18n.t("marker.left", {"a": int(round(absf(diff)))})
	else:
		dir_s = I18n.t("marker.right", {"a": int(round(absf(diff)))})
	var txt: String = I18n.t("marker.info", {"d": int(round(d)), "dir": dir_s})
	if landing_dist >= 0.0:
		var delta: float = landing_dist - d
		if absf(delta) < 3.0:
			txt += " - " + I18n.t("marker.on_target")
		elif delta < 0.0:
			txt += " - " + I18n.t("marker.short", {"d": int(round(-delta))})
		else:
			txt += " - " + I18n.t("marker.long", {"d": int(round(delta))})
	return txt

func _face_marker() -> void:
	var p: PlayerData = Game.cur()
	if p == null or Turn.sel == null:
		return
	var mk0: Vector3 = Game.marker_for(p)
	if mk0 == Vector3.INF:
		Events.toast.emit(I18n.t("marker.none"))
		return
	var heading: float = Util.dir_to_yaw(Util.flat(mk0 - Turn.sel.global_pos()))
	Turn.set_aim(heading, Turn.aim_elev, Turn.aim_power)
	Sfx.play("ui_click", Vector3.INF, 0.6, 0)
	Events.toast.emit(I18n.t("marker.faced"))

# ------------------------------------------------------------------ input
## Touch (phones / tablets): one finger aims like the mouse, TWO fingers pinch to zoom and drag to orbit the camera.
var _touches: Dictionary = {}
var _gesture: bool = false

func _touch_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() >= 2:
			_gesture = true
			cancel_drag()
		elif _touches.is_empty():
			_gesture = false
		return false
	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if _touches.size() >= 2:
			var old_d: float = 0.0
			var keys: Array = _touches.keys()
			old_d = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)
			_touches[sd.index] = sd.position
			var new_d: float = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)
			cam.zoom((new_d - old_d) / 40.0)
			cam.orbit_drag(sd.relative.x * 0.5, sd.relative.y * 0.5)
			return true
		_touches[sd.index] = sd.position
	return false

func _unhandled_input(event: InputEvent) -> void:
	if Game.state != Game.State.BATTLE:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if _touch_input(event):
			accept_event()
		return
	if _gesture and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return          # a two finger gesture is running: the emulated mouse of the first finger must not aim
	# camera orbit + zoom work in every phase of the own turn (right drag / wheel)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		if mb.pressed:
			if mb.shift_pressed and _human_aiming() and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				var de: float = 1.5 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.5
				Turn.set_aim(Turn.aim_yaw, Turn.aim_elev + de, Turn.aim_power)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				cam.zoom(1.0)
				accept_event()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cam.zoom(-1.0)
				accept_event()
				return
	if event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event
		cam.orbit_drag(mm.relative.x, mm.relative.y)
		return
	if not _human_aiming():
		return
	if Turn.is_action_mode():
		# relocate / wall: Actions handles the mouse and the movement keys; only the weapon / catapult keys work here
		if event is InputEventKey and event.pressed and not event.echo:
			_select_key(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		var mb2: InputEventMouseButton = event
		if mb2.button_index == MOUSE_BUTTON_LEFT:
			if mb2.pressed:
				dragging = true
				_trim = 0.0
				cam.aim_hold = true
				drag_start = mb2.position
				drag_cur = mb2.position
				_click_start = mb2.position
				Sfx.play("creak", Vector3.INF, 0.25, 0)
			elif dragging:
				dragging = false
				cam.aim_hold = false
				var pull: Vector2 = mb2.position - drag_start
				if pull.length() < 10.0 * _scale():
					# a click: maybe switch to another own catapult
					Turn.set_aim(Turn.aim_yaw, Turn.aim_elev, 0.0)
					if (mb2.position - _click_start).length() < 8.0:
						_try_select_at(mb2.position)
				else:
					_apply_drag(mb2.position)
					if Turn.can_fire():
						fired.emit()
						Turn.fire()
					else:
						Turn.set_aim(Turn.aim_yaw, Turn.aim_elev, 0.0)
			queue_redraw()
	elif event is InputEventMouseMotion and dragging:
		var mm2: InputEventMouseMotion = event
		drag_cur = mm2.position
		_apply_drag(mm2.position)
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		match k.keycode:
			KEY_ESCAPE:
				if dragging:
					cancel_drag()
					accept_event()
			KEY_SPACE:
				if Turn.aim_power < 0.08:
					Turn.set_aim(Turn.aim_yaw, Turn.aim_elev, maxf(_last_power, 0.5))
				fired.emit()
				Turn.fire()
				accept_event()
			KEY_TAB:
				Turn.cycle_catapult(-1 if k.shift_pressed else 1)
				accept_event()
			KEY_R:
				_face_next_enemy()
				accept_event()
			KEY_X:
				_face_marker()
				accept_event()
			_:
				_select_key(k)

## Weapon / action keys (1-9, 0, -, G, U, B) and Tab: shared by the aiming and the action modes
func _select_key(k: InputEventKey) -> void:
	var idx: int = -1
	match k.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			idx = int(k.keycode) - int(KEY_1)
		KEY_0:
			idx = 9
		KEY_MINUS, KEY_SLASH, 223:
			idx = 10
		KEY_G:
			idx = 11
		KEY_U:
			idx = 12
		KEY_B:
			idx = 13
		KEY_TAB:
			Turn.cycle_catapult(-1 if k.shift_pressed else 1)
			accept_event()
			return
		_:
			return
	var list: Array[AmmoDef] = AmmoDef.all()
	if idx < list.size():
		Turn.set_ammo(list[idx].id)
	accept_event()

func _apply_drag(pos: Vector2) -> void:
	var sc: float = _scale()
	var pull: Vector2 = pos - drag_start
	var max_px: float = Cfg.DRAG_MAX_PX * sc
	if pull.length() > max_px:
		pull = pull.normalized() * max_px
	var power: float = pull.length() / max_px
	if pull.length() < 10.0 * sc:
		power = 0.0
	# slingshot: the shot flies opposite to the pull, measured on screen (the camera is frozen while pulling)
	var yaw: float = Turn.aim_yaw
	if power > 0.0 and Turn.sel != null:
		yaw = _yaw_from_screen(-pull.normalized()) + _trim
	Turn.set_aim(yaw, Turn.aim_elev, power)
	if power > 0.0:
		_last_power = power

func _try_select_at(pos: Vector2) -> void:
	var best: Catapult = null
	var bd: float = 70.0 * _scale()
	for c in Turn.living_catapults():
		var cat: Catapult = c as Catapult
		if cat == Turn.sel:
			continue
		var wp: Vector3 = cat.global_pos() + Vector3(0, 1.4, 0)
		if cam.is_behind(wp):
			continue
		var sp: Vector2 = cam.project(wp)
		var d: float = sp.distance_to(pos)
		if d < bd:
			bd = d
			best = cat
	if best != null:
		Turn.select_catapult(best)
		Sfx.play("ui_click", Vector3.INF, 0.7, 0)

func _face_next_enemy() -> void:
	# turn the selected catapult toward the nearest not-yet-faced enemy village
	if Turn.sel == null:
		return
	var enemies: Array[PlayerData] = []
	for p in Game.players:
		if Game.cur().is_enemy(p) and not p.eliminated:
			enemies.append(p)
	if enemies.is_empty():
		return
	enemies.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		return Util.dist_xz(a.village_center, Turn.sel.global_pos()) < Util.dist_xz(b.village_center, Turn.sel.global_pos()))
	var cur_yaw: float = Turn.aim_yaw
	var pick: PlayerData = enemies[0]
	# choose the first enemy whose heading differs by > 8 degrees from the current one (cycles on repeated presses)
	for e in enemies:
		var h: float = Util.dir_to_yaw(Util.flat(e.village_center - Turn.sel.global_pos()))
		if absf(Util.angle_diff(h, cur_yaw)) > deg_to_rad(8.0):
			pick = e
			break
	var heading: float = Util.dir_to_yaw(Util.flat(pick.village_center - Turn.sel.global_pos()))
	Turn.set_aim(heading, Turn.aim_elev, Turn.aim_power)
	Sfx.play("ui_click", Vector3.INF, 0.6, 0)

# ------------------------------------------------------------------ per-frame
func _process(delta: float) -> void:
	_release_flash = maxf(_release_flash - delta, 0.0)
	var aiming: bool = _human_aiming()
	if not aiming:
		if _preview != null:
			_preview.visible = false
		if cam != null:
			cam.aim_hold = false
		if dragging:
			dragging = false
			queue_redraw()
		elif _overlay_on:
			_overlay_on = false
			queue_redraw()
		return
	if Turn.is_action_mode():
		if _preview != null:
			_preview.visible = false
		if dragging:
			cancel_drag()
		_overlay_on = false
		return
	_overlay_on = true
	queue_redraw()
	# keyboard fine tune (held keys repeat at 30 Hz)
	_key_acc += delta
	var step_t: float = 1.0 / 30.0
	while _key_acc >= step_t:
		_key_acc -= step_t
		var fine: bool = Input.is_key_pressed(KEY_SHIFT)
		var d: float = deg_to_rad(0.1 if fine else 0.5)
		var yaw: float = Turn.aim_yaw
		var elev: float = Turn.aim_elev
		var pw: float = Turn.aim_power
		var changed: bool = false
		var qe: float = 0.0
		if Input.is_key_pressed(KEY_Q):
			qe += 1.0
		if Input.is_key_pressed(KEY_E):
			qe -= 1.0
		if qe != 0.0:
			# Q / E turn the catapult - also while the slingshot is being pulled
			var dq: float = deg_to_rad(0.4 if fine else 2.0) * qe
			if dragging:
				_trim += dq
				_apply_drag(drag_cur)
			else:
				yaw += dq
				changed = true
		if Input.is_key_pressed(KEY_LEFT):
			yaw += d
			changed = true
		if Input.is_key_pressed(KEY_RIGHT):
			yaw -= d
			changed = true
		if Input.is_key_pressed(KEY_UP):
			elev += rad_to_deg(d)
			changed = true
		if Input.is_key_pressed(KEY_DOWN):
			elev -= rad_to_deg(d)
			changed = true
		if Input.is_key_pressed(KEY_W):
			pw += 0.02 * (0.25 if fine else 1.0)
			changed = true
		if Input.is_key_pressed(KEY_S):
			pw -= 0.02 * (0.25 if fine else 1.0)
			changed = true
		if changed and not dragging:
			Turn.set_aim(yaw, elev, maxf(pw, 0.0))
			_last_power = maxf(Turn.aim_power, _last_power * 0.0 + Turn.aim_power)
		elif changed and dragging and elev != Turn.aim_elev:
			# elevation can be tuned while pulling (heading and power stay with the mouse)
			Turn.set_aim(Turn.aim_yaw, elev, Turn.aim_power)
	_update_preview()

func _update_preview() -> void:
	if Turn.sel == null or Turn.aim_power < 0.05 or _preview == null:
		if _preview != null:
			_preview.visible = false
		return
	var vel: Vector3 = Turn.current_velocity()
	var origin: Vector3 = Turn.launch_origin(Turn.sel, Turn.aim_elev, Turn.aim_yaw)
	var tr: Dictionary = Turn.predict_trajectory(origin, vel, Turn.aim_ammo, Game.wind, 12.0)
	var flight: float = float(tr["flight_time"])
	var show_t: float = flight * Cfg.PREVIEW_FRACTION
	# points are stored every 3 sim steps = 0.05 s; long flights use a stride so 40 dots always cover the first 40%
	var pts: PackedVector3Array = tr["points"] as PackedVector3Array
	var total: int = mini(int(show_t / 0.05), pts.size() - 1)
	var stride: int = maxi(int(ceil(float(total) / 40.0)), 1)
	var n: int = mini(total / stride, 40)
	_preview_mm.visible_instance_count = n
	var cam_p: Vector3 = cam.camera_position() if cam != null else Vector3.ZERO
	for i in n:
		var p: Vector3 = pts[(i + 1) * stride]
		# far dots get bigger so they stay readable from the chase camera
		var far_k: float = clampf(cam_p.distance_to(p) / 28.0, 1.0, 6.0)
		_preview_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * (1.0 - 0.4 * float(i) / 40.0) * far_k), p))
		var a: float = 1.0 - float(i) / float(maxi(n, 1)) * 0.9
		_preview_mm.set_instance_color(i, Color(1.0, 0.95 - 0.35 * float(i) / 40.0, 0.35, a))
	_preview.visible = n > 0

# ------------------------------------------------------------------ overlay
func _draw() -> void:
	if _overlay_on and Turn.sel != null and cam != null:
		_draw_marker()
		_draw_heading()
	if not dragging:
		return
	var sc: float = _scale()
	var max_px: float = Cfg.DRAG_MAX_PX * sc
	var pull: Vector2 = drag_cur - drag_start
	if pull.length() > max_px:
		pull = pull.normalized() * max_px
	var cur: Vector2 = drag_start + pull
	var power: float = pull.length() / max_px
	# range rings
	for i in 4:
		var r: float = max_px * float(i + 1) / 4.0
		draw_arc(drag_start, r, 0.0, TAU, 48, Color(1, 1, 1, 0.16 if float(i + 1) / 4.0 > power else 0.4), 2.0, true)
	var col: Color = Color("#7cf05a").lerp(Color("#ffd400"), clampf(power * 2.0, 0.0, 1.0)).lerp(Color("#ff5b2e"), clampf(power * 2.0 - 1.0, 0.0, 1.0))
	var touch: bool = TouchMode.on
	var band: float = 2.0 if touch else 1.0          # a finger hides a thin line: much thicker on a touch screen
	if pull.length() >= 10.0 * sc:
		# rubber band from the anchor to the pulled point
		draw_line(drag_start, cur, Color(0.1, 0.06, 0.02, 0.9), 12.0 * band, true)
		draw_line(drag_start, cur, col, 7.0 * band, true)
	draw_circle(drag_start, 9.0 * sc, Color(0.1, 0.06, 0.02, 0.9))
	draw_circle(drag_start, 6.0 * sc, Color("#ffffff"))
	draw_circle(cur, 15.0 * sc, Color(0.1, 0.06, 0.02, 0.95))
	draw_circle(cur, 11.0 * sc, col)
	var f: Font = UITheme.font_bold()
	var t: String = "%d%%" % int(round(power * 100.0))
	if touch:
		# the thumb covers what is under it: the number sits beside the finger, on the side of the screen half the thumb is NOT in
		var fs: int = int(46 * sc)
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var tw: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tx: float = drag_cur.x + 110.0 * sc if drag_cur.x < vp.x * 0.5 else drag_cur.x - 110.0 * sc - tw
		var tp := Vector2(clampf(tx, 6.0, vp.x - tw - 6.0), clampf(drag_cur.y + fs * 0.35, fs + 4.0, vp.y - 6.0))
		draw_string_outline(f, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 9, Color(0.1, 0.06, 0.02))
		draw_string(f, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		return
	draw_string_outline(f, cur + Vector2(20, -12) * sc, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * sc), 6, Color(0.1, 0.06, 0.02))
	draw_string(f, cur + Vector2(20, -12) * sc, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * sc), Color.WHITE)

## The faithful aim arrow: starts at the catapult and follows the projection of the real launch heading
func _draw_heading() -> void:
	if Turn.aim_power < 0.04 and not dragging:
		return
	var sc: float = _scale()
	var base: Vector3 = Turn.sel.global_pos() + Vector3(0, 0.6, 0)
	if cam.is_behind(base):
		return
	var from: Vector2 = cam.project(base)
	var tip: Vector2 = _yaw_tip(Turn.aim_yaw, (90.0 + Turn.aim_power * 130.0) * sc)
	var dir: Vector2 = (tip - from).normalized()
	if tip.distance_to(from) < 4.0:
		return
	var side := Vector2(-dir.y, dir.x)
	draw_line(from, tip, Color(0.1, 0.06, 0.02, 0.8), 8.0 * sc, true)
	draw_line(from, tip, Color(1, 1, 1, 0.92), 4.0 * sc, true)
	var head := PackedVector2Array([tip + dir * 16.0 * sc, tip + side * 10.0 * sc, tip - side * 10.0 * sc])
	draw_colored_polygon(PackedVector2Array([tip + dir * 20.0 * sc, tip + side * 13.0 * sc, tip - side * 13.0 * sc]), Color(0.1, 0.06, 0.02, 0.85))
	draw_colored_polygon(head, Color(1, 1, 1, 0.95))

## Marker direction while aiming (spec 6.7): dashed ground line to the marker + compass chevron / label
func _draw_marker() -> void:
	var p: PlayerData = Game.cur()
	if p == null or Game.marker_for(p) == Vector3.INF:
		return
	var sc: float = _scale()
	var col: Color = p.color.lightened(0.3)
	var from: Vector3 = Turn.sel.global_pos()
	var mk: Vector3 = Game.marker_for(p)
	# dashed ground line
	var steps: int = 40
	var prev: Vector2 = Vector2.ZERO
	var prev_ok: bool = false
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var w: Vector3 = from.lerp(mk, t)
		w.y = maxf(Terrain.h(w.x, w.z), Cfg.WATER_LEVEL) + 0.4
		var ok: bool = not cam.is_behind(w)
		var sp: Vector2 = cam.project(w) if ok else Vector2.ZERO
		if ok and prev_ok and i % 2 == 1:
			draw_line(prev, sp, Color(0.1, 0.06, 0.02, 0.6), 5.0 * sc, true)
			draw_line(prev, sp, Color(col.r, col.g, col.b, 0.85), 2.5 * sc, true)
		prev = sp
		prev_ok = ok
	# label / chevron
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var margin: float = 46.0 * sc
	var target: Vector3 = mk + Vector3(0, 7.0, 0)
	var behind: bool = cam.is_behind(target)
	var sp2: Vector2 = cam.project(target)
	var center: Vector2 = vp * 0.5
	var on_screen: bool = (not behind) and sp2.x > margin and sp2.x < vp.x - margin and sp2.y > margin and sp2.y < vp.y - margin
	var f: Font = UITheme.font_bold()
	var label: String = "%d m" % int(round(Util.dist_xz(from, mk)))
	var pos: Vector2
	var ang: float = 0.0
	if on_screen:
		pos = sp2 + Vector2(0, -26.0 * sc)
		ang = PI * 0.5
	else:
		var d2: Vector2 = sp2 - center
		if behind:
			d2 = -d2
		if d2.length() < 1.0:
			d2 = Vector2(0, 1)
		d2 = d2.normalized()
		var k: float = INF
		var half: Vector2 = vp * 0.5 - Vector2(margin, margin)
		if absf(d2.x) > 0.001:
			k = minf(k, half.x / absf(d2.x))
		if absf(d2.y) > 0.001:
			k = minf(k, half.y / absf(d2.y))
		pos = center + d2 * k
		ang = d2.angle()
	# chevron (points toward the marker / down at it)
	var dirv: Vector2 = Vector2.from_angle(ang)
	var side: Vector2 = Vector2(-dirv.y, dirv.x)
	var c0: Vector2 = pos
	var poly := PackedVector2Array([c0 + dirv * 16.0 * sc, c0 - dirv * 10.0 * sc + side * 14.0 * sc, c0 - dirv * 10.0 * sc - side * 14.0 * sc])
	draw_colored_polygon(PackedVector2Array([c0 + dirv * 21.0 * sc, c0 - dirv * 14.0 * sc + side * 19.0 * sc, c0 - dirv * 14.0 * sc - side * 19.0 * sc]), Color(0.1, 0.06, 0.02, 0.9))
	draw_colored_polygon(poly, col)
	var fs: int = int(22 * sc)
	var w2: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp: Vector2 = c0 - dirv * 30.0 * sc + Vector2(-w2 * 0.5, fs * 0.35)
	tp.x = clampf(tp.x, 6.0, vp.x - w2 - 6.0)
	tp.y = clampf(tp.y, fs + 4.0, vp.y - 6.0)
	draw_string_outline(f, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.1, 0.06, 0.02))
	draw_string(f, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
