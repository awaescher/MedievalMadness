class_name Unlocks
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Weapon unlocks (spec 6.4b). Stone is always available, everything else is earned by what a player achieves (or
## pre-granted in the menu). Every rule grants ammo to ONE player and announces it. The rules come in tiers, the game mode
## decides which are active: tier 0 = core (always, incl. the team rules), 1 = power (Powerplay), 2 = chaos (Chaos; includes
## tier 1), 3 = quarry (only the Quarry preset). `Game.rule_level` (0-2) and `Game.rule_quarry` are set at match start.
## RULES lists, per weapon, which rules grant it ([tier, key]); the key is also the text key (unlock.<key> / unlock_how.<key>).

const RULES: Dictionary = {
	"scatter": [[0, "shrapnel"]],
	"boulder": [[0, "revenge"], [0, "landslide"], [0, "crate_small"], [1, "landmark"], [2, "tavern"], [3, "mill"]],
	"powderkeg": [[0, "smithy_lost"], [0, "team_down"], [1, "revenge_hit"], [2, "own_blast"]],
	"powdertrail": [[0, "last_stand"], [0, "team_last"]],
	"cow": [[0, "cow_down"], [2, "cow_flight"]],
	"log": [[0, "trees"], [0, "tree_felled"], [0, "crate_small"]],
	"quad": [[0, "double"], [0, "team_kill"]],
	"chain": [[0, "mowed"], [1, "demolition"]],
	"firebarrel": [[0, "arsonist"], [0, "team_lost"], [2, "chaos_loss"]],
	"drillbomb": [[0, "steeple"], [0, "hub"], [2, "sails"]],
	"meteor": [[0, "crate"]],
}

const TREES_FOR_LOG := 3
static var _log_turn: Dictionary = {}       # player id -> turn number of the last log reward (one per shot)
static var _last_slide: Dictionary = {}     # player id -> last landslide id that paid a boulder
static var _fire_turn: Dictionary = {}      # player id -> turn number of the last counted fire
static var _fire_turns: Dictionary = {}     # player id -> number of turns in which the player set something on fire
static var _own_blast_turn: Dictionary = {} # player id -> turn of the last own-goal keg
static var _revenge: Dictionary = {}       # player id -> player id of the one who last wrecked a catapult of theirs

static func reset() -> void:
	_log_turn.clear()
	_last_slide.clear()
	_fire_turn.clear()
	_fire_turns.clear()
	_own_blast_turn.clear()
	_revenge.clear()

## is a rule tier active in this match?
static func tier_on(tier: int) -> bool:
	return tier_active(tier, Game.rule_level, Game.rule_quarry)

static func tier_active(tier: int, level: int, quarry: bool) -> bool:
	match tier:
		0:
			return true
		1:
			return level >= 1
		2:
			return level >= 2
		3:
			return quarry
	return false

## all active rules of a mode, grouped per weapon: [[ammo id, [text, ...]], ...] (for the rules dialog in the menu)
static func rules_of_mode(level: int, quarry: bool) -> Array:
	var out: Array = []
	for a in RULES:
		var lines: Array[String] = []
		for r in (RULES[a] as Array):
			if tier_active(int(r[0]), level, quarry) and (Settings.crates_on or not str(r[1]).begins_with("crate")):
				lines.append(I18n.t("unlock_how." + str(r[1]), {"n": 2 if level >= 2 else 3, "trees": 2 if quarry else TREES_FOR_LOG}))
		if not lines.is_empty():
			out.append([a, lines])
	return out

## Lines for the tooltip of a locked weapon: how it is earned in THIS match
static func how(ammo_id: String) -> Array[String]:
	var out: Array[String] = []
	for r in (RULES.get(ammo_id, []) as Array):
		if tier_on(int(r[0])) and (Game.crates_on or not str(r[1]).begins_with("crate")):
			var key: String = str(r[1])
			out.append(I18n.t("unlock_how." + key, {"n": _fire_every(), "trees": _trees_needed()}))
	return out

static func _fire_every() -> int:
	return 2 if tier_on(2) else 3

static func _trees_needed() -> int:
	return 2 if tier_on(3) else TREES_FOR_LOG

## the other members of a player's team (not the player)
static func _mates(p: PlayerData) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for o in Game.players:
		if o.id != p.id and not o.eliminated and p.is_ally(o):
			out.append(o)
	return out

static func _pid(source: Dictionary) -> int:
	if source.is_empty() or not source.has("player_id"):
		return -1
	return int(source["player_id"])

static var _from_host: bool = false

## A grant announced by the host (online clients never decide this themselves)
static func net_grant(player_id: int, ammo_id: String, n: int, reason_key: String, pos: Vector3 = Vector3.INF) -> void:
	_from_host = true
	grant(player_id, ammo_id, n, reason_key, pos)
	_from_host = false

## Where the thing that earned the reward happened (last part break / fire / explosion); the reward popup floats up there
static var hint_pos: Vector3 = Vector3.INF
static var hint_time: float = -100.0

static func set_hint(pos: Vector3) -> void:
	hint_pos = pos
	hint_time = Time.get_ticks_msec() / 1000.0

static func _reward_pos(p: PlayerData, pos: Vector3) -> Vector3:
	if pos != Vector3.INF:
		return pos
	if hint_pos != Vector3.INF and Time.get_ticks_msec() / 1000.0 - hint_time < 8.0:
		return hint_pos
	return p.village_center

static func grant(player_id: int, ammo_id: String, n: int, reason_key: String, pos: Vector3 = Vector3.INF) -> void:
	if Net.is_client() and not _from_host:
		return
	var p: PlayerData = Game.player(player_id)
	if p == null or p.eliminated:
		return
	if Net.active and Net.is_host:
		NetGame.send_grant(player_id, ammo_id, n, reason_key, _reward_pos(p, pos))
	p.add_ammo(ammo_id, n)
	Events.ammo_changed.emit(p.id)
	Events.reward.emit(p.id, ammo_id, n, _reward_pos(p, pos))
	var txt: String = I18n.t("unlock.got", {"name": p.name, "ammo": I18n.t("ammo." + ammo_id), "n": n, "why": I18n.t("unlock." + reason_key)})
	Events.kill_feed.emit(txt)
	if p.is_human():
		Events.toast.emit(I18n.t("unlock." + reason_key))
		Sfx.play("stinger_event", Vector3.INF, 0.5, 5)

## Catapult of `owner_id` was destroyed
static func on_catapult_destroyed(owner_id: int, source: Dictionary, _reason: String) -> void:
	var victim: PlayerData = Game.player(owner_id)
	var att: int = _pid(source)
	if victim != null:
		victim.hits_taken += 1
		grant(owner_id, "boulder", 1, "revenge")
		if victim.catapults_left() == 1:
			grant(owner_id, "powdertrail", 1, "last_stand")
			for m in _mates(victim):
				grant(m.id, "powdertrail", 1, "team_last")
		for m2 in _mates(victim):
			grant(m2.id, "firebarrel", 1, "team_lost")
		if tier_on(2):
			for o in Game.players:
				if o.id != owner_id and not o.eliminated and not victim.is_ally(o):
					grant(o.id, "firebarrel", 1, "chaos_loss")
		if att >= 0 and att != owner_id:
			_revenge[owner_id] = att
	if att >= 0 and att != owner_id:
		grant(att, "scatter", 1, "shrapnel")
		var killer: PlayerData = Game.player(att)
		if killer != null:
			for m3 in _mates(killer):
				grant(m3.id, "quad", 1, "team_kill")
		# power: hitting back at the one who wrecked your catapult
		if tier_on(1) and int(_revenge.get(att, -1)) == owner_id:
			_revenge.erase(att)
			grant(att, "powderkeg", 1, "revenge_hit")

static func _is_fence_or_prop(kind: String) -> bool:
	return kind.begins_with("prop_") or ["palisadepost", "playerwall", "palisade", "stonewall", "flagpole", "tree", "ruin"].has(kind)

## Windmill of another player: the hub (axle) is shot away = a drill bomb (all modes); chaos: all four sails knocked off while
## the rest of the mill is hardly damaged = two drill bombs
static func on_windmill(s: Structure, what: String) -> void:
	var att: int = _pid(s.last_source)
	var ap: PlayerData = Game.player(att)
	var op: PlayerData = Game.player(s.owner_id)
	if ap == null or op == null or att == s.owner_id or ap.is_ally(op):
		return
	if what == "hub":
		grant(att, "drillbomb", 1, "hub", s.center + Vector3.UP * 7.0)
	elif what == "sails" and tier_on(2):
		grant(att, "drillbomb", 2, "sails", s.center + Vector3.UP * 7.0)

static func on_building_destroyed(kind: String, owner_id: int, source: Dictionary) -> void:
	if kind == "blacksmith" and owner_id >= 0:
		grant(owner_id, "powderkeg", 1, "smithy_lost")
	var att: int = _pid(source)
	if att < 0 or owner_id < 0:
		return
	var ap: PlayerData = Game.player(att)
	var op: PlayerData = Game.player(owner_id)
	if ap != null and op != null and (att == owner_id or ap.is_ally(op)):
		# own goal: wrecking your own (or a teammate's) building
		# only a real building counts, not a fence (palisade posts, walls) or a prop
		if tier_on(2) and not _is_fence_or_prop(kind) and int(_own_blast_turn.get(att, -1)) != Game.turn_number:
			_own_blast_turn[att] = Game.turn_number
			grant(att, "powderkeg", 1, "own_blast")
		return
	if kind == "powderstore" and tier_on(1):
		grant(att, "boulder", 1, "landmark")
	elif (kind == "church" or kind == "watchtower") and tier_on(0):
		grant(att, "drillbomb", 1, "steeple")
	elif kind == "tavern" and tier_on(2):
		grant(att, "boulder", 1, "tavern")
	elif kind == "windmill" and tier_on(3):
		grant(att, "boulder", 1, "mill")
	if str(source.get("ammo", "")) == "landslide" and int(source.get("slide", -1)) != int(_last_slide.get(att, -2)):
		_last_slide[att] = int(source["slide"])
		grant(att, "boulder", 1, "landslide")

## Three buildings wrecked by one shot
static func on_shot_buildings(player_id: int, count: int) -> void:
	if count == 2:
		grant(player_id, "quad", 1, "double")
	elif count == 3 and tier_on(1):
		grant(player_id, "chain", 1, "demolition")

static func on_shot_settlers(player_id: int, count: int) -> void:
	if count == 5:
		grant(player_id, "chain", 1, "mowed")

## Fires are counted per TURN (a fire that spreads over a whole village is still one fire)
static func on_fire_started(source: Dictionary) -> void:
	var p: PlayerData = Game.player(_pid(source))
	if p == null or int(_fire_turn.get(p.id, -1)) == Game.turn_number:
		return
	_fire_turn[p.id] = Game.turn_number
	_fire_turns[p.id] = int(_fire_turns.get(p.id, 0)) + 1
	if int(_fire_turns[p.id]) % _fire_every() == 0:
		grant(p.id, "firebarrel", 1, "arsonist")

## `owner_id`: the player whose camp the animal lived in. Only your own cow dying pays a cow shell.
static func on_animal_killed(kind: String, owner_id: int) -> void:
	if owner_id < 0:
		return
	if kind == "cow":
		grant(owner_id, "cow", 2 if tier_on(2) else 1, "cow_down")      # chaos: your own cow dying pays two
	elif tier_on(2):
		grant(owner_id, "cow", 1, "cow_flight")

static func on_tree_damaged(source: Dictionary, tree: Structure) -> void:
	var p: PlayerData = Game.player(_pid(source))
	if p == null:
		return
	p.trees_hit[tree.get_instance_id()] = true
	set_hint(tree.center + Vector3.UP * (tree.height * 0.5))
	if p.trees_hit.size() >= _trees_needed() and int(_log_turn.get(p.id, -1)) != Game.turn_number:
		p.trees_hit.clear()
		_log_turn[p.id] = Game.turn_number
		grant(p.id, "log", 1, "trees")

## A tree was shot to pieces: the player whose camp it stands near (within 45 m of the village centre) gets a log
static func on_tree_destroyed(tree: Structure) -> void:
	var best: PlayerData = null
	var bd: float = 45.0
	for pl in Game.players:
		var d: float = Util.dist_xz(pl.village_center, tree.center)
		if d < bd:
			bd = d
			best = pl
	if best != null:
		grant(best.id, "log", 1, "tree_felled")

static func on_powder_barrel(source: Dictionary) -> void:
	var att: int = _pid(source)
	if att >= 0:
		Scoring.award(att, 120, "chain")

## A player was eliminated: their surviving team mates get a powder keg
static func on_player_eliminated(victim_id: int) -> void:
	var v: PlayerData = Game.player(victim_id)
	if v == null:
		return
	for m in _mates(v):
		grant(m.id, "powderkeg", 1, "team_down")
