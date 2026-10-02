class_name Actions
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## The two turn actions that replace a shot (human only): RELOCATE (W/S drive, A/D turn the selected catapult, Space/Enter
## ends the turn) and WALL (stone wall: ghost on the ground, Q/E turns it, click builds it, click on a wall stacks another
## layer - same handling as the palisade fences). The result is sent through Turn.do_action().

var world_root: Node3D
var cam: CameraRig
var enabled_for_input: bool = true
var overview_active: bool = false

var _mode: String = ""
var _cat: Catapult = null
var _start_pos: Vector3 = Vector3.ZERO
var _start_yaw: float = 0.0
var _moved: bool = false
var _hits: Dictionary = {}          # part id -> [x, y, z, damage]: what the catapult has knocked down while driving
var _bump_cool: float = 0.0
const RAM_DAMAGE := 450.0           # damage per second to a building part the frame drives into
# wall
var _ghost: Node3D
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _wall_yaw: float = 0.0
var _w_center: Vector3 = Vector3.INF
var _w_stack: Dictionary = {}
var _w_valid: bool = false
var _rng := Rng.new(5)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_ok = _ghost_mat(Color(0.3, 1.0, 0.35, 0.5))
	_mat_bad = _ghost_mat(Color(1.0, 0.25, 0.2, 0.5))

static func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func attach(root: Node3D) -> void:
	world_root = root
	_ghost = Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(Walls.WIDTH, Walls.LAYER_H, Walls.THICK)
	body.mesh = bm
	body.position = Vector3(0, Walls.LAYER_H * 0.5, 0)
	body.material_override = _mat_ok
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(body)
	for k in 5:
		var mm := MeshInstance3D.new()
		var mb := BoxMesh.new()
		mb.size = Vector3(0.78, 0.55, Walls.THICK)
		mm.mesh = mb
		mm.position = Vector3(-Walls.WIDTH * 0.5 + 0.39 + (Walls.WIDTH - 0.78) / 4.0 * float(k), Walls.LAYER_H + 0.275, 0)
		mm.material_override = _mat_ok
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(mm)
	root.add_child(_ghost)
	_ghost.visible = false

func _human_turn() -> bool:
	if Game.state != Game.State.BATTLE or Turn.phase != Turn.Phase.AIMING:
		return false
	var p: PlayerData = Game.cur()
	return p != null and p.is_human() and enabled_for_input and not overview_active

## Moves done but not confirmed are undone when the player picks something else
func _revert() -> void:
	if _cat != null and is_instance_valid(_cat) and _moved and not _cat.destroyed:
		_cat.place_at(_start_pos, _start_yaw)
		if Turn.sel == _cat:
			Turn.aim_yaw = _start_yaw
	_moved = false
	_cat = null
	_hits.clear()
	Turn.move_used = 0.0

func _process(delta: float) -> void:
	var mode: String = Turn.action_mode() if _human_turn() else ""
	if mode != _mode or (_cat != null and (Turn.sel != _cat or Turn.phase != Turn.Phase.AIMING)):
		if _mode == "relocate":
			_revert()
		_mode = mode
		if mode == "relocate" and Turn.sel != null:
			_cat = Turn.sel
			_start_pos = _cat.global_pos()
			_start_yaw = _cat.yaw
			_moved = false
			_hits.clear()
			Turn.move_used = 0.0
		elif mode == "wall":
			_wall_yaw = Turn.aim_yaw
	if _ghost != null:
		_ghost.visible = false
	match _mode:
		"relocate":
			_drive(delta)
		"wall":
			_update_wall(delta)

# ------------------------------------------------------------------ relocate
func _drive(delta: float) -> void:
	if _cat == null or _cat.destroyed:
		return
	var turn: float = 0.0
	if Input.is_key_pressed(KEY_A):
		turn += 1.0
	if Input.is_key_pressed(KEY_D):
		turn -= 1.0
	var fwd: float = 0.0
	if Input.is_key_pressed(KEY_W):
		fwd += 1.0
	if Input.is_key_pressed(KEY_S):
		fwd -= 1.0
	if turn == 0.0 and fwd == 0.0:
		return
	var yaw: float = _cat.yaw + turn * deg_to_rad(75.0) * delta
	var pos: Vector3 = _cat.global_pos()
	var step: float = fwd * 5.0 * delta
	if absf(step) > 0.0:
		var np: Vector3 = pos + Util.yaw_to_dir(yaw) * step
		if _spot_ok(np, yaw, delta):
			pos = np
			Turn.move_used += absf(step)
		else:
			step = 0.0
	if turn != 0.0 or step != 0.0:
		_cat.place_at(pos, yaw)
		_moved = true
		Turn.aim_yaw = yaw
		if cam != null:
			cam.aim_at(_cat.global_pos(), yaw, deg_to_rad(Turn.aim_elev))

