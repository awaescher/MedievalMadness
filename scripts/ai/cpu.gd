class_name CpuAI
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## CPU bots (spec 14): four difficulties with the same aiming inputs as a human (azimuth, elevation,
## power, ammo) and the same +-0.5 degree launch spread. Solving is time-sliced over frames.

const AI := {
	"peasant": {"aim_noise_deg": 14.0, "power_noise": 0.25, "use_wind": false, "learns": false, "ammo_smart": "none", "target_smart": "random", "think_time": [0.8, 1.6], "sim_samples": 1},
	"squire": {"aim_noise_deg": 7.0, "power_noise": 0.14, "use_wind": false, "learns": false, "ammo_smart": "none", "target_smart": "nearest", "think_time": [1.0, 2.0], "sim_samples": 6},
	"knight": {"aim_noise_deg": 3.0, "power_noise": 0.07, "use_wind": true, "learns": true, "ammo_smart": "basic", "target_smart": "weakest", "think_time": [1.2, 2.4], "sim_samples": 20},
	"king": {"aim_noise_deg": 0.8, "power_noise": 0.02, "use_wind": true, "learns": true, "ammo_smart": "full", "target_smart": "threat", "think_time": [1.5, 2.8], "sim_samples": 60},
}

enum Stage { THINK, SOLVE, PULL, DONE }

static var rng: Rng = Rng.new(101)
static var stage: int = Stage.DONE
static var stage_time: float = 0.0
static var think_total: float = 1.5
static var params: Dictionary = {}
static var bot: PlayerData
static var shooter: Catapult
static var target_player: PlayerData = null
static var target_point: Vector3 = Vector3.ZERO
static var target_key: String = ""
static var aim_point: Vector3 = Vector3.ZERO
static var ammo_id: String = "stone"
static var best: Dictionary = {}
static var samples_left: int = 0
static var elev_pick: Array[float] = []
static var final_yaw: float = 0.0
static var final_elev: float = 30.0
static var final_power: float = 0.5
static var memory: Dictionary = {}          # bot id -> {key, err: Vector2}
static var _last_bot: int = -1
static var _last_target_pl: Dictionary = {}    # bot id -> last target player id
static var _silly: bool = false
static var _bubble_shown: bool = false

# ------------------------------------------------------------------ ballistic solver (pure functions, test-friendly)
## The solver itself lives in the pure `Ballistics` class (headless-testable); thin wrappers for readability.
static func solve_power(origin: Vector3, yaw: float, elev: float, dist: float, ammo: String, wind: Vector2) -> float:
	return Ballistics.solve_power(origin, yaw, elev, dist, ammo, wind)

## Full solve for one elevation sample: returns {yaw, elev, power, err} (err = horizontal miss distance)
static func solve_sample(origin_fn: Callable, shooter_pos: Vector3, target: Vector3, ammo: String, wind: Vector2, elev: float, yaw_jitter: float) -> Dictionary:
	return Ballistics.solve_sample(origin_fn, shooter_pos, target, ammo, wind, elev, yaw_jitter)

# ------------------------------------------------------------------ turn control
static func begin_turn(p: PlayerData) -> void:
	bot = p
	params = AI[p.type] as Dictionary
	stage = Stage.THINK
	stage_time = 0.0
	var tt: Array = params["think_time"] as Array
	think_total = rng.range_f(float(tt[0]), float(tt[1]))
	best = {}
	_silly = rng.chance(0.05)
	_bubble_shown = false
	_plan_targets()
	if shooter != null:
		Turn.select_catapult(shooter)
		Turn.aim_ammo = ammo_id
		shooter.set_ammo_visual(ammo_id)
	samples_left = int(params["sim_samples"])
	elev_pick.clear()
	# taunt
	if rng.chance(0.25) and shooter != null:
		Speech.say_random("speech.taunt", shooter, shooter, rng, 4.0)
	# thinking bubble
	if shooter != null:
		Speech.say(I18n.t("hud.thinking") if rng.chance(0.5) else I18n.t("hud.thinking2"), shooter, shooter, think_total, 4.6)

static func _living_enemies() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in Game.players:
		if p.id != bot.id and not p.eliminated and p.catapults_left() > 0:
			out.append(p)
	return out

static func _enemy_dist(p: PlayerData) -> float:
	return Util.dist_xz(p.village_center, bot.village_center)

static func _total_hp(p: PlayerData) -> float:
	return Breakable.village_hp(p.id)

