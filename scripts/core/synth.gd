class_name Synth
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Sound-synthesis kit (spec 17), v2: band-limited oscillators, FM, modal (bell / metal / wood) resonators,
## Karplus-Strong plucked strings, vocal formant source, RBJ biquads (static + swept), Freeverb-style reverb, echo,
## soft saturation and seamless loops. Everything is deterministic; output is 16-bit mono 32 kHz.

const SR := 32000
const SINE := 0
const SQUARE := 1
const SAW := 2
const TRI := 3
const WHITE := 0
const PINK := 1
const BROWN := 2

static func make(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(int(seconds * float(SR)), 1))
	return b

# ------------------------------------------------------------------ oscillators
## Oscillator with exponential pitch sweep (f0 -> f1), vibrato, tremolo and exponential decay; ADDS into buf.
## Saw / square are made with a soft polyBLEP so they do not alias into harsh digital noise.
static func osc(buf: PackedFloat32Array, wave: int, f0: float, f1: float, t0: float, dur: float, amp: float, decay: float = 6.0, vib_hz: float = 0.0, vib_depth: float = 0.0, attack: float = 0.004, trem_hz: float = 0.0, trem_depth: float = 0.0) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = int(dur * float(SR))
	var phase: float = 0.0
	var inv_sr: float = 1.0 / float(SR)
	var ratio: float = f1 / maxf(f0, 1.0)
	var tri_state: float = 0.0
	for i in n:
		var idx: int = start + i
		if idx >= buf.size():
			break
		var t: float = float(i) * inv_sr
		var u: float = float(i) / float(maxi(n - 1, 1))
		var f: float = f0 * pow(ratio, u)
		if vib_hz > 0.0:
			f *= 1.0 + sin(TAU * vib_hz * t) * vib_depth
		var dt: float = f * inv_sr
		phase += dt
		phase -= floorf(phase)
		var s: float
		match wave:
			SQUARE:
				s = (1.0 if phase < 0.5 else -1.0) + _blep(phase, dt) - _blep(fposmod(phase + 0.5, 1.0), dt)
			SAW:
				s = (phase * 2.0 - 1.0) - _blep(phase, dt)
			TRI:
				var sq: float = (1.0 if phase < 0.5 else -1.0) + _blep(phase, dt) - _blep(fposmod(phase + 0.5, 1.0), dt)
				tri_state += 4.0 * dt * sq
				tri_state *= 0.9995
				s = tri_state
			_:
				s = sin(TAU * phase)
		var env: float = exp(-decay * t)
		if t < attack:
			env *= t / attack
		if trem_hz > 0.0:
			env *= 1.0 - trem_depth + trem_depth * (0.5 + 0.5 * sin(TAU * trem_hz * t))
		buf[idx] += s * amp * env

static func _blep(t: float, dt: float) -> float:
	if t < dt:
		var x: float = t / dt
		return x + x - x * x - 1.0
	elif t > 1.0 - dt:
		var x2: float = (t - 1.0) / dt
		return x2 * x2 + x2 + x2 + 1.0
	return 0.0

## Frequency modulation: carrier fc, modulator fc*ratio, modulation index sliding idx0 -> idx1; ADDS into buf.
static func fm(buf: PackedFloat32Array, fc: float, ratio: float, idx0: float, idx1: float, t0: float, dur: float, amp: float, decay: float = 5.0, attack: float = 0.002, f_end: float = -1.0) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = int(dur * float(SR))
	var inv: float = 1.0 / float(SR)
	var ph_c: float = 0.0
	var ph_m: float = 0.0
	var fend: float = fc if f_end < 0.0 else f_end
	for i in n:
		var idx: int = start + i
		if idx >= buf.size():
			break
		var t: float = float(i) * inv
		var u: float = float(i) / float(maxi(n - 1, 1))
		var f: float = fc * pow(fend / maxf(fc, 1.0), u)
		ph_m += f * ratio * inv
		var index: float = lerpf(idx0, idx1, u)
		ph_c += f * inv + index * sin(TAU * ph_m) * f * ratio * inv
		var env: float = exp(-decay * t)
		if t < attack:
			env *= t / attack
		buf[idx] += sin(TAU * ph_c) * amp * env

