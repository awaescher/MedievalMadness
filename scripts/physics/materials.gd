class_name Materials
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Material table (spec section 4). Authoritative numbers. "leaf" is an internal helper
## material for tree crowns (spec 7.5: flammability 0.8, crown dies, trunk stays).

class MaterialDef extends RefCounted:
	var id: String = ""
	var density: float = 600.0
	var friction: float = 0.6
	var restitution: float = 0.2
	var break_force: float = 260.0
	var flammability: float = 0.0
	var burn_hp: float = 0.0
	var hp_per_m3: float = 400.0
	var shard: String = "splinter"
	var shard_color: Color = Color("#8a5a2a")
	var sound: String = "thunk"
	var comic: String = "wood"
	var palette: Array[Color] = []

static var _defs: Dictionary = {}

static func _mk(id: String, density: float, friction: float, restitution: float, break_force: float, flam: float, burn_hp: float, hp_m3: float, shard: String, shard_col: String, snd: String, comic: String, pal: Array) -> void:
	var d := MaterialDef.new()
	d.id = id
	d.density = density
	d.friction = friction
	d.restitution = restitution
	d.break_force = break_force
	d.flammability = flam
	d.burn_hp = burn_hp
	d.hp_per_m3 = hp_m3
	d.shard = shard
	d.shard_color = Color.html(shard_col)
	d.sound = snd
	d.comic = comic
	for c in pal:
		d.palette.append(Color.html(str(c)))
	_defs[id] = d

static func _ensure() -> void:
	if not _defs.is_empty():
		return
	#   id            dens  fric  rest  brk   flam burn  hp/m3 shard      shard col  sound    comic   palette
	_mk("wood",        600, 0.60, 0.20,  260, 0.70,  6.0,  400, "splinter", "#8a5a2a", "thunk",  "wood",  ["#b5763a", "#a0622d", "#c58a4a"])
	_mk("plank",       550, 0.55, 0.25,  160, 0.75,  7.0,  250, "splinter", "#c99a5a", "clack",  "wood",  ["#d09a5a", "#c48748"])
	_mk("stone",      2300, 0.80, 0.10,  900, 0.00,  0.0, 1200, "dust",     "#9a9a9a", "crunch", "stone", ["#9aa0a6", "#8a9096", "#a9aeb3"])
	_mk("brick",      1900, 0.75, 0.12,  600, 0.00,  0.0,  800, "dust",     "#b8503a", "crunch", "stone", ["#c0533a", "#b34a33"])
	_mk("thatch",      120, 0.90, 0.05,   60, 1.00, 12.0,   60, "straw",    "#e0c060", "swish",  "wood",  ["#e0c060", "#d4b04a"])
	_mk("cloth",        80, 0.90, 0.05,   40, 0.90, 10.0,   30, "straw",    "#d8d0c0", "fwump",  "impact", ["#e74c3c", "#f1c40f", "#3498db"])
	_mk("metal",      7800, 0.40, 0.20, 2500, 0.00,  0.0, 3000, "spark",    "#ffd27a", "clang",  "stone", ["#7f8c9a"])
	_mk("hay",          90, 0.95, 0.02,   80, 1.00, 14.0,   40, "straw",    "#e6cf6a", "fwump",  "impact", ["#e6c860", "#d9b955"])
	_mk("barrel_wood", 400, 0.50, 0.35,  220, 0.50,  5.0,  180, "splinter", "#8a5a2a", "thunk",  "wood",  ["#a5672f", "#95582a"])
	_mk("glass",      2500, 0.30, 0.10,   50, 0.00,  0.0,   20, "glitter",  "#bfefff", "tinkle", "impact", ["#9fe0ff"])
	_mk("flesh",      1000, 0.70, 0.15,    0, 0.40, 10.0,   30, "wool",     "#f0c8a0", "boing",  "settler", ["#f0c8a0"])
	_mk("leaf",        150, 0.80, 0.05,   80, 0.80,  8.0,   80, "leaf",     "#4caf50", "swish",  "wood",  ["#3f9c3f", "#4caf50", "#2e8b3d"])

static func get_def(id: String) -> MaterialDef:
	_ensure()
	if _defs.has(id):
		return _defs[id] as MaterialDef
	return _defs["wood"] as MaterialDef

static func has(id: String) -> bool:
	_ensure()
	return _defs.has(id)

static func all_ids() -> Array:
	_ensure()
	return _defs.keys()
