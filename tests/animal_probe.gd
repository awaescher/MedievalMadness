extends SceneTree
## Dev tool: prints the pitch track (autocorrelation) and the strongest spectral peaks of the animal sounds.
func _f0(b: PackedFloat32Array, at: int, win: int, fmin: float, fmax: float) -> float:
	var best: float = 0.0
	var best_lag: int = 0
	var lmin: int = int(float(Synth.SR) / fmax)
	var lmax: int = int(float(Synth.SR) / fmin)
	if at + win + lmax >= b.size():
		return 0.0
	var e0: float = 0.0
	for i in win:
		e0 += b[at + i] * b[at + i]
	if e0 < 0.5:
		return 0.0
	for lag in range(lmin, lmax):
		var c: float = 0.0
		for i in win:
			c += b[at + i] * b[at + i + lag]
		if c > best:
			best = c
			best_lag = lag
	return float(Synth.SR) / float(maxi(best_lag, 1)) if best > 0.3 * e0 else 0.0

func _peaks(b: PackedFloat32Array, at: int) -> String:
	var n: int = 2048
	var mags: Array = []
	for k in range(5, 160):
		var f: float = float(k) * 25.0
		var re: float = 0.0
		var im: float = 0.0
		for i in n:
			var w: float = 0.5 - 0.5 * cos(TAU * float(i) / float(n))
			var x: float = b[at + i] * w
			re += x * cos(TAU * f * float(i) / float(Synth.SR))
			im -= x * sin(TAU * f * float(i) / float(Synth.SR))
		mags.append([sqrt(re * re + im * im), f])
	var out: Array = []
	for k in range(1, mags.size() - 1):
		if (mags[k] as Array)[0] > (mags[k - 1] as Array)[0] and (mags[k] as Array)[0] > (mags[k + 1] as Array)[0]:
			out.append(mags[k])
	out.sort_custom(func(a: Array, c: Array) -> bool: return a[0] > c[0])
	var s: String = ""
	for k in mini(5, out.size()):
		s += "%d " % int((out[k] as Array)[1])
	return s

func _init() -> void:
	for nm in ["moo", "baa", "bawk", "neigh", "quack", "honk"]:
		for v in 2:
			var b: PackedFloat32Array = SoundRecipes.make(nm, v)
			var line: String = "%-6s v%d %.2fs f0:" % [nm, v, float(b.size()) / float(Synth.SR)]
			var step: int = int(float(b.size()) / 12.0)
			for k in 11:
				var at: int = k * step
				line += " %d" % int(_f0(b, at, 1400, 70.0, 1700.0))
			print(line)
			var mid: int = int(float(b.size()) * 0.3)
			print("        peaks at 30%%: %s" % _peaks(b, mid))
	quit()
