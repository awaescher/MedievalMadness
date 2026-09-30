class_name BBarn
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Big Hay Barn (spec 9): 6x8 plank walls 5 m, big gable plank roof, big double door, 4-6 hay bales inside.

const DEF := {"id": "barn", "footprint_radius": 6.0, "prop_hints": ["haybale", "haybale", "cart", "fence"], "name_key": "building.barn"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 6.0
	var hx: float = 3.0
	var hz: float = 4.0
	var y0: float = 0.35
	Kit.foundation(r, "stone", Vector2.ZERO, hx, hz, 0.35, 0.5, 1.6, rng)
	var wall_h: float = 4.8
	var door: Array = [Rect2(1.5, 0.0, 3.0, 3.4)]
	Kit.house_walls(r, "plank", Vector2.ZERO, hx - 0.15, hz - 0.15, y0, wall_h, 0.22, 2.0, 1.6, rng, door, [], [], [], Color("#c94a3a") if rng.chance(0.6) else Kit.NO_COLOR, "wall")
	# double door leaves (front = +Z)
	for s in [-1.0, 1.0]:
		Kit.box(r, "wood", Vector3(1.5, 3.4, 0.14), Vector3((s as float) * 0.75, y0 + 1.7, hz - 0.15), rng, Color("#7a4a25"), false, "door")
	# cross beams on the doors
	Kit.box(r, "wood", Vector3(3.0, 0.12, 0.08), Vector3(0, y0 + 1.7, hz - 0.05), rng, Color("#5a381c"), false, "frame")
	# corner posts
	for cx in [-hx + 0.15, hx - 0.15]:
		for cz in [-hz + 0.15, hz - 0.15]:
			Kit.post(r, "wood", Vector3(cx as float, y0, cz as float), wall_h + 0.1, 0.3, rng, "post")
	var rise: float = 2.4
	Kit.gable_roof(r, "plank", Vector2.ZERO, y0 + wall_h, hx + 0.05, hz, rise, 0.14, 1.75, rng, 0.4, Color("#8a5a2a"))
	Kit.gable_end(r, "plank", Vector2.ZERO, hz - 0.15, y0 + wall_h, hx, rise, 0.2, rng)
	Kit.gable_end(r, "plank", Vector2.ZERO, -hz + 0.15, y0 + wall_h, hx, rise, 0.2, rng)
	# hay inside
	var bales: int = rng.range_i(4, 6)
	for i in bales:
		var bx: float = rng.range_f(-hx + 1.0, hx - 1.0)
		var bz: float = rng.range_f(-hz + 1.2, hz - 3.0)
		Kit.box(r, "hay", Vector3(1.0, 0.7, 0.7), Vector3(bx, y0 + 0.4 + (0.72 if i >= 4 else 0.0), bz), rng, Kit.NO_COLOR, false, "hay", Vector3(0, rng.range_f(0, PI), 0))
	Kit.floor_planks(r, "plank", Vector2.ZERO, 2.0 * hx - 0.8, 2.0 * hz - 0.8, y0 + 0.05, 1.6, 0.1, rng, false, "floor")
	r.height = y0 + wall_h + rise
	return r
