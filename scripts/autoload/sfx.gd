extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Sound synthesis + playback pool (autoload "Sfx", spec 17). Every sound is synthesized at startup into an
## AudioStreamWAV by worker threads (progress on the menu). NOTE: Node already owns a signal called `ready`,
## so the "synthesis finished" signal is `synth_ready`.

signal synth_ready
signal synth_progress(p: float)

const POOL_2D := 24
const POOL_3D := 24
## Voices of people and animals: quiet and local - they fade out quickly with the distance to the camera (small unit size,
## short range), so a distant village never babbles over the battle
const CREATURES: Array[String] = ["scream", "yeet", "boing", "squeak", "moo", "bawk", "baa", "neigh", "quack", "honk"]
const IMPACT_SOUNDS: Array[String] = ["thunk", "clack", "crunch", "clang", "tinkle", "fwump", "swish", "splat"]

var is_ready: bool = false
var streams: Dictionary = {}           # name -> Array[AudioStreamWAV]
var _threads: Array[Thread] = []
var _mutex := Mutex.new()
var _done_count: int = 0
var _total: int = 0
var _started: bool = false
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _prio_2d: Array[int] = []
var _prio_3d: Array[int] = []
var _start_2d: Array[float] = []
var _start_3d: Array[float] = []
var _impact_times: Array[float] = []
var _loops: Dictionary = {}            # name -> AudioStreamPlayer (persistent loops)
var _rng := RandomNumberGenerator.new()
var _pending: Dictionary = {}          # thread results while synthesizing
var slice_ms: int = 12                 # web build: milliseconds of synthesis per frame (a loading screen may raise it)
var _queue: Array = []                 # work items still to do on the main thread (web build, no threads)
var enabled: bool = true
var _t_start: int = 0
var synth_seconds: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players_2d.append(p)
		_prio_2d.append(0)
		_start_2d.append(0.0)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 20.0
		p3.max_distance = 250.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED          # no volume falloff with the distance (enemy villages were too quiet); only the direction (panning) stays
		p3.bus = "Master"
		add_child(p3)
		_players_3d.append(p3)
		_prio_3d.append(0)
		_start_3d.append(0.0)
	for sname in SoundRecipes.LOOPED:
		var lp := AudioStreamPlayer.new()
		lp.bus = "Master"
		lp.volume_db = -80.0
		add_child(lp)
		_loops[sname] = lp

## Starts the worker threads (idempotent). Progress: synth_progress(0..1), then synth_ready.
func begin_synthesis() -> void:
	if _started:
		if is_ready:
			synth_ready.emit()
		return
	_started = true
	_t_start = Time.get_ticks_msec()
	# work items: [name, variant]
	var work: Array = []
	for sname in SoundRecipes.NAMES:
		for v in SoundRecipes.variants_of(sname):
			work.append([sname, v])
	_total = work.size()
	if Cfg.single_threaded():
		work.reverse()
		_queue = work
		return
	var n_threads: int = clampi(OS.get_processor_count() - 1, 1, 4)
	var buckets: Array = []
	for i in n_threads:
		buckets.append([])
	for i in work.size():
		(buckets[i % n_threads] as Array).append(work[i])
	for b in buckets:
		var t := Thread.new()
		t.start(_worker.bind(b))
		_threads.append(t)

## Web build: makes sounds for `slice_ms` per frame (no threads there)
func _synth_slice() -> void:
	var t0: int = Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < slice_ms * 1000:
		var it: Array = _queue.pop_back() as Array
		var sname: String = str(it[0])
		var v: int = int(it[1])
		var stream: AudioStreamWAV = Synth.to_stream(SoundRecipes.make(sname, v), SoundRecipes.is_looped(sname))
		if not _pending.has(sname):
			_pending[sname] = {}
		(_pending[sname] as Dictionary)[v] = stream
		_done_count += 1

