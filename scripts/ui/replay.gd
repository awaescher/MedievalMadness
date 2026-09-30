class_name ReplayUI
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Replay playback (spec 13.2): after a big shot (score > 600, at most once every 3 turns) the recorded transforms are
## re-applied in slow motion (0.4x) from a different camera angle while the world state is frozen; then restored.

signal finished

static var playing: bool = false
static var auto_skip: bool = false     # autotests skip replays

var cam: CameraRig
var _frames: Array[ReplayRec.Frame] = []
var _t: float = 0.0
var _saved: Dictionary = {}          # body id -> Transform3D (visual transform before the replay)
var _first_pose: Dictionary = {}     # body id -> Transform3D (first recorded pose)
var _ids: Array[int] = []
var _label: Label
var _hint: Label
var _grain: ColorRect
var _last_frame_idx: int = -1
var _focus: Vector3 = Vector3.ZERO
var _prev_mode: int = 0
var _fx_next: int = 0
var _speed: float = 0.5
var _ghosts: Array = []              # [{node, t}]: the original parts that die during the shot
var _first_seen: Dictionary = {}     # body id -> first frame index that contains it
var _hidden: Array[int] = []
var _t0: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_grain = ColorRect.new()
	_grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float border = 0.09;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + TIME) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float edge = 1.0 - smoothstep(0.0, border, d);
	float n = hash(FRAGCOORD.xy * 0.5);
	COLOR = vec4(vec3(0.03, 0.02, 0.05) + n * 0.35, edge * (0.55 + n * 0.3));
}
"""
	sm.shader = sh
	_grain.material = sm
	add_child(_grain)
	_label = UITheme.label(I18n.t("hud.replay"), 44, Color("#ff5b2e"), true, 12)
	_label.add_theme_font_override("font", ComicText.comic_font())
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -200
	_label.offset_right = 200
	_label.offset_top = 90
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	_hint = UITheme.label(I18n.t("hud.replay_hint"), 18, Color.WHITE, true, 8)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -60
	_hint.offset_bottom = -20
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

func start(camera: CameraRig, focus_pos: Vector3) -> bool:
	if not ReplayRec.has_frames() or auto_skip:
		return false
	cam = camera
	_frames = ReplayRec.frames.duplicate()
	_focus = focus_pos
	_t = 0.0
	_last_frame_idx = -1
	_fx_next = 0
	# save the current visual transforms of every recorded body, remember its first recorded pose
	_saved.clear()
	_first_pose.clear()
	_ids.clear()
	for fr in _frames:
		for i in fr.ids.size():
			var id: int = fr.ids[i]
			if _first_pose.has(id):
				continue
			var pb: PhysWorld.PBody = PhysWorld.body(id)
			if pb == null or pb.visual == null or not is_instance_valid(pb.visual):
				continue
			var k: int = i * 7
			var basis_ := Basis(Quaternion(fr.data[k + 3], fr.data[k + 4], fr.data[k + 5], fr.data[k + 6]))
			_first_pose[id] = Transform3D(basis_, Vector3(fr.data[k], fr.data[k + 1], fr.data[k + 2]))
			_saved[id] = pb.visual.transform
			_ids.append(id)
	if _ids.is_empty():
		return false
	_t0 = _frames[0].t
	_build_ghosts()
	# freeze the real world
	PhysicsServer3D.set_active(false)
	# start every recorded body at its first recorded pose
	for id2 in _ids:
		var pb2: PhysWorld.PBody = PhysWorld.body(id2)
		pb2.visual.transform = _first_pose[id2] as Transform3D
	playing = true
	visible = true
	_label.text = I18n.t("hud.replay")
	_hint.text = I18n.t("hud.replay_hint")
	_prev_mode = cam.mode
	cam.mode = CameraRig.Mode.REPLAY
	cam.focus = _focus
	cam.dist = 26.0
	cam.pitch = deg_to_rad(28.0)
	cam.yaw = cam.yaw + PI * 0.6
	Events.banner.emit(I18n.t("banner.replay"), "replay")
	return true

## Re-create every part that was alive when the shot was fired and died during it; hide debris until it is born
func _build_ghosts() -> void:
	_ghosts.clear()
	_first_seen.clear()
	_hidden.clear()
	for fi in _frames.size():
		for id in _frames[fi].ids:
			if not _first_seen.has(id):
				_first_seen[id] = fi
	for id2 in _ids:
		if int(_first_seen.get(id2, 0)) > 0:
			var pbx: PhysWorld.PBody = PhysWorld.body(id2)
			if pbx != null and pbx.visual != null and is_instance_valid(pbx.visual):
				pbx.visual.visible = false
				_hidden.append(id2)
	var n: int = 0
	var no_ghost: bool = OS.get_environment("MM_NOGHOST") != ""
	for i in ReplayRec.snap_parts.size():
		if no_ghost:
			break
		var p: Part = ReplayRec.snap_parts[i] as Part
		if p.state != Part.State.DEAD or not ReplayRec.break_times.has(p):
			continue
		if p.structure == null or p.structure.root == null or not is_instance_valid(p.structure.root):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = Breakable.part_mesh(p)
		if p.glow:
			mi.material_override = Toon.emissive(p.color, 1.2)
		else:
			mi.material_override = Toon.main()
			mi.set_instance_shader_parameter("tint", Color.WHITE if p.shape == "compound" else p.color)
		p.structure.root.add_child(mi)
		mi.transform = ReplayRec.snap_xf[i] as Transform3D
		_ghosts.append({"node": mi, "t": float(ReplayRec.break_times[p])})
		n += 1
		if n >= 1500:
			break

func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	var skip: bool = false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		skip = true
	elif event is InputEventKey and (event as InputEventKey).pressed and ((event as InputEventKey).keycode == KEY_SPACE or (event as InputEventKey).keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ENTER):
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_end()

func _process(delta: float) -> void:
	if not playing:
		return
	var real_dt: float = delta / maxf(Engine.time_scale, 0.05)
	_t += real_dt * _speed
	var idx: int = int(_t / ReplayRec.STEP)
	if idx >= _frames.size():
		_end()
		return
	if idx != _last_frame_idx:
		_apply(idx)
		_last_frame_idx = idx
	# ghosts vanish at the moment their part broke
	var now: float = _t0 + _t
	for g in _ghosts:
		var gn: Node3D = g["node"] as Node3D
		if is_instance_valid(gn) and gn.visible and now >= float(g["t"]):
			gn.visible = false
	cam.focus = cam.focus.lerp(_focus, 0.05)

func _apply(idx: int) -> void:
	var fr: ReplayRec.Frame = _frames[idx]
	for i in fr.ids.size():
		var id: int = fr.ids[i]
		var pb: PhysWorld.PBody = PhysWorld.body(id)
		if pb == null or pb.visual == null or not is_instance_valid(pb.visual):
			continue
		var k: int = i * 7
		var basis_ := Basis(Quaternion(fr.data[k + 3], fr.data[k + 4], fr.data[k + 5], fr.data[k + 6]))
		pb.visual.transform = Transform3D(basis_, Vector3(fr.data[k], fr.data[k + 1], fr.data[k + 2]))
		pb.visual.visible = true
	for ev in fr.events:
		var e: Dictionary = ev as Dictionary
		if str(e["kind"]) == "explosion":
			Fx.explosion_visual(e["pos"] as Vector3, float(e["radius"]), Color("#ffb347"), float(e["radius"]) > 6.0)

func _end() -> void:
	if not playing:
		return
	playing = false
	visible = false
	for g in _ghosts:
		var gn: Node3D = g["node"] as Node3D
		if is_instance_valid(gn):
			gn.queue_free()
	_ghosts.clear()
	for hid in _hidden:
		var hb: PhysWorld.PBody = PhysWorld.body(hid)
		if hb != null and hb.visual != null and is_instance_valid(hb.visual):
			hb.visual.visible = true
	_hidden.clear()
	# restore the real world state
	for id in _ids:
		var pb: PhysWorld.PBody = PhysWorld.body(id)
		if pb != null and pb.visual != null and is_instance_valid(pb.visual):
			pb.visual.transform = pb.xform
	PhysicsServer3D.set_active(true)
	if cam != null:
		cam.mode = CameraRig.Mode.IMPACT
	finished.emit()
