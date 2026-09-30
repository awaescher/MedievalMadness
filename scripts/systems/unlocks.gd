class_name Unlocks
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Weapon unlocks (spec 6.4b). Stone and the fire barrel are always available; everything else is earned by what a
## player achieves (or pre-granted in the menu). Every rule grants ammo to ONE player and announces it.
##
##   scatter   +1  destroying an enemy catapult                         (shrapnel from the wreck)
##   boulder   +1  losing a catapult                                    (revenge, every time)
##   powderkeg +1  losing a 2nd/4th/... catapult; blowing up a powder barrel; wrecking 3 buildings with one shot
##   cow       +1  one of your OWN cows dies in your own camp (whoever or whatever killed it)
##   log       +1  damaging 3 different trees
##   quad      +1  wrecking 2 buildings with one shot
##   chain     +1  launching 5 settlers with one shot
##   firebarrel +1  every 8th fire you start (you begin with only 2)
##   powdertrail +1 destroying an enemy blacksmith; losing the 3rd / 6th ... catapult
##   boulder   +1  (also) a landslide you started wrecks an enemy building
##   meteor    +1  destroying an enemy church or powder store; eliminating an enemy player

const TREES_FOR_LOG := 3
static var _log_turn: Dictionary = {}       # player id -> turn number of the last log reward (one per shot)
static var _last_slide: Dictionary = {}     # player id -> last landslide id that paid a boulder

static func _pid(source: Dictionary) -> int:
	if source.is_empty() or not source.has("player_id"):
		return -1
	return int(source["player_id"])

static var _from_host: bool = false

## A grant announced by the host (online clients never decide this themselves)
static func net_grant(player_id: int, ammo_id: String, n: int, reason_key: String) -> void:
	_from_host = true
	grant(player_id, ammo_id, n, reason_key)
	_from_host = false

static func grant(player_id: int, ammo_id: String, n: int, reason_key: String) -> void:
	if Net.is_client() and not _from_host:
		return
	var p: PlayerData = Game.player(player_id)
	if p == null or p.eliminated:
		return
	if Net.active and Net.is_host:
		NetGame.send_grant(player_id, ammo_id, n, reason_key)
	p.add_ammo(ammo_id, n)
	Events.ammo_changed.emit(p.id)
	var txt: String = I18n.t("unlock.got", {"name": p.name, "ammo": I18n.t("ammo." + ammo_id), "n": n, "why": I18n.t("unlock." + reason_key)})
	Events.kill_feed.emit(txt)
	if p.is_human():
		Events.banner.emit(I18n.t("unlock.banner", {"ammo": I18n.t("ammo." + ammo_id), "n": n}), "unlock")
		Events.toast.emit(I18n.t("unlock." + reason_key))
		Sfx.play("stinger_event", Vector3.INF, 0.5, 5)

## Catapult of `owner_id` was destroyed
static func on_catapult_destroyed(owner_id: int, source: Dictionary, _reason: String) -> void:
	var victim: PlayerData = Game.player(owner_id)
	if victim != null:
		victim.hits_taken += 1
		grant(owner_id, "boulder", 1, "revenge")
		if victim.hits_taken % 2 == 0:
			grant(owner_id, "powderkeg", 1, "underdog")
		if victim.hits_taken % 3 == 0:
			grant(owner_id, "powdertrail", 1, "salvage")
	var att: int = _pid(source)
	if att >= 0 and att != owner_id:
		grant(att, "scatter", 1, "shrapnel")

static func on_building_destroyed(kind: String, owner_id: int, source: Dictionary) -> void:
	var att: int = _pid(source)
	if att < 0 or att == owner_id or owner_id < 0:
		return
	if kind == "church" or kind == "powderstore":
		grant(att, "meteor", 1, "landmark")
	elif kind == "blacksmith":
		grant(att, "powdertrail", 1, "smithy")
	if str(source.get("ammo", "")) == "landslide" and int(source.get("slide", -1)) != int(_last_slide.get(att, -2)):
		_last_slide[att] = int(source["slide"])
		grant(att, "boulder", 1, "landslide")

## Three buildings wrecked by one shot
static func on_shot_buildings(player_id: int, count: int) -> void:
	if count == 2:
		grant(player_id, "quad", 1, "double")
	elif count == 3:
		grant(player_id, "powderkeg", 1, "demolition")

static func on_shot_settlers(player_id: int, count: int) -> void:
	if count == 5:
		grant(player_id, "chain", 1, "mowed")

static func on_fire_started(source: Dictionary) -> void:
	var p: PlayerData = Game.player(_pid(source))
	if p != null and p.stats.fires_started > 0 and p.stats.fires_started % 8 == 0:
		grant(p.id, "firebarrel", 1, "arsonist")

## `owner_id`: the player whose camp the animal lived in. Only your own cow dying pays a cow shell.
static func on_animal_killed(kind: String, owner_id: int) -> void:
	if owner_id >= 0 and kind == "cow":
		grant(owner_id, "cow", 1, "cow_down")

static func on_tree_damaged(source: Dictionary, tree: Structure) -> void:
	var p: PlayerData = Game.player(_pid(source))
	if p == null:
		return
	p.trees_hit[tree.get_instance_id()] = true
	if p.trees_hit.size() >= TREES_FOR_LOG and int(_log_turn.get(p.id, -1)) != Game.turn_number:
		p.trees_hit.clear()
		_log_turn[p.id] = Game.turn_number
		grant(p.id, "log", 1, "trees")

static func on_powder_barrel(source: Dictionary) -> void:
	var att: int = _pid(source)
	if att >= 0:
		grant(att, "powderkeg", 1, "barrel_blown")

static func on_player_eliminated(victim_id: int) -> void:
	var v: PlayerData = Game.player(victim_id)
	if v != null and v.last_damaged_by >= 0 and v.last_damaged_by != victim_id:
		grant(v.last_damaged_by, "meteor", 1, "eliminated")