static func _pick_target_player() -> PlayerData:
	var enemies: Array[PlayerData] = _living_enemies()
	if enemies.is_empty():
		return null
	var mode: String = str(params["target_smart"])
	match mode:
		"random":
			return enemies[rng.range_i(0, enemies.size() - 1)]
		"nearest":
			var bd: float = 1e9
			var pick: PlayerData = enemies[0]
			for e in enemies:
				var d: float = _enemy_dist(e)
				if d < bd:
					bd = d
					pick = e
			return pick
		"weakest":
			var w: PlayerData = enemies[0]
			for e2 in enemies:
				if e2.catapults_left() < w.catapults_left() or (e2.catapults_left() == w.catapults_left() and _total_hp(e2) < _total_hp(w)):
					w = e2
			return w
		_:
			# threat: 3 x catapults + 8 if their last shot hurt me + 1 for the leader - 0.02 x distance
			var leader: PlayerData = enemies[0]
			for e3 in enemies:
				if e3.catapults_left() > leader.catapults_left():
					leader = e3
			var bs: float = -1e9
			var bp: PlayerData = enemies[0]
			for e4 in enemies:
				var sc: float = 3.0 * float(e4.catapults_left())
				if bot.last_damaged_by == e4.id:
					sc += 8.0
				if e4 == leader:
					sc += 1.0
				sc -= 0.02 * _enemy_dist(e4)
				if sc > bs:
					bs = sc
					bp = e4
			return bp

## number of live parts near the straight line a -> b (cover along the flight path)
static func cover_along(a: Vector3, b: Vector3, radius: float = 1.6) -> int:
	var n: int = 0
	var seg_len: float = a.distance_to(b)
	if seg_len < 1.0:
		return 0
	var dir: Vector3 = (b - a) / seg_len
	for s in Breakable.structures:
		if s.kind == "tree" or s.free_parts or s.destroyed:
			continue
		var bb: AABB = s.aabb.grow(radius)
		if not bb.intersects_segment(a, b):
			continue
		for p in s.parts:
			if p.state == Part.State.DEAD:
				continue
			var t: float = clampf((p.xf.origin - a).dot(dir), 0.0, seg_len)
			var q: Vector3 = a + dir * t
			# ignore the target's own immediate surroundings
			if t > seg_len - 3.0:
				continue
			if (p.xf.origin - q).length() < radius + p.radius() * 0.3 and p.xf.origin.y > q.y - 1.0 and p.xf.origin.y < q.y + 8.0:
				n += 1
	return n

static func cover_near(pos: Vector3, radius: float = 4.0) -> int:
	var n: int = 0
	for s in Breakable.structures:
		if s.kind == "tree" or s.free_parts or s.destroyed:
			continue
		if not s.aabb.grow(radius).has_point(pos):
			continue
		for p in s.parts:
			if p.state != Part.State.DEAD and (p.xf.origin - pos).length() < radius:
				n += 1
	return n

static func _structures_of(owner: int, kind: String) -> Array[Structure]:
	var out: Array[Structure] = []
	for s in Breakable.structures:
		if s.owner_id == owner and s.kind == kind and not s.destroyed and s.live_count > 0:
			out.append(s)
	return out

