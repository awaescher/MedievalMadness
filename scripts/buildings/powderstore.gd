class_name BPowderStore
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Definitely Not Explosive (spec 9): stone shed 4x4x3, metal-studded door, skull sign, 6 powder kegs inside.

const DEF := {"id": "powderstore", "footprint_radius": 3.0, "prop_hints": ["crate", "barrel_powder"], "name_key": "building.powderstore"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 3.0
	var hx: float = 2.0
	var hz: float = 2.0
	var y0: float = 0.3
	Kit.foundation(r, "stone", Vector2.ZERO, hx, hz, 0.3, 0.5, 2.1, rng)
	Kit.house_walls(r, "stone", Vector2.ZERO, hx - 0.15, hz - 0.15, y0, 3.0, 0.34, 2.0, 1.5, rng, [Rect2(1.0, 0.0, 1.5, 1.5)], [], [], [], Color("#8a9096"), "wall")
	# metal-studded door
	Kit.box(r, "wood", Vector3(1.4, 1.5, 0.16), Vector3(-hx + 0.15 + 1.75, y0 + 0.75, hz - 0.15), rng, Color("#5a381c"), false, "door")
	for sx in [-0.4, 0.4]:
		Kit.box(r, "metal", Vector3(0.09, 0.09, 0.05), Vector3(-hx + 0.15 + 1.75 + (sx as float), y0 + 0.75, hz - 0.05), rng, Color("#9aa4b0"), false, "stud")
	# flat-ish plank roof (low gable)
	Kit.gable_roof(r, "plank", Vector2.ZERO, y0 + 3.0, hx + 0.05, hz, 0.9, 0.14, 2.1, rng, 0.3, Color("#4a4a52"))
	Kit.gable_end(r, "stone", Vector2.ZERO, hz - 0.15, y0 + 3.0, hx, 0.9, 0.3, rng)
	Kit.gable_end(r, "stone", Vector2.ZERO, -hz + 0.15, y0 + 3.0, hx, 0.9, 0.3, rng)
	# skull sign above the door
	Kit.box(r, "plank", Vector3(1.0, 0.7, 0.08), Vector3(0, y0 + 3.5, hz + 0.02), rng, Color("#f0f0e8"), false, "sign")
	Kit.box(r, "metal", Vector3(0.14, 0.14, 0.05), Vector3(-0.17, y0 + 3.55, hz + 0.08), rng, Color("#1a1a20"), false, "sign")
	Kit.box(r, "metal", Vector3(0.14, 0.14, 0.05), Vector3(0.17, y0 + 3.55, hz + 0.08), rng, Color("#1a1a20"), false, "sign")
	Kit.box(r, "metal", Vector3(0.28, 0.1, 0.05), Vector3(0.0, y0 + 3.3, hz + 0.08), rng, Color("#1a1a20"), false, "sign")
	Kit.floor_planks(r, "plank", Vector2.ZERO, 2.0 * hx - 0.6, 2.0 * hz - 0.6, y0 + 0.05, 3.4, 0.1, rng, false, "floor")
	# 6 kegs inside
	for i in 6:
		r.extra("prop", Vector3(-1.1 + float(i % 3) * 1.1, y0 + 0.05, -0.9 + float(i / 3) * 1.3), {"prop": "barrel_powder", "lift": y0 - 0.02, "ground": false})
	r.height = y0 + 3.9
	return r
