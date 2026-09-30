class_name BPalisade
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Sharp Fence (spec 9): a segment of 6 sharpened logs (3 m). Logs topple like dominoes.

const DEF := {"id": "palisade", "footprint_radius": 3.0, "prop_hints": [], "name_key": "building.palisade", "seg": 3.0}

static func build(_ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 1.6
	for i in 6:
		var x: float = -1.25 + float(i) * 0.5
		var h: float = 2.7 + rng.range_f(-0.15, 0.25)
		var log_ := Kit.frustum(r, "wood", 0.17, 0.05, h, Vector3(x, h * 0.5 - 0.15, rng.range_f(-0.03, 0.03)), rng, Kit.NO_COLOR, true, "log")
		log_.segs = 8
	r.height = 3.0
	return r
