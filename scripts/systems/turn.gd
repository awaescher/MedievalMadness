class_name Turn
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Turn manager (spec 2.4-2.5, 6.5) as a static state machine: TURN_START -> SELECT -> AIMING -> FIRING ->
## FLIGHT -> AFTERMATH -> TURN_END. Also hosts predict_trajectory() used by the preview and the CPU.

enum Phase { NONE, PLACEMENT, TURN_START, AIMING, FIRING, FLIGHT, AFTERMATH, TURN_END, GAME_OVER }

static var phase: int = Phase.NONE
static var phase_time: float = 0.0
static var world: GameWorld
static var cam: CameraRig
static var sel: Catapult = null
static var aim_yaw: float = 0.0            # radians (0 = facing -Z)
static var aim_elev: float = Cfg.DEFAULT_ELEVATION   # degrees
static var aim_power: float = 0.0          # 0..1
static var aim_ammo: String = "stone"
## Team gifts: a team mate offers a weapon of theirs to the player whose turn it is (ammo id -> offerer's player id).
## Only for this turn; the offerer pays one unit when the weapon is actually fired, otherwise it stays with them.
static var gifts: Dictionary = {}
static var has_aimed: bool = false
static var time_left: float = 0.0
static var timer_on: bool = false
static var impact_points: Array[Vector3] = []
static var shot_ammo: String = "stone"
static var shot_owner: int = -1
static var aftermath_time: float = 0.0
static var settle_acc: float = 0.0
static var _settle_check: float = 0.0
static var _pending_shot: Dictionary = {}
static var last_shot_score: float = 0.0
static var turn_count: int = 0
static var shots_this_turn: int = 0
static var _launch_dir: Vector3 = Vector3.ZERO
static var _banner_shown: bool = false
static var _hit_reported: bool = false
static var cpu_active: bool = false
static var _lightning_done: bool = false
static var _event_pending: bool = false
static var paused_by_focus: bool = false
static var _frozen_time: float = 0.0
static var _end_hold: float = 0.6
static var _epic_done: bool = false
static var _net_firing: bool = false
static var _pellet_first_t: float = -1.0       # flint sack: when the first piece landed (the camera waits for the rest)
static var drove_local: bool = false       # this machine drove the catapult itself (its ramming damage is already applied)
static var move_used: float = 0.0          # relocate action: metres driven so far this turn (set by the Actions UI)

# ------------------------------------------------------------------ ballistic prediction (also used by the CPU)
static func launch_velocity(yaw: float, elev_deg: float, power: float) -> Vector3:
	return Ballistics.launch_velocity(yaw, elev_deg, power)

## Simulates the flight (gravity, wind, per-ammo drag; terrain only) at the physics rate.
## Implemented in the pure `Ballistics` class (headless-testable); this is the API named in the spec.
static func predict_trajectory(start_pos: Vector3, velocity: Vector3, ammo_id: String, wind: Vector2, max_t: float = 12.0) -> Dictionary:
	return Ballistics.predict(start_pos, velocity, ammo_id, wind, max_t)

## Where the bucket releases the projectile for a given elevation (analytic, matches Catapult model)
static func launch_origin(c: Catapult, elev_deg: float, yaw: float) -> Vector3:
	var e: float = deg_to_rad(elev_deg)
	var l: float = Catapult.ARM_LEN_UP + 0.35
	var local := Vector3(0.0, Catapult.PIVOT.y + l * cos(e), Catapult.PIVOT.z - l * sin(e))
	return c.global_pos() + Basis(Vector3.UP, yaw) * local

# ------------------------------------------------------------------ helpers
static func current_player() -> PlayerData:
	return Game.cur()

static func _set_phase(p: int) -> void:
	phase = p
	phase_time = 0.0

static func wind_effective() -> Vector2:
	return Game.wind

# ------------------------------------------------------------------ battle start
static func start_battle(_players: Array) -> void:
	Game.turn_number = 0
	Game.elimination_count = 0
	Game.wind = Vector2.ZERO
	Game.current_player = -1
	Game.set_state(Game.State.BATTLE)
	Events.banner.emit(I18n.t("banner.battle"), "battle")
	Sfx.play("stinger_event", Vector3.INF, 0.8, 5)
	_next_turn()

