class_name BFlagpole
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Flagpole of a village: tall pole on a stone plinth with a big flag in the team colour (visible from far away).

const DEF := {"id": "flagpole", "footprint_radius": 1.6, "prop_hints": [], "name_key": "building.flagpole"}
const POLE_H := 10.0

static func build(ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 1.2
	Kit.box(r, "stone", Vector3(1.1, 0.5, 1.1), Vector3(0, 0.25, 0), rng, Color("#8a9096"), true, "plinth")
	Kit.cyl(r, "wood", 0.13, POLE_H, Vector3(0, 0.5 + POLE_H * 0.5, 0), rng, Color("#e8dcc0"), false, "pole")
	Kit.sph(r, "metal", 0.2, Vector3(0, 0.5 + POLE_H + 0.12, 0), rng, Color("#d9b24a"), "finial")
	# a stripe of the team colour on the plinth
	Kit.box(r, "cloth", Vector3(1.14, 0.12, 1.14), Vector3(0, 0.38, 0), rng, ctx.player_color, false, "accent")
	r.extra("flag", Vector3(0.14, 0.5 + POLE_H - 0.1, 0), {"color": ctx.player_color, "scale": 2.4})
	r.height = POLE_H + 0.8
	return r