## Own area, dry, not steep, no other catapult within 4 m. People, animals, crates and debris never stop the frame (props are
## shoved aside); buildings do not stop it either - it rams them: they take damage and only what survives blocks the way.
func _spot_ok(pos: Vector3, yaw: float, dt: float) -> bool:
	var p: PlayerData = Game.cur()
	if Util.dist_xz(pos, p.village_center) > Cfg.ZONE_RADIUS + 3.0:
		return false
	if Terrain.is_water(pos.x, pos.z) or Terrain.slope_deg(pos.x, pos.z) > 30.0:
		return false
	for o in Game.players:
		for c in o.catapults:
			if is_instance_valid(c) and c != _cat and not (c as Catapult).destroyed and Util.dist_xz((c as Catapult).global_pos(), pos) < 3.6:
				return false
	var blocked: bool = false
	var seen: Dictionary = {}
	var f: Vector3 = Util.yaw_to_dir(yaw)
	var source: Dictionary = Damage.make_source(p.id, "catapult")
	var rammed: Vector3 = Vector3.INF
	for off in [-0.9, 0.9]:
		var q: Vector3 = pos + f * float(off)
		PhysWorld.overlap_sphere(Vector3(q.x, Terrain.h(q.x, q.z) + 1.1, q.z), 1.0, func(pb: PhysWorld.PBody, _s: int, _r: RID) -> void:
			if pb == null or pb.owner == _cat or pb.kind == "projectile" or seen.has(pb.id):
				return
			seen[pb.id] = true
			if pb.kind == "catapult":
				blocked = true
			elif pb.kind == "struct":
				# a still dormant building: wake it up, its parts take the hit from the next step on
				Breakable.awaken(pb.owner as Structure)
				blocked = true
			elif pb.kind == "part" and pb.owner is Part:
				var part: Part = pb.owner as Part
				if part.structure.free_parts or part.state == Part.State.FREE:
					PhysWorld.apply_impulse(pb.id, (f * 1.0 + Vector3.UP * 0.3) * maxf(pb.mass, 1.0) * 3.0)
				elif part.state == Part.State.FROZEN:
					var amount: float = RAM_DAMAGE * dt
					Damage.damage_part(part, amount, source, f)
					var rec: Array = _hits.get(part.id, [part.xf.origin.x, part.xf.origin.y, part.xf.origin.z, 0.0]) as Array
					rec[3] = float(rec[3]) + amount
					_hits[part.id] = rec
					rammed = part.xf.origin
					if part.state != Part.State.DEAD:
						blocked = true, Cfg.LAYER_STRUCT | Cfg.LAYER_PART | Cfg.LAYER_PROP | Cfg.LAYER_CATAPULT)
	if rammed != Vector3.INF:
		_react(rammed)
	return not blocked

## Crash, shake and the neighbours' opinion about the driving
func _react(at: Vector3) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now < _bump_cool:
		return
	_bump_cool = now + 2.2
	Events.camera_shake.emit(0.25)
	Sfx.play("crunch", at, 0.9, 3)
	Fx.comic_kind("crash", at + Vector3.UP * 2.0)
	var near: Array[Settler] = []
	for st in Settler.all:
		if is_instance_valid(st) and st.state != Settler.State.DEAD and st.state != Settler.State.GONE and st.global_position.distance_to(at) < 18.0:
			near.append(st)
	near.sort_custom(func(x: Settler, y: Settler) -> bool: return x.global_position.distance_to(at) < y.global_position.distance_to(at))
	for k in mini(2, near.size()):
		Speech.say_random("speech.bump", near[k], near[k], _rng, 2.4)

