class_name AmmoDef
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Ammo table (spec 6.4) with typed access.

var id: String = "stone"
var slot: int = 1
var start_count: int = -1        # -1 = infinite
var mass: float = 40.0
var radius: float = 0.45
var wind_factor: float = 0.3
var drag: float = 0.01           # linear damping used by physics AND trajectory prediction
var color: Color = Color("#8d8d94")
var label: String = "ST"
var base: String = ""             # behaves like this ammo (the stone volley is made of stones)
var earnable: bool = false       # must be unlocked during the match (or pre-granted in the menu)
var kind: String = "shot"        # "shot" = fires a projectile | "action" = something else a turn can be spent on (relocate, build)

static var _all: Array[AmmoDef] = []
static var _by_id: Dictionary = {}

static func _mk(id: String, slot: int, count: int, mass: float, radius: float, wf: float, drag: float, col: String, label: String) -> void:
	var a := AmmoDef.new()
	a.id = id
	a.slot = slot
	a.start_count = count
	a.mass = mass
	a.radius = radius
	a.wind_factor = wf
	a.drag = drag
	a.color = Color.html(col)
	a.label = label
	_all.append(a)
	_by_id[id] = a

static func _ensure() -> void:
	if not _all.is_empty():
		return
	# stone + fire barrel are always there; everything else has to be earned (see Unlocks) or pre-granted in the menu
	_mk("stone", 1, -1, 40.0, 0.45, 0.30, 0.010, "#9a9aa2", "ST")
	_mk("quad", 2, 0, 40.0, 0.45, 0.30, 0.010, "#9a9aa2", "S4")
	(_by_id["quad"] as AmmoDef).base = "stone"
	_mk("chain", 3, 0, 80.0, 0.40, 0.25, 0.008, "#26262c", "CH")
	_mk("boulder", 4, 0, 12000.0, 0.9, 0.12, 0.012, "#7d7d86", "BO")
	_mk("log", 5, 0, 300.0, 0.35, 0.20, 0.010, "#8a5a2a", "LG")
	_mk("firebarrel", 6, 2, 60.0, 0.50, 0.25, 0.012, "#ff7a1a", "FB")
	_mk("powderkeg", 7, 0, 35.0, 0.50, 0.40, 0.020, "#3a3a44", "PK")
	_mk("scatter", 8, 0, 30.0, 0.40, 0.35, 0.020, "#c9a15a", "SG")
	_mk("cow", 9, 0, 250.0, 0.90, 0.15, 0.030, "#f2f2f2", "MU")
	_mk("powdertrail", 10, 0, 28.0, 0.3, 0.25, 0.012, "#2a2a30", "PT")
	_mk("meteor", 11, 0, 30.0, 0.30, 0.30, 0.010, "#35ff86", "MT")
	# turn actions instead of a shot: always available, never earned
	_mk("relocate", 12, -1, 0.0, 0.0, 0.0, 0.0, "#8a8a94", "MV")
	_mk("wall", 13, -1, 0.0, 0.0, 0.0, 0.0, "#8a9096", "WL")
	for aid in ["relocate", "wall"]:
		(_by_id[aid] as AmmoDef).kind = "action"
	for a in _all:
		a.earnable = a.id != "stone" and a.kind == "shot"

## Label of the key that selects this slot (1-9, 0, -, U, B)
func key_label() -> String:
	match slot:
		10:
			return "0"
		11:
			return "-"
		12:
			return "U"
		13:
			return "B"
	return str(slot)

func is_action() -> bool:
	return kind == "action"

static func is_action_id(id: String) -> bool:
	_ensure()
	return _by_id.has(id) and (_by_id[id] as AmmoDef).kind == "action"

static func all() -> Array[AmmoDef]:
	_ensure()
	return _all

static func get_def(id: String) -> AmmoDef:
	_ensure()
	return (_by_id[id] if _by_id.has(id) else _by_id["stone"]) as AmmoDef

## The weapons that can be pre-granted in the menu / earned in a match
static func earnable_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for a in _all:
		if a.earnable:
			out.append(a.id)
	return out

static func ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for a in _all:
		out.append(a.id)
	return out