static func _next_turn() -> void:
	if Net.is_client():
		return          # online: the host decides who plays next and sends it (net_turn_start)
	var n: int = Game.players.size()
	var idx: int = Game.current_player
	for i in n:
		idx = (idx + 1) % n
		if not Game.players[idx].eliminated:
			break
	Game.current_player = idx
	Game.turn_number += 1
	turn_count += 1
	# wind: change speed +-3 and rotate direction +-40 degrees (x1.8 during storms)
	var r: Rng = Game.rng_battle
	# wind option: none / light (few m/s, little effect) / strong (the full range)
	var lvl: float = [0.0, 0.25, 1.0][clampi(Game.wind_level, 0, 2)]
	var base_speed: float = clampf(Game.wind_speed() / _wind_mult() + r.range_f(-Cfg.WIND_CHANGE_MAX, Cfg.WIND_CHANGE_MAX) * lvl, 0.0, Cfg.WIND_MAX * lvl)
	var ang: float = atan2(Game.wind.y, Game.wind.x) if Game.wind.length() > 0.05 else r.range_f(0.0, TAU)
	ang += deg_to_rad(r.range_f(-40.0, 40.0))
	# weather first (may change the multiplier)
	Weather.turn_start()
	Game.wind = Vector2(cos(ang), sin(ang)) * base_speed * _wind_mult() if lvl > 0.0 else Vector2.ZERO
	_begin_turn()
	if Net.active:
		NetGame.send_turn_start()

## Online client: the host announced the next turn (player, number, wind)
static func net_turn_start(d: Dictionary) -> void:
	Game.current_player = int(d["cur"])
	Game.turn_number = int(d["turn"])
	turn_count = Game.turn_number
	Game.wind = Vector2(float(d["wx"]), float(d["wy"]))
	_begin_turn()

static func _begin_turn() -> void:
	var p: PlayerData = Game.cur()
	impact_points.clear()
	gifts.clear()
	has_aimed = false
	shots_this_turn = 0
	_hit_reported = false
	_lightning_done = false
	sel = null
	timer_on = false
	NetGame.awaiting_shot = false
	Events.wind_changed.emit(Game.wind)
	_set_phase(Phase.TURN_START)
	Events.turn_start.emit(p.id)
	Events.banner.emit(I18n.pick("banner.turn_start", Game.rng_battle, {"name": p.name}), "turn")
	Sfx.play("turn_start", Vector3.INF, 0.8, 5)
	# camera to the village
	if cam != null:
		cam.focus_on(p.village_center + Vector3(0, 0, 0), 46.0, 40.0)
	# every player keeps their own ammo choice (nothing carries over from the previous player)
	aim_ammo = p.ammo_sel if p.has_ammo(p.ammo_sel) else "stone"

static func _wind_mult() -> float:
	return 1.8 if Game.weather == "storm" else 1.0

# ------------------------------------------------------------------ selection & aiming API (human or CPU)
static func living_catapults() -> Array:
	var p: PlayerData = Game.cur()
	return p.living_catapults() if p != null else []

static func select_catapult(c: Catapult) -> void:
	if c == null or c.destroyed:
		return
	if sel != null and sel != c:
		sel.set_selected(false)
		sel.rest_arm()
		sel.hide_ammo_visual()
	sel = c
	if not c.ensure_grounded():
		sel = null
		return
	c.set_selected(true)
	Game.cur().last_catapult = c.index
	aim_yaw = c.yaw
	aim_elev = clampf(c.elevation_deg if c.elevation_deg > 0.0 else Cfg.DEFAULT_ELEVATION, Cfg.MIN_ELEVATION, Cfg.MAX_ELEVATION)
	aim_power = 0.0
	c.set_ammo_visual(aim_ammo)
	c.show_hp_bar(2.5)
	if cam != null:
		cam.aim_at(c.global_pos(), aim_yaw, deg_to_rad(aim_elev))

static func cycle_catapult(dir: int = 1) -> void:
	var list: Array = living_catapults()
	if list.is_empty():
		return
	var i: int = list.find(sel)
	i = (i + dir + list.size()) % list.size() if i >= 0 else 0
	select_catapult(list[i] as Catapult)

## "" while a weapon is selected, "relocate" / "wall" while a turn action is selected
static func action_mode() -> String:
	return aim_ammo if AmmoDef.is_action_id(aim_ammo) else ""