## Damage the other machines have to repeat (online): [[x, y, z, damage], ...]; applied to the part nearest to the point
static func apply_hits(p: PlayerData, hits: Array) -> void:
	var source: Dictionary = Damage.make_source(p.id, "catapult")
	for h in hits:
		var a: Array = h as Array
		var at := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var best: Part = null
		var bd: float = 0.7
		for s in Breakable.structures:
			if s.free_parts or s.destroyed or not s.aabb.grow(0.8).has_point(at):
				continue
			for part in s.parts:
				if part.state == Part.State.DEAD:
					continue
				var d: float = part.xf.origin.distance_to(at)
				if d < bd:
					bd = d
					best = part
		if best != null:
			Damage.damage_part(best, float(a[3]), source, Vector3.ZERO)

func confirm_move() -> void:
	if _cat == null or not _moved:
		Events.toast.emit(I18n.t("action.move_first"))
		return
	var o: Vector3 = _cat.global_pos()
	var d: Dictionary = {"t": "move", "cat": _cat.index, "p": [o.x, o.y, o.z], "y": _cat.yaw, "hits": _hits.values()}
	Turn.drove_local = true  # the damage is already done on this machine
	_hits.clear()
	_moved = false           # keep it where it is
	_cat = null
	Turn.move_used = 0.0
	_mode = ""
	Turn.do_action(d)

# ------------------------------------------------------------------ wall
func _update_wall(delta: float) -> void:
	var rot: float = 0.0
	if Input.is_key_pressed(KEY_Q):
		rot += 1.0
	if Input.is_key_pressed(KEY_E):
		rot -= 1.0
	_wall_yaw += rot * deg_to_rad(120.0) * delta
	_w_center = Vector3.INF
	_w_stack = {}
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != self and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		return
	var p: PlayerData = Game.cur()
	var mp: Vector2 = get_viewport().get_mouse_position()
	var o: Vector3 = cam.cam.project_ray_origin(mp)
	var d: Vector3 = cam.cam.project_ray_normal(mp)
	var yaw: float = _wall_yaw
	var w: Dictionary = Walls.hover(p, o, d)
	if not w.is_empty():
		_w_stack = w
		_w_center = (w["center"] as Vector3) + Vector3.UP * Walls.LAYER_H * float(Walls.layer_count(w))
		yaw = float(w["yaw"])
		_w_valid = Walls.can_stack(w) and Walls.total_layers(p) < Walls.MAX_PER_PLAYER
	else:
		var hit: Vector3 = Terrain.pick(o, d, 500.0)
		if hit == Vector3.INF:
			return
		var sn: Dictionary = Walls.snap(p, hit, yaw)
		var c: Vector3 = sn["center"] as Vector3
		yaw = float(sn["yaw"])
		_w_valid = Walls.footprint_valid(p, c, yaw)
		_w_center = Walls.ground_base(c, yaw)
	_ghost.visible = true
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, yaw), _w_center)
	for g in _ghost.get_children():
		(g as MeshInstance3D).material_override = _mat_ok if _w_valid else _mat_bad

func _place_wall() -> void:
	if _w_center == Vector3.INF:
		return
	if not _w_valid:
		var p: PlayerData = Game.cur()
		var key: String = "action.wall_invalid"
		if Walls.total_layers(p) >= Walls.MAX_PER_PLAYER:
			key = "action.wall_max"
		elif not _w_stack.is_empty():
			key = "action.wall_high"
		Events.toast.emit(I18n.t(key))
		Sfx.play("clack", Vector3.INF, 0.4, 0)
		return
	var c: Vector3 = (_w_stack["center"] as Vector3) if not _w_stack.is_empty() else _w_center
	var yaw: float = float(_w_stack["yaw"]) if not _w_stack.is_empty() else _ghost_yaw()
	_mode = ""
	Turn.do_action({"t": "wall", "c": [c.x, c.y, c.z], "y": yaw, "stack": not _w_stack.is_empty()})

func _ghost_yaw() -> float:
	var a: Vector3 = _ghost.global_transform.basis * Vector3.RIGHT
	return atan2(-a.z, a.x)

func _unhandled_input(event: InputEvent) -> void:
	if _mode == "":
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if _mode == "wall" and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_place_wall()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			if _mode == "relocate":
				confirm_move()
			else:
				_place_wall()
			get_viewport().set_input_as_handled()
