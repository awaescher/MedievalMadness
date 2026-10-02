class_name Debris
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Debris cap + cleanup (spec 5.5). Tracks shards and released building parts.
## When over the cap the oldest sleeping items fade out first. Sleeping shards expire after DEBRIS_LIFETIME.

class Item extends RefCounted:
	var body_id: int = 0
	var part: Part = null           # released building part (null for pure shards)
	var born: float = 0.0
	var asleep_since: float = -1.0
	var fading: float = -1.0        # fade progress start time, < 0 = not fading
	var visual: Node3D = null
	var base_scale: Vector3 = Vector3.ONE
	var persistent: bool = false     # stays for the whole match (a pointy log that did not stick)

static var items: Array[Item] = []
static var _time: float = 0.0
static var _check_timer: float = 0.0
static var lifetime_mult: float = 1.0

static func reset() -> void:
	items.clear()
	_time = 0.0

static func register_shard(body_id: int, visual: Node3D, persistent: bool = false) -> void:
	var it := Item.new()
	it.body_id = body_id
	it.born = _time
	it.visual = visual
	it.persistent = persistent
	items.append(it)

static func register_part(p: Part) -> void:
	var it := Item.new()
	it.body_id = p.body_id
	it.part = p
	it.born = _time
	it.visual = p.mesh
	items.append(it)

static func count() -> int:
	return items.size()

static func _begin_fade(it: Item) -> void:
	if it.fading >= 0.0:
		return
	it.fading = _time
	if it.visual != null and is_instance_valid(it.visual):
		it.base_scale = it.visual.scale

static func _remove(it: Item) -> void:
	if it.part != null:
		Breakable.discard_part(it.part)
	elif PhysWorld.bodies.has(it.body_id):
		PhysWorld.remove_body(it.body_id)

static func tick(dt: float) -> void:
	_time += dt
	# fade animation
	var i: int = items.size() - 1
	while i >= 0:
		var it: Item = items[i]
		if it.part != null and (it.part.state == Part.State.DEAD or it.part.state == Part.State.FROZEN):
			items.remove_at(i)      # broke normally (cleaned up) or was carried back and fixed again by settlers
		elif it.part == null and not PhysWorld.bodies.has(it.body_id):
			items.remove_at(i)
		elif it.fading >= 0.0:
			var t: float = (_time - it.fading) / 0.4
			if it.visual != null and is_instance_valid(it.visual):
				it.visual.scale = it.base_scale * maxf(1.0 - t, 0.001)
			if t >= 1.0:
				_remove(it)
				items.remove_at(i)
		i -= 1
	_check_timer -= dt
	if _check_timer > 0.0:
		return
	_check_timer = 0.25
	var life: float = Cfg.DEBRIS_LIFETIME * lifetime_mult
	var sleepers: Array[Item] = []
	for it2 in items:
		if it2.fading >= 0.0:
			continue
		var sl: bool = PhysWorld.is_sleeping(it2.body_id)
		if sl:
			if it2.asleep_since < 0.0:
				it2.asleep_since = _time
			# pure shards expire; released building parts stay unless over the cap
			if it2.persistent:
				pass
			elif it2.part == null and _time - it2.asleep_since > life:
				_begin_fade(it2)
			else:
				sleepers.append(it2)
		else:
			it2.asleep_since = -1.0
	var over: int = items.size() - Quality.body_cap
	if over > 0:
		# oldest sleeping first
		for it3 in sleepers:
			if over <= 0:
				break
			if it3.fading < 0.0 and not it3.persistent:
				_begin_fade(it3)
				over -= 1
		if over > 0:
			# still too many: oldest non-part shards
			for it4 in items:
				if over <= 0:
					break
				if it4.fading < 0.0 and it4.part == null and not it4.persistent:
					_begin_fade(it4)
					over -= 1
