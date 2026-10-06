class_name MapMarker
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## The per-player map marker (spec 6.7): a tall beacon (pole, pennant, pulsing ground ring, faint light beam).
## One node for the whole game; it always shows the marker of the player whose turn it is (hot-seat friendly).

const BEAM_H := 90.0

var _pole: MeshInstance3D
var _flag: MeshInstance3D
var _ring: MeshInstance3D
var _beam: MeshInstance3D
var _flag_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _t: float = 0.0
var cam: CameraRig
var slot: int = -1          # -1: the viewer's own marker; otherwise the marker of that (allied) seat
var _label: Label3D

func _ready() -> void:
	visible = false
	_pole = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.12
	pm.bottom_radius = 0.16
	pm.height = 8.0
	pm.radial_segments = 6
	pm.rings = 1
	_pole.mesh = pm
	_pole.position = Vector3(0, 4.0, 0)
	_pole.material_override = _mat(Color("#fff4d6"), false)
	_pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pole)
	_flag = MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(3.2, 1.9, 0.12)
	_flag.mesh = fm
	_flag.rotation = Vector3(0, 0, -PI * 0.5)
	_flag.position = Vector3(1.6, 6.8, 0)
	_flag_mat = _mat(Color.WHITE, false)
	_flag.material_override = _flag_mat
	_flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flag)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	tm.rings = 24
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring_mat = _mat(Color.WHITE, true)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 0.25, 0)
	add_child(_ring)
	_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.25
	bm.bottom_radius = 0.9
	bm.height = BEAM_H
	bm.radial_segments = 8
	bm.rings = 1
	bm.cap_top = false
	bm.cap_bottom = false
	_beam.mesh = bm
	_beam.position = Vector3(0, BEAM_H * 0.5, 0)
	_beam_mat = _mat(Color.WHITE, true)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = 200.0
	add_child(_beam)
	if slot >= 0:
		_label = Label3D.new()
		_label.font = Speech.ui_font()
		_label.font_size = 40
		_label.outline_size = 10
		_label.outline_modulate = Color(0.08, 0.05, 0.1)
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.fixed_size = true
		_label.pixel_size = 0.0007
		_label.no_depth_test = true
		_label.shaded = false
		_label.position = Vector3(0, 10.5, 0)
		add_child(_label)

func _mat(c: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _process(delta: float) -> void:
	var p: PlayerData = Game.viewer() if Game.state == Game.State.BATTLE else null
	if p != null and slot >= 0:
		var mate: PlayerData = Game.player(slot)
		p = mate if p.is_ally(mate) else null
	if p == null or p.marker == Vector3.INF:
		visible = false
		return
	visible = true
	_t += delta
	position = p.marker
	var col: Color = p.color.lightened(0.25)
	if _label != null:
		_label.text = p.name
		_label.modulate = col.lightened(0.3)
	_flag_mat.albedo_color = col
	# keep it readable from far away: the whole beacon grows in proportion (pole, pennant, ring, beam), never only the pennant
	var d: float = 60.0
	if cam != null:
		d = cam.camera_position().distance_to(position)
	var hs: float = clampf(d / 70.0, 1.0, 5.0)
	_pole.scale = Vector3(hs * 0.6, hs, hs * 0.6)
	_pole.position = Vector3(0, 4.0 * hs, 0)
	_flag.scale = Vector3.ONE * hs
	_flag.position = Vector3(1.6 * hs, 6.8 * hs, 0)
	var pulse: float = fmod(_t * 0.9, 1.0)
	_ring.scale = Vector3(hs, hs, hs) * 1.2 * (0.7 + pulse * 1.3)
	var ring_col := Color(col.r, col.g, col.b, 1.0)
	_ring_mat.albedo_color = ring_col * (1.0 - pulse) * 0.9
	_beam.scale = Vector3(hs * 0.7, 1.0, hs * 0.7)
	var bc: Color = col
	_beam_mat.albedo_color = Color(bc.r, bc.g, bc.b, 1.0) * (0.42 + 0.1 * sin(_t * 3.0))
	# the pennant waves a little
	_flag.rotation.y = sin(_t * 2.3) * 0.25
