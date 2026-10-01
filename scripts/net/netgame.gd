class_name NetGame
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Online game sync (spec 19). Host-authoritative rules, replicated simulation:
##  * every machine builds the same world from seed + layout nonce and simulates every shot itself (visuals),
##  * a shot is sent to the host, which stamps it with a random seed and broadcasts it; all machines then fire the
##    same shot with the same RNG state,
##  * the host alone decides turn order, wind, damage to catapults, unlocks, eliminations and the winner and sends
##    them (plus a snapshot at every turn end) to the clients, who simply apply them.
## Nothing here runs without an active `Net` session.

static var main: Node = null
static var queued_shot: Dictionary = {}       # a shot that arrived before we reached the AIMING phase
static var awaiting_shot: bool = false
static var _aim_acc: float = 0.0
static var _placed_pending: Dictionary = {}   # "idx:stage" -> message that arrived before its turn in the placement
static var hash_mismatches: int = 0
static var last_host_hash: int = 0
static var shot_serial: int = 0
static var in_game: bool = false
static var fixed_parts: int = 0           # parts that stood here but not on the host: removed after a turn
static var missing_parts: int = 0         # parts that stand on the host but fell here: put back after the turn

static func setup(main_node: Node) -> void:
	main = main_node
	Net.on("start", _on_start)
	Net.on("placed", _on_placed)
	Net.on("aim", _on_aim)
	Net.on("fire_req", _on_fire_req)
	Net.on("shot", _on_shot)
	Net.on("skip", _on_skip)
	Net.on("turn_start", _on_turn_start)
	Net.on("turn_end", _on_turn_end)
	Net.on("cat_dead", _on_cat_dead)
	Net.on("grant", _on_grant)
	Net.on("drop", _on_drop)
	Net.on("over", _on_over)
	Net.on("peer", _on_peer)
	Net.on("reject", _on_reject)

static func reset() -> void:
	queued_shot = {}
	awaiting_shot = false
	_aim_acc = 0.0
	_placed_pending.clear()
	hash_mismatches = 0
	fixed_parts = 0
	missing_parts = 0
	in_game = false

# ------------------------------------------------------------------ start
## Host: the player list of the match from the menu rows + the connected peers (peer i takes seat i)
static func make_cfg(rows_cfg: Array, seat_count: int) -> Dictionary:
	var peers: Array = []
	for id in Net.roster:
		if int(id) != 1:
			peers.append(int(id))
	peers.sort()
	var total: int = clampi(maxi(seat_count, 1 + peers.size()), Cfg.MIN_PLAYERS, Cfg.MAX_PLAYERS)
	var players: Array = []
	for i in total:
		var row: Dictionary = (rows_cfg[i] as Dictionary).duplicate() if i < rows_cfg.size() else {"name": "CPU %d" % (i + 1), "color": i, "type": "squire"}
		if i == 0:
			row["type"] = "human"
			row["net_peer"] = 1
			row["name"] = Net.peer_name(1)
		elif i - 1 < peers.size():
			row["type"] = "human"
			row["net_peer"] = int(peers[i - 1])
			row["name"] = Net.peer_name(int(peers[i - 1]))
		else:
			if str(row["type"]) == "human":
				row["type"] = "squire"
			row["net_peer"] = -1
		row["color"] = int(row["color"])
		players.append(row)
	return {"k": "start", "seed": Settings.seed_text, "nonce": str(randi()), "players": players, "timer": Settings.timer, "cats": Settings.catapult_count, "posts": Settings.palisade_count, "hills": Settings.terrain_hills, "arsenal": Settings.arsenal.duplicate(), "ver": Cfg.game_version()}

static func host_start(cfg: Dictionary) -> void:
	Net.send_all(cfg)
	in_game = true
	main.call("net_start", cfg)

static func _on_start(_from: int, d: Dictionary) -> void:
	if Net.is_host:
		return
	if str(d.get("ver", "")) != Cfg.game_version():
		Events.toast.emit(I18n.t("net.version", {"host": str(d.get("ver", "?")), "me": Cfg.game_version()}))
	in_game = true
	main.call("net_start", d)

