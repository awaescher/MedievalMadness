class_name PartDef
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Blueprint of one part (spec 9). Position/rotation are relative to the building base.

var material: String = "wood"
var size: Vector3 = Vector3.ONE        # box: full extents | cyl: (diameter, height, diameter) | sphere: (d,d,d) | frustum: (bottom d, height, top d)
var pos: Vector3 = Vector3.ZERO
var rot: Vector3 = Vector3.ZERO        # euler radians (applied XYZ)
var shape: String = "box"              # box | cyl | sphere | frustum
var color: Color = Color(-1, -1, -1)   # r < 0 -> pick from material palette
var anchor: bool = false
var tag: String = ""
var glow: bool = false                 # emissive (forge coal etc.)
var segs: int = 12                     # radial segments for cyl / frustum
var mass_override: float = -1.0        # >0: use this mass instead of density x volume
var hp_override: float = -1.0          # >0: use this hp
var subs: Array[PartDef] = []          # compound: sub-shapes (pos/rot relative to the part), shape must be "compound"
var restitution_override: float = -1.0
var sub_glow_color: Color = Color(-1, -1, -1)

func xf() -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)
