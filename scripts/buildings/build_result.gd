class_name BuildResult
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Output of a building builder: parts + extras (props to spawn, special markers).

var parts: Array[PartDef] = []
var extras: Array = []                  # [{kind: String, pos: Vector3, rot: float, ...}]
var footprint_radius: float = 3.0
var height: float = 4.0

func add(p: PartDef) -> PartDef:
	parts.append(p)
	return p

func extra(kind: String, pos: Vector3, data: Dictionary = {}) -> void:
	var d: Dictionary = data.duplicate()
	d["kind"] = kind
	d["pos"] = pos
	extras.append(d)