static func _on_reject(_from: int, d: Dictionary) -> void:
	Events.toast.emit(I18n.t("net." + str(d.get("why", "busy"))))
	Net.leave()

# ------------------------------------------------------------------ placement
static func placement_payload(idx: int, stage: int) -> Dictionary:
	var p: PlayerData = Game.players[idx]
	var out: Dictionary = {"k": "placed", "idx": idx, "stage": stage}
	if stage == 0:
		var cats: Array = []
		for c in p.catapults:
			if is_instance_valid(c):
				var cat: Catapult = c as Catapult
				var o: Vector3 = cat.global_pos()
				cats.append([o.x, o.y, o.z, cat.yaw])
		out["cats"] = cats
	else:
		var fences: Array = []
		for f in p.fences:
			var fd: Dictionary = f as Dictionary
			var c2: Vector3 = fd["center"] as Vector3
			fences.append({"c": [c2.x, c2.y, c2.z], "y": float(fd["yaw"]), "n": Posts.fence_layers(fd)})
		out["fences"] = fences
	return out

## A seat's placement is finished (human pressed Done, or the host auto-placed a CPU)
static func send_placed(idx: int, stage: int) -> void:
	if not Net.active:
		return
	var d: Dictionary = placement_payload(idx, stage)
	if Net.is_host:
		Net.send_all(d)
	else:
		Net.send_host(d)

static func _on_placed(from: int, d: Dictionary) -> void:
	if Net.is_host:
		# relay to everybody else (the author already has it)
		for id in Net.roster:
			if int(id) != 1 and int(id) != from:
				Net.send_to(int(id), d)
	var pl: Node = main.get("placement") as Node
	if pl == null or not bool(pl.get("_active")):
		_placed_pending["%d:%d" % [int(d["idx"]), int(d["stage"])]] = d
		return
	pl.call("net_placed", d)

static func take_pending_placed(idx: int, stage: int) -> Dictionary:
	var key: String = "%d:%d" % [idx, stage]
	if _placed_pending.has(key):
		var d: Dictionary = _placed_pending[key] as Dictionary
		_placed_pending.erase(key)
		return d
	return {}

static func apply_placement(world: GameWorld, d: Dictionary, rng: Rng) -> void:
	var p: PlayerData = Game.players[int(d["idx"])]
	if int(d["stage"]) == 0:
		for e in (d["cats"] as Array):
			var a: Array = e as Array
			world.place_catapult(p, Vector3(float(a[0]), float(a[1]), float(a[2])), float(a[3]))
	else:
		for f in (d["fences"] as Array):
			var fd: Dictionary = f as Dictionary
			var c: Array = fd["c"] as Array
			var fence: Dictionary = Posts.place_fence(p, Vector3(float(c[0]), float(c[1]), float(c[2])), float(fd["y"]), rng)
			for k in range(1, int(fd["n"])):
				Posts.stack_fence(p, fence, rng)

# ------------------------------------------------------------------ aiming and shots
## Called every physics tick while a LOCAL human aims: the others watch the catapult turn
static func tick_aim(dt: float) -> void:
	if not Net.active or Turn.sel == null:
		return
	_aim_acc += dt
	if _aim_acc < 0.12:
		return
	_aim_acc = 0.0
	var d: Dictionary = {"k": "aim", "cat": Turn.sel.index, "yaw": Turn.aim_yaw, "elev": Turn.aim_elev, "power": Turn.aim_power, "ammo": Turn.aim_ammo, "seat": Game.current_player}
	if Net.is_host:
		Net.send_all(d)
	else:
		Net.send_host(d)

static func _on_aim(from: int, d: Dictionary) -> void:
	if Net.is_host:
		for id in Net.roster:
			if int(id) != 1 and int(id) != from:
				Net.send_to(int(id), d)
	var p: PlayerData = Game.cur()
	if p == null or p.is_human() or Turn.phase != Turn.Phase.AIMING or int(d["seat"]) != Game.current_player:
		return
	Turn.net_aim(d)