static func _plan_targets() -> void:
	target_player = _pick_target_player()
	var living: Array = bot.living_catapults()
	if target_player == null or living.is_empty():
		shooter = living[0] as Catapult if not living.is_empty() else null
		target_point = bot.village_center + Vector3(20, 0, 0)
		ammo_id = "stone"
		return
	var mode: String = str(params["ammo_smart"])
	# --- target point
	var enemy_cats: Array = target_player.living_catapults()
	var chosen_cat: Catapult = null
	var t_point: Vector3 = Vector3.ZERO
	var t_key: String = "cat"
	var ref_pos: Vector3 = (living[0] as Catapult).global_pos()
	if bot.type == "peasant" and rng.chance(0.3):
		# any random building of the enemy
		var bs: Array[Structure] = []
		for s in Breakable.structures:
			if s.owner_id == target_player.id and not s.free_parts and s.kind != "tree" and not s.destroyed:
				bs.append(s)
		if not bs.is_empty():
			var st: Structure = bs[rng.range_i(0, bs.size() - 1)]
			t_point = st.center
			t_key = "b" + str(st.id)
	if t_point == Vector3.ZERO and not enemy_cats.is_empty():
		if bot.type == "king" or bot.type == "knight":
			# least cover
			var bestc: Catapult = enemy_cats[0] as Catapult
			var bcover: int = 1 << 30
			for c in enemy_cats:
				var cc: Catapult = c as Catapult
				var cv: int = cover_near(cc.global_pos()) if bot.type == "knight" else cover_along(ref_pos + Vector3(0, 2, 0), cc.global_pos() + Vector3(0, 1, 0))
				if cv < bcover:
					bcover = cv
					bestc = cc
			chosen_cat = bestc
		else:
			chosen_cat = enemy_cats[rng.range_i(0, enemy_cats.size() - 1)] as Catapult
		t_point = chosen_cat.global_pos()
		t_key = "c" + str(target_player.id) + "_" + str(chosen_cat.index)
	if t_point == Vector3.ZERO:
		# no catapult reachable: any building of the strongest enemy
		var strongest: PlayerData = target_player
		var bs2: Array[Structure] = []
		for s2 in Breakable.structures:
			if s2.owner_id == strongest.id and not s2.free_parts and s2.kind != "tree" and not s2.destroyed:
				bs2.append(s2)
		if not bs2.is_empty():
			var st2: Structure = bs2[rng.range_i(0, bs2.size() - 1)]
			t_point = st2.center
			t_key = "b" + str(st2.id)
		else:
			t_point = target_player.village_center
			t_key = "v" + str(target_player.id)
	# --- fire targets for the King: powder store near a catapult, barn / haystacks near a catapult
	var fire_target: bool = false
	if mode == "full":
		for ps in _structures_of(target_player.id, "powderstore"):
			for c2 in enemy_cats:
				if (c2 as Catapult).global_pos().distance_to(ps.center) < 4.0:
					t_point = ps.center
					t_key = "ps" + str(ps.id)
					fire_target = true
		if not fire_target:
			for br in _structures_of(target_player.id, "barn"):
				for c3 in enemy_cats:
					if (c3 as Catapult).global_pos().distance_to(br.center) < 8.0:
						t_point = br.center
						t_key = "br" + str(br.id)
						fire_target = true
	target_point = t_point
	target_key = t_key
	# --- learning: correct by the observed error when the target is unchanged
	aim_point = target_point
	if bool(params["learns"]) and memory.has(bot.id):
		var m: Dictionary = memory[bot.id] as Dictionary
		if str(m["key"]) == target_key:
			var k: float = 1.0 if bot.type == "king" else 0.8
			var err: Vector2 = m["err"] as Vector2
			aim_point = target_point - Vector3(err.x, 0.0, err.y) * k
	# --- pick the catapult to fire from
	shooter = _pick_shooter(living)
	# --- choose ammo
	ammo_id = _choose_ammo(mode, fire_target, chosen_cat)

static func _pick_shooter(living: Array) -> Catapult:
	if bot.type == "peasant" or bot.type == "squire" or living.size() == 1:
		return living[rng.range_i(0, living.size() - 1)] as Catapult
	var best_c: Catapult = living[0] as Catapult
	var best_score: float = -1e9
	for c in living:
		var cat: Catapult = c as Catapult
		var sc: float = -float(cover_along(cat.global_pos() + Vector3(0, 2, 0), target_point + Vector3(0, 1, 0))) * 1.0
		# stay away from burning parts
		if Fire.fires_near(cat.global_pos(), 15.0):
			sc -= 12.0
		sc += rng.range_f(0.0, 1.5)
		if sc > best_score:
			best_score = sc
			best_c = cat
	return best_c

static func _choose_ammo(mode: String, fire_target: bool, target_cat: Catapult) -> String:
	if mode == "none":
		return "stone"
	if mode == "basic":
		if bot.has_ammo("firebarrel") and rng.chance(0.4):
			return "firebarrel"
		if target_cat != null and rng.chance(0.25):
			var walls: int = cover_along(shooter.global_pos() + Vector3(0, 2, 0), target_cat.global_pos() + Vector3(0, 1, 0))
			var settlers_near: int = 0
			for st in Settler.all:
				if st.owner_id == target_player.id and st.state != Settler.State.DEAD and Util.dist_xz(st.global_pos(), target_cat.global_pos()) < 8.0:
					settlers_near += 1
			var options: Array[String] = []
			if walls > 0:
				for a in ["powderkeg", "boulder", "scatter"]:
					if bot.has_ammo(a):
						options.append(a)
			if settlers_near >= 5:
				for a2 in ["scatter", "cow", "beehive"]:
					if bot.has_ammo(a2):
						options.append(a2)
			if not options.is_empty():
				return options[rng.range_i(0, options.size() - 1)]
		return "stone"
	# full
	if target_player != null and target_player.catapults_left() <= 2 and bot.has_ammo("redkeg"):
		return "redkeg"
	if target_cat != null:
		var walls_n: int = cover_along(shooter.global_pos() + Vector3(0, 2, 0), target_cat.global_pos() + Vector3(0, 1, 0))
		if walls_n >= 3 and bot.has_ammo("powderkeg"):
			return "powderkeg"
	# a boulder ploughs through walls and towers: use it whenever something solid stands in the way
	if target_cat != null and bot.has_ammo("boulder"):
		if cover_along(shooter.global_pos() + Vector3(0, 2, 0), target_cat.global_pos() + Vector3(0, 1, 0)) >= 1 or fire_target:
			return "boulder"
	if target_cat != null and bot.has_ammo("scatter"):
		var cluster: int = 0
		for c in target_player.living_catapults():
			if (c as Catapult).global_pos().distance_to(target_cat.global_pos()) < 8.0:
				cluster += 1
		if cluster >= 3:
			return "scatter"
	if bot.has_ammo("powdertrail") and rng.chance(0.4):
		return "powdertrail"
	if bot.has_ammo("beehive") and rng.chance(0.3):
		return "beehive"
	if bot.has_ammo("cow") and rng.chance(0.3):
		return "cow"
	if bot.has_ammo("firebarrel") and rng.chance(0.4):
		return "firebarrel"
	return "stone"

