class_name BBlacksmith
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Ye Olde Smithy (spec 9): stone base, open front with anvil, forge with glowing coal, bellows, weapon rack.

const DEF := {"id": "blacksmith", "footprint_radius": 4.0, "prop_hints": ["barrel_water", "crate", "bucket"], "name_key": "building.blacksmith"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 4.0
	var hx: float = 2.6
	var hz: float = 2.0
	var y0: float = 0.3
	Kit.foundation(r, "stone", Vector2.ZERO, hx, hz, 0.3, 0.5, 1.9, rng)
	# back + side walls stone, open front (+Z)
	Kit.wall(r, "stone", Vector2(hx - 0.2, -hz + 0.2), Vector2(-hx + 0.2, -hz + 0.2), y0, 2.8, 0.34, 1.9, 1.4, rng, [], false, Color("#8a9096"), "wall")
	Kit.wall(r, "stone", Vector2(-hx + 0.2, -hz + 0.4), Vector2(-hx + 0.2, hz - 0.2), y0, 2.8, 0.34, 1.9, 1.4, rng, [], false, Color("#8a9096"), "wall")
	Kit.wall(r, "stone", Vector2(hx - 0.2, hz - 0.2), Vector2(hx - 0.2, -hz + 0.4), y0, 1.4, 0.34, 1.9, 1.4, rng, [], false, Color("#8a9096"), "wall")
	# front posts and roof (plank gable with a chimney)
	for sx in [-hx + 0.2, hx - 0.2]:
		Kit.post(r, "wood", Vector3(sx as float, y0, hz - 0.2), 3.0, 0.26, rng, "post")
	Kit.gable_roof(r, "thatch", Vector2.ZERO, y0 + 3.0, hx + 0.05, hz, 1.2, 0.16, 1.8, rng, 0.35)
	# forge: stone block + glowing coal
	Kit.box(r, "stone", Vector3(1.3, 0.9, 1.0), Vector3(-1.4, y0 + 0.45, -1.3), rng, Color("#6f757a"), false, "forge")
	var coal := Kit.box(r, "stone", Vector3(1.0, 0.16, 0.7), Vector3(-1.4, y0 + 0.98, -1.3), rng, Color("#ff5a1a"), false, "coal")
	coal.glow = true
	coal.mass_override = 30.0
	# chimney above the forge
	for i in 3:
		Kit.box(r, "stone", Vector3(0.7, 1.0, 0.6), Vector3(-1.4, y0 + 1.5 + float(i) * 1.0, -1.7), rng, Color("#7f858a"), false, "chimney")
	# bellows
	Kit.box(r, "wood", Vector3(0.5, 0.35, 0.7), Vector3(-0.35, y0 + 0.6, -1.5), rng, Color("#5a381c"), false, "bellows")
	Kit.frustum(r, "cloth", 0.25, 0.05, 0.6, Vector3(0.05, y0 + 0.62, -1.5), rng, Color("#7a4a25"), false, "bellows")
	# weapon rack on the side wall
	Kit.box(r, "wood", Vector3(0.1, 1.4, 1.6), Vector3(hx - 0.55, y0 + 1.3, -0.7), rng, Color("#5a381c"), false, "rack")
	for i in 2:
		Kit.box(r, "metal", Vector3(0.05, 1.0, 0.1), Vector3(hx - 0.65, y0 + 1.3, -1.1 + float(i) * 0.7), rng, Color("#c9d1d9"), false, "sword")
	# anvil (metal prop) near the front + water trough barrel
	r.extra("prop", Vector3(0.6, 0.0, 0.4), {"prop": "anvil", "lift": y0 - 0.02, "ground": false})
	r.extra("forge_fire", Vector3(-1.4, y0 + 1.1, -1.3), {})
	r.height = y0 + 4.5
	return r
