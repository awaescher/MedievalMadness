class_name BWindmill
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Windy Windmill (spec 9): 8-sided stone tower 8 m, wooden cap, 4 sails on a hinged rotor (see Specials.WindmillBehavior).

const DEF := {"id": "windmill", "footprint_radius": 4.0, "prop_hints": ["crate", "cart"], "name_key": "building.windmill"}

static func build(ctx: BuildContext, rng: Rng, _opts: Dictionary) -> BuildResult:
	var r := BuildResult.new()
	r.footprint_radius = 4.0
	var rad: float = 2.4
	# tower: 8 sides x 5 rows (door gap at +Z: angle where local +Z lies)
	# ring() places blocks at angle a: pos = (cos a, sin a) in (x, z); +Z is a = PI/2
	Kit.ring(r, "stone", Vector2.ZERO, rad, 0.0, 6.3, 0.5, 8, 0.9, rng, true, [Vector2(PI * 0.5, 0.5)], Color("#e8dcc0"), "tower")
	Kit.door(r, Vector2(0, rad), 0.0, 1.0, 2.0, 0.0, rng)
	# taper: upper narrower ring of 8 x 1 (belt)
	Kit.ring(r, "stone", Vector2.ZERO, rad - 0.3, 6.3, 1.4, 0.5, 8, 0.7, rng, false, [], Color("#d8ccb0"), "tower")
	# wooden cap: cone (frustum) with a small overhang
	var cap := Kit.frustum(r, "plank", 2.3, 0.15, 2.0, Vector3(0, 7.7 + 1.0, 0), rng, Color("#8a5a2a"), false, "cap")
	cap.segs = 8
	# hub (axle) sticking out at the front where the rotor is attached
	Kit.box(r, "metal", Vector3(0.3, 0.3, 0.9), Vector3(0, 6.9, rad + 0.05), rng, Color("#5c6672"), false, "hub")
	r.extra("rotor", Vector3(0, 6.9, rad + 0.6), {})
	r.extra("flag", Vector3(0, 9.9, 0), {"color": ctx.player_color})
	r.height = 10.0
	return r
