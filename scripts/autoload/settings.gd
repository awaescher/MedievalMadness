extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Persistent settings (autoload "Settings"), stored via ConfigFile at user://settings.cfg (spec 18.3).

const PATH := "user://settings.cfg"
const QUALITY_TIERS: Array[String] = ["low", "medium", "high", "ultra"]
const LIGHTING_MODES: Array[String] = ["basic", "enhanced", "rt"]

var language: String = "en"
var volume: float = 0.8
var quality: String = "medium"
var relay_url: String = Cfg.DEFAULT_RELAY             # online play: wss://<your worker>.workers.dev (see relay/README.md)
var net_name: String = ""
var lighting: String = "enhanced"      # basic | enhanced | rt (needs the Forward+ renderer)
var shake: bool = true
var timer: int = 0
var weather_on: bool = true
var events_on: bool = true
var crates_on: bool = true               # supply crates (meteor crate + small boulder / log crates)
var auto_quality: bool = true
var fullscreen: bool = false
var vsync: bool = true
var cpu_particles: bool = false
var win_size: Vector2i = Vector2i(1600, 900)
var players: Array = []      # last used player list: [{name, color, type}]
var player_count: int = 4
var seed_text: String = ""
var catapult_count: int = 3
var palisade_count: int = 4
var terrain_hills: int = 2
var arsenal_preset: String = "standard"   # standard | powerplay | chaos | quarry | custom (see Arsenal)
var rules_level: int = 0                  # unlock rules of the Custom mode: 0 core, 1 power, 2 chaos (presets bring their own)
var arsenal_custom: Dictionary = {}       # the player's own selection: ammo id -> count (-1 = unlimited), saved on this machine
## Which unlock rules the chosen mode uses (see Unlocks.RULES): Standard / Quarry core, Powerplay +power, Chaos +chaos
func effective_rule_level() -> int:
	match arsenal_preset:
		"powerplay":
			return 1
		"chaos":
			return 2
		"custom":
			return rules_level
	return 0

## The starting arsenal of the chosen preset: ammo id -> count (-1 = unlimited)
var arsenal_edit: Dictionary = {}         # a preset tweaked in the dialog: this session only, never saved
var arsenal_edit_preset: String = ""
var arsenal: Dictionary:
	get:
		if arsenal_edit_preset != "" and arsenal_edit_preset == arsenal_preset:
			return arsenal_edit.duplicate()
		return Arsenal.counts(arsenal_preset, arsenal_custom)
var debug: bool = false

func _ready() -> void:
	debug = OS.is_debug_build() or "--debug" in OS.get_cmdline_user_args()
	load_settings()

func load_settings() -> void:
	var cf := ConfigFile.new()
	var err: int = cf.load(PATH)
	if err != OK:
		return   # missing / corrupt file: silently use defaults
	language = str(cf.get_value("main", "language", language))
	if language != "en" and language != "de":
		language = "en"
	volume = clampf(float(cf.get_value("main", "volume", volume)), 0.0, 1.0)
	quality = str(cf.get_value("main", "quality", quality))
	if not QUALITY_TIERS.has(quality):
		quality = "medium"
	lighting = str(cf.get_value("main", "lighting", lighting))
	if not LIGHTING_MODES.has(lighting):
		lighting = "enhanced"
	relay_url = str(cf.get_value("main", "relay_url", relay_url))
	if relay_url.strip_edges() == "":
		relay_url = Cfg.DEFAULT_RELAY
	net_name = str(cf.get_value("main", "net_name", net_name))
	shake = bool(cf.get_value("main", "shake", shake))
	timer = int(cf.get_value("main", "timer", timer))
	if not [0, 20, 30, 45, 60].has(timer):
		timer = 0
	weather_on = bool(cf.get_value("main", "weather_on", weather_on))
	events_on = bool(cf.get_value("main", "events_on", events_on))
	crates_on = bool(cf.get_value("main", "crates_on", crates_on))
	auto_quality = bool(cf.get_value("main", "auto_quality", auto_quality))
	fullscreen = bool(cf.get_value("main", "fullscreen", fullscreen))
	vsync = bool(cf.get_value("main", "vsync", vsync))
	cpu_particles = bool(cf.get_value("main", "cpu_particles", cpu_particles))
	player_count = clampi(int(cf.get_value("main", "player_count", player_count)), Cfg.MIN_PLAYERS, Cfg.MAX_PLAYERS)
	seed_text = str(cf.get_value("main", "seed_text", seed_text))
	catapult_count = clampi(int(cf.get_value("main", "catapult_count", catapult_count)), 1, Cfg.CATAPULTS_PER_PLAYER)
	palisade_count = clampi(int(cf.get_value("main", "palisade_count", palisade_count)), 1, 10)
	terrain_hills = clampi(int(cf.get_value("main", "terrain_hills", terrain_hills)), 0, 4)
	arsenal_preset = str(cf.get_value("main", "arsenal_preset", arsenal_preset))
	if not Arsenal.PRESETS.has(arsenal_preset):
		arsenal_preset = "standard"
	rules_level = clampi(int(cf.get_value("main", "rules_level", rules_level)), 0, 2)
	var ac: Variant = cf.get_value("main", "arsenal_custom", {})
	if ac is Dictionary:
		arsenal_custom = (ac as Dictionary).duplicate()
	var ws: Variant = cf.get_value("main", "win_size", win_size)
	if ws is Vector2i:
		var v: Vector2i = ws
		if v.x >= 1024 and v.y >= 600:
			win_size = v
	var pl: Variant = cf.get_value("main", "players", [])
	if pl is Array:
		players = (pl as Array).duplicate(true)