static func is_action_mode() -> bool:
	return AmmoDef.is_action_id(aim_ammo)

## Offer (on) or take back (off) one unit of a weapon for the player whose turn it is. Returns whether it was applied.
## `force`: online clients apply what the host decided.
static func set_gift(offerer_id: int, ammo_id: String, on: bool, force: bool = false) -> bool:
	var cur_p: PlayerData = Game.cur()
	var o: PlayerData = Game.player(offerer_id)
	if cur_p == null or o == null:
		return false
	if not force:
		var a: AmmoDef = AmmoDef.get_def(ammo_id)
		if phase != Phase.AIMING or not o.is_ally(cur_p) or o.eliminated or a == null or a.is_action() or ammo_id == "stone":
			return false
		if on and (o.ammo_count(ammo_id) <= 0 or (gifts.has(ammo_id) and int(gifts[ammo_id]) != offerer_id)):
			return false
		if not on and int(gifts.get(ammo_id, -1)) != offerer_id:
			return false
	if on:
		gifts[ammo_id] = offerer_id
		if cur_p.is_human():
			Events.toast.emit(I18n.t("gift.offered", {"name": o.name, "ammo": I18n.t("ammo." + ammo_id)}))
			Sfx.play("stinger_event", Vector3.INF, 0.35, 5)
	else:
		gifts.erase(ammo_id)
	Events.gifts_changed.emit()
	return true

static func set_ammo(id: String) -> void:
	var p: PlayerData = Game.cur()
	if p == null or not (p.has_ammo(id) or gifts.has(id)):
		return
	var action: bool = AmmoDef.is_action_id(id)
	aim_ammo = id
	if not action:
		p.ammo_sel = id
	if sel != null and phase == Phase.AIMING:
		sel.set_ammo_visual(id)
		if action:
			set_aim(aim_yaw, aim_elev, 0.0)
			sel.rest_arm()
			if id == "wall" and cam != null:
				cam.focus_on(p.village_center, 46.0, 40.0)
	Sfx.play("ui_click", Vector3.INF, 0.5, 0)

static func set_aim(yaw: float, elev_deg: float, power: float) -> void:
	if sel == null or phase != Phase.AIMING:
		return
	aim_yaw = yaw
	aim_elev = clampf(elev_deg, Cfg.MIN_ELEVATION, Cfg.MAX_ELEVATION)
	aim_power = clampf(power, 0.0, 1.0)
	sel.set_yaw(yaw)
	sel.set_pull(aim_power, aim_elev)
	if cam != null:
		cam.aim_at(sel.global_pos(), aim_yaw, deg_to_rad(aim_elev))
	has_aimed = has_aimed or aim_power > 0.04

static func can_fire() -> bool:
	return phase == Phase.AIMING and sel != null and not sel.destroyed and aim_power > 0.08

static func current_velocity() -> Vector3:
	return launch_velocity(aim_yaw, aim_elev, aim_power)

## Fire with the current aim (human release / space / timeout / CPU)
static func fire() -> void:
	if phase != Phase.AIMING or sel == null or sel.destroyed or is_action_mode():
		return
	if Net.active and not _net_firing:
		NetGame.request_fire()          # host: broadcast the shot; client: ask the host
		return
	if not sel.ensure_grounded():
		return
	var p: PlayerData = Game.cur()
	if not p.has_ammo(aim_ammo) and not gifts.has(aim_ammo):
		aim_ammo = "stone"
	p.ammo_sel = aim_ammo
	shot_ammo = aim_ammo
	_pellet_first_t = -1.0
	shot_owner = p.id
	var vel: Vector3 = launch_velocity(aim_yaw, aim_elev, aim_power)
	var origin: Vector3 = launch_origin(sel, aim_elev, aim_yaw)
	_pending_shot = {"vel": vel, "origin": origin, "ammo": shot_ammo}
	var giver: PlayerData = Game.player(int(gifts.get(shot_ammo, -1)))
	if giver != null and giver.ammo_count(shot_ammo) > 0:
		giver.use_ammo(shot_ammo)            # a gift from a team mate is used first: the giver has one less
		Events.kill_feed.emit(I18n.t("gift.used", {"from": giver.name, "to": p.name, "ammo": I18n.t("ammo." + shot_ammo)}))
		Events.ammo_changed.emit(giver.id)
	else:
		p.use_ammo(shot_ammo)
	gifts.clear()
	Events.gifts_changed.emit()
	Events.ammo_changed.emit(p.id)
	shots_this_turn += 1
	_epic_done = false
	timer_on = false
	if not sel.released.is_connected(_on_released):
		sel.released.connect(_on_released, CONNECT_ONE_SHOT)
	sel.set_selected(false)
	sel.set_pull(aim_power, aim_elev)
	sel.play_fire()
	_set_phase(Phase.FIRING)
	Sfx.play("creak", sel.global_pos(), 0.5, 0)

