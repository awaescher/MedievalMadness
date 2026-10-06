extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Background music (autoload "Music"): the songs of `MusicGen` are composed and synthesised in a worker thread once the sound effects
## are ready (the first song is playing after a few seconds, the others follow while it plays) and then play one after the other,
## quietly, on their own bus "Music" with its own volume (`Settings.music_volume`, quieter than the effects by default).

const BUS := "Music"

var _player: AudioStreamPlayer
var _thread: Thread
var _mutex := Mutex.new()
var _songs: Array = []                # AudioStreamWAV (ready ones, in song order; null = not yet)
var _next: int = 0
var _started: bool = false
var current: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or Settings._is_test_run():
		return                                   # no music in headless runs and automated tests
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, "Master")
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.finished.connect(_play_next)
	add_child(_player)
	for i in MusicGen.song_count():
		_songs.append(null)
	apply_volume()
	if Sfx.is_ready:
		_start()
	else:
		Sfx.synth_ready.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	if _started:
		return
	_started = true
	_thread = Thread.new()
	_thread.start(_worker)

func _worker() -> void:
	# a random song first, then the others (so a short visit does not always hear the same tune)
	var first: int = randi() % MusicGen.song_count()
	for k in MusicGen.song_count():
		var i: int = (first + k) % MusicGen.song_count()
		var s: AudioStreamWAV = MusicGen.render_song(i)
		_mutex.lock()
		_songs[i] = s
		_mutex.unlock()
		if k == 0:
			_next = i

func _process(_delta: float) -> void:
	if _player == null or _player.playing:
		return
	_play_next()

func _play_next() -> void:
	_mutex.lock()
	var n: int = _songs.size()
	var pick: int = -1
	var start: int = (current + 1) % n if current >= 0 else _next
	for k in n:
		var i: int = (start + k) % n
		if _songs[i] != null:
			pick = i
			break
	var stream: AudioStream = _songs[pick] as AudioStream if pick >= 0 else null
	_mutex.unlock()
	if stream == null:
		return
	current = pick
	_player.stream = stream
	_player.play()
	print("[music] playing \"%s\" (%.0f s)" % [MusicGen.song_name(pick), (stream as AudioStreamWAV).get_length()])

func apply_volume() -> void:
	var idx: int = AudioServer.get_bus_index(BUS)
	if idx < 0:
		return
	var v: float = clampf(Settings.music_volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
