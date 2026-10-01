class_name Landslide
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Landslides (spec 7.7): a heavy hit on a VERY steep slope loosens the soil and it slides down - as a thermal-erosion
## simulation on the heightfield: material moves to the lowest neighbour wherever the slope is steeper than the angle of
## repose, so the slide stops by itself where the mountain flattens out. The size depends on the strength of the hit
## (stone: small, boulder: bigger, explosion close to the ground: huge). Whatever the moving soil runs into is smashed.

const MIN_SLOPE := 36.0            # degrees: only really steep slopes slide
const REPOSE_TAN := 0.62           # tan(~32 degrees)
const MAX_SLIDES := 3
const STEP_TIME := 0.05

class Slide extends RefCounted:
	var id: int = 0
	var ix0: int = 0
	var iz0: int = 0
	var ix1: int = 0
	var iz1: int = 0
	var iters_left: int = 0
	var strength: float = 1.0
	var source: Dictionary = {}
	var center: Vector3 = Vector3.ZERO
	var acc: float = 0.0
	var calm: int = 0
	var total: float = 0.0          # metres of soil moved (sum over iterations)
	var hit_count: int = 0

static var slides: Array[Slide] = []
static var _next_id: int = 1
static var rng: Rng = Rng.new(91)

static func reset() -> void:
	slides.clear()

static func active() -> bool:
	return not slides.is_empty()

## Steepest slope (degrees) around a point: the impact itself plus a ring of 3 m
static func steepness(pos: Vector3) -> float:
	var m: float = Terrain.slope_deg(pos.x, pos.z)
	for k in 6:
		var a: float = TAU * float(k) / 6.0
		m = maxf(m, Terrain.slope_deg(pos.x + cos(a) * 3.0, pos.z + sin(a) * 3.0))
	return m

## Starts a landslide if the slope is steep enough and the hit strong enough. Returns true if one started.
static func trigger(pos: Vector3, strength: float, source: Dictionary) -> bool:
	if strength < 0.2 or Terrain.current == null or Terrain.current.data == null:
		return false
	if slides.size() >= MAX_SLIDES or Terrain.is_water(pos.x, pos.z):
		return false
	if steepness(pos) < MIN_SLOPE:
		return false
	for s in slides:
		if Util.dist_xz(s.center, pos) < 6.0:
			return false
	var sl := Slide.new()
	sl.id = _next_id
	_next_id += 1
	sl.strength = clampf(strength, 0.2, 8.0)
	sl.center = pos
	var data: MapData = Terrain.current.data
	var radius: float = clampf(4.0 + sl.strength * 3.5, 4.0, 28.0)
	sl.ix0 = clampi(floori((pos.x - radius - data.origin) / data.cell), 1, data.n - 2)
	sl.ix1 = clampi(ceili((pos.x + radius - data.origin) / data.cell), 1, data.n - 2)
	sl.iz0 = clampi(floori((pos.z - radius - data.origin) / data.cell), 1, data.n - 2)
	sl.iz1 = clampi(ceili((pos.z + radius - data.origin) / data.cell), 1, data.n - 2)
	sl.iters_left = int(24.0 + sl.strength * 28.0)
	sl.source = source.duplicate()
	sl.source["slide"] = sl.id
	sl.source["ammo"] = "landslide"
	# the blow loosens the soil right at the impact
	Terrain.current.dig(pos, 1.4 + sl.strength * 0.8, 0.2 + sl.strength * 0.2, 0.0, 0.6)
	slides.append(sl)
	Sfx.play("crunch", pos, 1.0, 4)
	Sfx.play("thunk", pos, 1.0, 4)
	Fx.burst("dust", pos, Color("#8a6d4a"), 1.0, Vector3.UP)
	Events.camera_shake.emit(clampf(0.25 + sl.strength * 0.1, 0.25, 0.9))
	Events.banner.emit(I18n.t("banner.landslide"), "info")
	return true

