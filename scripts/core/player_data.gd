class_name PlayerData
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## One player (human or CPU): identity, ammo inventory, catapults, statistics (spec 13).

class Stats extends RefCounted:
	var shots: int = 0
	var hits: int = 0
	var damage_dealt: float = 0.0
	var settlers_launched: int = 0
	var settlers_killed: int = 0
	var catapults_destroyed: int = 0
	var buildings_destroyed: int = 0
	var fires_started: int = 0
	var fires_extinguished: int = 0
	var cows_fired: int = 0
	var cheese_used: int = 0
	var self_damage: float = 0.0
	var water_misses: int = 0
	var longest_shot: float = 0.0
	var turns_survived: int = 0

var id: int = 0
var name: String = ""
var color: Color = Color.RED
var type: String = "human"          # human | peasant | squire | knight | king
var catapults: Array = []           # Array[Catapult]
var ammo: Dictionary = {}           # ammo id -> count (-1 = infinite)
var eliminated: bool = false
var eliminated_order: int = -1      # 0 = first eliminated
var last_catapult: int = -1
var stats: Stats = Stats.new()
var village_center: Vector3 = Vector3.ZERO
var last_damaged_by: int = -1       # player id whose last shot damaged this player
var placed: int = 0
var posts: Array = []                 # palisade columns: [{base: Vector3, structs: Array[Structure]}]
var post_log: Array = []              # undo steps in placement order: each is an Array[Structure] (a fence of 3 posts or a stacked row)
var fences: Array = []                # [{id, cols, center, yaw}]
var fence_counter: int = 0
var hits_taken: int = 0               # catapults lost (for the consolation weapons)
var trees_hit: Dictionary = {}        # distinct trees damaged since the last beehive
var ammo_sel: String = "stone"      # this player's own ammo choice (kept between turns, never shared)
var marker: Vector3 = Vector3.INF   # the one map marker of this player (spec 6.7), INF = none

func is_human() -> bool:
	return type == "human"

func is_cpu() -> bool:
	return type != "human"

## `extra`: weapons pre-granted in the menu (ammo id -> count)
func reset_ammo(extra: Dictionary = {}) -> void:
	ammo.clear()
	for a in AmmoDef.all():
		ammo[a.id] = a.start_count
		if a.start_count >= 0 and extra.has(a.id):
			ammo[a.id] = a.start_count + maxi(int(extra[a.id]), 0)
	ammo_sel = "stone"
	hits_taken = 0
	trees_hit.clear()

func add_ammo(ammo_id: String, n: int = 1) -> void:
	var c: int = ammo_count(ammo_id)
	if c < 0:
		return
	ammo[ammo_id] = c + n

func ammo_count(ammo_id: String) -> int:
	return int(ammo.get(ammo_id, 0))

func has_ammo(ammo_id: String) -> bool:
	var c: int = ammo_count(ammo_id)
	return c != 0

func use_ammo(ammo_id: String) -> void:
	var c: int = ammo_count(ammo_id)
	if c > 0:
		ammo[ammo_id] = c - 1

func living_catapults() -> Array:
	var out: Array = []
	for c in catapults:
		if is_instance_valid(c) and not (c as Catapult).destroyed:
			out.append(c)
	return out

func catapults_left() -> int:
	var n: int = 0
	for c in catapults:
		if is_instance_valid(c) and not (c as Catapult).destroyed:
			n += 1
	return n
