class_name Scoring
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Statistics + titles (spec 13). Systems call the on_* functions; stats live in PlayerData.Stats.

static var shot_score: float = 0.0            # accumulates during the current shot
static var shot_player: int = -1
static var shot_settlers_launched: int = 0
static var shot_buildings: int = 0
static var shot_catapults: int = 0
static var shot_explosions: int = 0
static var shot_damage: float = 0.0
static var shot_hit: bool = false
static var shot_any: bool = false             # anything at all happened (damage to anyone, fire, blast, kills): worth watching
static var _first_elimination: int = -1
static var shot_ammo_id: String = ""

const BUILDING_POINTS: Dictionary = {"church": 250, "powderstore": 300, "tavern": 150, "windmill": 200, "outhouse": 60, "barn": 120, "blacksmith": 140, "watchtower": 180, "well": 70, "stable": 100, "granary": 110}

## Points (cosmetic): every action pays, funny or spectacular ones pay more. `quiet` = no popup (small stuff).
## Online only the host decides; clients get the awards as messages.
static func award(pid: int, pts: int, key: String, quiet: bool = false) -> void:
	if Net.is_client():
		return
	if _apply_award(pid, pts, key, quiet) and Net.active and Net.is_host:
		NetGame.send_pts(pid, pts, key, quiet)

static func net_award(pid: int, pts: int, key: String, quiet: bool) -> void:
	_apply_award(pid, pts, key, quiet)

static func _apply_award(pid: int, pts: int, key: String, quiet: bool) -> bool:
	var p: PlayerData = Game.player(pid)
	if p == null or pts == 0:
		return false
	p.points += pts
	if not quiet:
		Events.points_awarded.emit(pid, pts, I18n.t("pts." + key))
	return true

## Small amounts add up silently (damage points)
static func award_f(pid: int, amount: float) -> void:
	var p: PlayerData = Game.player(pid)
	if p == null or Net.is_client():
		return
	p.points_frac += amount
	if absf(p.points_frac) >= 1.0:
		var whole: int = int(p.points_frac)
		p.points_frac -= float(whole)
		p.points += whole

static func reset() -> void:
	begin_shot(-1)
	_first_elimination = -1

static func begin_shot(player_id: int) -> void:
	shot_player = player_id
	shot_score = 0.0
	shot_settlers_launched = 0
	shot_buildings = 0
	shot_catapults = 0
	shot_explosions = 0
	shot_damage = 0.0
	shot_hit = false
	shot_any = false

static func current_shot_score() -> float:
	return shot_damage + 50.0 * float(shot_settlers_launched) + 200.0 * float(shot_buildings) + 300.0 * float(shot_catapults) + float(shot_explosions) * 30.0

static func _pl(source: Dictionary) -> PlayerData:
	if source.is_empty() or not source.has("player_id"):
		return null
	return Game.player(int(source["player_id"]))

## Damage dealt to a structure of `owner_id` (part hp lost)
static func on_damage(source: Dictionary, owner_id: int, amount: float) -> void:
	var p: PlayerData = _pl(source)
	if p == null or amount <= 0.0:
		return
	if int(source["player_id"]) == shot_player:
		shot_any = true
	if owner_id == p.id:
		p.stats.self_damage += amount
		award_f(p.id, -amount * 0.02)
		return
	if owner_id < 0:
		return
	award_f(p.id, amount * 0.04)
	p.stats.damage_dealt += amount
	if int(source["player_id"]) == shot_player:
		shot_damage += amount
		shot_hit = true
	var victim: PlayerData = Game.player(owner_id)
	if victim != null:
		victim.last_damaged_by = p.id

static func on_part_broken(_s: Structure, _source: Dictionary) -> void:
	pass

static func on_building_destroyed(kind: String, owner_id: int, source: Dictionary) -> void:
	var p: PlayerData = _pl(source)
	if p == null or kind == "tree":
		return
	if owner_id != p.id and owner_id >= 0:
		p.stats.buildings_destroyed += 1
		award(p.id, int(BUILDING_POINTS.get(kind, 100)), "b_" + kind if BUILDING_POINTS.has(kind) else "building")
		if int(source["player_id"]) == shot_player:
			shot_buildings += 1
			Unlocks.on_shot_buildings(p.id, shot_buildings)
			if shot_buildings == 3:
				award(p.id, 200, "wrecking")
			elif shot_buildings == 5:
				award(p.id, 400, "carnage")
	else:
		p.stats.self_damage += 20.0
		award(p.id, -60, "own_goal")