static func _shot_msg() -> Dictionary:
	return {"k": "shot", "seat": Game.current_player, "cat": Turn.sel.index, "yaw": Turn.aim_yaw, "elev": Turn.aim_elev, "power": Turn.aim_power, "ammo": Turn.aim_ammo}

## `Turn.fire()` in an online game: the host broadcasts the shot, a client asks the host to do so
static func request_fire() -> void:
	if Turn.sel == null:
		return
	var m: Dictionary = _shot_msg()
	if Net.is_host:
		_broadcast_shot(m)
	elif Game.cur().is_human() and not awaiting_shot:
		awaiting_shot = true
		m["k"] = "fire_req"
		Net.send_host(m)

static func _on_fire_req(from: int, d: Dictionary) -> void:
	var p: PlayerData = Game.cur()
	if not Net.is_host or p == null or p.net_peer != from or Turn.phase != Turn.Phase.AIMING or int(d["seat"]) != Game.current_player:
		return
	d["k"] = "shot"
	_broadcast_shot(d)

static func _broadcast_shot(m: Dictionary) -> void:
	shot_serial += 1
	m["k"] = "shot"
	m["seed"] = randi() & 0x7fffffff
	m["n"] = shot_serial
	Net.send_all(m)
	_on_shot(1, m)

static func _on_shot(_from: int, d: Dictionary) -> void:
	awaiting_shot = false
	if Turn.phase == Turn.Phase.AIMING:
		Turn.net_fire(d)
	else:
		queued_shot = d

## Same RNG state everywhere before a shot is simulated
static func reseed(seed_value: int) -> void:
	Projectile.rng = Rng.new(seed_value)
	Explosion.rng = Rng.new(seed_value + 1)
	Breakable.rng = Rng.new(seed_value + 2)
	Fire.rng = Rng.new(seed_value + 3)
	Landslide.rng = Rng.new(seed_value + 4)
	Powder.rng = Rng.new(seed_value + 5)
	WaterSys.rng = Rng.new(seed_value + 6)
	Settler.rng = Rng.new(seed_value + 7)
	Animal.rng = Rng.new(seed_value + 8)
	Brigade.rng = Rng.new(seed_value + 9)

static func send_skip() -> void:
	if Net.is_host:
		Turn.skip_turn()
	else:
		Net.send_host({"k": "skip", "seat": Game.current_player})

static func _on_skip(from: int, d: Dictionary) -> void:
	var p: PlayerData = Game.cur()
	if Net.is_host and p != null and p.net_peer == from and int(d["seat"]) == Game.current_player:
		Turn.skip_turn()

# ------------------------------------------------------------------ turns (host decides, clients follow)
static func send_turn_start() -> void:
	Net.send_all({"k": "turn_start", "cur": Game.current_player, "turn": Game.turn_number, "wx": Game.wind.x, "wy": Game.wind.y})

static func _on_turn_start(_from: int, d: Dictionary) -> void:
	if Net.is_host:
		return
	Turn.net_turn_start(d)

static func live_hash() -> int:
	var h: int = 17
	for s in Breakable.structures:
		if s.free_parts:
			continue
		h = (h * 31 + s.live_count) % 1000003
	return h

static func dead_total() -> int:
	var n: int = 0
	for st in Breakable.structures:
		if not st.free_parts:
			n += maxi(st.initial_count - st.live_count, 0)
	return n

static func _skey(s: Structure) -> String:
	return "%d|%s|%d|%d" % [s.owner_id, s.kind, roundi(s.center.x * 5.0), roundi(s.center.z * 5.0)]

## Damaged structures as bitmaps of their living parts ("1" = stands), by a position key
static func struct_changes() -> Dictionary:
	var out: Dictionary = {}
	for st in Breakable.structures:
		if st.free_parts or st.live_count >= st.initial_count:
			continue
		var bm: String = ""
		for p in st.parts:
			bm += "0" if p.state == Part.State.DEAD else "1"
		out[_skey(st)] = bm
	return out