## A turn action instead of a shot (local human): {t: "wall", c: [x,y,z], y: yaw, stack: bool} or
## {t: "move", cat: index, p: [x,y,z], y: yaw}. Online the host stamps it and everybody applies it.
static func do_action(d: Dictionary) -> void:
	if phase != Phase.AIMING or sel == null or sel.destroyed:
		return
	if Net.active:
		NetGame.request_act(d)
	else:
		d["seed"] = randi() & 0x7fffffff
		net_act(d)

## Runs on every machine: the action happens and the turn is spent
static func net_act(d: Dictionary) -> void:
	var p: PlayerData = Game.cur()
	if p == null or phase != Phase.AIMING or int(d.get("seat", Game.current_player)) != Game.current_player:
		return
	match str(d["t"]):
		"wall":
			var c: Array = d["c"] as Array
			var pos := Vector3(float(c[0]), float(c[1]), float(c[2]))
			if Walls.apply(p, d, Rng.new(int(d.get("seed", 1)))):
				Sfx.play("thunk", pos, 1.0, 3)
				Fx.burst("dust", pos + Vector3.UP * 0.4, Color("#9a9a9a"), 1.0)
				Scoring.award(p.id, 20, "wall", true)
		"move":
			for c2 in p.living_catapults():
				if (c2 as Catapult).index == int(d["cat"]):
					var a: Array = d["p"] as Array
					(c2 as Catapult).place_at(Vector3(float(a[0]), float(a[1]), float(a[2])), float(d["y"]))
			if not drove_local:
				Actions.apply_hits(p, d.get("hits", []) as Array)
			drove_local = false
	if sel != null:
		sel.set_selected(false)
		sel.rest_arm()
	Scoring.begin_shot(p.id)
	shot_ammo = ""
	shots_this_turn = 0
	timer_on = false
	aftermath_time = 0.0
	settle_acc = 0.0
	_set_phase(Phase.AFTERMATH)

## Online: the host sent a shot (seat, catapult, aim, ammo, RNG seed): everybody fires exactly that
static func net_fire(d: Dictionary) -> void:
	var p: PlayerData = Game.cur()
	if p == null or phase != Phase.AIMING or int(d["seat"]) != Game.current_player:
		return
	var cat: Catapult = null
	for c in p.living_catapults():
		if (c as Catapult).index == int(d["cat"]):
			cat = c as Catapult
	if cat == null:
		return
	if sel != cat:
		select_catapult(cat)
	if sel == null:
		return
	aim_ammo = str(d["ammo"])
	if p.has_ammo(aim_ammo):
		p.ammo_sel = aim_ammo
	set_aim(float(d["yaw"]), float(d["elev"]), float(d["power"]))
	NetGame.reseed(int(d["seed"]))
	_net_firing = true
	fire()
	_net_firing = false

## Online: the active player's aim, shown on the other machines
static func net_aim(d: Dictionary) -> void:
	var p: PlayerData = Game.cur()
	if p == null:
		return
	if sel == null or sel.index != int(d["cat"]):
		for c in p.living_catapults():
			if (c as Catapult).index == int(d["cat"]):
				select_catapult(c as Catapult)
	if sel == null:
		return
	aim_ammo = str(d["ammo"])
	sel.set_ammo_visual(aim_ammo)
	set_aim(float(d["yaw"]), float(d["elev"]), float(d["power"]))

static func _on_released() -> void:
	if _pending_shot.is_empty():
		return
	var vel: Vector3 = _pending_shot["vel"] as Vector3
	var origin: Vector3 = _pending_shot["origin"] as Vector3
	var ammo: String = str(_pending_shot["ammo"])
	_pending_shot = {}
	var pr: Projectile = Projectile.launch(ammo, origin, vel, shot_owner, sel)
	_launch_dir = vel.normalized()
	_set_phase(Phase.FLIGHT)
	Events.camera_shake.emit(0.15)
	if cam != null:
		cam.follow_projectile(pr.position(), vel)

