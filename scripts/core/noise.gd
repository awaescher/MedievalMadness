class_name VNoise
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Own 2D value noise + fbm (no FastNoiseLite so results are identical on all platforms).

static func _hash(ix: int, iy: int, seed_value: int) -> float:
	var h: int = (ix * 374761393 + iy * 668265263 + seed_value * 2147483647) & 0xFFFFFFFF
	h = Rng.imul(h ^ (h >> 13), 1274126177)
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0

static func value2(x: float, y: float, seed_value: int) -> float:
	var ix: int = floori(x)
	var iy: int = floori(y)
	var fx: float = x - float(ix)
	var fy: float = y - float(iy)
	var ux: float = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	var uy: float = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
	var a: float = _hash(ix, iy, seed_value)
	var b: float = _hash(ix + 1, iy, seed_value)
	var c: float = _hash(ix, iy + 1, seed_value)
	var d: float = _hash(ix + 1, iy + 1, seed_value)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)

## fbm in [0, 1)
static func fbm(x: float, y: float, seed_value: int, octaves: int = 4, base_freq: float = 1.0) -> float:
	var sum: float = 0.0
	var amp: float = 0.5
	var freq: float = base_freq
	var norm: float = 0.0
	for o in octaves:
		sum += value2(x * freq, y * freq, seed_value + o * 101) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.0
	return sum / norm