## Modal resonator bank: a struck bell / metal bar / glass / wood block. `partials` = [[ratio, amp, decay], ...]
static func modal(buf: PackedFloat32Array, f0: float, partials: Array, t0: float, amp: float, decay_mul: float = 1.0, detune: float = 0.0) -> void:
	var start: int = int(t0 * float(SR))
	var inv: float = 1.0 / float(SR)
	for pr in partials:
		var p: Array = pr as Array
		var f: float = f0 * float(p[0])
		var a: float = float(p[1]) * amp
		var dec: float = float(p[2]) * decay_mul
		var n: int = mini(int(minf(7.0 / maxf(dec, 0.1), 6.0) * float(SR)), buf.size() - start)
		var ph: float = 0.0
		var f2: float = f * (1.0 + detune)
		for i in n:
			var t: float = float(i) * inv
			ph += f * inv
			var s: float = sin(TAU * ph)
			if detune != 0.0:
				s = 0.5 * s + 0.5 * sin(TAU * f2 * t)
			var env: float = exp(-dec * t)
			if t < 0.0008:
				env *= t / 0.0008
			buf[start + i] += s * a * env

## Karplus-Strong plucked string / twang: a burst of noise circulating through a damped delay line
static func pluck(buf: PackedFloat32Array, freq: float, t0: float, dur: float, amp: float, damping: float, r: Rng, glide: float = 1.0) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = mini(int(dur * float(SR)), buf.size() - start)
	var period: int = maxi(int(float(SR) / freq), 4)
	var line := PackedFloat32Array()
	line.resize(period)
	for i in period:
		line[i] = r.next_f() * 2.0 - 1.0
	var pos: int = 0
	var prev: float = 0.0
	for i in n:
		var cur: float = line[pos]
		var nxt: float = line[(pos + 1) % period]
		var v: float = (cur + nxt) * 0.5 * damping
		line[pos] = v
		pos = (pos + 1) % period
		prev = v
		buf[start + i] += prev * amp
	# optional pitch droop is applied by the caller via `glide` (kept for API symmetry)
	if glide != 1.0:
		pass

# ------------------------------------------------------------------ noise
static func gen_noise(seconds: float, kind: int, r: Rng) -> PackedFloat32Array:
	var b: PackedFloat32Array = make(seconds)
	var b0: float = 0.0
	var b1: float = 0.0
	var b2: float = 0.0
	var brown: float = 0.0
	for i in b.size():
		var w: float = r.next_f() * 2.0 - 1.0
		match kind:
			PINK:
				b0 = 0.99765 * b0 + w * 0.0990460
				b1 = 0.96300 * b1 + w * 0.2965164
				b2 = 0.57000 * b2 + w * 1.0526913
				b[i] = (b0 + b1 + b2 + w * 0.1848) * 0.25
			BROWN:
				brown = (brown + 0.02 * w) / 1.02
				b[i] = brown * 3.5
			_:
				b[i] = w
	return b

## Filtered noise burst (kept from v1 for simple cases); ADDS into buf.
static func noise(buf: PackedFloat32Array, kind: int, t0: float, dur: float, amp: float, decay: float, lp0: float, lp1: float, hp: float, r: Rng, attack: float = 0.002) -> void:
	var seg: PackedFloat32Array = gen_noise(dur, kind, r)
	# two cascaded one-pole low passes (12 dB/oct) with a cutoff sweep, then an optional high pass
	var inv: float = 1.0 / float(SR)
	var ratio: float = lp1 / maxf(lp0, 1.0)
	var y1: float = 0.0
	var y2: float = 0.0
	var hz: float = 0.0
	var hp_a: float = 1.0 - exp(-TAU * maxf(hp, 1.0) * inv)
	var n: int = seg.size()
	var start: int = int(t0 * float(SR))
	for i in n:
		var idx: int = start + i
		if idx >= buf.size():
			break
		var t: float = float(i) * inv
		var u: float = float(i) / float(maxi(n - 1, 1))
		var fc: float = lp0 * pow(ratio, u)
		var a: float = 1.0 - exp(-TAU * fc * inv)
		y1 += a * (seg[i] - y1)
		y2 += a * (y1 - y2)
		var y: float = y2
		if hp > 0.0:
			hz += hp_a * (y - hz)
			y -= hz
		var env: float = exp(-decay * t)
		if t < attack:
			env *= t / attack
		buf[idx] += y * amp * env

