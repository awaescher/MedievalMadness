class_name BStable
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Stable (spec 9): plank open shed 6x3.5x3 with a thatch roof, 2 horses. The long side (+X) is open;
## DEF.yaw_offset turns that side toward the village center.

const DEF := {"id": "stable", "footprint_radius": 4.0, "prop_hints": ["haybale", "fence", "bucket"], "name_key": "building.stable", "yaw_offset": -PI * 0.5}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 4.0
	var hx: float = 1.75
	var hz: float = 3.0
	var y0: float = 0.2
	Kit.foundation(r, "stone", Vector2.ZERO, hx, hz, 0.2, 0.4, 1.5, rng)
	# back wall (-X) and both short sides (+-Z); the +X long side stays open
	Kit.wall(r, "plank", Vector2(-hx + 0.1, hz - 0.1), Vector2(-hx + 0.1, -hz + 0.1), y0, 2.8, 0.2, 1.8, 1.4, rng, [], false, Kit.NO_COLOR, "wall")
	Kit.wall(r, "plank", Vector2(-hx + 0.3, hz - 0.1), Vector2(hx - 0.1, hz - 0.1), y0, 2.8, 0.2, 1.4, 1.4, rng, [], false, Kit.NO_COLOR, "wall")
	Kit.wall(r, "plank", Vector2(hx - 0.1, -hz + 0.1), Vector2(-hx + 0.3, -hz + 0.1), y0, 2.8, 0.2, 1.4, 1.4, rng, [], false, Kit.NO_COLOR, "wall")
	# open-side posts + stall divider
	for sz in [-hz + 0.15, -1.0, 1.0, hz - 0.15]:
		Kit.post(r, "wood", Vector3(hx - 0.15, y0, sz as float), 3.0, 0.24, rng, "post")
	Kit.box(r, "plank", Vector3(2.6, 1.1, 0.12), Vector3(-0.3, y0 + 0.55, 0.0), rng, Kit.NO_COLOR, false, "divider")
	Kit.gable_roof(r, "thatch", Vector2.ZERO, y0 + 2.9, hx + 0.25, hz, 1.1, 0.16, 1.4, rng, 0.35)
	r.extra("animal", Vector3(0.2, 0.0, -1.6), {"animal": "horse"})
	r.extra("animal", Vector3(0.2, 0.0, 1.6), {"animal": "horse"})
	r.height = y0 + 4.0
	return r
