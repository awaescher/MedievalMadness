extends SceneTree
## Dev tool: synthesizes every sound and prints duration / peak / RMS / synthesis time / low-mid-high energy split.
func _init() -> void:
	var total_ms: int = 0
	for n in SoundRecipes.NAMES:
		var t0: int = Time.get_ticks_msec()
		var b: PackedFloat32Array = SoundRecipes.make(n, 0)
		var ms: int = Time.get_ticks_msec() - t0
		total_ms += ms
		var peak: float = 0.0
		var sum: float = 0.0
		var bad: int = 0
		for x in b:
			if is_nan(x) or is_inf(x):
				bad += 1
				continue
			peak = maxf(peak, absf(x))
			sum += x * x
		var rms: float = sqrt(sum / float(maxi(b.size(), 1)))
		# rough spectrum split with two one-pole filters: low < 300 Hz, high > 3 kHz
		var lo: float = 0.0
		var lo_e: float = 0.0
		var hi_e: float = 0.0
		var a_lo: float = 1.0 - exp(-TAU * 300.0 / float(Synth.SR))
		var a_hi: float = 1.0 - exp(-TAU * 3000.0 / float(Synth.SR))
		var lp_hi: float = 0.0
		for x2 in b:
			lo += a_lo * (x2 - lo)
			lp_hi += a_hi * (x2 - lp_hi)
			lo_e += lo * lo
			hi_e += (x2 - lp_hi) * (x2 - lp_hi)
		var tot: float = maxf(sum, 0.000001)
		print("%-14s %5.2fs peak %.2f rms %.3f  low %2d%% high %2d%%  nan %d  [%d ms]" % [n, float(b.size()) / float(Synth.SR), peak, rms, int(100.0 * lo_e / tot), int(100.0 * hi_e / tot), bad, ms])
	print("total synthesis (variant 0 only): %d ms" % total_ms)
	quit()