static func skip_turn() -> void:
	if Net.is_client():
		NetGame.send_skip()
		return
	if phase == Phase.AIMING or phase == Phase.TURN_START:
		Events.banner.emit(I18n.t("banner.skipped", {"name": Game.cur().name}), "info")
		if sel != null:
			sel.set_selected(false)
			sel.rest_arm()
		_finish_turn()

# ------------------------------------------------------------------ update
static func update(dt: float) -> void:
	if Game.state != Game.State.BATTLE:
		return
	phase_time += dt
	var real_dt: float = dt / maxf(Engine.time_scale, 0.05)
	match phase:
		Phase.TURN_START:
			if phase_time > 1.0:
				_begin_aiming()
		Phase.AIMING:
			if not Net.is_client() and not _aim_still_possible():
				return
			if timer_on:
				time_left -= real_dt
				if time_left <= 0.0:
					_timeout()
			if cpu_active:
				CpuAI.update(dt)
			elif sel != null and cam != null and cam.mode != CameraRig.Mode.OVERVIEW and action_mode() != "wall":
				cam.aim_at(sel.global_pos(), aim_yaw, deg_to_rad(aim_elev))
			if Net.active and Game.cur() != null and Game.cur().is_human():
				NetGame.tick_aim(dt)
		Phase.FIRING:
			if phase_time > 4.0 and not Projectile.any_alive():
				_set_phase(Phase.AFTERMATH)
		Phase.FLIGHT:
			_update_flight()
		Phase.AFTERMATH:
			_update_aftermath(dt)
		Phase.TURN_END:
			if phase_time > _end_hold:
				_next_turn()

## The selected catapult may be lost while aiming (landslide, fire, falling debris ...). Pick another one, or - if the
## player has none left - end the turn right away, so the elimination / next player / game over logic runs. false = turn ended.
static func _aim_still_possible() -> bool:
	var p: PlayerData = Game.cur()
	if p == null or (sel != null and not sel.destroyed):
		return true
	var list: Array = p.living_catapults()
	if list.is_empty():
		_finish_turn()
		return false
	if not cpu_active and not p.is_remote():
		sel = null
		select_catapult(list[0] as Catapult)
	return true

static func _begin_aiming() -> void:
	var p: PlayerData = Game.cur()
	var list: Array = p.living_catapults()
	if list.is_empty():
		_finish_turn()
		return
	_set_phase(Phase.AIMING)
	cpu_active = p.is_cpu() and not Net.is_client()
	var pick: Catapult = null
	if p.last_catapult >= 0:
		for c in list:
			if (c as Catapult).index == p.last_catapult:
				pick = c as Catapult
	if pick == null:
		pick = list[0] as Catapult
	if cpu_active:
		CpuAI.begin_turn(p)
	else:
		select_catapult(pick)
	# online: a shot that reached us before this machine was ready to aim
	if not NetGame.queued_shot.is_empty():
		var qs: Dictionary = NetGame.queued_shot
		NetGame.queued_shot = {}
		net_fire(qs)
	timer_on = Game.turn_timer > 0 and p.is_human()
	time_left = float(Game.turn_timer)

static func p_ammo_fallback() -> String:
	var p: PlayerData = Game.cur()
	return p.ammo_sel if p != null and p.has_ammo(p.ammo_sel) else "stone"

static func _timeout() -> void:
	timer_on = false
	Events.banner.emit(I18n.t("banner.timeout"), "info")
	if sel == null:
		var l: Array = living_catapults()
		if l.is_empty():
			_finish_turn()
			return
		select_catapult(l[0] as Catapult)
	if is_action_mode():
		aim_ammo = p_ammo_fallback()
	if not has_aimed or aim_power < 0.08:
		# never aimed: random angle at 50% power with a stone
		aim_ammo = "stone"
		var r: Rng = Game.rng_battle
		set_aim(sel.yaw + deg_to_rad(r.range_f(-25.0, 25.0)), Cfg.DEFAULT_ELEVATION + r.range_f(10.0, 25.0), 0.5)
	fire()