# ------------------------------------------------------------------ filters (RBJ biquad)
## In-place biquad. type: "lp", "hp", "bp" (constant 0 dB peak), "notch", "peak", "lowshelf", "highshelf"
static func biquad(buf: PackedFloat32Array, type: String, f: float, q: float = 0.707, gain_db: float = 0.0) -> void:
	var c: Array = _coeffs(type, f, q, gain_db)
	var b0: float = c[0]
	var b1: float = c[1]
	var b2: float = c[2]
	var a1: float = c[3]
	var a2: float = c[4]
	var x1: float = 0.0
	var x2: float = 0.0
	var y1: float = 0.0
	var y2: float = 0.0
	for i in buf.size():
		var x: float = buf[i]
		var y: float = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[i] = y

## Biquad whose cutoff sweeps exponentially f0 -> f1 over [t0, t0 + dur] (coefficients refreshed every 24 samples)
static func biquad_sweep(buf: PackedFloat32Array, type: String, f0: float, f1: float, q: float, t0: float = 0.0, dur: float = -1.0) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = buf.size() - start if dur < 0.0 else mini(int(dur * float(SR)), buf.size() - start)
	var x1: float = 0.0
	var x2: float = 0.0
	var y1: float = 0.0
	var y2: float = 0.0
	var b0: float = 0.0
	var b1: float = 0.0
	var b2: float = 0.0
	var a1: float = 0.0
	var a2: float = 0.0
	var ratio: float = f1 / maxf(f0, 1.0)
	for i in n:
		if i % 24 == 0:
			var u: float = float(i) / float(maxi(n - 1, 1))
			var c: Array = _coeffs(type, clampf(f0 * pow(ratio, u), 20.0, float(SR) * 0.45), q, 0.0)
			b0 = c[0]
			b1 = c[1]
			b2 = c[2]
			a1 = c[3]
			a2 = c[4]
		var x: float = buf[start + i]
		var y: float = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[start + i] = y

static func _coeffs(type: String, f: float, q: float, gain_db: float) -> Array:
	var fc: float = clampf(f, 20.0, float(SR) * 0.45)
	var w0: float = TAU * fc / float(SR)
	var cw: float = cos(w0)
	var sw: float = sin(w0)
	var alpha: float = sw / (2.0 * maxf(q, 0.05))
	var a: float = pow(10.0, gain_db / 40.0)
	var b0: float = 1.0
	var b1: float = 0.0
	var b2: float = 0.0
	var a0: float = 1.0
	var a1: float = 0.0
	var a2: float = 0.0
	match type:
		"hp":
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = (1.0 + cw) * 0.5
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		"bp":
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		"notch":
			b0 = 1.0
			b1 = -2.0 * cw
			b2 = 1.0
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		"peak":
			b0 = 1.0 + alpha * a
			b1 = -2.0 * cw
			b2 = 1.0 - alpha * a
			a0 = 1.0 + alpha / a
			a1 = -2.0 * cw
			a2 = 1.0 - alpha / a
		"lowshelf":
			var sq: float = 2.0 * sqrt(a) * alpha
			b0 = a * ((a + 1.0) - (a - 1.0) * cw + sq)
			b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cw)
			b2 = a * ((a + 1.0) - (a - 1.0) * cw - sq)
			a0 = (a + 1.0) + (a - 1.0) * cw + sq
			a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cw)
			a2 = (a + 1.0) + (a - 1.0) * cw - sq
		"highshelf":
			var sq2: float = 2.0 * sqrt(a) * alpha
			b0 = a * ((a + 1.0) + (a - 1.0) * cw + sq2)
			b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cw)
			b2 = a * ((a + 1.0) + (a - 1.0) * cw - sq2)
			a0 = (a + 1.0) - (a - 1.0) * cw + sq2
			a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cw)
			a2 = (a + 1.0) - (a - 1.0) * cw - sq2
		_:
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = (1.0 - cw) * 0.5
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
	return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]

## Parallel band-pass resonators (formants); replaces buf with (dry * buf + wet * sum of bands)
static func formants(buf: PackedFloat32Array, freqs: Array, q: float, wet: float, dry: float) -> void:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] * dry
	for fr in freqs:
		var tmp: PackedFloat32Array = buf.duplicate()
		biquad(tmp, "bp", float(fr), q)
		for i in buf.size():
			out[i] += tmp[i] * wet
	for i in buf.size():
		buf[i] = out[i]

static func lowpass(buf: PackedFloat32Array, fc: float) -> void:
	biquad(buf, "lp", fc, 0.707)

static func highpass(buf: PackedFloat32Array, fc: float) -> void:
	biquad(buf, "hp", fc, 0.707)