# ------------------------------------------------------------------ per-frame
static func _origin_fn(elev: float, yaw: float) -> Vector3:
	return Turn.launch_origin(shooter, elev, yaw)

static func update(dt: float) -> void:
	if bot == null or shooter == null or shooter.destroyed or Turn.phase != Turn.Phase.AIMING:
		return
	stage_time += dt
	var wind: Vector2 = Game.wind if bool(params["use_wind"]) else Vector2.ZERO
	match stage:
		Stage.THINK:
			# solve a few samples per frame while "thinking"
			_solve_slice(wind, 3)
			if stage_time >= think_total and samples_left <= 0:
				_finalize()
				stage = Stage.PULL
				stage_time = 0.0
				Sfx.play("creak", shooter.global_pos(), 0.6, 1)
		Stage.PULL:
			var t: float = clampf(stage_time / 0.9, 0.0, 1.0)
			var e: float = Util.ease_in_out(t)
			Turn.aim_yaw = final_yaw
			Turn.set_aim(final_yaw, final_elev, final_power * e)
			if t >= 1.0:
				stage = Stage.DONE
				Events.banner.emit(I18n.t("banner.cpu_fire", {"name": bot.name, "ammo": I18n.t("ammo." + ammo_id)}), "cpu")
				Turn.fire()

static func _solve_slice(wind: Vector2, n: int) -> void:
	var count: int = 0
	var sample_count: int = int(params["sim_samples"])
	while samples_left > 0 and count < n:
		samples_left -= 1
		count += 1
		var elev: float
		var jitter: float
		if sample_count == 1:
			elev = rng.range_f(28.0, 60.0)
			jitter = 0.0
		else:
			elev = rng.range_f(20.0, 70.0)
			jitter = deg_to_rad(rng.range_f(-3.0, 3.0))
		var r: Dictionary = solve_sample(Callable(CpuAI, "_origin_fn"), shooter.global_pos(), aim_point, ammo_id, wind, elev, jitter)
		if best.is_empty() or float(r["err"]) < float(best["err"]):
			best = r

static func _finalize() -> void:
	if best.is_empty():
		var wind: Vector2 = Game.wind if bool(params["use_wind"]) else Vector2.ZERO
		best = solve_sample(Callable(CpuAI, "_origin_fn"), shooter.global_pos(), aim_point, ammo_id, wind, 45.0, 0.0)
	var yaw: float = float(best["yaw"])
	var elev: float = float(best["elev"])
	var power: float = float(best["power"])
	# out of range: fall back to the nearest building of the strongest enemy in range, else full power at the target
	if float(best["err"]) > 15.0 and target_player != null:
		var wind2: Vector2 = Game.wind if bool(params["use_wind"]) else Vector2.ZERO
		var alt_best: Dictionary = best
		for s in Breakable.structures:
			if s.owner_id != target_player.id or s.free_parts or s.kind == "tree" or s.destroyed:
				continue
			var r: Dictionary = solve_sample(Callable(CpuAI, "_origin_fn"), shooter.global_pos(), s.center, ammo_id, wind2, 45.0, 0.0)
			if float(r["err"]) < float(alt_best["err"]):
				alt_best = r
				if float(r["err"]) < 6.0:
					break
		yaw = float(alt_best["yaw"])
		elev = float(alt_best["elev"])
		power = float(alt_best["power"])
	# human-like inaccuracy
	yaw += deg_to_rad(rng.gauss() * float(params["aim_noise_deg"]))
	power = clampf(power + rng.gauss() * float(params["power_noise"]) * power, 0.1, 1.0)
	if _silly:
		power = rng.range_f(0.2, 1.0)
	final_yaw = yaw
	final_elev = clampf(elev, Cfg.MIN_ELEVATION, Cfg.MAX_ELEVATION)
	final_power = power

## Called by the turn manager once the shot has landed to feed the learning bots
static func record_result(landing: Vector3) -> void:
	if bot == null:
		return
	if bool(params.get("learns", false)):
		# systematic bias = where the shot landed relative to where it was aimed
		var err := Vector2(landing.x - aim_point.x, landing.z - aim_point.z)
		memory[bot.id] = {"key": target_key, "err": err}
