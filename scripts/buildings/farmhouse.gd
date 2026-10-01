class_name BFarmhouse
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Cosy Cottage (spec 9): stone foundation 5x5, brick/plank walls 3 m, gable roof (thatch or tile), chimney, windows, door.

const DEF := {"id": "farmhouse", "footprint_radius": 4.0, "prop_hints": ["fence", "haybale", "crate"], "name_key": "building.farmhouse"}

static func build(ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 4.0
	var hx: float = 2.5
	var hz: float = 2.5
	var wall_mat: String = "brick" if rng.chance(0.5) else "plank"
	var plaster: bool = rng.chance(0.4)
	var wall_col: Color = Color("#f2e6c9") if plaster else Kit.NO_COLOR
	var thatch: bool = ctx.thatch_roof or rng.chance(0.5)
	Kit.foundation(r, "stone", Vector2.ZERO, hx, hz, 0.4, 0.5, 1.9, rng)
	# door + windows (front = +Z)
	var front: Array = [Rect2(1.4, 0.0, 1.0, 1.5), Rect2(0.0, 1.5, 0.9, 0.9), Rect2(3.6, 1.5, 0.9, 0.9)]
	var side: Array = [Rect2(1.7, 1.5, 0.9, 0.9)]
	var y0: float = 0.4
	# walls: 3 courses of 1.0 m panels
	Kit.house_walls(r, wall_mat, Vector2.ZERO, hx - 0.15, hz - 0.15, y0, 3.0, 0.24, 1.7, 1.5, rng, front, [], side, side, wall_col, "wall")
	# door + windows (front wall is drawn from x=-hx to +hx along +Z)
	Kit.door(r, Vector2(-hx + 0.15 + 1.9, hz - 0.15), y0, 1.0, 1.5, 0.0, rng)
	Kit.window(r, Vector2(-hx + 0.15 + 0.45, hz - 0.15), y0 + 1.5, 0.9, 0.9, 0.0, rng)
	Kit.window(r, Vector2(-hx + 0.15 + 4.05, hz - 0.15), y0 + 1.5, 0.9, 0.9, 0.0, rng)
	Kit.window(r, Vector2(-hx + 0.15, 0.1), y0 + 1.5, 0.9, 0.9, PI * 0.5, rng)
	Kit.window(r, Vector2(hx - 0.15, -0.1), y0 + 1.5, 0.9, 0.9, PI * 0.5, rng)
	# timber corner posts
	for cx in [-hx + 0.15, hx - 0.15]:
		for cz in [-hz + 0.15, hz - 0.15]:
			Kit.post(r, "wood", Vector3(cx as float, y0, cz as float), 3.1, 0.3, rng, "post")
	# roof
	var rise: float = 1.5
	var roof_mat: String = "thatch" if thatch else "plank"
	var roof_col: Color = Kit.NO_COLOR
	if not thatch:
		roof_col = Color("#c0392b") if rng.chance(0.85) else Color("#d35400")
	Kit.gable_roof(r, roof_mat, Vector2.ZERO, y0 + 3.0, hx + 0.05, hz, rise, 0.16 if thatch else 0.12, 1.75, rng, 0.35, roof_col)
	Kit.gable_end(r, "plank", Vector2.ZERO, hz - 0.15, y0 + 3.0, hx, rise, 0.2, rng)
	Kit.gable_end(r, "plank", Vector2.ZERO, -hz + 0.15, y0 + 3.0, hx, rise, 0.2, rng)
	# floor
	Kit.floor_planks(r, "plank", Vector2.ZERO, 2.0 * hx - 0.6, 2.0 * hz - 0.6, y0 + 0.05, 2.4, 0.1, rng, false, "floor")
	# chimney (bricks, smoke)
	for i in 3:
		Kit.box(r, "brick", Vector3(0.6, 1.0, 0.6), Vector3(1.4, y0 + 3.0 + 0.5 + float(i) * 1.0, -1.0), rng, Kit.NO_COLOR, false, "chimney")
	r.extra("smoke", Vector3(1.4, y0 + 3.0 + 3.0 + 0.6, -1.0))
	r.height = y0 + 3.0 + rise + 1.0
	return r