# ------------------------------------------------------------------ voices
## A vocal-ish voice: band-limited saw glottal source (f0 glides f_a -> f_b) with vibrato, breath noise and a bank of
## formant resonators whose centres glide from `forms_a` to `forms_b` ([[freq, gain], ...]). ADDS into buf.
static func voice(buf: PackedFloat32Array, f_a: float, f_b: float, t0: float, dur: float, amp: float, forms_a: Array, forms_b: Array, r: Rng, vib_hz: float = 5.0, vib_depth: float = 0.02, breath: float = 0.05, attack: float = 0.03, release: float = 0.08, tremolo_hz: float = 0.0, tremolo_depth: float = 0.0, q: float = 6.0) -> void:
	var n: int = int(dur * float(SR))
	var src := make(dur)
	var inv: float = 1.0 / float(SR)
	var phase: float = 0.0
	var ratio: float = f_b / maxf(f_a, 1.0)
	for i in n:
		var t: float = float(i) * inv
		var u: float = float(i) / float(maxi(n - 1, 1))
		var f: float = f_a * pow(ratio, u) * (1.0 + sin(TAU * vib_hz * t) * vib_depth)
		var dt: float = f * inv
		phase += dt
		phase -= floorf(phase)
		var s: float = (phase * 2.0 - 1.0) - _blep(phase, dt)
		s += (r.next_f() * 2.0 - 1.0) * breath
		var env: float = 1.0
		if t < attack:
			env = t / attack
		var to_end: float = dur - t
		if to_end < release:
			env *= maxf(to_end / release, 0.0)
		if tremolo_hz > 0.0:
			env *= 1.0 - tremolo_depth + tremolo_depth * (0.5 + 0.5 * sin(TAU * tremolo_hz * t))
		src[i] = s * env
	var out := make(dur)
	for k in forms_a.size():
		var fa: Array = forms_a[k] as Array
		var fb: Array = forms_b[mini(k, forms_b.size() - 1)] as Array
		var band: PackedFloat32Array = src.duplicate()
		biquad_sweep(band, "bp", float(fa[0]), float(fb[0]), q)
		var g: float = lerpf(float(fa[1]), float(fb[1]), 0.5)
		for i in n:
			out[i] += band[i] * g
	var start: int = int(t0 * float(SR))
	for i in n:
		if start + i >= buf.size():
			break
		buf[start + i] += out[i] * amp

