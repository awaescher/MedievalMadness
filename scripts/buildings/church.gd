class_name BChurch
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Church of Holy Confusion (spec 9): stone nave 6x10x5, steeple tower 3x3x10 with a metal bell, red tile roof, stained glass.

const DEF := {"id": "church", "footprint_radius": 5.0, "prop_hints": ["banner", "fence"], "name_key": "building.church"}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 5.5
	var hx: float = 3.0
	var hz: float = 4.6
	var y0: float = 0.35
	# nave centered at z = +1.0 so the tower sits at the rear (-Z)
	var c := Vector2(0, 1.4)
	Kit.foundation(r, "stone", c, hx, hz, 0.35, 0.55, 3.2, rng)
	var wall_h: float = 5.0
	var front: Array = [Rect2(2.0, 0.0, 2.0, 1.7)]
	var side: Array = [Rect2(2.4, 1.7, 1.2, 1.7), Rect2(6.0, 1.7, 1.2, 1.7)]
	Kit.house_walls(r, "stone", c, hx - 0.15, hz - 0.15, y0, wall_h, 0.34, 2.6, 1.7, rng, front, [], side, side, Kit.NO_COLOR, "wall")
	# door + stained glass front window above
	Kit.door(r, Vector2(0, c.y + hz - 0.15), y0, 1.9, 1.7, 0.0, rng)
	var glass := Kit.box(r, "glass", Vector3(0.9, 1.4, 0.08), Vector3(0, y0 + 3.9, c.y + hz - 0.15), rng, Color("#e0407a"), false, "window")
	glass.color = Color("#d060c0")
	Kit.box(r, "glass", Vector3(0.6, 0.7, 0.09), Vector3(0, y0 + 4.05, c.y + hz - 0.14), rng, Color("#ffd34a"), false, "window")
	for sz in [3.0, 6.6]:
		var zz: float = c.y - hz + 0.34 + (sz as float)
		Kit.box(r, "glass", Vector3(0.07, 1.7, 1.2), Vector3(-hx + 0.15, y0 + 2.55, zz), rng, Color("#6fb8ff"), false, "window")
		Kit.box(r, "glass", Vector3(0.07, 1.7, 1.2), Vector3(hx - 0.15, y0 + 2.55, zz), rng, Color("#6fb8ff"), false, "window")
	# nave roof: red tile gable
	var rise: float = 2.4
	Kit.gable_roof(r, "plank", c, y0 + wall_h, hx + 0.05, hz, rise, 0.14, 2.6, rng, 0.35, Color("#c0392b") if rng.chance(0.8) else Color("#a83226"))
	Kit.gable_end(r, "stone", c, c.y + hz - 0.15, y0 + wall_h, hx, rise, 0.3, rng, Kit.NO_COLOR, 1.2)
	# steeple tower at the rear: 3x3, 10 m
	var tc := Vector2(0, c.y - hz - 1.35)
	var th: float = 10.0
	Kit.foundation(r, "stone", tc, 1.5, 1.5, 0.35, 0.5, 3.0, rng)
	Kit.house_walls(r, "stone", tc, 1.5 - 0.15, 1.5 - 0.15, y0, th - 2.5, 0.32, 2.7, 2.5, rng, [], [], [], [], Color("#a9aeb3"), "tower")
	# belfry openings top (4 posts instead of walls at the top 2.5 m)
	var ty: float = y0 + th - 2.5
	for px in [-1.3, 1.3]:
		for pz in [-1.3, 1.3]:
			Kit.post(r, "stone", Vector3(tc.x + (px as float), ty, tc.y + (pz as float)), 2.5, 0.42, rng, "tower")
	# bell (metal cylinder) hanging inside
	var bell := Kit.cyl(r, "metal", 0.5, 0.9, Vector3(tc.x, ty + 1.3, tc.y), rng, Color("#d4a020"), false, "bell")
	bell.mass_override = 300.0
	Kit.box(r, "wood", Vector3(2.6, 0.2, 0.2), Vector3(tc.x, ty + 2.1, tc.y), rng, Color("#5a381c"), false, "tower")
	# steeple roof: pyramid
	Kit.pyramid_roof(r, "plank", tc, ty + 2.5, 1.7, 3.6, rng, Color("#a83226"), "roof")
	# cross on top
	Kit.box(r, "metal", Vector3(0.14, 1.0, 0.14), Vector3(tc.x, ty + 2.5 + 3.6 + 0.4, tc.y), rng, Color("#e8c060"), false, "cross")
	Kit.box(r, "metal", Vector3(0.6, 0.14, 0.14), Vector3(tc.x, ty + 2.5 + 3.6 + 0.6, tc.y), rng, Color("#e8c060"), false, "cross")
	# floor
	Kit.floor_planks(r, "plank", c, 2.0 * hx - 0.7, 2.0 * hz - 0.7, y0 + 0.05, 3.6, 0.1, rng, false, "floor")
	r.extra("flag", Vector3(tc.x, ty + 2.5 + 3.6 + 1.1, tc.y), {"height": 0.0})
	r.height = ty + 2.5 + 3.6 + 1.2
	return r
