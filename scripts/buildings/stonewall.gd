class_name BStoneWall
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Sturdy Wall (spec 9): stone block wall 4x2x0.8 with crenellations. Blocks are heavy and can protect catapults.

const DEF := {"id": "stonewall", "footprint_radius": 4.0, "prop_hints": [], "name_key": "building.stonewall", "seg": 4.0}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 2.2
	Kit.wall(r, "stone", Vector2(-2.0, 0.0), Vector2(2.0, 0.0), 0.0, 2.0, 0.8, 0.8, 0.5, rng, [], true, Kit.NO_COLOR, "block")
	Kit.crenellations(r, "stone", Vector2.ZERO, 1.85, 0.0, 2.0, Vector3(0.6, 0.45, 0.7), 0.6, rng)
	r.height = 2.5
	return r
