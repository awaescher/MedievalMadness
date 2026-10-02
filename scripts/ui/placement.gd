class_name Placement
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## PLACEMENT phase (spec 2.3): every player in order places their catapults inside the village zone and then a few
## palisade posts (stage 2, spec 2.3b).
## Human: click on the ground (ghost = green/red), Q/E rotate, right-click or Z removes the last one,
## Auto-place and Done buttons. CPU: automatic (Knight/King prefer cover, King avoids powder/barn).

signal finished

var world: GameWorld
var cam: CameraRig
var player_idx: int = 0
var yaw: float = 0.0
var ghost: Node3D
var ghost_mesh: MeshInstance3D
var ghost_ring: MeshInstance3D
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var title: Label
var hint: Label
var auto_btn: Button
var done_btn: Button
var quick_btn: Button
var _quick_mine: bool = false          # online: keep placing my own seat automatically
var remove_btn: Button
var bar: PanelContainer
var _cur_valid: bool = false
var _cur_pos: Vector3 = Vector3.INF
var _active: bool = false
var _rmb_down_pos: Vector2 = Vector2.ZERO
var _rmb_moved: bool = false
var _cpu_timer: float = 0.0
var _rng := Rng.new(9)
var _bad_toast_t: float = 0.0
var stage: int = 0                     # 0 = catapults, 1 = palisade posts
var round_no: int = 0                  # round 0: everybody places catapults, round 1: everybody places posts
var post_ghost: Node3D
var post_ghost_mesh: MeshInstance3D
var _post_center: Vector3 = Vector3.INF   # middle of the fence that a click would set (or the row to stack)
var _post_yaw: float = 0.0
var _post_fence: Dictionary = {}          # fence to stack on (empty = new fence on the ground)
var _post_valid: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.build()
	visible = false
	_mat_ok = StandardMaterial3D.new()
	_mat_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_ok.albedo_color = Color(0.3, 1.0, 0.35, 0.55)
	_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_bad = StandardMaterial3D.new()
	_mat_bad.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_bad.albedo_color = Color(1.0, 0.25, 0.2, 0.55)
	_mat_bad.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# UI
	bar = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -430
	bar.offset_right = 430
	bar.offset_top = 12
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bar.add_child(v)
	title = UITheme.label("", 26, UITheme.INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	hint = UITheme.label("", 15, Color("#6b4a2a"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	remove_btn = UITheme.dialog_button("", "ParchButton", 160.0)
	remove_btn.pressed.connect(_remove_last)
	h.add_child(remove_btn)
	auto_btn = UITheme.dialog_button("", "GoldButton", 200.0)
	auto_btn.pressed.connect(_auto_place)
	h.add_child(auto_btn)
	done_btn = UITheme.dialog_button("", "GreenButton", 160.0)
	done_btn.pressed.connect(_done)
	h.add_child(done_btn)
	quick_btn = UITheme.dialog_button("", "RedButton", 190.0)
	quick_btn.pressed.connect(_quick_start)
	h.add_child(quick_btn)
	Events.language_changed.connect(_refresh)

func start(w: GameWorld, camera: CameraRig) -> void:
	world = w
	cam = camera
	player_idx = -1
	round_no = 0
	_quick_mine = false
	_active = true
	visible = true
	if ghost == null:
		_build_ghost()
	Events.banner.emit(I18n.t("banner.placement"), "info")
	_next_player()

func _build_ghost() -> void:
	ghost = Node3D.new()
	ghost_mesh = MeshInstance3D.new()
	var b := MeshGen.Buf.new()
	MeshGen.add_box(b, Vector3(1.9, 0.9, 2.4), Transform3D(Basis(), Vector3(0, 0.55, 0)), Color.WHITE, 0.0)
	MeshGen.add_box(b, Vector3(0.3, 0.3, 1.6), Transform3D(Basis(), Vector3(0, 1.6, -0.5)), Color.WHITE, 0.0)
	# forward arrow
	MeshGen.add_box(b, Vector3(0.25, 0.1, 1.6), Transform3D(Basis(), Vector3(0, 0.15, -2.0)), Color.WHITE, 0.0)
	MeshGen.add_box(b, Vector3(0.9, 0.1, 0.3), Transform3D(Basis(), Vector3(0, 0.15, -2.9)), Color.WHITE, 0.0)
	ghost_mesh.mesh = b.to_mesh()
	ghost_mesh.material_override = _mat_ok
	ghost_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(ghost_mesh)
	ghost_ring = MeshInstance3D.new()
	ghost_ring.mesh = MeshGen.ring_mesh(2.1, 2.3, 32)
	ghost_ring.material_override = _mat_ok
	ghost_ring.position = Vector3(0, 0.08, 0)
	ghost_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(ghost_ring)
	world.add_child(ghost)
	ghost.visible = false
	post_ghost = Node3D.new()
	# a fence ghost: three posts side by side
	var post_mesh: Mesh = MeshGen.cyl_mesh(Posts.POST_R, Posts.POST_H, 10)
	for gi in Posts.FENCE_POSTS:
		var gm := MeshInstance3D.new()
		gm.mesh = post_mesh
		gm.position = Vector3(Posts.SPACING * float(gi - 1), Posts.POST_H * 0.5, 0)
		gm.material_override = _mat_ok
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post_ghost.add_child(gm)
		if gi == 0:
			post_ghost_mesh = gm
	world.add_child(post_ghost)
	post_ghost.visible = false

func _refresh() -> void:
	if not _active or player_idx < 0 or player_idx >= Game.players.size():
		return
	var p: PlayerData = Game.players[player_idx]
	remove_btn.text = I18n.t("placement.remove")
	auto_btn.text = I18n.t("placement.auto")
	quick_btn.text = I18n.t("placement.quick")
	quick_btn.disabled = false
	if stage == 0:
		title.text = I18n.t("placement.title", {"name": p.name})
		hint.text = I18n.t("placement.hint", {"n": p.catapults.size(), "max": Game.catapults_per_player})
		var last_player: bool = player_idx >= Game.players.size() - 1
		if not last_player:
			done_btn.text = I18n.t("placement.next_player")
		else:
			done_btn.text = I18n.t("placement.to_posts") if Game.palisades_per_player > 0 else I18n.t("placement.done")
		done_btn.disabled = p.catapults.size() < Game.catapults_per_player
		remove_btn.disabled = p.catapults.is_empty()
	else:
		title.text = I18n.t("placement.title_posts", {"name": p.name})
		hint.text = I18n.t("placement.hint_posts", {"n": Posts.count(p), "max": Game.palisades_per_player})
		done_btn.text = I18n.t("placement.done")
		done_btn.disabled = false
		remove_btn.disabled = p.post_log.is_empty()

func _next_player() -> void:
	player_idx += 1
	if player_idx >= Game.players.size():
		# everybody's catapults stand: now everybody sets their palisade posts
		if round_no == 0 and Game.palisades_per_player > 0:
			round_no = 1
			player_idx = 0
			Events.banner.emit(I18n.t("banner.posts"), "info")
		else:
			_finish()
			return
	var p: PlayerData = Game.players[player_idx]
	if p.eliminated:
		_next_player()          # somebody who left the online game
		return
	Game.current_player = player_idx
	stage = round_no
	post_ghost.visible = false
	cam.focus_on(p.village_center, 44.0, 52.0, 0.0)
	Events.turn_start.emit(p.id)
	yaw = _default_yaw(p)
	if p.is_cpu() or p.is_remote():
		title.text = I18n.t("placement.cpu_placing", {"name": p.name})
		hint.text = ""
		for b in [remove_btn, auto_btn, done_btn, quick_btn]:
			(b as Button).disabled = true
		ghost.visible = false
		_cpu_timer = 0.45
		if p.is_remote() or Net.is_client():
			# somebody else places (a human on another machine, or the host's CPU): wait for their message
			var pd: Dictionary = NetGame.take_pending_placed(player_idx, stage)
			if not pd.is_empty():
				net_placed(pd)
	else:
		_refresh()
		if _quick_mine:
			_auto_place.call_deferred()
			_done.call_deferred()

## Quick start: everybody's catapults and palisades are placed automatically and the battle begins.
## Online only the seats of this machine are placed (the others place theirs themselves).
func _quick_start() -> void:
	if not _active or player_idx < 0 or player_idx >= Game.players.size():
		return
	Sfx.play("ui_click", Vector3.INF, 0.8, 0)
	if Net.active:
		var me: PlayerData = _cur()
		if not me.is_human():
			return
		_quick_mine = true
		_auto_place()
		_done()
		return
	var guard: int = 0
	while _active and guard < 64:
		guard += 1
		var p: PlayerData = _cur()
		if round_no == 0:
			auto_place(p, world, p.type if p.is_cpu() else "squire", _rng)
		else:
			Posts.auto_place(p, _rng)
		_next_player()

## Online: another seat finished its placement (message from its author)
func net_placed(d: Dictionary) -> void:
	if not _active or int(d["idx"]) != player_idx or int(d["stage"]) != stage:
		NetGame._placed_pending["%d:%d" % [int(d["idx"]), int(d["stage"])]] = d
		return
	NetGame.apply_placement(world, d, _rng)
	_next_player()

## Online: the seat that was placing left the game
func net_player_dropped(seat: int) -> void:
	if _active and seat == player_idx:
		_next_player()

func _default_yaw(p: PlayerData) -> float:
	var best: PlayerData = null
	var bd: float = 1e9
	for o in Game.players:
		if p.is_enemy(o):
			var d: float = Util.dist_xz(o.village_center, p.village_center)
			if d < bd:
				bd = d
				best = o
	if best == null:
		return 0.0
	return Util.dir_to_yaw(Util.flat(best.village_center - p.village_center))

func _finish() -> void:
	_active = false
	_hide_arrows()
	visible = false
	if ghost != null:
		ghost.visible = false
	if post_ghost != null:
		post_ghost.visible = false
	finished.emit()

# ------------------------------------------------------------------ actions
func _cur() -> PlayerData:
	return Game.players[player_idx]

func _place_at(pos: Vector3) -> bool:
	var p: PlayerData = _cur()
	if p.catapults.size() >= Game.catapults_per_player:
		return false
	if not world.spot_valid_for_catapult(p, pos):
		return false
	world.place_catapult(p, pos, yaw)
	Sfx.play("thunk", pos, 0.8, 2)
	Fx.burst("dust", pos + Vector3.UP * 0.3, Color("#8a6d4a"), 0.4)
	_refresh()
	return true

func _place_post() -> void:
	var p: PlayerData = _cur()
	if _post_center == Vector3.INF:
		return
	if Posts.count(p) >= Game.palisades_per_player:
		Events.toast.emit(I18n.t("placement.hint_posts", {"n": Posts.count(p), "max": Game.palisades_per_player}))
		return
	if not _post_valid:
		Events.toast.emit(I18n.t("placement.post_invalid"))
		Sfx.play("clack", Vector3.INF, 0.4, 0)
		return
	if not _post_fence.is_empty():
		Posts.stack_fence(p, _post_fence, _rng)
	else:
		Posts.place_fence(p, _post_center, _post_yaw, _rng)
	Sfx.play("thunk", _post_center, 0.9, 2)
	Fx.burst("dust", _post_center + Vector3.UP * 0.3, Color("#8a6d4a"), 0.5)
	_refresh()

func _remove_last() -> void:
	var p: PlayerData = _cur()
	if stage == 1:
		Posts.remove_last(p)
		Sfx.play("ui_click", Vector3.INF, 0.6, 0)
		_refresh()
		return
	if p.catapults.is_empty():
		return
	var c: Catapult = p.catapults.pop_back() as Catapult
	if c.body_id != 0:
		PhysWorld.remove_body(c.body_id)
	c.queue_free()
	Sfx.play("ui_click", Vector3.INF, 0.6, 0)
	_refresh()

func _auto_place() -> void:
	var p: PlayerData = _cur()
	if stage == 1:
		Posts.auto_place(p, _rng)
	else:
		auto_place(p, world, p.type if p.is_cpu() else "squire", _rng)
	_refresh()
	Sfx.play("ui_click", Vector3.INF, 0.6, 0)

func _done() -> void:
	if stage == 0 and _cur().catapults.size() < Game.catapults_per_player:
		return
	Sfx.play("ui_click", Vector3.INF, 0.8, 0)
	NetGame.send_placed(player_idx, stage)
	_next_player()

## Fill the player's remaining catapults with valid spots (spec 14.3). Static so tests/CPU can call it.
static func auto_place(p: PlayerData, w: GameWorld, kind: String, r: Rng) -> void:
	while p.catapults.size() < Game.catapults_per_player:
		var best_pos: Vector3 = Vector3.INF
		var best_score: float = -1e9
		for t in 30:
			var off: Vector2 = r.in_circle(Cfg.ZONE_RADIUS - 2.0)
			var pos := Vector3(p.village_center.x + off.x, 0, p.village_center.z + off.y)
			pos.y = Terrain.h(pos.x, pos.z)
			if not w.spot_valid_for_catapult(p, pos):
				continue
			var score: float = r.range_f(0.0, 1.0)
			# spread from own catapults (>= 5 m mandatory)
			var mind: float = 1e9
			for c in p.catapults:
				mind = minf(mind, Util.dist_xz((c as Catapult).global_pos(), pos))
			if mind < 5.0:
				continue
			score += minf(mind, 12.0) * 0.1
			# keep a few metres of open space around the catapult (camera + shots need room)
			var near_b: float = 99.0
			for sb in Breakable.structures:
				if sb.free_parts or sb.owner_id != p.id or sb.kind == "tree":
					continue
				var bx: float = maxf(maxf(sb.aabb.position.x - pos.x, pos.x - (sb.aabb.position.x + sb.aabb.size.x)), 0.0)
				var bz: float = maxf(maxf(sb.aabb.position.z - pos.z, pos.z - (sb.aabb.position.z + sb.aabb.size.z)), 0.0)
				near_b = minf(near_b, sqrt(bx * bx + bz * bz))
			if near_b < 5.0:
				score -= (5.0 - near_b) * 1.6
			if kind == "knight" or kind == "king":
				# prefer buildings within 6 m in the direction of enemies (cover)
				var toward: Vector3 = Vector3.ZERO
				for o in Game.players:
					if p.is_enemy(o) and not o.eliminated:
						toward += Util.flat(o.village_center - p.village_center).normalized()
				toward = toward.normalized()
				for s in Breakable.structures:
					if s.owner_id != p.id or s.free_parts or s.kind == "tree":
						continue
					var d: Vector3 = Util.flat(s.center - pos)
					var dl: float = d.length()
					if dl < 9.0 + s.radius and dl > 4.5 + s.radius * 0.5 and d.normalized().dot(toward) > 0.4:
						score += 2.0
				if kind == "king":
					for s2 in Breakable.structures:
						if s2.owner_id != p.id:
							continue
						if s2.kind == "powderstore" and s2.center.distance_to(pos) < 8.0:
							score -= 6.0
						if s2.kind == "barn" and s2.center.distance_to(pos) < 8.0:
							score -= 5.0
			if score > best_score:
				best_score = score
				best_pos = pos
		if best_pos == Vector3.INF:
			# relax: try many random spots ignoring the 5 m spread
			for t2 in 120:
				var off2: Vector2 = r.in_circle(Cfg.ZONE_RADIUS - 2.0)
				var pos2 := Vector3(p.village_center.x + off2.x, 0, p.village_center.z + off2.y)
				pos2.y = Terrain.h(pos2.x, pos2.z)
				if w.spot_valid_for_catapult(p, pos2):
					best_pos = pos2
					break
		if best_pos == Vector3.INF:
			break
		var yaw_c: float = 0.0
		var best_o: PlayerData = null
		var bd: float = 1e9
		for o2 in Game.players:
			if p.is_enemy(o2) and not o2.eliminated:
				var d2: float = Util.dist_xz(o2.village_center, p.village_center)
				if d2 < bd:
					bd = d2
					best_o = o2
		if best_o != null:
			yaw_c = Util.dir_to_yaw(Util.flat(best_o.village_center - best_pos))
		w.place_catapult(p, best_pos, yaw_c)

# ------------------------------------------------------------------ per-frame + input
func _process(delta: float) -> void:
	if not _active:
		return
	if player_idx >= 0 and player_idx < Game.players.size() and (Game.players[player_idx].is_cpu() or Game.players[player_idx].is_remote()):
		var pp: PlayerData = Game.players[player_idx]
		if pp.is_remote() or Net.is_client():
			return          # waiting for the message of the seat's author
		_cpu_timer -= delta
		if _cpu_timer <= 0.0:
			if round_no == 0:
				auto_place(pp, world, pp.type, _rng)
			else:
				Posts.auto_place(pp, _rng)
			NetGame.send_placed(player_idx, round_no)
			_next_player()
		return
	if player_idx < 0 or player_idx >= Game.players.size():
		return
	# rotate with Q / E (held)
	var rot: float = 0.0
	if Input.is_key_pressed(KEY_Q):
		rot += 1.0
	if Input.is_key_pressed(KEY_E):
		rot -= 1.0
	if rot != 0.0:
		yaw += rot * deg_to_rad(120.0) * delta
	_update_ghost()
	_bad_toast_t = maxf(_bad_toast_t - delta, 0.0)
	_update_arrows()
	queue_redraw()

func _mouse_ground() -> Vector3:
	var mp: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = cam.cam.project_ray_origin(mp)
	var dir: Vector3 = cam.cam.project_ray_normal(mp)
	return Terrain.pick(origin, dir, 500.0)

func _update_post_ghost() -> void:
	ghost.visible = false
	var mp: Vector2 = get_viewport().get_mouse_position()
	var over_ui: bool = false
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != self and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		over_ui = true
	var p: PlayerData = _cur()
	var o: Vector3 = cam.cam.project_ray_origin(mp)
	var d: Vector3 = cam.cam.project_ray_normal(mp)
	_post_fence = {}
	_post_center = Vector3.INF
	if over_ui:
		post_ghost.visible = false
		return
	var room: bool = Posts.count(p) < Game.palisades_per_player
	var col: Dictionary = Posts.hover_column(p, o, d)
	var fence: Dictionary = Posts.fence_of(p, col) if not col.is_empty() else {}
	if not fence.is_empty():
		# pointing at an own fence: the next row of 3 goes on top of it
		_post_fence = fence
		_post_center = Posts.fence_stack_center(fence)
		_post_yaw = float(fence["yaw"])
		_post_valid = room and Posts.fence_can_stack(fence)
	else:
		var hit: Vector3 = Terrain.pick(o, d, 500.0)
		if hit == Vector3.INF:
			post_ghost.visible = false
			return
		var sn: Dictionary = Posts.snap_fence(p, hit, yaw)
		_post_center = sn["center"] as Vector3
		_post_yaw = float(sn["yaw"])
		_post_valid = room and Posts.fence_valid(p, _post_center, _post_yaw)
	post_ghost.visible = true
	post_ghost.global_transform = Transform3D(Basis(Vector3.UP, _post_yaw), _post_center)
	for gm in post_ghost.get_children():
		(gm as MeshInstance3D).material_override = _mat_ok if _post_valid else _mat_bad

func _update_ghost() -> void:
	if stage == 1:
		_update_post_ghost()
		return
	post_ghost.visible = false
	var hit: Vector3 = _mouse_ground()
	var over_ui: bool = false
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != self and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		over_ui = true
	if hit == Vector3.INF or over_ui:
		ghost.visible = false
		_cur_pos = Vector3.INF
		return
	_cur_pos = hit
	var p: PlayerData = _cur()
	_cur_valid = p.catapults.size() < Game.catapults_per_player and world.spot_valid_for_catapult(p, hit)
	ghost.visible = true
	ghost.global_transform = Transform3D(Basis(Vector3.UP, yaw), hit + Vector3(0, 0.05, 0))
	var m: StandardMaterial3D = _mat_ok if _cur_valid else _mat_bad
	ghost_mesh.material_override = m
	ghost_ring.material_override = m

func _unhandled_input(event: InputEvent) -> void:
	if not _active or player_idx < 0 or player_idx >= Game.players.size() or _cur().is_cpu() or _cur().is_remote():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if stage == 1:
				_place_post()
			elif _cur_pos != Vector3.INF:
				if _cur_valid:
					_place_at(_cur_pos)
				else:
					Events.toast.emit(I18n.t("placement.invalid"))
					Sfx.play("clack", Vector3.INF, 0.4, 0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmb_down_pos = mb.position
				_rmb_moved = false
			else:
				if not _rmb_moved:
					_remove_last()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom(1.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom(-1.0)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			if (mm.position - _rmb_down_pos).length() > 5.0:
				_rmb_moved = true
			cam.orbit_drag(mm.relative.x, mm.relative.y)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_Z:
			_remove_last()
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			_done()

# ------------------------------------------------------------------ where are the others? (direction markers)
## While placing, every other village is marked with its colour and name: above the village when it is on screen, as an arrow
## on the screen border when it is not. Teammates get a green shield, enemies crossed red swords, plus the distance.
func _draw() -> void:
	if not _active or cam == null or player_idx < 0 or player_idx >= Game.players.size():
		return
	var me: PlayerData = _cur()
	if me.is_cpu() or me.is_remote():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var sc: float = maxf(vp.y / 900.0, 0.6)
	var f: Font = UITheme.font_bold()
	var fs: int = int(17.0 * sc)
	var margin: float = 70.0 * sc
	var center: Vector2 = vp * 0.5
	for o in Game.players:
		if o.id == me.id or o.eliminated:
			continue
		var target: Vector3 = o.village_center + Vector3(0, 7.0, 0)
		var behind: bool = cam.is_behind(target)
		var sp: Vector2 = cam.project(target)
		var on_screen: bool = (not behind) and sp.x > margin and sp.x < vp.x - margin and sp.y > margin and sp.y < vp.y - margin
		var ally: bool = me.is_ally(o)
		var label: String = "%s  %d m" % [o.name, int(round(Util.dist_xz(cam.camera_position(), o.village_center)))]
		var tag: String = I18n.t("placement.ally") if ally else I18n.t("placement.enemy")
		var pos: Vector2
		var dirv: Vector2 = Vector2.ZERO
		if on_screen:
			pos = sp
		else:
			var d2: Vector2 = sp - center
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
			dirv = d2
		var tw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var gw: float = f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8)).x
		var w: float = tw + gw + 70.0 * sc
		var h: float = 34.0 * sc
		var rect := Rect2(pos - Vector2(w * 0.5, h * 0.5 + (22.0 * sc if on_screen else 0.0)), Vector2(w, h))
		rect.position.x = clampf(rect.position.x, 34.0 * sc, vp.x - w - 34.0 * sc)
		rect.position.y = clampf(rect.position.y, 34.0 * sc, vp.y - h - 34.0 * sc)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.08, 0.05, 0.82)
		sb.border_color = o.color
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(int(10.0 * sc))
		draw_style_box(sb, rect)
		# colour chip + icon (shield = team mate, crossed swords = enemy)
		draw_rect(Rect2(rect.position + Vector2(8, 8) * sc, Vector2(10, h - 16 * sc)), o.color)
		var ic: Vector2 = rect.position + Vector2(34.0 * sc, h * 0.5)
		if ally:
			draw_colored_polygon(PackedVector2Array([ic + Vector2(-9, -10) * sc, ic + Vector2(9, -10) * sc, ic + Vector2(9, 2) * sc, ic + Vector2(0, 11) * sc, ic + Vector2(-9, 2) * sc]), Color("#46d36b"))
		else:
			draw_line(ic + Vector2(-9, -9) * sc, ic + Vector2(9, 9) * sc, Color("#ff6a5a"), 3.0 * sc, true)
			draw_line(ic + Vector2(9, -9) * sc, ic + Vector2(-9, 9) * sc, Color("#ff6a5a"), 3.0 * sc, true)
		draw_string(f, rect.position + Vector2(52.0 * sc, h * 0.5 + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		draw_string(f, rect.position + Vector2(56.0 * sc + tw, h * 0.5 + fs * 0.3), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), Color("#46d36b") if ally else Color("#ff9a8a"))
		# a pointer: arrow on the border towards an off-screen village, a small triangle under an on-screen label
		if on_screen:
			draw_colored_polygon(PackedVector2Array([Vector2(rect.get_center().x - 7.0 * sc, rect.end.y), Vector2(rect.get_center().x + 7.0 * sc, rect.end.y), Vector2(rect.get_center().x, rect.end.y + 11.0 * sc)]), o.color)
		else:
			var tip: Vector2 = rect.get_center() + dirv * (maxf(w, h) * 0.5 + 6.0 * sc)
			var side := Vector2(-dirv.y, dirv.x)
			draw_colored_polygon(PackedVector2Array([tip + dirv * 16.0 * sc, tip - dirv * 4.0 * sc + side * 11.0 * sc, tip - dirv * 4.0 * sc - side * 11.0 * sc]), o.color)

# ------------------------------------------------------------------ 3D direction arrows at the own village
## While a human places, a 3D arrow hovers at the edge of the own village for every other player, pointing towards that
## player's village: in the player's colour, a green ring under it and a "Team" tag for teammates, red crossed swords above it
## (the names and distances are on the screen pills).
var _arrows: Dictionary = {}          # player id -> Node3D

func _hide_arrows() -> void:
	for k in _arrows.keys():
		(_arrows[k] as Node3D).visible = false

func _make_arrow(o: PlayerData, ally: bool) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * 0.85
	var buf := MeshGen.Buf.new()
	MeshGen.add_box(buf, Vector3(0.8, 0.8, 4.0), Transform3D(Basis(), Vector3(0, 0, 1.2)), o.color, 0.05)
	MeshGen.add_frustum(buf, 1.7, 0.05, 2.8, 8, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -1.7)), o.color, 0.05)
	var body := MeshInstance3D.new()
	body.mesh = buf.to_mesh()
	body.material_override = Toon.colored(o.color)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var mark := MeshInstance3D.new()
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ally:
		mark.mesh = MeshGen.ring_mesh(1.9, 2.5, 28)
		mark.material_override = Toon.unlit(Color("#46d36b"), false, true)
		mark.position = Vector3(0, -1.1, 0.4)
	else:
		var mb := MeshGen.Buf.new()
		# two crossed swords (blade, tip, crossguard, grip), tilted +-40 degrees
		for sg in [-1.0, 1.0]:
			var bs := Basis(Vector3.BACK, 0.7 * float(sg))
			MeshGen.add_box(mb, Vector3(0.42, 2.2, 0.3), Transform3D(bs, bs * Vector3(0, 0.5, 0)), Color("#e9edf2"), 0.03)
			MeshGen.add_frustum(mb, 0.21, 0.02, 0.7, 4, Transform3D(bs * Basis(Vector3.BACK, 0.0), bs * Vector3(0, 1.95, 0)), Color("#e9edf2"), 0.03)
			MeshGen.add_box(mb, Vector3(1.3, 0.3, 0.4), Transform3D(bs, bs * Vector3(0, -0.75, 0)), Color("#ff3b2e"), 0.03)
			MeshGen.add_box(mb, Vector3(0.3, 0.8, 0.3), Transform3D(bs, bs * Vector3(0, -1.3, 0)), Color("#b3261e"), 0.03)
		mark.mesh = mb.to_mesh()
		mark.material_override = Toon.colored(Color.WHITE)
		mark.position = Vector3(0, 2.4, 1.6)
	root.add_child(mark)
	world.add_child(root)
	return root

func _update_arrows() -> void:
	var me: PlayerData = _cur() if player_idx >= 0 and player_idx < Game.players.size() else null
	if not _active or world == null or me == null or me.is_cpu() or me.is_remote():
		_hide_arrows()
		return
	var t: float = float(Time.get_ticks_msec()) * 0.001
	for o in Game.players:
		if o.id == me.id or o.eliminated:
			if _arrows.has(o.id):
				(_arrows[o.id] as Node3D).visible = false
			continue
		var ally: bool = me.is_ally(o)
		var arrow: Node3D = _arrows.get(o.id) as Node3D
		if arrow == null or not is_instance_valid(arrow) or bool(arrow.get_meta("ally", false)) != ally:
			if arrow != null and is_instance_valid(arrow):
				arrow.queue_free()
			arrow = _make_arrow(o, ally)
			arrow.set_meta("ally", ally)
			_arrows[o.id] = arrow
		var dir: Vector3 = Util.flat(o.village_center - me.village_center)
		if dir.length() < 0.5:
			arrow.visible = false
			continue
		dir = dir.normalized()
		var at: Vector3 = me.village_center + dir * (Cfg.ZONE_RADIUS + 4.0)
		at.y = Terrain.h(at.x, at.z) + 6.0 + sin(t * 2.2 + float(o.id)) * 0.45
		arrow.global_transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), at)
		arrow.visible = true