func _worker(items: Array) -> void:
	for it in items:
		var sname: String = str((it as Array)[0])
		var v: int = int((it as Array)[1])
		var buf: PackedFloat32Array = SoundRecipes.make(sname, v)
		var stream: AudioStreamWAV = Synth.to_stream(buf, SoundRecipes.is_looped(sname))
		_mutex.lock()
		if not _pending.has(sname):
			_pending[sname] = {}
		(_pending[sname] as Dictionary)[v] = stream
		_done_count += 1
		_mutex.unlock()

func _process(_delta: float) -> void:
	if _started and not is_ready:
		_synth_slice()
		_mutex.lock()
		var done: int = _done_count
		_mutex.unlock()
		synth_progress.emit(float(done) / float(maxi(_total, 1)))
		if done >= _total:
			for t in _threads:
				t.wait_to_finish()
			_threads.clear()
			for sname in _pending:
				var d: Dictionary = _pending[sname] as Dictionary
				var arr: Array = []
				var keys: Array = d.keys()
				keys.sort()
				for k in keys:
					arr.append(d[k])
				streams[sname] = arr
			_pending.clear()
			is_ready = true
			synth_seconds = float(Time.get_ticks_msec() - _t_start) / 1000.0
			for sname2 in SoundRecipes.LOOPED:
				var lp: AudioStreamPlayer = _loops[sname2] as AudioStreamPlayer
				var st: Array = streams.get(sname2, []) as Array
				if not st.is_empty():
					lp.stream = st[0] as AudioStream
					lp.play()
			synth_ready.emit()
	if is_ready:
		_update_loops(_delta)

func synth_started_msec() -> int:
	return _t_start

## Share of the sounds that are made (0..1)
func synth_fraction() -> float:
	return float(_done_count) / float(maxi(_total, 1))

func has_sound(sname: String) -> bool:
	return streams.has(sname) and not (streams[sname] as Array).is_empty()

func sound_names() -> Array:
	return streams.keys()

func _exit_tree() -> void:
	for t in _threads:
		if t.is_started():
			t.wait_to_finish()
	for p in _players_2d:
		p.stream = null
	for p3 in _players_3d:
		p3.stream = null
	for lp in _loops.values():
		(lp as AudioStreamPlayer).stream = null
	streams.clear()
	_pending.clear()

# ------------------------------------------------------------------ playback
## Sfx.play(name, position := Vector3.INF, volume := 1.0, priority := 0)   (INF = non-positional)
func play(sname: String, pos: Vector3 = Vector3.INF, volume: float = 1.0, priority: int = 0) -> void:
	if not is_ready or not enabled:
		return
	var arr: Array = streams.get(sname, []) as Array
	if arr.is_empty():
		return
	var now: float = Time.get_ticks_msec() * 0.001
	# no more than 6 impact sounds per 100 ms
	if IMPACT_SOUNDS.has(sname):
		var i: int = _impact_times.size() - 1
		while i >= 0:
			if now - _impact_times[i] > 0.1:
				_impact_times.remove_at(i)
			i -= 1
		if _impact_times.size() >= 6:
			return
		_impact_times.append(now)
	var stream: AudioStream = arr[_rng.randi() % arr.size()] as AudioStream
	var pitch: float = _rng.randf_range(0.92, 1.08)
	var db: float = linear_to_db(clampf(volume, 0.0001, 4.0))
	if pos == Vector3.INF:
		var idx: int = _pick(_players_2d, _prio_2d, _start_2d, priority)
		if idx < 0:
			return
		var p: AudioStreamPlayer = _players_2d[idx]
		p.stream = stream
		p.pitch_scale = pitch
		p.volume_db = db
		_prio_2d[idx] = priority
		_start_2d[idx] = now
		p.play()
	else:
		var idx3: int = _pick_3d(priority)
		if idx3 < 0:
			return
		var p3: AudioStreamPlayer3D = _players_3d[idx3]
		p3.stream = stream
		p3.pitch_scale = pitch
		var creature: bool = CREATURES.has(sname)
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE if creature else AudioStreamPlayer3D.ATTENUATION_DISABLED
		p3.unit_size = 5.0 if creature else 20.0
		p3.max_distance = 70.0 if creature else 0.0          # (0 = no limit)
		p3.volume_db = db - (3.0 if creature else 0.0)
		p3.global_position = pos
		_prio_3d[idx3] = priority
		_start_3d[idx3] = now
		p3.play()

