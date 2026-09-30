class_name BStall
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Market Stall (spec 9): wood frame, striped cloth awning, table with crates and fruit.

const DEF := {"id": "stall", "footprint_radius": 2.0, "prop_hints": ["crate", "crate"], "name_key": "building.stall"}

static func build(ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 2.0
	# frame posts (front tall, back taller so the awning slopes)
	for sx in [-1.0, 1.0]:
		Kit.post(r, "wood", Vector3((sx as float), 0.0, 0.8), 2.2, 0.14, rng, "post", true)
		Kit.post(r, "wood", Vector3((sx as float), 0.0, -0.8), 2.6, 0.14, rng, "post", true)
	# table
	Kit.box(r, "plank", Vector3(2.0, 0.1, 0.9), Vector3(0, 0.9, 0.35), rng, Kit.NO_COLOR, false, "table")
	Kit.box(r, "wood", Vector3(1.9, 0.75, 0.08), Vector3(0, 0.45, 0.75), rng, Kit.NO_COLOR, false, "table")
	Kit.box(r, "wood", Vector3(1.9, 0.75, 0.08), Vector3(0, 0.45, -0.05), rng, Kit.NO_COLOR, false, "table")
	# striped awning (3 cloth panels tilted toward the front)
	var cols: Array[Color] = [Color("#e74c3c"), Color("#f4f1e8"), Color("#e74c3c")]
	if rng.chance(0.5):
		cols = [ctx.player_color, Color("#f4f1e8"), ctx.player_color]
	var tilt: float = atan2(0.4, 1.7)
	for i in 3:
		Kit.box(r, "cloth", Vector3(0.7, 0.05, 2.0), Vector3(-0.7 + float(i) * 0.7, 2.55, 0.0), rng, cols[i], false, "awning", Vector3(tilt, 0, 0))
	# side boards + price sign
	Kit.box(r, "plank", Vector3(0.08, 0.5, 0.9), Vector3(-1.0, 1.25, 0.35), rng, Kit.NO_COLOR, false, "board")
	Kit.box(r, "plank", Vector3(0.08, 0.5, 0.9), Vector3(1.0, 1.25, 0.35), rng, Kit.NO_COLOR, false, "board")
	Kit.box(r, "plank", Vector3(1.2, 0.35, 0.06), Vector3(0.0, 1.55, 0.85), rng, Color("#f4e4bc"), false, "sign")
	Kit.box(r, "cloth", Vector3(1.9, 0.5, 0.05), Vector3(0.0, 0.75, 0.85), rng, cols[0], false, "skirt")
	# crates behind
	Kit.box(r, "wood", Vector3(0.6, 0.6, 0.6), Vector3(-0.6, 0.3, -0.5), rng, Kit.NO_COLOR, false, "crate")
	Kit.box(r, "wood", Vector3(0.6, 0.6, 0.6), Vector3(0.4, 0.3, -0.55), rng, Kit.NO_COLOR, false, "crate")
	# fruit on the table (dynamic props)
	for i in 5:
		r.extra("prop", Vector3(rng.range_f(-0.8, 0.8), 1.0, rng.range_f(0.1, 0.6)), {"prop": "fruit", "lift": 0.0, "ground": false})
	r.height = 2.8
	return r