## Remove what the host has already lost (what fell here but still stands there cannot be put back)
static func reconcile_structures(host: Dictionary) -> void:
	var local: Dictionary = {}
	for st in Breakable.structures:
		if not st.free_parts:
			local[_skey(st)] = st
	var keys: Dictionary = {}
	for k in host:
		keys[k] = true
	for k2 in local:
		if (local[k2] as Structure).live_count < (local[k2] as Structure).initial_count:
			keys[k2] = true
	for key in keys:
		var ls: Structure = local.get(key) as Structure
		if ls == null:
			continue
		# a structure the host has not listed is undamaged there: every part stands
		var bm: String = str(host[key]) if host.has(key) else "1".repeat(ls.parts.size())
		var diff_before: int = absi(bm.count("1") - ls.live_count)
		if diff_before >= 15 and Settings.debug:
			print("[net] %s: host has %d of %d parts standing, here %d" % [key, bm.count("1"), ls.parts.size(), ls.live_count])
		for i in mini(bm.length(), ls.parts.size()):
			var alive_here: bool = ls.parts[i].state != Part.State.DEAD
			if alive_here and bm[i] == "0":
				Breakable.discard_part(ls.parts[i])
				fixed_parts += 1
			elif not alive_here and bm[i] == "1":
				Breakable.revive_part(ls.parts[i])
				missing_parts += 1
		ls.support_dirty = false

static func snapshot() -> Dictionary:
	var pl: Array = []
	for p in Game.players:
		var st: PlayerData.Stats = p.stats
		var cats: Array = []
		for c in p.catapults:
			if is_instance_valid(c):
				var cat: Catapult = c as Catapult
				var o: Vector3 = cat.global_pos() if not cat.destroyed else Vector3.ZERO
				cats.append([cat.index, cat.hp, cat.destroyed, o.x, o.y, o.z])
		pl.append({"ammo": p.ammo.duplicate(), "hits": p.hits_taken, "ldb": p.last_damaged_by, "cats": cats, "st": [st.shots, st.hits, st.damage_dealt, st.settlers_launched, st.settlers_killed, st.catapults_destroyed, st.buildings_destroyed, st.fires_started, st.fires_extinguished, st.cows_fired, st.cheese_used, st.self_damage, st.water_misses, st.longest_shot, st.turns_survived]})
	return {"pl": pl, "hash": live_hash(), "sc": struct_changes()}

static func apply_snapshot(s: Dictionary) -> void:
	var pls: Array = s["pl"] as Array
	for i in mini(pls.size(), Game.players.size()):
		var d: Dictionary = pls[i] as Dictionary
		var p: PlayerData = Game.players[i]
		for k in (d["ammo"] as Dictionary):
			p.ammo[str(k)] = int((d["ammo"] as Dictionary)[k])
		p.hits_taken = int(d["hits"])
		p.last_damaged_by = int(d["ldb"])
		var sa: Array = d["st"] as Array
		var st: PlayerData.Stats = p.stats
		st.shots = int(sa[0])
		st.hits = int(sa[1])
		st.damage_dealt = float(sa[2])
		st.settlers_launched = int(sa[3])
		st.settlers_killed = int(sa[4])
		st.catapults_destroyed = int(sa[5])
		st.buildings_destroyed = int(sa[6])
		st.fires_started = int(sa[7])
		st.fires_extinguished = int(sa[8])
		st.cows_fired = int(sa[9])
		st.cheese_used = int(sa[10])
		st.self_damage = float(sa[11])
		st.water_misses = int(sa[12])
		st.longest_shot = float(sa[13])
		st.turns_survived = int(sa[14])
		for e in (d["cats"] as Array):
			var a: Array = e as Array
			for c in p.catapults:
				if not is_instance_valid(c) or (c as Catapult).index != int(a[0]):
					continue
				var cat: Catapult = c as Catapult
				if bool(a[2]):
					cat.destroy("net", true)
				elif not cat.destroyed:
					cat.hp = float(a[1])
					var want := Vector3(float(a[3]), float(a[4]), float(a[5]))
					if cat.body_id != 0 and cat.global_pos().distance_to(want) > 0.6:
						var xf: Transform3D = PhysWorld.get_transform(cat.body_id)
						PhysWorld.set_transform(cat.body_id, Transform3D(xf.basis, want))
						PhysWorld.set_velocity(cat.body_id, Vector3.ZERO, Vector3.ZERO)
	last_host_hash = int(s["hash"])
	reconcile_structures(s["sc"] as Dictionary)
	if live_hash() != last_host_hash:
		hash_mismatches += 1
		if Settings.debug:
			print("[net] world differs from the host (structure hash %d vs %d), %d times so far" % [live_hash(), last_host_hash, hash_mismatches])

