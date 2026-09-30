class_name BWatchtower
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Lookout Tower (spec 9): stone tower 3x3x9, wooden platform with crenellations, banner in player color, one archer.

const DEF := {"id": "watchtower", "footprint_radius": 3.0, "prop_hints": ["barrel_water", "crate"], "name_key": "building.watchtower"}

static func build(ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 3.0
	var y0: float = 0.4
	Kit.foundation(r, "stone", Vector2.ZERO, 1.6, 1.6, 0.4, 0.5, 2.0, rng)
	var h: float = 8.0
	Kit.house_walls(r, "stone", Vector2.ZERO, 1.5, 1.5, y0, h, 0.34, 1.8, 1.6, rng, [Rect2(0.9, 0.0, 1.2, 1.6)], [], [], [], Kit.NO_COLOR, "wall")
	Kit.door(r, Vector2(-1.5 + 1.5, 1.5), y0, 1.1, 1.6, 0.0, rng)
	# arrow slits (glass-less: thin dark boxes)
	for i in 2:
		Kit.box(r, "wood", Vector3(0.12, 0.5, 0.06), Vector3(0, y0 + 2.6 + float(i) * 2.2, 1.55), rng, Color("#2b2b33"), false, "slit")
	# wooden platform (overhanging) + inner floor
	var py: float = y0 + h
	Kit.floor_planks(r, "plank", Vector2.ZERO, 4.0, 4.0, py + 0.08, 0.8, 0.16, rng, false, "platform")
	# crenellations on the platform edge
	Kit.crenellations(r, "wood", Vector2.ZERO, 1.9, 1.9, py + 0.16, Vector3(0.8, 0.8, 0.3), 0.6, rng)
	# corner posts + roofless top (open) with banner mast
	Kit.post(r, "wood", Vector3(1.7, py + 0.16, -1.7), 2.6, 0.18, rng, "mast")
	var flag := Kit.box(r, "cloth", Vector3(0.05, 0.7, 1.0), Vector3(1.7, py + 2.4, -1.2), rng, ctx.player_color, false, "banner")
	flag.mass_override = 3.0
	r.extra("flag", Vector3(1.7, py + 2.8, -1.7), {"color": ctx.player_color})
	r.extra("archer", Vector3(0.0, py + 0.16, 0.0), {})
	r.height = py + 2.8
	return r
