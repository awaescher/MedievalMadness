class_name Quality
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Quality tiers (spec 15.1). Applies live; caps are read by pools / spawners.

class Tier extends RefCounted:
	var id: String
	var scale: float
	var msaa: int
	var shadows: bool
	var atlas: int
	var particles: int
	var bodies: int
	var settlers: int
	var fire_emitters: int
	var lights: int
	var outlines: bool
	var soft: bool = false
	var shadow_dist: float = 90.0

static var tiers: Dictionary = {}
static var current: Tier
static var current_id: String = "medium"

# convenient static mirrors
static var particle_cap: int = 1500
static var body_cap: int = 600
static var settlers_per_village: int = 10
static var fire_emitters: int = 40
static var max_lights: int = 4

static func _mk(id: String, scale: float, msaa: int, shadows: bool, atlas: int, particles: int, bodies: int, settlers: int, fires: int, lights: int, outlines: bool, soft: bool, sdist: float) -> void:
	var t := Tier.new()
	t.id = id
	t.scale = scale
	t.msaa = msaa
	t.shadows = shadows
	t.atlas = atlas
	t.particles = particles
	t.bodies = bodies
	t.settlers = settlers
	t.fire_emitters = fires
	t.lights = lights
	t.outlines = outlines
	t.soft = soft
	t.shadow_dist = sdist
	tiers[id] = t

static func _ensure() -> void:
	if not tiers.is_empty():
		return
	_mk("low", 0.75, 0, false, 1024, 600, 350, 6, 20, 2, false, false, 60.0)
	_mk("medium", 1.0, 2, true, 2048, 1500, 600, 10, 40, 4, true, false, 90.0)
	_mk("high", 1.0, 4, true, 2048, 3000, 900, 14, 60, 6, true, false, 110.0)
	_mk("ultra", 1.0, 4, true, 4096, 6000, 1400, 16, 80, 8, true, true, 130.0)
	current = tiers["medium"] as Tier

static func get_tier(id: String) -> Tier:
	_ensure()
	return (tiers[id] if tiers.has(id) else tiers["medium"]) as Tier

static func lower(id: String) -> String:
	var order: Array[String] = ["low", "medium", "high", "ultra"]
	var i: int = order.find(id)
	return order[maxi(i - 1, 0)]

## Apply a tier to the viewport and the sky rig.
static func apply(id: String, viewport: Viewport, sky: SkyRig) -> void:
	_ensure()
	var t: Tier = get_tier(id)
	current = t
	current_id = t.id
	if viewport != null:
		viewport.scaling_3d_scale = t.scale
		match t.msaa:
			0:
				viewport.msaa_3d = Viewport.MSAA_DISABLED
			2:
				viewport.msaa_3d = Viewport.MSAA_2X
			_:
				viewport.msaa_3d = Viewport.MSAA_4X
	if sky != null:
		sky.apply_quality(t.shadows, t.atlas, t.soft)
		sky.sun.directional_shadow_max_distance = t.shadow_dist
		sky.apply_lighting("basic" if t.id == "low" else Settings.lighting)
	Toon.set_outlines(t.outlines)
	particle_cap = t.particles
	body_cap = mini(t.bodies, Cfg.MAX_DYNAMIC_BODIES if t.id != "ultra" else t.bodies)
	settlers_per_village = t.settlers
	fire_emitters = t.fire_emitters
	max_lights = t.lights