func _pick(players: Array, prios: Array, starts: Array, priority: int) -> int:
	for i in players.size():
		if not (players[i] as AudioStreamPlayer).playing:
			return i
	# steal: lowest priority (<= priority), oldest first
	var best: int = -1
	var best_score: float = 1e18
	for i in players.size():
		var pr: int = int(prios[i])
		if pr > priority:
			continue
		var score: float = float(pr) * 1000.0 + float(starts[i])
		if score < best_score:
			best_score = score
			best = i
	return best

func _pick_3d(priority: int) -> int:
	for i in _players_3d.size():
		if not _players_3d[i].playing:
			return i
	var best: int = -1
	var best_score: float = 1e18
	for i in _players_3d.size():
		var pr: int = _prio_3d[i]
		if pr > priority:
			continue
		var score: float = float(pr) * 1000.0 + _start_3d[i]
		if score < best_score:
			best_score = score
			best = i
	return best

## A looping sound that follows a node (the sizzling fuse of a flying powder keg). Caller frees it with the node.
func attach_loop(sname: String, parent: Node3D, volume: float = 1.0) -> AudioStreamPlayer3D:
	if not is_ready or not enabled:
		return null
	var arr: Array = streams.get(sname, []) as Array
	if arr.is_empty():
		return null
	var p3 := AudioStreamPlayer3D.new()
	p3.stream = arr[0] as AudioStream
	p3.unit_size = 14.0
	p3.max_distance = 140.0
	p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	p3.volume_db = linear_to_db(clampf(volume, 0.0001, 4.0))
	p3.bus = "Master"
	parent.add_child(p3)
	p3.play()
	return p3

func play_delayed(sname: String, delay: float, pos: Vector3 = Vector3.INF, volume: float = 1.0) -> void:
	if delay <= 0.02:
		play(sname, pos, volume, 3)
		return
	get_tree().create_timer(delay, true, false, true).timeout.connect(func() -> void: play(sname, pos, volume, 3))

# ------------------------------------------------------------------ looped ambience
var _loop_vol: Dictionary = {"fire_loop": 0.0, "rain_loop": 0.0, "gust": 0.0, "buzz": 0.0}

func _update_loops(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var target: Dictionary = {"fire_loop": 0.0, "rain_loop": 0.0, "gust": 0.0, "buzz": 0.0}
	if Game.state == Game.State.BATTLE or Game.state == Game.State.PLACEMENT:
		# fire crackle: number of fires near the camera
		if cam != null:
			var near_fires: int = 0
			for p in Fire.burning_list:
				if p.xf.origin.distance_to(cam.global_position) < 45.0:
					near_fires += 1
					if near_fires >= 12:
						break
			target["fire_loop"] = clampf(float(near_fires) / 10.0, 0.0, 1.0) * 0.55
		if Game.weather == "rain" or Game.weather == "thunder":
			target["rain_loop"] = 0.35
		if Game.weather == "storm":
			target["gust"] = 0.55
		elif Game.wind.length() > 6.0:
			target["gust"] = 0.18
	for sname in _loop_vol:
		var cur: float = float(_loop_vol[sname])
		var tg: float = float(target[sname])
		cur = lerpf(cur, tg, clampf(delta * 3.0, 0.0, 1.0))
		_loop_vol[sname] = cur
		var lp: AudioStreamPlayer = _loops[sname] as AudioStreamPlayer
		lp.volume_db = linear_to_db(maxf(cur, 0.0001))
		if sname == "buzz":
			lp.pitch_scale = 1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.05
