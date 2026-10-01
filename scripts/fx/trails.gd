class_name Trail
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Camera-facing ribbon trail behind a moving point (projectiles). Additive, vertex colored.

var _mesh := ImmediateMesh.new()
var _mi: MeshInstance3D
var _pts: Array[Vector3] = []
var max_points: int = 22
var width: float = 0.35
var color: Color = Color(1, 1, 1, 0.8)
var fade_out: bool = false

static func reset_statics() -> void:
	pass

func _init() -> void:
	top_level = true

func _ready() -> void:
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = Toon.unlit(Color(1, 1, 1, 1), true)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 200.0
	add_child(_mi)

func push(p: Vector3) -> void:
	_pts.append(p)
	while _pts.size() > max_points:
		_pts.pop_front()

func stop() -> void:
	fade_out = true

func _process(_delta: float) -> void:
	if fade_out and not _pts.is_empty():
		_pts.pop_front()
		if _pts.is_empty():
			queue_free()
			return
	_mesh.clear_surfaces()
	if _pts.size() < 2:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n: int = _pts.size()
	for i in n:
		var p: Vector3 = _pts[i]
		var dir: Vector3
		if i < n - 1:
			dir = _pts[i + 1] - p
		else:
			dir = p - _pts[i - 1]
		if dir.length() < 0.0001:
			dir = Vector3.FORWARD
		var side: Vector3 = dir.cross(cp - p).normalized()
		var t: float = float(i) / float(n - 1)
		var w: float = width * t
		var c: Color = Color(color.r, color.g, color.b, color.a * t)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + side * w)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side * w)
	_mesh.surface_end()