# ------------------------------------------------------------------ animal / vocal tract
static func _pt(pts: Array, u: float) -> float:
	if u <= float((pts[0] as Array)[0]):
		return float((pts[0] as Array)[1])
	for i in range(1, pts.size()):
		var b: Array = pts[i] as Array
		if u <= float(b[0]):
			var a: Array = pts[i - 1] as Array
			var k: float = (u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			k = k * k * (3.0 - 2.0 * k)
			return lerpf(float(a[1]), float(b[1]), k)
	return float((pts[pts.size() - 1] as Array)[1])

## A more natural voice: glottal source with a pitch contour (control points [[u, hz], ...] over u = 0..1), random
## jitter / shimmer, optional vocal fry (subharmonic) and tremolo, driving a bank of time-varying 2-pole formant
## resonators. `forms` = [[[[u, hz], ...], bandwidth_hz, gain], ...]; `amp_pts` = [[u, level], ...].
## opts: jitter, shimmer, breath, vib_hz, vib_depth, trem_hz, trem_depth, fry (0..1 strength), fry_from (u), tilt (Hz
## low-pass on the source, 0 = bright/buzzy), drive (soft clip). ADDS into buf at t0.
static func vocal(buf: PackedFloat32Array, t0: float, dur: float, amp: float, f0_pts: Array, forms: Array, amp_pts: Array, r: Rng, opts: Dictionary = {}) -> void:
	var n: int = int(dur * float(SR))
	if n < 8:
		return
	var jitter: float = float(opts.get("jitter", 0.01))
	var shimmer: float = float(opts.get("shimmer", 0.08))
	var breath: float = float(opts.get("breath", 0.03))
	var vib_hz: float = float(opts.get("vib_hz", 0.0))
	var vib_depth: float = float(opts.get("vib_depth", 0.0))
	var trem_hz: float = float(opts.get("trem_hz", 0.0))
	var trem_depth: float = float(opts.get("trem_depth", 0.0))
	var fry: float = float(opts.get("fry", 0.0))
	var fry_from: float = float(opts.get("fry_from", 0.8))
	var tilt: float = float(opts.get("tilt", 2500.0))
	var drive: float = float(opts.get("drive", 0.0))
	var inv: float = 1.0 / float(SR)
	var tilt_a: float = 1.0 if tilt <= 0.0 else 1.0 - exp(-TAU * tilt * inv)
	var src := PackedFloat32Array()
	src.resize(n)
	var phase: float = 0.0
	var jn: float = 0.0
	var sn: float = 0.0
	var lp: float = 0.0
	var alt: bool = false
	for i in n:
		var t: float = float(i) * inv
		var u: float = float(i) / float(maxi(n - 1, 1))
		jn = lerpf(jn, r.next_f() * 2.0 - 1.0, 0.003)
		sn = lerpf(sn, r.next_f() * 2.0 - 1.0, 0.003)
		var f: float = _pt(f0_pts, u) * (1.0 + jn * jitter * 40.0)
		if vib_hz > 0.0:
			f *= 1.0 + sin(TAU * vib_hz * t) * vib_depth
		var dt: float = clampf(f * inv, 0.0001, 0.45)
		phase += dt
		var a_pulse: float = 1.0
		if phase >= 1.0:
			phase -= 1.0
			alt = not alt
		if fry > 0.0 and u >= fry_from and alt:
			a_pulse = 1.0 - 0.65 * fry * clampf((u - fry_from) / maxf(1.0 - fry_from, 0.01) + 0.3, 0.0, 1.0)
		var sv: float = (phase * 2.0 - 1.0) - _blep(phase, dt)
		if tilt > 0.0:
			lp += tilt_a * (sv - lp)
			sv = lp * 1.6
		var env: float = _pt(amp_pts, u) * maxf(0.0, 1.0 + sn * shimmer * 30.0) * a_pulse
		if trem_hz > 0.0:
			env *= 1.0 - trem_depth + trem_depth * (0.5 + 0.5 * sin(TAU * trem_hz * t))
		sv += (r.next_f() * 2.0 - 1.0) * breath
		src[i] = sv * env
	var out := PackedFloat32Array()
	out.resize(n)
	for fm in forms:
		var fpts: Array = (fm as Array)[0] as Array
		var bw: float = float((fm as Array)[1])
		var gain: float = float((fm as Array)[2])
		var y1: float = 0.0
		var y2: float = 0.0
		var b1: float = 0.0
		var b2: float = 0.0
		var ga: float = 0.0
		for i in n:
			if i % 16 == 0:
				var fc: float = _pt(fpts, float(i) / float(maxi(n - 1, 1)))
				var rr: float = exp(-PI * bw * inv)
				b1 = 2.0 * rr * cos(TAU * fc * inv)
				b2 = -rr * rr
				ga = (1.0 - rr) * 2.2
			var y: float = ga * src[i] + b1 * y1 + b2 * y2
			y2 = y1
			y1 = y
			out[i] += y * gain
	if drive > 0.0:
		for i in n:
			out[i] = tanh(out[i] * drive) / tanh(drive)
	var start: int = int(t0 * float(SR))
	for i in n:
		if start + i >= buf.size():
			break
		buf[start + i] += out[i] * amp

# ------------------------------------------------------------------ space / dynamics
## Freeverb-style mono reverb (4 damped combs + 2 allpass). Mixes the tail into the buffer; give the buffer a long
## enough tail beforehand.
static func reverb(buf: PackedFloat32Array, room: float = 0.6, damp: float = 0.35, wet: float = 0.25) -> void:
	var comb_len: Array[int] = [1116, 1188, 1277, 1356]
	var scale: float = float(SR) / 44100.0
	var dry: PackedFloat32Array = buf.duplicate()
	var acc := PackedFloat32Array()
	acc.resize(buf.size())
	var feedback: float = 0.7 + room * 0.28
	for cl in comb_len:
		var len_c: int = maxi(int(float(cl) * scale), 8)
		var line := PackedFloat32Array()
		line.resize(len_c)
		var pos: int = 0
		var store: float = 0.0
		for i in buf.size():
			var out: float = line[pos]
			store = out * (1.0 - damp) + store * damp
			line[pos] = dry[i] * 0.25 + store * feedback
			pos += 1
			if pos >= len_c:
				pos = 0
			acc[i] += out
	for ap in [556, 441]:
		var len_a: int = maxi(int(float(ap) * scale), 8)
		var aline := PackedFloat32Array()
		aline.resize(len_a)
		var apos: int = 0
		for i in buf.size():
			var bufout: float = aline[apos]
			var inp: float = acc[i]
			aline[apos] = inp + bufout * 0.5
			acc[i] = bufout - inp
			apos += 1
			if apos >= len_a:
				apos = 0
	for i in buf.size():
		buf[i] = dry[i] + acc[i] * wet

static func echo(buf: PackedFloat32Array, delay_s: float, feedback: float, mix: float) -> void:
	var d: int = maxi(int(delay_s * float(SR)), 1)
	var dry: PackedFloat32Array = buf.duplicate()
	var y := PackedFloat32Array()
	y.resize(buf.size())
	for i in buf.size():
		y[i] = dry[i] + (y[i - d] * feedback if i >= d else 0.0)
	for i in buf.size():
		buf[i] = dry[i] + (y[i] - dry[i]) * mix

## Soft saturation (tanh-like)
static func saturate(buf: PackedFloat32Array, drive: float) -> void:
	var norm: float = 1.0 / tanh(maxf(drive, 0.01))
	for i in buf.size():
		buf[i] = tanh(buf[i] * drive) * norm

static func distort(buf: PackedFloat32Array, amount: float) -> void:
	saturate(buf, 1.0 + amount)

## Multiplies a region with an attack/decay envelope (for shaping mixed layers)
static func envelope(buf: PackedFloat32Array, t0: float, attack: float, decay: float, t1: float = -1.0) -> void:
	var start: int = int(t0 * float(SR))
	var end: int = buf.size() if t1 < 0.0 else mini(int(t1 * float(SR)), buf.size())
	var inv: float = 1.0 / float(SR)
	for i in range(start, end):
		var t: float = float(i - start) * inv
		var e: float = exp(-decay * t)
		if t < attack:
			e *= t / maxf(attack, 0.00001)
		buf[i] *= e

## Amplitude curve: multiplies the buffer by a piecewise-linear curve [[t, gain], ...]
static func curve(buf: PackedFloat32Array, points: Array) -> void:
	var seg: int = 0
	for i in buf.size():
		var t: float = float(i) / float(SR)
		while seg < points.size() - 2 and t > float((points[seg + 1] as Array)[0]):
			seg += 1
		var a: Array = points[seg] as Array
		var b: Array = points[mini(seg + 1, points.size() - 1)] as Array
		var span: float = maxf(float(b[0]) - float(a[0]), 0.00001)
		var u: float = clampf((t - float(a[0])) / span, 0.0, 1.0)
		buf[i] *= lerpf(float(a[1]), float(b[1]), u)

## Seamless loop: cross-fade the tail into the head (equal power) and drop the tail
static func loopify(buf: PackedFloat32Array, xfade_s: float = 0.25) -> PackedFloat32Array:
	var x: int = mini(int(xfade_s * float(SR)), buf.size() / 3)
	var n: int = buf.size() - x
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = buf[i]
	for i in x:
		var u: float = float(i) / float(x)
		out[i] = buf[i] * sin(u * PI * 0.5) + buf[n + i] * cos(u * PI * 0.5)
	return out

static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float, offset_t: float = 0.0) -> void:
	var off: int = int(offset_t * float(SR))
	for i in src.size():
		var idx: int = off + i
		if idx >= dst.size():
			break
		dst[idx] += src[i] * gain

static func fade_out(buf: PackedFloat32Array, seconds: float = 0.01) -> void:
	var n: int = mini(int(seconds * float(SR)), buf.size())
	for i in n:
		var idx: int = buf.size() - 1 - i
		buf[idx] *= float(i) / float(maxi(n, 1))

static func fade_in(buf: PackedFloat32Array, seconds: float = 0.002) -> void:
	var n: int = mini(int(seconds * float(SR)), buf.size())
	for i in n:
		buf[i] *= float(i) / float(maxi(n, 1))

static func normalize(buf: PackedFloat32Array, peak: float = 0.85) -> void:
	var m: float = 0.0001
	for i in buf.size():
		m = maxf(m, absf(buf[i]))
	var g: float = peak / m
	for i in buf.size():
		buf[i] *= g

## Removes DC offset and sub-audible rumble
static func dc_block(buf: PackedFloat32Array) -> void:
	var x1: float = 0.0
	var y1: float = 0.0
	for i in buf.size():
		var x: float = buf[i]
		var y: float = x - x1 + 0.995 * y1
		x1 = x
		y1 = y
		buf[i] = y

## Build a 16-bit mono AudioStreamWAV
static func to_stream(buf: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var v: int = clampi(int(buf[i] * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = data
	if looped:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s