static func _update_flight() -> void:
	var pr: Projectile = Projectile.primary
	if pr != null and pr.alive:
		var pos: Vector3 = pr.position()
		var vel: Vector3 = pr.velocity()
		if pr.impact_time >= 0.0 and pr.first_impact_pos != Vector3.INF:
			impact_points.append(pr.first_impact_pos)
			if cpu_active:
				CpuAI.record_result(pr.first_impact_pos)
			if cam != null and not Meteor.active():
				cam.impact_cam(_impact_focus(pr.first_impact_pos), _launch_dir)
			aftermath_time = 0.0
			settle_acc = 0.0
			_set_phase(Phase.AFTERMATH)
			return
		if cam != null and pos != Vector3.INF:
			cam.follow_projectile(pos, vel)
	else:
		# a scatter shot / cow burst: the sack is gone but its pieces are still flying - keep the camera on them
		# (and then on the target) instead of swinging back to the shooter
		var waiting_for_pieces: bool = false
		if shot_ammo == "scatter" and Projectile.any_alive() and phase_time < 10.0:
			# the first piece to land is often a short one: wait ~0.9 s for the rest, then look at where most of them came down
			if Projectile.last_impact_pos != Vector3.INF and _pellet_first_t < 0.0:
				_pellet_first_t = phase_time
			waiting_for_pieces = _pellet_first_t < 0.0 or phase_time - _pellet_first_t < 0.9
		if (Projectile.last_impact_pos == Vector3.INF or waiting_for_pieces) and Projectile.any_alive() and phase_time < 10.0:
			var sub_pos: Vector3 = Projectile.last_pos
			if cam != null and sub_pos != Vector3.INF:
				cam.follow_projectile(sub_pos, Vector3(_launch_dir.x, -0.2, _launch_dir.z).normalized() * 20.0)
			return
		# projectile already gone (water, timeout, detonated same tick)
		_enter_aftermath_from_gone()

## Centre of the village (within 34 m) around a position, or Vector3.INF
static func _village_near(pos: Vector3) -> Vector3:
	for pl in Game.players:
		if Util.dist_xz(pl.village_center, pos) < 34.0:
			return pl.village_center
	return Vector3.INF

## The village around an impact must stay in view: the camera aims a little towards the village centre
static func _impact_focus(pos: Vector3) -> Vector3:
	for pl in Game.players:
		if Util.dist_xz(pl.village_center, pos) < 34.0:
			return pos.lerp(pl.village_center, 0.3)
	return pos

static func _enter_aftermath_from_gone() -> void:
	var pr_last: Vector3 = Vector3.INF
	# the projectile may have detonated in the same tick (keg, cheese, hive, water): use its recorded impact
	if impact_points.is_empty() and Projectile.last_impact_pos != Vector3.INF:
		impact_points.append(Projectile.last_impact_pos)
	if not impact_points.is_empty():
		pr_last = impact_points[impact_points.size() - 1]
	if pr_last == Vector3.INF and Projectile.last_pos != Vector3.INF:
		pr_last = Projectile.last_pos
	if pr_last == Vector3.INF and sel != null:
		pr_last = sel.global_pos() + _launch_dir * 40.0
	if shot_ammo == "scatter" and not Projectile.pellet_impacts.is_empty():
		# the camera shows the village that the pieces hit: the one nearest to where most of them landed
		var cen := Vector3.ZERO
		for ip in Projectile.pellet_impacts:
			cen += ip
		cen /= float(Projectile.pellet_impacts.size())
		var focus: Vector3 = cen
		var bd: float = 70.0
		for pl in Game.players:
			var d: float = Util.dist_xz(pl.village_center, cen)
			if d < bd:
				bd = d
				focus = cen.lerp(pl.village_center, 0.45)
		for ip2 in Projectile.pellet_impacts:
			impact_points.append(ip2)
		if cam != null and not Meteor.active():
			cam.impact_cam(focus, _launch_dir)
	elif pr_last != Vector3.INF and cam != null and not Meteor.active():
		cam.impact_cam(_impact_focus(pr_last), _launch_dir)
	aftermath_time = 0.0
	settle_acc = 0.0
	_set_phase(Phase.AFTERMATH)

static func register_impact(pos: Vector3) -> void:
	impact_points.append(pos)

static func _is_relevant(pos: Vector3) -> bool:
	for ip in impact_points:
		if pos.distance_to(ip) < 40.0:
			return true
	return false

