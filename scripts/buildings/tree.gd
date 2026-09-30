class_name BTree
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Trees (spec 7.5): oak (trunk + sphere crown) and pine (trunk + 3 stacked cones). Dormant until something hits them;
## trunk is anchored, the crown burns and dies while the trunk stays.

const DEF := {"id": "tree", "footprint_radius": 1.2, "prop_hints": [], "name_key": "building.tree"}

static func build(_ctx: BuildContext, rng: Rng, opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	var pine: bool = bool(opts.get("pine", rng.chance(0.4)))
	var s: float = rng.range_f(0.8, 1.35)
	if pine:
		var th: float = 2.4 * s
		Kit.cyl(r, "wood", 0.2 * s, th, Vector3(0, th * 0.5, 0), rng, Color("#6a4a2a"), true, "trunk")
		var cols: Array[Color] = [Color("#2f7a3a"), Color("#2a6d34"), Color("#358a40")]
		for i in 3:
			var cy: float = th + (0.2 + float(i) * 1.15) * s
			var rb: float = (1.5 - float(i) * 0.4) * s
			var f := Kit.frustum(r, "leaf", rb, rb * 0.08, 1.6 * s, Vector3(0, cy + 0.6 * s, 0), rng, cols[i], false, "crown")
			f.segs = 8
			f.mass_override = 60.0 * s
		r.height = th + 4.2 * s
	else:
		var th2: float = 2.0 * s
		Kit.cyl(r, "wood", 0.26 * s, th2, Vector3(0, th2 * 0.5, 0), rng, Color("#7a5230"), true, "trunk")
		var crown := Kit.sph(r, "leaf", 1.7 * s, Vector3(0, th2 + 1.2 * s, 0), rng, Color("#3f9c3f") if rng.chance(0.7) else Color("#4caf50"), "crown")
		crown.mass_override = 120.0 * s
		var c2 := Kit.sph(r, "leaf", 1.0 * s, Vector3(0.9 * s, th2 + 0.6 * s, 0.3 * s), rng, Color("#3a9040"), "crown")
		c2.mass_override = 40.0 * s
		r.height = th2 + 3.0 * s
	r.footprint_radius = 1.4
	return r
