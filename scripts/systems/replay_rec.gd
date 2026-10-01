class_name ReplayRec
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Best-hit replay recorder (spec 13.2): every 1/20 s the transforms of the top 150 moving bodies (+ the projectile) are
## stored in a ring buffer (max 12 s = 240 frames) together with explosion events. Playback (ui/replay.gd) re-applies the
## buffered transforms to the same meshes in slow motion while the real world state is frozen.

const MAX_FRAMES := 240
const MAX_BODIES := 150
const STEP := 0.05

class Frame extends RefCounted:
	var t: float = 0.0
	var ids: PackedInt32Array = PackedInt32Array()
	var data: PackedFloat32Array = PackedFloat32Array()    # 7 floats per id: px py pz qx qy qz qw
	var events: Array = []                                  # [{kind, pos, radius, color}]

static var frames: Array[Frame] = []
static var recording: bool = false
static var _acc: float = 0.0
static var _time: float = 0.0
static var pending_events: Array = []
static var connected: bool = false
static var focus: Vector3 = Vector3.ZERO
## State of the settlement at the moment of firing: every live part with its pose. Parts that die during the shot are
## re-created as "ghosts" by the replay so it shows the ORIGINAL buildings being destroyed, not the ruins.
static var snap_parts: Array = []
static var snap_xf: Array = []
static var break_times: Dictionary = {}     # Part -> recorder time at which it died

static func reset() -> void:
	frames.clear()
	recording = false
	pending_events.clear()
	snap_parts.clear()
	snap_xf.clear()
	break_times.clear()

static var _abs: int = 0
static var impact_abs: int = -1

static func begin() -> void:
	frames.clear()
	pending_events.clear()
	snap_parts.clear()
	snap_xf.clear()
	break_times.clear()
	for s in Breakable.structures:
		if s.destroyed and s.live_count <= 0:
			continue
		for p in s.parts:
			if p.state != Part.State.DEAD and p.shape != "":
				snap_parts.append(p)
				snap_xf.append(p.xf)
	recording = true
	_acc = 0.0
	_time = 0.0
	_abs = 0
	impact_abs = -1
	if not connected:
		connected = true
		Events.explosion.connect(func(pos: Vector3, radius: float, _d: float, _s: Dictionary) -> void:
			if recording:
				pending_events.append({"kind": "explosion", "pos": pos, "radius": radius}))

## The first impact of the shot happened now: remember the frame so the replay can be cropped around it
static func on_part_dead(p: Part) -> void:
	if recording and not break_times.has(p):
		break_times[p] = _time

static func mark_impact() -> void:
	if recording and impact_abs < 0:
		impact_abs = _abs

static func stop() -> void:
	recording = false
	# crop to 1.5 s before and 5 s after the first impact (spec: max 12 s buffer)
	if impact_abs >= 0 and not frames.is_empty():
		var first_abs: int = _abs - frames.size() + 1
		var lo: int = clampi(impact_abs - 30 - first_abs, 0, frames.size() - 1)
		var hi: int = clampi(impact_abs + 100 - first_abs, lo, frames.size() - 1)
		frames = frames.slice(lo, hi + 1)

static func has_frames() -> bool:
	return frames.size() >= 12

static func tick(dt: float) -> void:
	if not recording:
		return
	_acc += dt
	while _acc >= STEP:
		_acc -= STEP
		_time += STEP
		_capture()

static func _capture() -> void:
	var f := Frame.new()
	f.t = _time
	var f_now: int = Engine.get_physics_frames()
	# collect moving bodies, keep the 150 fastest
	var cand: Array = []
	for id in PhysWorld.bodies:
		var pb: PhysWorld.PBody = PhysWorld.bodies[id] as PhysWorld.PBody
		if pb.visual == null or pb.mass <= 0.0 or f_now - pb.last_active > 3:
			continue
		if pb.kind == "catapult":
			continue
		cand.append(pb)
	if cand.size() > MAX_BODIES:
		var scored: Array = []
		for pb2 in cand:
			var p2: PhysWorld.PBody = pb2 as PhysWorld.PBody
			var sp: float = PhysWorld.get_velocity(p2.id).length_squared()
			if p2.kind == "projectile":
				sp += 1e6
			scored.append([sp, p2])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		cand.clear()
		for i in MAX_BODIES:
			cand.append((scored[i] as Array)[1])
	f.ids.resize(cand.size())
	f.data.resize(cand.size() * 7)
	for i in cand.size():
		var pb3: PhysWorld.PBody = cand[i] as PhysWorld.PBody
		f.ids[i] = pb3.id
		var q: Quaternion = pb3.xform.basis.get_rotation_quaternion()
		var o: Vector3 = pb3.xform.origin
		var k: int = i * 7
		f.data[k] = o.x
		f.data[k + 1] = o.y
		f.data[k + 2] = o.z
		f.data[k + 3] = q.x
		f.data[k + 4] = q.y
		f.data[k + 5] = q.z
		f.data[k + 6] = q.w
	f.events = pending_events.duplicate()
	pending_events.clear()
	_abs += 1
	frames.append(f)
	if frames.size() > MAX_FRAMES:
		frames.pop_front()
