class_name BTavern
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## The Drunken Goose (spec 9): two-story plank + stone building, swinging sign, balcony, 3 beer barrels + 4 mugs outside.

const DEF := {"id": "tavern", "footprint_radius": 5.0, "prop_hints": ["barrel_beer", "barrel_beer", "barrel_beer", "crate", "mug"], "name_key": "building.tavern"}

static func build(ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 5.0
	var hx: float = 3.4
	var hz: float = 2.8
	Kit.foundation(r, "stone", Vector2.ZERO, hx, hz, 0.35, 0.5, 2.4, rng)
	var y0: float = 0.35
	# ground floor: stone
	var door: Array = [Rect2(2.4, 0.0, 1.5, 1.35), Rect2(0.2, 1.35, 1.0, 1.0), Rect2(5.2, 1.35, 1.0, 1.0)]
	Kit.house_walls(r, "stone", Vector2.ZERO, hx - 0.15, hz - 0.15, y0, 2.7, 0.3, 2.4, 1.35, rng, door, [], [], [], Kit.NO_COLOR, "wall")
	Kit.door(r, Vector2(-hx + 0.15 + 3.15, hz - 0.15), y0, 1.3, 1.35, 0.0, rng)
	Kit.window(r, Vector2(-hx + 0.15 + 0.7, hz - 0.15), y0 + 1.35, 1.0, 1.0, 0.0, rng)
	Kit.window(r, Vector2(-hx + 0.15 + 5.7, hz - 0.15), y0 + 1.35, 1.0, 1.0, 0.0, rng)
	# floor between stories
	Kit.floor_planks(r, "plank", Vector2.ZERO, 2.0 * hx - 0.5, 2.0 * hz - 0.5, y0 + 2.75, 2.0, 0.12, rng, false, "floor")
	# upper floor: planks (timber frame look)
	var y1: float = y0 + 2.8
	var up_open: Array = [Rect2(0.5, 0.8, 1.0, 1.0), Rect2(2.6, 0.0, 1.5, 1.3), Rect2(5.2, 0.8, 1.0, 1.0)]
	Kit.house_walls(r, "plank", Vector2.ZERO, hx - 0.15, hz - 0.15, y1, 2.6, 0.24, 2.4, 1.3, rng, up_open, [], [], [], Color("#d9b88a"), "wall")
	Kit.window(r, Vector2(-hx + 0.15 + 1.0, hz - 0.15), y1 + 0.8, 1.0, 1.0, 0.0, rng)
	Kit.window(r, Vector2(-hx + 0.15 + 5.7, hz - 0.15), y1 + 0.8, 1.0, 1.0, 0.0, rng)
	# balcony door
	Kit.door(r, Vector2(-hx + 0.15 + 3.35, hz - 0.15), y1, 1.3, 1.3, 0.0, rng)
	# balcony (front, above the door): floor + rail + 2 posts
	Kit.box(r, "plank", Vector3(3.4, 0.14, 1.3), Vector3(0.0, y1 - 0.05, hz + 0.55), rng, Kit.NO_COLOR, false, "balcony")
	Kit.box(r, "plank", Vector3(3.4, 0.1, 0.1), Vector3(0.0, y1 + 0.95, hz + 1.15), rng, Kit.NO_COLOR, false, "rail")
	for sx in [-1.65, 1.65]:
		Kit.post(r, "wood", Vector3(sx as float, y0, hz + 1.15), y1 - y0 + 0.95, 0.2, rng, "post", true)
	# corner posts
	for cx in [-hx + 0.15, hx - 0.15]:
		for cz in [-hz + 0.15, hz - 0.15]:
			Kit.post(r, "wood", Vector3(cx as float, y0, cz as float), 5.5, 0.3, rng, "post")
	# roof (tile) with a colored accent cloth strip on the ridge
	var rise: float = 1.9
	var top: float = y1 + 2.6
	Kit.gable_roof(r, "plank", Vector2.ZERO, top, hx + 0.05, hz, rise, 0.12, 1.9, rng, 0.35, Color("#c0392b"))
	Kit.gable_end(r, "plank", Vector2.ZERO, hz - 0.15, top, hx, rise, 0.2, rng)
	Kit.gable_end(r, "plank", Vector2.ZERO, -hz + 0.15, top, hx, rise, 0.2, rng)
	var accent: PartDef = Kit.box(r, "cloth", Vector3(0.1, 0.1, 2.2 * hz), Vector3(0, top + rise + 0.18, 0), rng, ctx.player_color, false, "accent")
	accent.mass_override = 5.0
	# swinging sign at the front corner
	Kit.box(r, "wood", Vector3(0.14, 1.5, 0.14), Vector3(hx + 0.5, y0 + 3.2, hz - 0.1), rng, Color("#5a381c"), false, "signpost")
	Kit.box(r, "wood", Vector3(1.3, 0.12, 0.12), Vector3(hx - 0.1, y0 + 3.85, hz - 0.1), rng, Color("#5a381c"), false, "signarm")
	Kit.box(r, "cloth", Vector3(0.8, 0.7, 0.06), Vector3(hx - 0.35, y0 + 3.4, hz - 0.1), rng, Color("#f1c40f"), false, "sign")
	# outside props: 3 beer barrels + 4 mugs
	r.extra("prop", Vector3(hx + 0.9, 0.0, hz - 1.4), {"prop": "barrel_beer"})
	r.extra("prop", Vector3(hx + 0.9, 0.0, hz - 0.3), {"prop": "barrel_beer"})
	r.extra("prop", Vector3(hx + 0.9, 0.0, hz + 0.9), {"prop": "barrel_beer"})
	for i in 4:
		r.extra("prop", Vector3(-1.5 + float(i) * 0.9, 0.0, hz + 1.1), {"prop": "mug", "lift": 0.0})
	r.extra("gather", Vector3(0.0, 0.0, hz + 1.6), {})
	r.height = top + rise
	return r
