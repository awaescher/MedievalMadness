class_name Structure
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## A building / big prop / tree (spec 5.2): dormant (merged mesh + one static compound collider)
## or awake (individual part bodies, static-frozen until released by the glue/support rules).

var id: int = 0
var kind: String = "farmhouse"
var owner_id: int = -1
var parts: Array[Part] = []
var center: Vector3 = Vector3.ZERO
var radius: float = 4.0
var height: float = 4.0
var aabb: AABB = AABB()
var awake: bool = false
var root: Node3D
var dormant_body: int = 0
var dormant_mesh: MeshInstance3D
var dormant_extra: Array[MeshInstance3D] = []
var dormant_shape_parts: Array[Part] = []
var live_count: int = 0
var initial_count: int = 0
var initial_hp: float = 0.0
var destroyed: bool = false
var support_dirty: bool = false
var support_timer: float = 0.0
var last_source: Dictionary = {}
var last_source_time: float = -1000.0
var free_parts: bool = false          # props: bodies exist from the start, no glue/support logic
var shard_count: int = 0
var name_key: String = ""
var undermined: bool = false       # the ground under it gave way: the support check is much stricter (no cantilevers)
var extras: Array = []                # extra nodes / helper objects owned by this structure (flags, rotor...)
var behavior: RefCounted = null       # Specials.Behavior (hooks: on_hit, on_break, on_fire, tick, on_destroyed)
var tag_counts: Dictionary = {}
var last_hit_time: float = -1000.0
var is_decor: bool = false
var no_dormant_mesh: bool = false

func live_hp() -> float:
	var s: float = 0.0
	for p in parts:
		if p.state != Part.State.DEAD:
			s += p.hp
	return s

func live_parts() -> Array[Part]:
	var out: Array[Part] = []
	for p in parts:
		if p.state != Part.State.DEAD:
			out.append(p)
	return out

func destroyed_fraction() -> float:
	if initial_count <= 0:
		return 0.0
	return 1.0 - float(live_count) / float(initial_count)

## Position of the highest still-attached live part (for fx)
func top_pos() -> Vector3:
	var best: Vector3 = center
	var by: float = -1e9
	for p in parts:
		if p.state != Part.State.DEAD and p.xf.origin.y > by:
			by = p.xf.origin.y
			best = p.xf.origin
	return best

func has_tag(tag: String) -> bool:
	for p in parts:
		if p.state != Part.State.DEAD and p.tag == tag:
			return true
	return false

func parts_with_tag(tag: String) -> Array[Part]:
	var out: Array[Part] = []
	for p in parts:
		if p.state != Part.State.DEAD and p.tag == tag:
			out.append(p)
	return out
