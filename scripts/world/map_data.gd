class_name MapData
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Result of map generation (pure data, no scene nodes -> testable headless).

var seed_str: String = ""
var seed_int: int = 0
var player_count: int = 2
var map_radius: float = 88.0
var side: float = 216.0
var n: int = 109              # vertices per side
var cell: float = 2.0
var origin: float = -108.0    # min corner (x and z)
var heights: PackedFloat32Array = PackedFloat32Array()
var sites: Array[Vector3] = []          # village centers (y = ground height)
var rivers: Array = []                   # [{pts, ws, width, depth, bank, prof, dry, is_dry, kind, bb}]
var lakes: Array = []                    # [{c, r, depth, bank, prof, rot, sx, wob, reach}]
var center_kind: String = "ruin"         # "ruin" | "lake"
var center: Vector3 = Vector3.ZERO
var duck_pos: Vector3 = Vector3.INF      # rubber duck spot (water), INF if none

func idx(ix: int, iz: int) -> int:
	return iz * n + ix

func height_at(x: float, z: float) -> float:
	var fx: float = (x - origin) / cell
	var fz: float = (z - origin) / cell
	var ix: int = clampi(floori(fx), 0, n - 2)
	var iz: int = clampi(floori(fz), 0, n - 2)
	var tx: float = clampf(fx - float(ix), 0.0, 1.0)
	var tz: float = clampf(fz - float(iz), 0.0, 1.0)
	var h00: float = heights[iz * n + ix]
	var h10: float = heights[iz * n + ix + 1]
	var h01: float = heights[(iz + 1) * n + ix]
	var h11: float = heights[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func normal_at(x: float, z: float) -> Vector3:
	var e: float = cell * 0.5
	var hx: float = height_at(x + e, z) - height_at(x - e, z)
	var hz: float = height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

func slope_deg_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))

func in_bounds(x: float, z: float) -> bool:
	var lim: float = absf(origin) - cell
	return absf(x) < lim and absf(z) < lim

## Deterministic hash of the whole heightmap (quantized to 1 mm) for the same-seed test.
func heights_hash() -> int:
	var h: int = 0x811c9dc5
	for i in heights.size():
		var q: int = int(roundf(heights[i] * 1000.0))
		h = h ^ (q & 0xFFFF)
		h = (h * 0x01000193) & 0xFFFFFFFF
		h = h ^ ((q >> 16) & 0xFFFF)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h