## While a guest sits in an online lobby the host's match settings are shown in its menu. They are only a temporary overlay:
## the guest's own saved settings come back when the lobby is left, and are what is written to disk meanwhile.
var _stash: Dictionary = {}

func _snapshot() -> Dictionary:
	return {"player_count": player_count, "players": players.duplicate(true), "seed_text": seed_text, "timer": timer,
		"catapult_count": catapult_count, "palisade_count": palisade_count, "terrain_hills": terrain_hills,
		"crates_on": crates_on, "arsenal_preset": arsenal_preset, "rules_level": rules_level, "arsenal_edit": arsenal_edit.duplicate(), "arsenal_edit_preset": arsenal_edit_preset}

func _apply_snapshot(d: Dictionary) -> void:
	player_count = int(d["player_count"])
	players = (d["players"] as Array).duplicate(true)
	seed_text = str(d["seed_text"])
	timer = int(d["timer"])
	catapult_count = int(d["catapult_count"])
	palisade_count = int(d["palisade_count"])
	terrain_hills = int(d["terrain_hills"])
	arsenal_preset = str(d["arsenal_preset"])
	rules_level = int(d["rules_level"])
	crates_on = bool(d["crates_on"])
	arsenal_edit = (d["arsenal_edit"] as Dictionary).duplicate()
	arsenal_edit_preset = str(d["arsenal_edit_preset"])

func push_lobby() -> void:
	if _stash.is_empty():
		_stash = _snapshot()

func pop_lobby() -> bool:
	if _stash.is_empty():
		return false
	_apply_snapshot(_stash)
	_stash.clear()
	return true

func save_settings() -> void:
	if not _stash.is_empty():
		var shown: Dictionary = _snapshot()
		_apply_snapshot(_stash)
		_save_now()
		_apply_snapshot(shown)
	else:
		_save_now()

## Automated test runs (`-- --autotest=...`) must never overwrite the player's saved settings
static func _is_test_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest"):
			return true
	return false

## "Reset options": everything of the options panel back to the first-start defaults (language, names, players, seed and
## the saved custom arsenal are kept). `local_only`: a guest in an online lobby only resets its own display / sound options.
func reset_options(local_only: bool = false) -> void:
	volume = 0.8
	quality = "medium"
	lighting = "enhanced"
	shake = true
	auto_quality = true
	vsync = true
	fullscreen = false
	weather_on = true
	events_on = true
	crates_on = true
	if not local_only:
		timer = 0
		catapult_count = 3
		palisade_count = 4
		terrain_hills = 2
		arsenal_preset = "standard"
		rules_level = 0
		arsenal_edit.clear()
		arsenal_edit_preset = ""
	apply_display()
	apply_volume()
	save_settings()

func _save_now() -> void:
	if _is_test_run():
		return
	var cf := ConfigFile.new()
	cf.set_value("main", "language", language)
	cf.set_value("main", "volume", volume)
	cf.set_value("main", "quality", quality)
	cf.set_value("main", "lighting", lighting)
	cf.set_value("main", "relay_url", relay_url)
	cf.set_value("main", "net_name", net_name)
	cf.set_value("main", "shake", shake)
	cf.set_value("main", "timer", timer)
	cf.set_value("main", "weather_on", weather_on)
	cf.set_value("main", "events_on", events_on)
	cf.set_value("main", "crates_on", crates_on)
	cf.set_value("main", "auto_quality", auto_quality)
	cf.set_value("main", "fullscreen", fullscreen)
	cf.set_value("main", "vsync", vsync)
	cf.set_value("main", "cpu_particles", cpu_particles)
	cf.set_value("main", "player_count", player_count)
	cf.set_value("main", "seed_text", seed_text)
	cf.set_value("main", "catapult_count", catapult_count)
	cf.set_value("main", "palisade_count", palisade_count)
	cf.set_value("main", "terrain_hills", terrain_hills)
	# only "Custom" is remembered; every other preset (and every tweak of one) is for this session only
	cf.set_value("main", "arsenal_preset", "custom" if arsenal_preset == "custom" else "standard")
	cf.set_value("main", "arsenal_custom", arsenal_custom)
	cf.set_value("main", "rules_level", rules_level)
	cf.set_value("main", "win_size", win_size)
	cf.set_value("main", "players", players)
	var err: int = cf.save(PATH)
	if err != OK:
		push_warning("Could not save settings (error %d)" % err)

func apply_display() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var w: Window = get_window()
	if w == null:
		return
	w.min_size = Vector2i(1024, 600)
	if fullscreen:
		w.mode = Window.MODE_FULLSCREEN
	elif w.mode == Window.MODE_FULLSCREEN:
		w.mode = Window.MODE_WINDOWED

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_display()
	save_settings()

func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)

func apply_volume() -> void:
	var v: float = clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.001)
