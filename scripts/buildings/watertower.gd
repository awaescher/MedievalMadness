class_name BWaterTower
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Aqua Tower (spec 9): 4 wooden stilts 5 m tall + a big round wooden tank on top, full of water.

const DEF := {"id": "watertower", "footprint_radius": 3.0, "prop_hints": ["barrel_water", "bucket"], "name_key": "building.watertower"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 3.0
	var h: float = 5.0
	var s: float = 1.5
	# stilts (anchored) + cross braces
	for sx in [-s, s]:
		for sz in [-s, s]:
			Kit.post(r, "wood", Vector3(sx as float, 0.0, sz as float), h, 0.36, rng, "stilt", true)
	for y in [1.8, 3.6]:
		for sx2 in [-s, s]:
			Kit.box(r, "wood", Vector3(0.16, 0.16, 2.0 * s), Vector3(sx2 as float, y as float, 0.0), rng, Kit.NO_COLOR, false, "brace")
		for sz2 in [-s, s]:
			Kit.box(r, "wood", Vector3(2.0 * s, 0.16, 0.16), Vector3(0.0, y as float, sz2 as float), rng, Kit.NO_COLOR, false, "brace")
	# platform
	var cyl_base := Kit.cyl(r, "plank", 2.0, 0.2, Vector3(0, h + 0.1, 0), rng, Color("#a0622d"), false, "platform")
	cyl_base.mass_override = 200.0
	# tank: ring of planks (2 rows x 10) + lid, full of water
	Kit.ring(r, "plank", Vector2.ZERO, 1.85, h + 0.2, 2.5, 0.24, 10, 1.25, rng, false, [], Color("#b5763a"), "tank")
	var lid := Kit.cyl(r, "plank", 1.95, 0.16, Vector3(0, h + 2.78, 0), rng, Color("#8a5a2a"), false, "tank")
	lid.mass_override = 150.0
	Kit.cyl(r, "metal", 1.98, 0.09, Vector3(0, h + 1.2, 0), rng, Color("#5c6672"), false, "hoop")
	r.height = h + 3.0
	return r