## Click / Space after the first impact: don't wait for the world, go on with the next player
static func skip_aftermath() -> bool:
	if phase != Phase.AFTERMATH or Meteor.active():
		return false
	_finish_turn()
	return true

static func _update_aftermath(dt: float) -> void:
	aftermath_time += dt
	# a really good hit is shown in bullet time (once per turn)
	if shot_ammo == "meteor" or Meteor.active():
		Meteor.camera(cam, dt)
	# (bullet time is only played for a direct hit on a catapult, see Projectile; nothing else slows the game down)
	# a rolling fire barrel is followed by the impact camera while it burns its way through the village
	if (shot_ammo == "firebarrel" or shot_ammo == "boulder" or shot_ammo == "powdertrail") and Projectile.primary != null and Projectile.primary.alive and cam != null:
		var bp: Vector3 = Projectile.primary.position()
		if bp != Vector3.INF:
			# follow the rolling thing but keep the village that is being hit in the picture
			var vc: Vector3 = _village_near(impact_points[0] if not impact_points.is_empty() else bp)
			if vc == Vector3.INF:
				cam.impact_cam(bp)
			else:
				cam.impact_cam(bp.lerp(vc, 0.5))
				cam.dist = clampf(maxf(34.0, Util.dist_xz(bp, vc) * 1.05 + 30.0), 34.0, 120.0)
	if not _lightning_done and Game.weather == "thunder" and aftermath_time > 2.0 and Game.rng_battle.chance(0.4):
		_lightning_done = true
		Weather.lightning_strike()
	if aftermath_time >= (Cfg.SETTLE_MAX * 2.0 if shot_ammo == "drillbomb" else Cfg.SETTLE_MAX) and not Meteor.active():
		_finish_turn()
		return
	if Meteor.active():
		return
	if aftermath_time < 0.5:
		return
	# nothing relevant happened (a plain miss): move on right after the impact
	if not shot_relevant() and aftermath_time >= 0.9 and not Projectile.any_alive():
		_finish_turn()
		return
	# something happened: let the camera stay on the impact and let the destruction play out
	if aftermath_time < min_dwell():
		return
	_settle_check -= dt
	if _settle_check > 0.0:
		return
	_settle_check = 0.1
	if Projectile.any_alive() or Explosion.is_active() or Landslide.active() or Powder.active() or DrillBomb.active():
		settle_acc = 0.0
		return
	# fastest awake relevant body
	var fastest: float = 0.0
	var f: int = Engine.get_physics_frames()
	for id in PhysWorld.bodies:
		var pb: PhysWorld.PBody = PhysWorld.bodies[id] as PhysWorld.PBody
		if pb.mass <= 0.0 or f - pb.last_active > 3:
			continue
		if pb.kind == "catapult" or (impact_points.is_empty() or _is_relevant(pb.xform.origin)):
			var sp: float = PhysWorld.get_velocity(pb.id).length()
			if sp > fastest:
				fastest = sp
	if fastest < Cfg.SETTLE_SPEED:
		settle_acc += 0.1
	else:
		settle_acc = 0.0
	if settle_acc >= Cfg.SETTLE_TIME:
		_finish_turn()

## Did this shot do anything worth watching (damage, blast, fire, kills, bees, stink)?
static func shot_relevant() -> bool:
	return Scoring.shot_any or Meteor.active() or shot_ammo == "meteor" or shot_ammo == "firebarrel" or shot_ammo == "boulder" or shot_ammo == "powdertrail" or shot_ammo == "drillbomb" or DrillBomb.active() or Landslide.active() or Powder.active() or not Stink.clouds.is_empty()

static func min_dwell() -> float:
	if shot_ammo == "drillbomb":
		return 4.0
	if shot_ammo == "meteor":
		return 6.0
	return 2.8 if Scoring.current_shot_score() > 250.0 else 2.0

