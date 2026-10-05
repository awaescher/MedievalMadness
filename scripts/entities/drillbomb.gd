class_name DrillBomb
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Drill bomb (spec 6.4 "drillbomb"). The fired bomb calls `start()` where it lands. It waits WAIT seconds, then drills
## straight down for DRILL_TIME seconds until it reaches sea level (y = 0), where it blows up UNDERGROUND with the size of
## the Mighty Powder Keg. The ground above has nothing to stand on any more: it sinks into the cavity (a bell-shaped
## sinkhole that is dug in several steps), whatever stood on it loses its footing and comes down, and the rim slides in
## after it (a forced landslide).

const WAIT := 0.5
const DRILL_TIME := 2.0
const TARGET_Y := 0.0                # "zero level" of the map: the bomb drills down to here
const MIN_COVER := 1.5               # on low ground it still stays at least this far below the surface
const BLAST_RADIUS := 12.0           # same as the Mighty Powder Keg
const BLAST_DAMAGE := 1700.0
const SINK_RADIUS := 26.0            # radius of the sinkhole (metres)
const SINK_TIME := 1.6
const SINK_STEPS := 8
const TIP_OFF := 1.05                # the drill tip hangs this far below the centre of the bomb

static var bombs: Array[DrillBomb] = []
static var rng: Rng = Rng.new(57)
static var last_boom: float = -100.0
static var boom_pos: Vector3 = Vector3.INF
static var _clock: float = 0.0

var source: Dictionary = {}
var state: int = 0                   # 0 falls / waits, 1 drills, 2 sinking ground, 3 done
var x: float = 0.0
var z: float = 0.0
var y: float = 0.0                   # centre of the bomb
var vy: float = 0.0
var ground_y: float = 0.0
var end_y: float = 0.0               # where the bomb blows up
var t: float = 0.0                   # time in the current state
var root: Node3D
var _grounded: bool = false
var _fx_acc: float = 0.0
var _snd: AudioStreamPlayer3D = null
var _steps_done: int = 0
var _sink_depth: float = 0.0
var _spin: float = 0.0

static func reset() -> void:
	for b in bombs:
		b._free_nodes()
	bombs.clear()
	_clock = 0.0
	last_boom = -100.0
	boom_pos = Vector3.INF

## A bomb is still working (waiting, drilling, or the ground is still sinking)
static func active() -> bool:
	for b in bombs:
		if b.state < 3:
			return true
	return false

static func start(pos: Vector3, src: Dictionary) -> void:
	var b := DrillBomb.new()
	b.source = src
	b.x = pos.x
	b.z = pos.z
	b.ground_y = Terrain.h(pos.x, pos.z) if Terrain.current != null else pos.y
	b.y = maxf(pos.y, b.ground_y + TIP_OFF - 0.1)
	b.end_y = minf(TARGET_Y, b.ground_y - MIN_COVER)
	b._build()
	bombs.append(b)
	Events.banner.emit(I18n.t("banner.drillbomb"), "info")

## The model: a round black bomb with an amber band, a fuse on top and a steel drill below (the drill points down, -Y).
## The bomb's centre is the origin; the tip is TIP_OFF below it.
static func build_mesh(buf: MeshGen.Buf) -> void:
	MeshGen.add_sphere(buf, 0.42, Transform3D(Basis(), Vector3.ZERO), Color("#2b2b33"), 0.0, 8, 12)
	MeshGen.add_cyl(buf, 0.435, 0.11, 12, Transform3D(Basis(), Vector3(0, 0.05, 0)), Color("#c9962a"))
	MeshGen.add_cyl(buf, 0.33, 0.09, 12, Transform3D(Basis(), Vector3(0, -0.34, 0)), Color("#6d7683"))
	MeshGen.add_frustum(buf, 0.03, 0.3, 0.74, 10, Transform3D(Basis(), Vector3(0, -0.68, 0)), Color("#9aa3ad"))
	# the thread of the drill: small ridges that wind around the cone
	for i in 7:
		var u: float = float(i) / 7.0
		var r: float = 0.3 * (1.0 - u * 0.88) - 0.01
		var a: float = float(i) * 1.15
		MeshGen.add_box(buf, Vector3(0.13, 0.07, 0.07), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * r, -0.42 - u * 0.58, sin(a) * r)), Color("#d4d9e0"))
	# the fuse
	MeshGen.add_cyl(buf, 0.12, 0.08, 8, Transform3D(Basis(), Vector3(0, 0.44, 0)), Color("#6d7683"))
	MeshGen.add_cyl(buf, 0.03, 0.3, 5, Transform3D(Basis(), Vector3(0, 0.62, 0)), Color("#e8c060"))

func _build() -> void:
	if Game.world == null or not is_instance_valid(Game.world.fx_root):
		return
	root = Node3D.new()
	Game.world.fx_root.add_child(root)
	var buf := MeshGen.Buf.new()
	build_mesh(buf)
	var mi := MeshInstance3D.new()
	mi.mesh = buf.to_mesh()
	mi.material_override = Toon.main()
	root.add_child(mi)
	root.global_position = Vector3(x, y, z)

func _free_nodes() -> void:
	if _snd != null and is_instance_valid(_snd):
		_snd.stop()
		_snd.queue_free()
	_snd = null
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null

static func tick_all(dt: float) -> void:
	_clock += dt
	var i: int = bombs.size() - 1
	while i >= 0:
		var b: DrillBomb = bombs[i]
		b._tick(dt)
		if b.state >= 3:
			b._free_nodes()
			bombs.remove_at(i)
		i -= 1

