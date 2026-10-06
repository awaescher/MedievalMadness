class_name MapTracker
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Map mode while somebody else plays: a pulsing ring + beam on the catapult that is on turn (in its player's colour) and a bright
## marker with a short trail on the projectile, both scaled with the camera distance so they stay readable from far away.

var cam: CameraRig
var active: bool = false
var _ring: MeshInstance3D
var _beam: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _ball: MeshInstance3D
var _ball_mat: StandardMaterial3D
var _trail: Array[MeshInstance3D] = []
var _trail_pos: Array[Vector3] = []
var _t: float = 0.0

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.disable_fog = true
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _ready() -> void:
	visible = false
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.4
	tm.outer_radius = 3.0
	tm.rings = 32
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring_mat = _mat(Color.WHITE)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.3
	bm.bottom_radius = 0.9
	bm.height = 60.0
	bm.cap_top = false
	bm.cap_bottom = false
	_beam.mesh = bm
	_beam_mat = _mat(Color.WHITE)
	_beam.material_override = _beam_mat
	_beam.position = Vector3(0, 30.0, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = 100.0
	add_child(_beam)
	_ball = MeshInstance3D.new()
	_ball.mesh = MeshGen.sphere_mesh(1.0, 8, 12)
	_ball_mat = _mat(Color("#fff6c0"))
	_ball.material_override = _ball_mat
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.top_level = true
	add_child(_ball)
	for i in 14:
		var m := MeshInstance3D.new()
		m.mesh = _ball.mesh
		m.material_override = _mat(Color(1.0, 0.8, 0.3, 0.0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.top_level = true
		add_child(m)
		_trail.append(m)

func _process(delta: float) -> void:
	_t += delta
	var cur: PlayerData = Game.cur()
	if not active or cur == null or cam == null:
		visible = false
		return
	visible = true
	var col: Color = cur.color.lightened(0.2)
	var spot: Vector3 = cur.village_center
	if Turn.sel != null and is_instance_valid(Turn.sel) and not Turn.sel.destroyed:
		spot = Turn.sel.global_pos()
	var d: float = cam.camera_position().distance_to(spot)
	var s: float = clampf(d / 60.0, 1.0, 6.0)
	global_position = spot
	var pulse: float = fmod(_t * 0.9, 1.0)
	_ring.scale = Vector3(s, s, s) * (1.2 + pulse * 1.6)
	_ring_mat.albedo_color = Color(col.r, col.g, col.b, (1.0 - pulse) * 0.95)
	_beam.scale = Vector3(s * 0.3, 1.0, s * 0.3)
	_beam_mat.albedo_color = Color(col.r, col.g, col.b, 0.30 + 0.08 * sin(_t * 4.0))
	# the projectile
	var pp: Vector3 = Vector3.INF
	if Projectile.primary != null and Projectile.primary.alive:
		pp = Projectile.primary.position()
	elif Projectile.last_pos != Vector3.INF and Projectile.any_alive():
		pp = Projectile.last_pos
	if pp == Vector3.INF:
		_ball.visible = false
		_trail_pos.clear()
		for m in _trail:
			m.visible = false
		return
	var ds: float = cam.camera_position().distance_to(pp)
	var r: float = clampf(ds / 38.0, 0.7, 6.0)
	_ball.visible = true
	_ball.global_position = pp
	_ball.scale = Vector3.ONE * r
	_ball_mat.albedo_color = Color(1.0, 0.97, 0.75, 0.95)
	if _trail_pos.is_empty() or _trail_pos[0].distance_to(pp) > r * 1.6:
		_trail_pos.push_front(pp)
		if _trail_pos.size() > _trail.size():
			_trail_pos.pop_back()
	for i in _trail.size():
		var m: MeshInstance3D = _trail[i]
		if i < _trail_pos.size():
			m.visible = true
			m.global_position = _trail_pos[i]
			m.scale = Vector3.ONE * r * (0.8 - 0.045 * float(i))
			(m.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.7, 0.25, 0.65 * (1.0 - float(i) / float(_trail.size())))
		else:
			m.visible = false
