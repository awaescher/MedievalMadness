class_name Flag
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Waving flag (spec 6.3): a small subdivided cloth quad with a sine vertex shader that streams downwind.

static var all: Array[Flag] = []
static var _mesh: ArrayMesh
static var _shader: Shader
static var world_root: Node3D

var structure: Structure = null
var mat: ShaderMaterial
var mast: Part = null
var _pole: MeshInstance3D
var _cloth: MeshInstance3D
var alive: bool = true

static func reset() -> void:
	for f in all:
		if is_instance_valid(f):
			f.queue_free()
	all.clear()

static func _cloth_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var buf := MeshGen.Buf.new()
	var nx: int = 8
	var ny: int = 4
	var ids: Array = []
	for j in ny + 1:
		var row: Array[int] = []
		for i in nx + 1:
			var u: float = float(i) / float(nx)
			var v: float = float(j) / float(ny)
			row.append(buf.vert(Vector3(u * 1.4, -v * 0.9, 0.0), Vector3(0, 0, 1), Color(1, 1, 1), Vector3.ZERO))
		ids.append(row)
	for j in ny:
		for i in nx:
			var a: int = (ids[j] as Array)[i]
			var b: int = (ids[j] as Array)[i + 1]
			var c: int = (ids[j + 1] as Array)[i + 1]
			var d: int = (ids[j + 1] as Array)[i]
			buf.quad(a, b, c, d, Vector3(0, 0, 1))
			buf.quad(a, d, c, b, Vector3(0, 0, -1))
	_mesh = buf.to_mesh()
	return _mesh

static func spawn(pos: Vector3, color: Color, s: Structure) -> Flag:
	var f := Flag.new()
	f.structure = s
	f.position = pos
	if _shader == null:
		_shader = load("res://scripts/render/shaders/flag.gdshader") as Shader
	f.mat = ShaderMaterial.new()
	f.mat.shader = _shader
	f.mat.set_shader_parameter("albedo", color)
	f._cloth = MeshInstance3D.new()
	f._cloth.mesh = _cloth_mesh()
	f._cloth.material_override = f.mat
	f._cloth.position = Vector3(0.05, 0.0, 0.0)
	f._cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(f._cloth)
	world_root.add_child(f)
	all.append(f)
	return f

## The owner's name floats above the village flag (small, no outline box, gone beyond ~140 m): you always see whose
## village you are hitting without the loud labels of the overview
func add_owner_name(owner_name: String, col: Color, flag_scale: float) -> void:
	var l := Label3D.new()
	l.font = Speech.ui_font()
	l.text = owner_name
	l.font_size = 56
	l.pixel_size = 0.0094 / maxf(flag_scale, 0.1)       # (the flag node is scaled up)
	l.outline_size = 16
	l.outline_modulate = Color(0.08, 0.05, 0.1, 1.0)
	l.modulate = col.lightened(0.6)
	l.modulate.a = 1.0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.no_depth_test = true          # never hidden behind a roof
	l.double_sided = true
	l.position = Vector3(0.7, 0.9, 0.0)
	l.visibility_range_end = 140.0
	l.visibility_range_end_margin = 30.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(l)

static func update_all(wind: Vector2, dt: float) -> void:
	var speed: float = wind.length()
	var yaw_t: float = atan2(wind.x, wind.y) - PI * 0.5 if speed > 0.1 else 0.0
	var i: int = all.size() - 1
	while i >= 0:
		var f: Flag = all[i]
		if not is_instance_valid(f):
			all.remove_at(i)
		else:
			if f.structure != null and (f.structure.destroyed or f.structure.destroyed_fraction() > 0.5):
				f.alive = false
			if not f.alive:
				f.scale = f.scale * maxf(1.0 - dt * 2.0, 0.01)
				f.position.y -= dt * 3.0
				if f.scale.x < 0.06:
					all.remove_at(i)
					f.queue_free()
			else:
				f.rotation.y = lerp_angle(f.rotation.y, yaw_t, minf(dt * 2.0, 1.0))
				f.mat.set_shader_parameter("strength", 0.6 + speed * 0.12)
		i -= 1