static func on_settler_launched(source: Dictionary, owner_id: int) -> void:
	var p: PlayerData = _pl(source)
	if p == null:
		return
	shot_any = true
	if owner_id != p.id:
		p.stats.settlers_launched += 1
		shot_hit = true
		award(p.id, 25, "launch", true)
		if int(source["player_id"]) == shot_player:
			shot_settlers_launched += 1
			Unlocks.on_shot_settlers(p.id, shot_settlers_launched)
			if shot_settlers_launched == 3:
				award(p.id, 75, "triple")
			elif shot_settlers_launched == 5:
				award(p.id, 150, "strike")
			elif shot_settlers_launched == 10:
				award(p.id, 400, "bowling")

static func on_settler_killed(source: Dictionary, owner_id: int) -> void:
	var p: PlayerData = _pl(source)
	if p == null:
		return
	shot_any = true
	if owner_id != p.id:
		p.stats.settlers_killed += 1
		award(p.id, 15, "kill", true)
		shot_hit = true

static func on_catapult_destroyed(owner_id: int, source: Dictionary) -> void:
	var p: PlayerData = _pl(source)
	if p == null:
		return
	if owner_id != p.id:
		p.stats.catapults_destroyed += 1
		shot_hit = true
		award(p.id, 400, "cat_kill")
		if int(source["player_id"]) == shot_player:
			shot_catapults += 1
			if shot_catapults == 2:
				award(p.id, 200, "double_cat")
	else:
		p.stats.self_damage += 100.0
		award(p.id, -200, "cat_self")

static func on_catapult_damage(owner_id: int, source: Dictionary, amount: float) -> void:
	var p: PlayerData = _pl(source)
	if p == null:
		return
	shot_any = true
	if owner_id == p.id:
		p.stats.self_damage += amount
		award_f(p.id, -amount * 0.1)
	else:
		award_f(p.id, amount * 0.3)
		p.stats.damage_dealt += amount
		shot_damage += amount
		shot_hit = true

static func on_fire_started(source: Dictionary) -> void:
	var p: PlayerData = _pl(source)
	if p != null:
		if int(source["player_id"]) == shot_player:
			shot_any = true
		p.stats.fires_started += 1
		award(p.id, 20, "fire", true)
		Unlocks.on_fire_started(source)

static func on_fire_extinguished(source: Dictionary) -> void:
	var p: PlayerData = _pl(source)
	if p != null:
		p.stats.fires_extinguished += 1
		award(p.id, 15, "firefighter")

static func on_explosion() -> void:
	shot_any = true
	shot_explosions += 1

static func on_shot(player_id: int, ammo: String) -> void:
	var p: PlayerData = Game.player(player_id)
	if p == null:
		return
	p.stats.shots += 1
	award(player_id, 5, "shot", true)
	shot_ammo_id = ammo
	if ammo == "cow":
		p.stats.cows_fired += 1
	if ammo == "meteor":
		p.stats.cheese_used += 1
	begin_shot(player_id)

static func on_shot_landed(player_id: int, shot_distance: float, in_water: bool) -> void:
	var p: PlayerData = Game.player(player_id)
	if p == null:
		return
	if shot_hit:
		p.stats.hits += 1
	if in_water and not shot_hit:
		p.stats.water_misses += 1
		award(player_id, 10, "fishfood")
	if shot_hit and shot_distance > 80.0:
		award(player_id, mini(int((shot_distance - 80.0) * 1.5), 300), "longshot")
	if shot_hit and shot_ammo_id == "cow":
		award(player_id, 100, "cow_burst")
	p.stats.longest_shot = maxf(p.stats.longest_shot, shot_distance)

static func on_elimination(player_id: int) -> void:
	var p: PlayerData = Game.player(player_id)
	if p == null:
		return
	p.eliminated = true
	p.eliminated_order = Game.elimination_count
	Game.elimination_count += 1
	if p.last_damaged_by >= 0 and p.last_damaged_by != player_id:
		award(p.last_damaged_by, 500, "eliminated")