static func send_turn_end(newly: Array) -> void:
	Net.send_all({"k": "turn_end", "newly": newly, "snap": snapshot()})

static func _on_turn_end(_from: int, d: Dictionary) -> void:
	if Net.is_host:
		return
	Turn.net_turn_end(d)

static func send_over(winner: int) -> void:
	Net.send_all({"k": "over", "winner": winner})

static func _on_over(_from: int, d: Dictionary) -> void:
	if Net.is_host:
		return
	Turn.net_game_over(int(d["winner"]))

# ------------------------------------------------------------------ host decisions pushed to the clients
static func send_cat_dead(owner_id: int, idx: int, reason: String) -> void:
	Net.send_all({"k": "cat_dead", "pid": owner_id, "idx": idx, "reason": reason})

static func _on_cat_dead(_from: int, d: Dictionary) -> void:
	if Net.is_host:
		return
	var p: PlayerData = Game.player(int(d["pid"]))
	if p == null:
		return
	for c in p.catapults:
		if is_instance_valid(c) and (c as Catapult).index == int(d["idx"]):
			(c as Catapult).destroy(str(d["reason"]), true)

static func send_grant(pid: int, ammo_id: String, n: int, why: String) -> void:
	Net.send_all({"k": "grant", "pid": pid, "ammo": ammo_id, "n": n, "why": why})

static func _on_grant(_from: int, d: Dictionary) -> void:
	if not Net.is_host:
		Unlocks.net_grant(int(d["pid"]), str(d["ammo"]), int(d["n"]), str(d["why"]))

# ------------------------------------------------------------------ leaving players
static func _on_peer(pid: int, d: Dictionary) -> void:
	if not Net.is_host:
		return
	if bool(d["on"]):
		if in_game:
			Net.send_to(pid, {"k": "reject", "why": "running"})
		return
	for p in Game.players:
		if p.net_peer == pid and not p.eliminated:
			Net.send_all({"k": "drop", "seat": p.id})
			apply_drop(p.id)

static func _on_drop(_from: int, d: Dictionary) -> void:
	if not Net.is_host:
		apply_drop(int(d["seat"]))

## A player left: they are out, their catapults vanish
static func apply_drop(seat: int) -> void:
	var p: PlayerData = Game.player(seat)
	if p == null or p.eliminated:
		return
	print("[net] seat %d (%s) left the game" % [seat, p.name])
	for c in p.catapults:
		if is_instance_valid(c):
			var cat: Catapult = c as Catapult
			if cat.body_id != 0:
				PhysWorld.remove_body(cat.body_id)
			cat.queue_free()
	p.catapults.clear()
	Scoring.on_elimination(seat)
	Events.player_eliminated.emit(seat)
	Events.banner.emit(I18n.t("net.left", {"name": p.name}), "elim")
	Events.kill_feed.emit(I18n.t("net.left", {"name": p.name}))
	if main != null and Game.state == Game.State.PLACEMENT:
		var pl: Node = main.get("placement") as Node
		if pl != null:
			pl.call("net_player_dropped", seat)
	elif Game.state == Game.State.BATTLE and Net.is_host:
		Turn.host_player_dropped(seat)
