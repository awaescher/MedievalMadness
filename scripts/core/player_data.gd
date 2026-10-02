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
var walls: Array = []                 # stone walls built during the battle: [{id, center, yaw, layers: Array[Structure]}]
var wall_counter: int = 0
var posts: Array = []                 # palisade columns: [{base: Vector3, structs: Array[Structure]}]
var post_log: Array = []              # undo steps in placement order: each is an Array[Structure] (a fence of 3 posts or a stacked row)
var fences: Array = []                # [{id, cols, center, yaw}]
var fence_counter: int = 0
var hits_taken: int = 0               # catapults lost (for the consolation weapons)
var trees_hit: Dictionary = {}        # distinct trees damaged since the last log
var ammo_sel: String = "stone"      # this player's own ammo choice (kept between turns, never shared)
var team: int = 0                   # team = colour index: same colour, same team (teams win together)
var marker: Vector3 = Vector3.INF   # the one map marker of this player (spec 6.7), INF = none

## Online play: set by the Net autoload. `net_peer` is the peer that controls this seat (-1 = nobody / the CPU).
static var net_on: bool = false
static var net_id: int = -1
var net_peer: int = -1
var points: int = 0                   # the (cosmetic) score: every action pays, funny or spectacular ones more
var points_frac: float = 0.0

## A human on THIS machine (in an online game: only the seat this peer controls)
func is_human() -> bool:
	return type == "human" and (not net_on or net_peer == net_id)

## A human on another machine (online game)
func is_remote() -> bool:
	return type == "human" and net_on and net_peer != net_id

## Someone else on the same team (never `self`)
func is_ally(o: PlayerData) -> bool:
	return o != null and o.id != id and o.team == team

## Somebody this player has to beat
func is_enemy(o: PlayerData) -> bool:
	return o != null and o.id != id and o.team != team

func is_cpu() -> bool:
	return type != "human"

## `start`: the starting arsenal of the match (ammo id -> count, -1 = unlimited, see Arsenal); everything else starts at its default
func reset_ammo(start: Dictionary = {}) -> void:
	ammo.clear()
	for a in AmmoDef.all():
		ammo[a.id] = a.start_count
		if a.earnable and start.has(a.id):
			ammo[a.id] = maxi(int(start[a.id]), -1)
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