static func on_turn_survived() -> void:
	for p in Game.players:
		if not p.eliminated:
			p.stats.turns_survived += 1
			award(p.id, 10, "survive", true)

# ------------------------------------------------------------------ titles
## Returns Array of {player_id, title_id}; max 2 titles per player, awarded in table order.
static func compute_titles(winner_id: int) -> Array:
	var out: Array = []
	var count: Dictionary = {}
	var players: Array[PlayerData] = Game.players

	var give := func(pid: int, tid: String) -> void:
		var c: int = int(count.get(pid, 0))
		if c >= 2:
			return
		count[pid] = c + 1
		out.append({"player_id": pid, "title_id": tid})

	var best_by := func(metric: Callable, threshold: float) -> int:
		var best: int = -1
		var bv: float = -1.0
		for p in players:
			var v: float = float(metric.call(p))
			if v >= threshold and v > bv and int(count.get(p.id, 0)) < 2:
				bv = v
				best = p.id
		return best

	var pid: int = int(best_by.call(func(p: PlayerData) -> float: return float(p.stats.cows_fired), 1.0))
	if pid >= 0:
		give.call(pid, "cow_launcher")
	pid = int(best_by.call(func(p: PlayerData) -> float: return float(p.stats.fires_started), 10.0))
	if pid >= 0:
		give.call(pid, "pyro")
	# pacifist: fewest hits among players with shots >= 3
	var pac: int = -1
	var pac_hits: int = 1 << 30
	for p in players:
		if p.stats.shots >= 3 and p.stats.hits < pac_hits and int(count.get(p.id, 0)) < 2:
			pac_hits = p.stats.hits
			pac = p.id
	if pac >= 0:
		give.call(pac, "pacifist")
	# sniper: highest ratio, shots >= 4, >= 60%
	var sn: int = -1
	var sn_r: float = 0.0
	for p in players:
		if p.stats.shots >= 4 and int(count.get(p.id, 0)) < 2:
			var ratio: float = float(p.stats.hits) / float(p.stats.shots)
			if ratio >= 0.6 and ratio > sn_r:
				sn_r = ratio
				sn = p.id
	if sn >= 0:
		give.call(sn, "sniper")
	pid = int(best_by.call(func(p: PlayerData) -> float: return float(p.stats.water_misses), 3.0))
	if pid >= 0:
		give.call(pid, "fisherman")
	pid = int(best_by.call(func(p: PlayerData) -> float: return float(p.stats.buildings_destroyed), 4.0))
	if pid >= 0:
		give.call(pid, "destroyer")
	pid = int(best_by.call(func(p: PlayerData) -> float: return float(p.stats.settlers_launched), 15.0))
	if pid >= 0:
		give.call(pid, "settler_bowler")
	pid = int(best_by.call(func(p: PlayerData) -> float: return p.stats.self_damage, 200.0))
	if pid >= 0:
		give.call(pid, "self_own")
	pid = int(best_by.call(func(p: PlayerData) -> float: return float(p.stats.fires_extinguished), 5.0))
	if pid >= 0:
		give.call(pid, "firefighter")
	pid = int(best_by.call(func(p: PlayerData) -> float: return float(p.stats.cheese_used), 1.0))
	if pid >= 0:
		give.call(pid, "cheesemaster")
	pid = int(best_by.call(func(p: PlayerData) -> float: return p.stats.longest_shot, 90.0))
	if pid >= 0:
		give.call(pid, "longshot")
	# survivor: most turns survived, winner excluded
	var sv: int = -1
	var sv_t: int = -1
	for p in players:
		if p.id != winner_id and p.stats.turns_survived > sv_t and int(count.get(p.id, 0)) < 2:
			sv_t = p.stats.turns_survived
			sv = p.id
	if sv >= 0 and sv_t > 0:
		give.call(sv, "survivor")
	# loser: first eliminated
	for p in players:
		if p.eliminated_order == 0 and int(count.get(p.id, 0)) < 2:
			give.call(p.id, "loser")
			break
	return out