static func _finish_turn(net: Dictionary = {}) -> void:
	if Net.is_client() and net.is_empty():
		return          # online: the host decides when a turn is over (net_turn_end)
	# announce the shot result
	var p: PlayerData = Game.cur()
	if p != null and shots_this_turn > 0:
		last_shot_score = Scoring.current_shot_score()
		Events.shot_scored.emit(p.id, last_shot_score)
		var r: Rng = Game.rng_battle
		if not _hit_reported:
			_hit_reported = true
			if Scoring.shot_hit:
				if Scoring.shot_settlers_launched >= 3 or Scoring.shot_buildings >= 1 or Scoring.shot_catapults >= 1:
					Events.banner.emit(I18n.pick("banner.big_hit", r), "hit")
			else:
				Events.banner.emit(I18n.pick("banner.miss", r), "miss")
	if sel != null:
		sel.set_selected(false)
	_end_hold = 1.5 if (shots_this_turn > 0 and shot_relevant()) else 0.35
	_set_phase(Phase.TURN_END)
	_end_of_turn_checks(net)

## Online client: the host says the turn is over: apply its snapshot and the eliminations it found
static func net_turn_end(d: Dictionary) -> void:
	if Game.state != Game.State.BATTLE:
		return
	NetGame.apply_snapshot(d["snap"] as Dictionary)
	_finish_turn(d)

## Online host: a seat left in the middle of the battle
static func host_player_dropped(seat: int) -> void:
	if Game.living_teams().size() <= 1:
		_end_of_turn_checks({})
		return
	if Game.current_player == seat and (phase == Phase.TURN_START or phase == Phase.AIMING):
		_finish_turn()

static func net_game_over(winner: int) -> void:
	if Game.state == Game.State.BATTLE:
		_game_over(winner)

static func _end_of_turn_checks(net: Dictionary = {}) -> void:
	# eliminations are checked here only (spec 2.5)
	var newly: Array[PlayerData] = []
	if net.is_empty():
		for pl in Game.players:
			if not pl.eliminated and pl.catapults_left() == 0:
				newly.append(pl)
	else:
		for id in (net["newly"] as Array):
			var np: PlayerData = Game.player(int(id))
			if np != null and not np.eliminated:
				newly.append(np)
	if Net.is_host:
		var ids: Array = []
		for np2 in newly:
			ids.append(np2.id)
		NetGame.send_turn_end(ids)
	for pl2 in newly:
		Scoring.on_elimination(pl2.id)
		if not Net.is_client():
			Unlocks.on_player_eliminated(pl2.id)
		Events.player_eliminated.emit(pl2.id)
		Events.banner.emit(I18n.pick("banner.eliminated", Game.rng_battle, {"name": pl2.name}), "elim")
		Sfx.play("defeat", Vector3.INF, 0.9, 5)
	Scoring.on_turn_survived()
	Events.turn_end.emit(Game.current_player)
	var alive: Array[PlayerData] = Game.living_players()
	if Net.is_client():
		return          # the host announces the end of the game ("over")
	if Game.living_teams().size() <= 1:
		var winner: int = -1
		if not alive.is_empty():
			winner = alive[0].id          # everybody who is left is on the winning team
		elif not newly.is_empty():
			# everybody eliminated at once: most remaining building HP wins, ties lose
			var best: float = -1.0
			var tie: bool = false
			for pl3 in newly:
				var hp: float = Breakable.village_hp(pl3.id)
				if hp > best + 0.5:
					best = hp
					winner = pl3.id
					tie = false
				elif absf(hp - best) <= 0.5:
					tie = true
			if tie:
				winner = -1
		_game_over(winner)
		return
	SupplyCrate.turn_end_check()
	RandomEvents.turn_end_check()

static func _game_over(winner: int) -> void:
	if winner >= 0:
		for tm in Game.team_members(Game.player(winner).team):
			Scoring.award(tm.id, 1000, "winner")
	if Net.is_host:
		NetGame.send_over(winner)
	_set_phase(Phase.GAME_OVER)
	Game.last_winner = winner
	Game.set_state(Game.State.GAME_OVER)
	if winner >= 0:
		var crew: Array[PlayerData] = Game.team_members(Game.player(winner).team)
		if crew.size() > 1:
			var names: Array[String] = []
			for tm2 in crew:
				names.append(tm2.name)
			Events.banner.emit(I18n.t("banner.team_win", {"names": " + ".join(names)}), "win")
		else:
			Events.banner.emit(I18n.t("banner.win", {"name": Game.player(winner).name}), "win")
		Sfx.play("victory", Vector3.INF, 1.0, 5)
	else:
		Events.banner.emit(I18n.t("banner.everybody_loses"), "win")
		Sfx.play("defeat", Vector3.INF, 1.0, 5)
	Events.game_over.emit(winner)
