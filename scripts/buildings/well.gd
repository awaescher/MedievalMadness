class_name BWell
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Wishing Well (spec 9): stone ring, wooden roof frame, bucket, rope. Water inside.

const DEF := {"id": "well", "footprint_radius": 1.6, "prop_hints": ["bucket"], "name_key": "building.well"}

static func build(ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 1.6
	# ring: 10 blocks x 2 rows
	Kit.ring(r, "stone", Vector2.ZERO, 0.95, 0.0, 1.0, 0.4, 10, 0.5, rng, true, [], Kit.NO_COLOR, "ring")
	# water inside
	var water := Kit.cyl(r, "glass", 0.7, 0.06, Vector3(0, 0.5, 0), rng, Color("#3fa9f5"), false, "water")
	water.mass_override = 2.0
	water.hp_override = 100000.0
	# roof frame: 2 posts, cross beam, mini gable
	for sx in [-1.0, 1.0]:
		Kit.post(r, "wood", Vector3((sx as float), 1.0, 0.0), 1.9, 0.2, rng, "post", false)
	Kit.box(r, "wood", Vector3(2.4, 0.16, 0.2), Vector3(0, 2.9, 0), rng, Kit.NO_COLOR, false, "beam")
	for s in [-1.0, 1.0]:
		Kit.box(r, "plank", Vector3(1.6, 0.1, 1.6), Vector3((s as float) * 0.62, 3.2, 0), rng, Color("#c0392b"), false, "roof", Vector3(0, 0, -(s as float) * 0.5))
	# bucket + rope
	Kit.cyl(r, "wood", 0.17, 0.26, Vector3(0.0, 2.1, 0.0), rng, Color("#8a5a2a"), false, "bucket")
	Kit.cyl(r, "cloth", 0.02, 0.6, Vector3(0.0, 2.55, 0.0), rng, Color("#d8c9a0"), false, "rope")
	# banner flag in player color on one post
	var flag := Kit.box(r, "cloth", Vector3(0.05, 0.5, 0.7), Vector3(1.0, 2.7, 0.4), rng, ctx.player_color, false, "banner")
	flag.mass_override = 2.0
	r.extra("flag", Vector3(1.0, 3.1, 0.0), {"color": ctx.player_color})
	r.height = 3.3
	return r