func _tick(dt: float) -> void:
	t += dt
	match state:
		0:
			_tick_wait(dt)
		1:
			_tick_drill(dt)
		2:
			_tick_sink(dt)

## falls the last bit if it hit a roof, then lies there for WAIT seconds
func _tick_wait(dt: float) -> void:
	var rest_y: float = ground_y + TIP_OFF - 0.1
	if not _grounded:
		vy -= 9.81 * dt
		y += vy * dt
		if y <= rest_y:
			y = rest_y
			_grounded = true
			t = 0.0
			Fx.burst("dust", Vector3(x, ground_y, z), Color("#8a6d4a"), 0.6, Vector3.UP)
			Sfx.play("thunk", Vector3(x, ground_y, z), 0.8, 2)
	elif t >= WAIT:
		state = 1
		t = 0.0
		# the drill bites: a small entry hole
		if Terrain.current != null:
			Terrain.current.dig(Vector3(x, ground_y, z), 1.1, 0.3, 0.1, 0.6)
		_snd = Sfx.attach_loop("drill", root, 1.0) if root != null else null
	_sync()

func _tick_drill(dt: float) -> void:
	var u: float = clampf(t / DRILL_TIME, 0.0, 1.0)
	# starts slowly, bores faster once it has bitten in
	var e: float = u * u * (3.0 - 2.0 * u) * 0.6 + u * 0.4
	var top: float = ground_y + TIP_OFF - 0.1
	y = lerpf(top, end_y, e)
	_spin += dt * (14.0 + 20.0 * u)
	_fx_acc += dt
	var pos := Vector3(x, ground_y, z)
	if _fx_acc >= 0.06:
		_fx_acc = 0.0
		# soil flies out of the hole, the ground trembles
		Fx.burst("dust", pos + Vector3(0, 0.1, 0), Color("#8a6d4a"), 0.35, Vector3.UP)
		if rng.chance(0.4):
			Fx.burst("splinter", pos + Vector3(0, 0.2, 0), Color("#6a4a2a"), 0.3)
		Events.camera_shake.emit(0.06 + 0.12 * u)
	if root != null:
		root.rotation = Vector3(rng.range_f(-0.03, 0.03), _spin, rng.range_f(-0.03, 0.03))
	_sync()
	if u >= 1.0:
		_detonate()

func _sync() -> void:
	if root != null:
		root.global_position = Vector3(x + (rng.range_f(-0.03, 0.03) if state == 1 else 0.0), y, z)

## The bomb blows up at sea level, deep under the surface
func _detonate() -> void:
	var blast := Vector3(x, y, z)
	var surface := Vector3(x, ground_y, z)
	if _snd != null and is_instance_valid(_snd):
		_snd.stop()
		_snd.queue_free()
	_snd = null
	if root != null:
		root.visible = false
	Explosion.explode(blast, BLAST_RADIUS, BLAST_DAMAGE, {"source": source, "sound": "bigboom", "fire": false, "no_crater": true, "shock": true})
	# the blast is hidden by the ground: dirt and dust burst out of the surface instead
	for k in 5:
		var a: float = rng.range_f(0.0, TAU)
		var off := Vector3(cos(a), 0.0, sin(a)) * rng.range_f(0.0, 6.0)
		Fx.burst("dust", surface + off, Color("#8a6d4a"), 1.0, Vector3.UP)
	Fx.burst("splinter", surface, Color("#6a4a2a"), 1.0)
	Fx.comic_kind("explosion", surface + Vector3.UP * 3.0)
	Events.camera_shake.emit(1.2)
	last_boom = _clock
	boom_pos = surface
	state = 2
	t = 0.0
	_steps_done = 0
	_sink_depth = clampf((ground_y - end_y) * 0.5 + 4.0, 6.0, 18.0)
	# whoever stands over the cavity falls into it
	Damage.damage_settlers_in_radius(surface, SINK_RADIUS * 0.8, 90.0, source, Vector3.DOWN, 0.2)
	Sfx.play("crunch", surface, 1.0, 4)

## The ground sinks into the cavity in several steps; after every step whatever hangs over it loses its footing
func _tick_sink(_dt: float) -> void:
	var want: int = mini(int(t / SINK_TIME * float(SINK_STEPS)) + 1, SINK_STEPS)
	while _steps_done < want:
		_steps_done += 1
		if Terrain.current != null:
			var c := Vector3(x, ground_y, z)
			Terrain.current.dig(c, SINK_RADIUS, _sink_depth / float(SINK_STEPS), 0.15, 0.55)
			Breakable.ground_changed(AABB(Vector3(x - SINK_RADIUS - 2.0, -60.0, z - SINK_RADIUS - 2.0), Vector3((SINK_RADIUS + 2.0) * 2.0, 220.0, (SINK_RADIUS + 2.0) * 2.0)))
			Fx.burst("dust", c + Vector3(rng.range_f(-9.0, 9.0), 0.2, rng.range_f(-9.0, 9.0)), Color("#8a6d4a"), 0.8, Vector3.UP)
		Sfx.play("crunch", Vector3(x, ground_y, z), 0.9, 3)
		Events.camera_shake.emit(0.5)
	if _steps_done >= SINK_STEPS and t >= SINK_TIME:
		# the edges of the hole are steep now: the soil slides in after it
		Landslide.trigger(Vector3(x, Terrain.h(x, z), z), 4.0, source, true)
		Events.banner.emit(I18n.t("banner.cavein"), "info")
		state = 3
