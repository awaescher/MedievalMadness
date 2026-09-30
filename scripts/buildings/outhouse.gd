class_name BOuthouse
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## The Royal Loo (spec 9): wooden 1.2x1.2x2.2 with a crescent moon on the door. Launches its occupant when destroyed.

const DEF := {"id": "outhouse", "footprint_radius": 1.2, "prop_hints": [], "name_key": "building.outhouse"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 1.2
	Kit.box(r, "stone", Vector3(1.3, 0.2, 1.3), Vector3(0, 0.1, 0), rng, Color("#8a9096"), true, "foundation")
	# walls: 4 sides x 2 planks tall
	Kit.wall(r, "plank", Vector2(-0.6, 0.6), Vector2(0.6, 0.6), 0.2, 2.0, 0.12, 1.2, 2.0, rng, [], false, Kit.NO_COLOR, "wall")
	Kit.wall(r, "plank", Vector2(0.6, -0.6), Vector2(-0.6, -0.6), 0.2, 2.0, 0.12, 1.2, 2.0, rng, [], false, Kit.NO_COLOR, "wall")
	Kit.wall(r, "plank", Vector2(-0.6, -0.5), Vector2(-0.6, 0.5), 0.2, 2.0, 0.12, 1.0, 2.0, rng, [], false, Kit.NO_COLOR, "wall")
	Kit.wall(r, "plank", Vector2(0.6, 0.5), Vector2(0.6, -0.5), 0.2, 2.0, 0.12, 1.0, 2.0, rng, [], false, Kit.NO_COLOR, "wall")
	# door (front) with a crescent moon
	Kit.box(r, "wood", Vector3(0.8, 1.7, 0.1), Vector3(0, 1.05, 0.66), rng, Color("#a0622d"), false, "door")
	Kit.box(r, "wood", Vector3(0.16, 0.16, 0.05), Vector3(0.0, 1.6, 0.73), rng, Color("#f1c40f"), false, "moon")
	Kit.box(r, "wood", Vector3(0.08, 0.2, 0.05), Vector3(-0.06, 1.6, 0.73), rng, Color("#f1c40f"), false, "moon")
	# roof: two sloped planks
	for s in [-1.0, 1.0]:
		Kit.box(r, "plank", Vector3(0.8, 0.08, 1.5), Vector3((s as float) * 0.32, 2.42, 0.0), rng, Color("#8a5a2a"), false, "roof", Vector3(0, 0, -(s as float) * 0.35))
	# ridge cap, seat and doorstep
	Kit.box(r, "wood", Vector3(0.14, 0.1, 1.5), Vector3(0.0, 2.72, 0.0), rng, Color("#5a381c"), false, "ridge")
	Kit.box(r, "plank", Vector3(0.7, 0.14, 0.5), Vector3(0.0, 0.7, -0.2), rng, Kit.NO_COLOR, false, "seat")
	Kit.box(r, "stone", Vector3(0.9, 0.12, 0.35), Vector3(0.0, 0.06, 0.85), rng, Color("#8a9096"), false, "step")
	r.extra("occupant", Vector3(0, 0.2, 0), {})
	r.height = 2.7
	return r
