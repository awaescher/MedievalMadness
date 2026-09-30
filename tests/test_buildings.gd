extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Every building blueprint builds cleanly (no NaN, valid materials, part counts near the spec ranges) (spec 9).

# id -> [min parts, max parts] (spec table; a little slack for the generated variants)
const RANGES: Dictionary = {
	"farmhouse": [55, 85], "barn": [78, 115], "tavern": [85, 115], "church": [85, 115], "watchtower": [48, 75],
	"well": [18, 32], "stall": [14, 27], "stable": [38, 62], "granary": [38, 58], "powderstore": [38, 55],
	"watertower": [24, 38], "windmill": [58, 85], "blacksmith": [43, 65], "outhouse": [11, 17], "palisade": [6, 6], "stonewall": [19, 32],
}

func _check_result(id: String, res: BuildResult) -> void:
	var nan_count: int = 0
	var bad_mat: int = 0
	for p in res.parts:
		if not is_finite(p.pos.x) or not is_finite(p.pos.y) or not is_finite(p.pos.z) or not is_finite(p.rot.x) or not is_finite(p.rot.y) or not is_finite(p.rot.z):
			nan_count += 1
		if not is_finite(p.size.x) or not is_finite(p.size.y) or not is_finite(p.size.z) or p.size.x <= 0.0 or p.size.y <= 0.0 or p.size.z <= 0.0:
			nan_count += 1
		if not Materials.has(p.material):
			bad_mat += 1
	TestBase.eq(nan_count, 0, "%s: no NaN / degenerate parts" % id)
	TestBase.eq(bad_mat, 0, "%s: only known materials" % id)

func test_all_buildings_build() -> void:
	var ctx := BuildContext.new()
	for id in Buildings.all_ids():
		for seed_i in 3:
			var rng := Rng.from_string("%s-%d" % [id, seed_i])
			var res: BuildResult = Buildings.build(id, ctx, rng)
			TestBase.check(res.parts.size() > 0, "%s builds parts" % id)
			_check_result(id, res)

func test_part_counts_match_spec() -> void:
	var ctx := BuildContext.new()
	for id in RANGES:
		var lo: int = int((RANGES[id] as Array)[0])
		var hi: int = int((RANGES[id] as Array)[1])
		var worst_lo: int = 1 << 20
		var worst_hi: int = 0
		for seed_i in 6:
			var rng := Rng.from_string("count-%s-%d" % [id, seed_i])
			var n: int = Buildings.build(id, ctx, rng).parts.size()
			worst_lo = mini(worst_lo, n)
			worst_hi = maxi(worst_hi, n)
		TestBase.check(worst_lo >= lo and worst_hi <= hi, "%s part count %d..%d within %d..%d" % [id, worst_lo, worst_hi, lo, hi])

func test_anchors_and_special_parts() -> void:
	var ctx := BuildContext.new()
	var rng := Rng.new(3)
	for id in ["farmhouse", "barn", "church", "watchtower", "tavern", "windmill", "powderstore"]:
		var res: BuildResult = Buildings.build(id, ctx, rng)
		var anchors: int = 0
		for p in res.parts:
			if p.anchor:
				anchors += 1
		TestBase.check(anchors > 0, "%s has anchored foundation parts" % id)
	var church: BuildResult = Buildings.build("church", ctx, rng)
	var bells: int = 0
	for p in church.parts:
		if p.tag == "bell":
			bells += 1
	TestBase.eq(bells, 1, "church contains exactly one bell")
	var ps: BuildResult = Buildings.build("powderstore", ctx, rng)
	var kegs: int = 0
	for e in ps.extras:
		if str((e as Dictionary).get("prop", "")) == "barrel_powder":
			kegs += 1
	TestBase.eq(kegs, 6, "powder store holds six kegs")
	var pal: BuildResult = Buildings.build("palisade", ctx, rng)
	TestBase.eq(pal.parts.size(), 6, "palisade segment has exactly six logs")
