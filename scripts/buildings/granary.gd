class_name BGranary
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Granary (spec 9): raised wooden building on 4 stone stilts, plank walls, thatch roof, flour sacks.

const DEF := {"id": "granary", "footprint_radius": 3.0, "prop_hints": ["crate", "haybale"], "name_key": "building.granary"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 3.0
	var hx: float = 1.9
	var hz: float = 1.9
	var lift: float = 0.9
	# 4 stone stilts (anchored)
	for sx in [-hx + 0.3, hx - 0.3]:
		for sz in [-hz + 0.3, hz - 0.3]:
			Kit.box(r, "stone", Vector3(0.5, lift, 0.5), Vector3(sx as float, lift * 0.5, sz as float), rng, Kit.NO_COLOR, true, "stilt")
	var y0: float = lift
	Kit.floor_planks(r, "plank", Vector2.ZERO, 2.0 * hx, 2.0 * hz, y0 + 0.08, 0.95, 0.16, rng, false, "floor")
	var yb: float = y0 + 0.16
	Kit.house_walls(r, "plank", Vector2.ZERO, hx - 0.1, hz - 0.1, yb, 2.4, 0.2, 1.3, 1.2, rng, [Rect2(1.2, 0.0, 1.0, 1.9)], [], [], [], Kit.NO_COLOR, "wall")
	Kit.door(r, Vector2(-hx + 0.1 + 1.7, hz - 0.1), yb, 1.0, 1.9, 0.0, rng)
	Kit.gable_roof(r, "thatch", Vector2.ZERO, yb + 2.4, hx + 0.1, hz, 1.4, 0.16, 1.4, rng, 0.35)
	Kit.gable_end(r, "plank", Vector2.ZERO, hz - 0.1, yb + 2.4, hx, 1.4, 0.18, rng)
	Kit.gable_end(r, "plank", Vector2.ZERO, -hz + 0.1, yb + 2.4, hx, 1.4, 0.18, rng)
	# flour sacks inside + a few outside on the steps
	for i in 4:
		var sack := Kit.sph(r, "cloth", 0.3, Vector3(rng.range_f(-1.0, 1.0), yb + 0.35, rng.range_f(-1.2, 0.2)), rng, Color("#e8dcc0"), "sack")
		sack.mass_override = 20.0
	# steps
	Kit.box(r, "plank", Vector3(1.2, 0.3, 0.6), Vector3(-hx + 1.7, 0.15, hz + 0.3), rng, Kit.NO_COLOR, false, "step")
	r.height = yb + 2.4 + 1.4
	return r
