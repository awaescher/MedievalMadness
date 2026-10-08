class_name Cfg
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## All authoritative constants (spec section 3) plus a few derived helpers.

## The browser build runs without threads and without the optional looks (graphics styles, lighting modes, music)
static func is_web() -> bool:
	return OS.has_feature("web")

## No worker threads available (the web export): sound synthesis then runs in small slices on the main thread
static func single_threaded() -> bool:
	return OS.has_feature("web") and not OS.has_feature("threads")

const PHYSICS_HZ := 60
const MAX_SUBSTEPS := 3
const GRAVITY := -19.62                # stronger than real for snappy comic feel (project gravity 19.62)
const MIN_PLAYERS := 2
const MAX_PLAYERS := 8
const CATAPULTS_PER_PLAYER := 5
const ZONE_RADIUS := 22.0              # village zone radius, meters
const WORLD_UNIT := 1.0                # 1 unit = 1 meter
const MAX_DYNAMIC_BODIES := 900        # hard cap (quality-scaled, see 15)
const DEBRIS_LIFETIME := 25.0          # seconds after sleep before fade (Medium)
const SETTLE_SPEED := 0.35             # m/s: below this a body counts as still
const SETTLE_TIME := 0.8               # seconds all relevant bodies must be still
const SETTLE_MAX := 8.0                # seconds max aftermath wait, then force end
const WIND_MAX := 20.0                 # m/s
const WIND_CHANGE_MAX := 6.0
const DRAG_MAX_PX := 220.0             # max slingshot pull in screen pixels (at 1600x900 reference)
const POWER_MAX_SPEED := 140.0         # m/s launch speed at 100% power (must out-range the biggest map, see tests)
const POWER_MIN_SPEED := 8.0           # at 0% (still valid > 8%)
const PREVIEW_FRACTION := 0.4          # show first 40% of predicted flight path
const CATAPULT_HP := 100.0
const SETTLER_HP := 30.0
const TURN_TIMER_DEFAULT := 30
const FIRE_TICK := 0.5                 # seconds between fire logic ticks
const FIRE_SPREAD_RADIUS := 3.2
const SLOWMO_SCALE := 0.25

# --- derived / helper constants (not part of the balance table) ---
const WATER_LEVEL := -0.5
const TERRAIN_CELL := 2.0              # 1 vertex per 2 m
const TERRAIN_MAX_VERTS := 256
const WIND_ACCEL_FACTOR := 0.35        # wind speed -> m/s^2
const LAUNCH_SPREAD_DEG := 0.5
const PROJECTILE_TIMEOUT := 12.0
const OUTLINE_COLOR := Color(0.10, 0.07, 0.13)
const AIM_DEG_PER_PX := 0.25
const ELEV_DEG_PER_PX := 0.3
const DEFAULT_ELEVATION := 30.0
const MIN_ELEVATION := 15.0
const MAX_ELEVATION := 60.0
## The version lives in the VERSION file (single source of truth, bumped by tools/release.sh, exported with the game)
## The relay every build connects to by default (set after deploying relay/cloudflare/worker.js); players can change it in the lobby
const DEFAULT_RELAY := "wss://mm-relay.twilight-mouse-b997.workers.dev"

static func game_version() -> String:
	var f: FileAccess = FileAccess.open("res://VERSION", FileAccess.READ)
	if f == null:
		return "dev"
	return f.get_as_text().strip_edges()

# collision layers (bit values)
const LAYER_TERRAIN := 1
const LAYER_STRUCT := 2
const LAYER_PART := 4
const LAYER_PROJECTILE := 8
const LAYER_CATAPULT := 16
const LAYER_SETTLER := 32
const LAYER_PROP := 64
const LAYER_DEBRIS := 128
const LAYER_ALL := 255
