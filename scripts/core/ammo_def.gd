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
var earnable: bool = false       # must be unlocked during the match (or pre-granted in the menu)

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
	_mk("firebarrel", 2, 2, 60.0, 0.50, 0.25, 0.012, "#ff7a1a", "FB")
	_mk("boulder", 3, 0, 12000.0, 0.9, 0.12, 0.012, "#7d7d86", "BO")
	_mk("powderkeg", 4, 0, 35.0, 0.50, 0.40, 0.020, "#3a3a44", "PK")
	_mk("scatter", 5, 0, 30.0, 0.40, 0.35, 0.020, "#c9a15a", "SG")
	_mk("cow", 6, 0, 250.0, 0.90, 0.15, 0.030, "#f2f2f2", "MU")
	_mk("beehive", 7, 0, 20.0, 0.40, 0.50, 0.060, "#f1c40f", "BH")
	_mk("redkeg", 8, 0, 160.0, 0.75, 0.20, 0.012, "#d6281f", "RK")
	_mk("powdertrail", 9, 0, 28.0, 0.3, 0.25, 0.012, "#2a2a30", "PT")
	for a in _all:
		a.earnable = a.id != "stone"

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