static func tick(dt: float) -> void:
	if slides.is_empty() or Terrain.current == null:
		return
	var i: int = slides.size() - 1
	while i >= 0:
		var sl: Slide = slides[i]
		sl.acc += dt
		while sl.acc >= STEP_TIME and sl.iters_left > 0:
			sl.acc -= STEP_TIME
			_step(sl)
		if sl.iters_left <= 0 or sl.calm >= 4:
			slides.remove_at(i)
			Terrain.current.mark_dirty(sl.ix0 - 1, sl.iz0 - 1, sl.ix1 + 1, sl.iz1 + 1)
			# whatever now hangs over the changed ground comes down
			var dd: MapData = Terrain.current.data
			Breakable.ground_changed(AABB(Vector3(dd.origin + float(sl.ix0) * dd.cell, -50.0, dd.origin + float(sl.iz0) * dd.cell), Vector3(float(sl.ix1 - sl.ix0) * dd.cell, 200.0, float(sl.iz1 - sl.iz0) * dd.cell)))
		i -= 1

## A few erosion iterations + damage to whatever the moving soil hits
static func _step(sl: Slide) -> void:
	var t: Terrain = Terrain.current
	var data: MapData = t.data
	var n: int = data.n
	var h: PackedFloat32Array = data.heights
	var step_moved: float = 0.0
	var gain := {}                                   # index -> metres deposited in this step
	var dir_sum := Vector2.ZERO
	var water: float = t.water_y
	for rep in 3:
		for iz in range(sl.iz0, sl.iz1 + 1):
			for ix in range(sl.ix0, sl.ix1 + 1):
				var idx: int = iz * n + ix
				var h0: float = h[idx]
				if h0 < water:
					continue
				var best: int = -1
				var best_drop: float = 0.0
				var best_dist: float = 1.0
				for oz in range(-1, 2):
					for ox in range(-1, 2):
						if ox == 0 and oz == 0:
							continue
						var nidx: int = (iz + oz) * n + (ix + ox)
						var dist: float = data.cell * (1.0 if (ox == 0 or oz == 0) else 1.4142)
						var drop: float = (h0 - h[nidx]) - REPOSE_TAN * dist
						if drop > best_drop:
							best_drop = drop
							best = nidx
							best_dist = dist
				if best >= 0:
					var amt: float = minf(best_drop * 0.14, 0.25)
					h[idx] -= amt
					h[best] += amt
					step_moved += amt
					gain[best] = float(gain.get(best, 0.0)) + amt
					var ox2: int = (best % n) - ix
					var oz2: int = (best / n) - iz
					dir_sum += Vector2(float(ox2), float(oz2)) * amt
	sl.iters_left -= 1
	sl.total += step_moved
	if sl.iters_left % 3 == 0:
		Breakable.ground_changed(AABB(Vector3(data.origin + float(sl.ix0) * data.cell, -50.0, data.origin + float(sl.iz0) * data.cell), Vector3(float(sl.ix1 - sl.ix0) * data.cell, 200.0, float(sl.iz1 - sl.iz0) * data.cell)))
	if step_moved < 0.02:
		sl.calm += 1
	else:
		sl.calm = 0
	t.mark_dirty(sl.ix0 - 1, sl.iz0 - 1, sl.ix1 + 1, sl.iz1 + 1)
	if gain.is_empty():
		return
	# where soil piled up, things get buried / pushed downhill
	var dir3 := Vector3(dir_sum.x, 0.0, dir_sum.y).normalized()
	var keys: Array = gain.keys()
	var samples: int = mini(keys.size(), 5)
	for k in samples:
		var idx2: int = int(keys[rng.range_i(0, keys.size() - 1)])
		var dep: float = float(gain[idx2])
		if dep < 0.03:
			continue
		var x: float = data.origin + float(idx2 % n) * data.cell
		var z: float = data.origin + float(idx2 / n) * data.cell
		var p := Vector3(x, h[idx2], z)
		var energy: float = 26000.0 * clampf(dep * 6.0, 0.3, 3.0) * clampf(0.5 + sl.strength * 0.2, 0.5, 2.0)
		var broken: int = Damage.impact_at(p + Vector3.UP * 0.6, 2.4, energy, dir3, sl.source)
		sl.hit_count += broken
		Damage.damage_settlers_in_radius(p, 2.8, 40.0 + 10.0 * sl.strength, sl.source, dir3, 1.0)
		if rng.chance(0.5):
			Fx.burst("dust", p, Color("#8a6d4a"), 0.7, Vector3.UP)
	if rng.chance(0.25):
		Sfx.play("crunch", sl.center, 0.5, 1)
