extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Persistent settings (autoload "Settings"), stored via ConfigFile at user://settings.cfg (spec 18.3).

const PATH := "user://settings.cfg"
const QUALITY_TIERS: Array[String] = ["low", "medium", "high", "ultra"]
const LIGHTING_MODES: Array[String] = ["basic", "enhanced", "rt"]

var language: String = "en"
var volume: float = 0.8
var quality: String = "medium"
var lighting: String = "enhanced"      # basic | enhanced | rt (needs the Forward+ renderer)
var shake: bool = true
var timer: int = 30
var weather_on: bool = true
var events_on: bool = true
var auto_quality: bool = true
var fullscreen: bool = false
var vsync: bool = true
var cpu_particles: bool = false
var win_size: Vector2i = Vector2i(1600, 900)
var players: Array = []      # last used player list: [{name, color, type}]
var player_count: int = 4
var seed_text: String = ""
var catapult_count: int = 5
var palisade_count: int = 4
var terrain_hills: int = 2
var arsenal: Dictionary = {}           # pre-granted weapons: ammo id -> count
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
	shake = bool(cf.get_value("main", "shake", shake))
	timer = int(cf.get_value("main", "timer", timer))
	if not [0, 20, 30, 45, 60].has(timer):
		timer = 30
	weather_on = bool(cf.get_value("main", "weather_on", weather_on))
	events_on = bool(cf.get_value("main", "events_on", events_on))
	auto_quality = bool(cf.get_value("main", "auto_quality", auto_quality))
	fullscreen = bool(cf.get_value("main", "fullscreen", fullscreen))
	vsync = bool(cf.get_value("main", "vsync", vsync))
	cpu_particles = bool(cf.get_value("main", "cpu_particles", cpu_particles))
	player_count = clampi(int(cf.get_value("main", "player_count", player_count)), Cfg.MIN_PLAYERS, Cfg.MAX_PLAYERS)
	seed_text = str(cf.get_value("main", "seed_text", seed_text))
	catapult_count = clampi(int(cf.get_value("main", "catapult_count", catapult_count)), 1, Cfg.CATAPULTS_PER_PLAYER)
	palisade_count = clampi(int(cf.get_value("main", "palisade_count", palisade_count)), 1, 10)
	terrain_hills = clampi(int(cf.get_value("main", "terrain_hills", terrain_hills)), 0, 4)
	var ar: Variant = cf.get_value("main", "arsenal", {})
	if ar is Dictionary:
		arsenal = (ar as Dictionary).duplicate()
	var ws: Variant = cf.get_value("main", "win_size", win_size)
	if ws is Vector2i:
		var v: Vector2i = ws
		if v.x >= 1024 and v.y >= 600:
			win_size = v
	var pl: Variant = cf.get_value("main", "players", [])
	if pl is Array:
		players = (pl as Array).duplicate(true)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("main", "language", language)
	cf.set_value("main", "volume", volume)
	cf.set_value("main", "quality", quality)
	cf.set_value("main", "lighting", lighting)
	cf.set_value("main", "shake", shake)
	cf.set_value("main", "timer", timer)
	cf.set_value("main", "weather_on", weather_on)
	cf.set_value("main", "events_on", events_on)
	cf.set_value("main", "auto_quality", auto_quality)
	cf.set_value("main", "fullscreen", fullscreen)
	cf.set_value("main", "vsync", vsync)
	cf.set_value("main", "cpu_particles", cpu_particles)
	cf.set_value("main", "player_count", player_count)
	cf.set_value("main", "seed_text", seed_text)
	cf.set_value("main", "catapult_count", catapult_count)
	cf.set_value("main", "palisade_count", palisade_count)
	cf.set_value("main", "terrain_hills", terrain_hills)
	cf.set_value("main", "arsenal", arsenal)
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
