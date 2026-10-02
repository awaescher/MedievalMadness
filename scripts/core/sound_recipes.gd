class_name SoundRecipes
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Synthesis recipes for every sound (spec 17), v2. Each effect is a LAYERED design (transient + body + tail), built
## with modal resonators, FM, filtered noise, Karplus-Strong strings, a vocal formant source and a room reverb, then
## loudness-matched. `make(name, variant)` returns a PackedFloat32Array. Deterministic per (name, variant).

const NAMES: Array[String] = [
	"thunk", "clack", "crunch", "clang", "tinkle", "fwump", "swish", "boom", "bigboom", "whoosh", "twang", "creak",
	"fire_loop", "splash", "moo", "bawk", "baa", "neigh", "quack", "honk", "squeak", "bell", "scream", "yeet", "boing",
	"buzz", "thunder", "zap", "rain_loop", "gust", "stinger_event", "ui_click", "ui_hover", "turn_start", "victory",
	"defeat", "splat", "pop", "fuse", "crate_epic", "fanfare"]

const VARIANTS: Dictionary = {
	"thunk": 3, "clack": 3, "crunch": 3, "splash": 3, "boing": 3, "scream": 3, "moo": 3, "tinkle": 3, "fwump": 2, "swish": 2,
	"clang": 3, "boom": 3, "bigboom": 2, "splat": 3, "yeet": 2, "twang": 2, "creak": 2, "pop": 2, "zap": 2, "bawk": 3, "baa": 3, "quack": 3, "neigh": 2, "honk": 2,
}
const LOOPED: Array[String] = ["fire_loop", "rain_loop", "gust", "buzz"]
## looped streams that are not part of the global ambience mix: players attach them to things (Sfx.attach_loop)
const LOOP_SINGLE: Array[String] = ["fuse"]
## Final peak level per sound (UI stays discreet, loops sit under everything else)
const LEVEL: Dictionary = {
	"ui_hover": 0.30, "ui_click": 0.55, "fire_loop": 0.55, "rain_loop": 0.5, "gust": 0.5, "buzz": 0.5, "tinkle": 0.7,
	"fuse": 0.6, "clack": 0.8, "squeak": 0.4, "pop": 0.7, "bawk": 0.36, "quack": 0.36, "baa": 0.38, "moo": 0.45, "neigh": 0.38, "honk": 0.4, "scream": 0.38, "yeet": 0.5, "boing": 0.45, "creak": 0.4,
}

static func variants_of(name: String) -> int:
	return int(VARIANTS.get(name, 1))

static func is_looped(name: String) -> bool:
	return LOOPED.has(name) or LOOP_SINGLE.has(name)

## A brass note: two detuned saws + a square an octave down through a low-pass that opens (the "blaat" of a horn)
static func _brass(b: PackedFloat32Array, f: float, t0: float, dur: float, amp: float, f_end: float = -1.0, wah: float = 0.0) -> void:
	var n: PackedFloat32Array = Synth.make(dur)
	var fe: float = f if f_end < 0.0 else f_end
	Synth.osc(n, Synth.SAW, f, fe, 0.0, dur, 0.5, 0.0, 5.6, 0.008, 0.035)
	Synth.osc(n, Synth.SAW, f * 1.006, fe * 1.006, 0.0, dur, 0.4, 0.0, 5.2, 0.008, 0.04)
	Synth.osc(n, Synth.SQUARE, f * 0.5, fe * 0.5, 0.0, dur, 0.25, 0.0, 0.0, 0.0, 0.05)
	Synth.biquad_sweep(n, "lp", 600.0, 3600.0 if wah == 0.0 else 600.0 + wah, 1.1, 0.0, minf(dur, 0.18))
	Synth.biquad(n, "lp", 3800.0, 0.6)
	# soft release
	var rel: int = mini(int(0.07 * float(Synth.SR)), n.size())
	for i in rel:
		n[n.size() - 1 - i] *= float(i) / float(rel)
	Synth.mix_into(b, n, amp, t0)

static func make(name: String, variant: int) -> PackedFloat32Array:
	var r: Rng = Rng.from_string("%s#%d" % [name, variant])
	var v: float = float(variant)
	var b: PackedFloat32Array
	match name:
		"thunk":
			# heavy wooden / earthen thud: pitch-dropping sub, dull body noise, tiny click, short room
			b = Synth.make(0.5)
			Synth.osc(b, Synth.SINE, 135.0 - v * 10.0, 42.0, 0.0, 0.32, 1.0, 10.0, 0.0, 0.0, 0.002)
			Synth.noise(b, Synth.PINK, 0.0, 0.14, 0.9, 30.0, 950.0 + v * 120.0, 240.0, 0.0, r, 0.001)
			Synth.noise(b, Synth.WHITE, 0.0, 0.015, 0.45, 160.0, 4500.0, 2000.0, 700.0, r, 0.0005)
			Synth.biquad(b, "peak", 210.0, 1.2, 7.0)
			Synth.saturate(b, 1.7)
			Synth.reverb(b, 0.25, 0.5, 0.14)
		"clack":
			# two wooden knocks from modal resonators
			b = Synth.make(0.45)
			var wood: Array = [[1.0, 1.0, 55.0], [2.3, 0.55, 85.0], [3.9, 0.3, 130.0], [6.1, 0.12, 200.0]]
			Synth.modal(b, 880.0 + v * 70.0, wood, 0.0, 0.9)
			Synth.modal(b, 610.0 + v * 50.0, wood, 0.04, 0.65)
			Synth.noise(b, Synth.WHITE, 0.0, 0.012, 0.35, 220.0, 7000.0, 3500.0, 1500.0, r, 0.0003)
			Synth.biquad(b, "hp", 180.0, 0.7)
			Synth.reverb(b, 0.3, 0.5, 0.12)
		"crunch":
			# stone / timber giving way: a spray of sharp grains over a low thud
			b = Synth.make(0.8)
			var t: float = 0.0
			for k in 10:
				var f_c: float = r.range_f(1100.0, 4800.0)
				Synth.noise(b, Synth.WHITE, t, r.range_f(0.02, 0.07), r.range_f(0.45, 1.0) * (1.0 - float(k) * 0.05), 60.0, f_c, f_c * 0.45, r.range_f(250.0, 1000.0), r, 0.0008)
				t += r.range_f(0.01, 0.04)
			Synth.osc(b, Synth.SINE, 105.0 - v * 8.0, 48.0, 0.0, 0.22, 0.4, 14.0, 0.0, 0.0, 0.002)
			Synth.noise(b, Synth.BROWN, 0.0, 0.3, 0.3, 12.0, 700.0, 180.0, 0.0, r, 0.002)
			Synth.saturate(b, 2.2)
			Synth.reverb(b, 0.4, 0.5, 0.16)
		"clang":
			# struck metal: inharmonic modal bank + FM shimmer + sharp transient
			b = Synth.make(2.0)
			var metal: Array = [[1.0, 1.0, 3.6], [2.76, 0.75, 5.0], [5.4, 0.55, 7.5], [8.93, 0.35, 11.0], [13.3, 0.18, 17.0]]
			Synth.modal(b, 480.0 * (1.0 + v * 0.14), metal, 0.0, 0.9, 1.0, 0.003)
			Synth.fm(b, 1900.0, 1.41, 3.5, 0.2, 0.0, 0.2, 0.32, 16.0, 0.0008)
			Synth.noise(b, Synth.WHITE, 0.0, 0.012, 0.6, 180.0, 9000.0, 4000.0, 1500.0, r, 0.0003)
			Synth.biquad(b, "highshelf", 3500.0, 0.7, 3.0)
			Synth.reverb(b, 0.55, 0.3, 0.24)
		"tinkle":
			# scattering glass
			b = Synth.make(1.1)
			var glass: Array = [[1.0, 1.0, 13.0], [2.41, 0.45, 19.0], [3.72, 0.22, 30.0]]
			var pings: int = 6 + r.range_i(0, 3)
			for k in pings:
				Synth.modal(b, r.range_f(2300.0, 5400.0), glass, r.range_f(0.0, 0.3), r.range_f(0.25, 0.55))
			Synth.biquad(b, "hp", 1200.0, 0.7)
			Synth.reverb(b, 0.55, 0.25, 0.22)
		"fwump":
			# soft low ignition whoomph
			b = Synth.make(0.8)
			Synth.noise(b, Synth.BROWN, 0.0, 0.55, 1.6, 6.5, 750.0 + v * 100.0, 120.0, 30.0, r, 0.035)
			Synth.osc(b, Synth.SINE, 72.0, 33.0, 0.0, 0.45, 0.8, 6.0, 0.0, 0.0, 0.025)
			Synth.noise(b, Synth.WHITE, 0.0, 0.12, 0.3, 28.0, 3800.0, 700.0, 500.0, r, 0.004)
			Synth.saturate(b, 1.5)
			Synth.reverb(b, 0.4, 0.45, 0.16)
		"swish":
			# cloth / branches / something swung past
			b = Synth.make(0.6)
			Synth.noise(b, Synth.WHITE, 0.0, 0.5, 1.0, 0.0, 9000.0, 9000.0, 0.0, r, 0.1)
			Synth.biquad_sweep(b, "bp", 1000.0 + v * 200.0, 3400.0, 1.5)
			Synth.curve(b, [[0.0, 0.0], [0.16, 1.0], [0.5, 0.0], [0.6, 0.0]])
			Synth.reverb(b, 0.3, 0.5, 0.1)
		"boom":
			# explosion: crack + pressure body + sub + rattling debris + big room
			b = Synth.make(2.4)
			Synth.noise(b, Synth.WHITE, 0.0, 0.07, 1.8, 55.0, 10000.0, 3000.0, 450.0, r, 0.0004)
			Synth.noise(b, Synth.PINK, 0.02, 0.5, 0.6, 7.0, 6000.0, 900.0, 300.0, r, 0.002)
			Synth.noise(b, Synth.BROWN, 0.0, 1.5, 1.3, 3.0, 3800.0, 170.0, 35.0, r, 0.004)
			Synth.osc(b, Synth.SINE, 98.0 - v * 10.0, 27.0, 0.0, 1.2, 1.2, 3.2, 0.0, 0.0, 0.003)
			for k in 12:
				Synth.noise(b, Synth.WHITE, 0.12 + float(k) * r.range_f(0.05, 0.09), r.range_f(0.02, 0.05), r.range_f(0.12, 0.35), 40.0, r.range_f(1800.0, 3200.0), 700.0, 300.0, r, 0.001)
			Synth.saturate(b, 2.2)
			Synth.biquad(b, "lp", 7500.0, 0.7)
			Synth.reverb(b, 0.75, 0.45, 0.3)
			Synth.dc_block(b)
		"bigboom":
			# the big one: two-stage detonation with a long rolling tail
			b = Synth.make(4.0)
			Synth.noise(b, Synth.WHITE, 0.0, 0.09, 2.0, 45.0, 11000.0, 2500.0, 350.0, r, 0.0004)
			Synth.noise(b, Synth.PINK, 0.02, 0.8, 0.7, 4.5, 6500.0, 800.0, 250.0, r, 0.002)
			Synth.noise(b, Synth.BROWN, 0.0, 2.6, 1.4, 1.5, 4500.0, 90.0, 28.0, r, 0.005)
			Synth.osc(b, Synth.SINE, 72.0 - v * 6.0, 22.0, 0.0, 2.2, 1.5, 1.4, 0.0, 0.0, 0.004)
			Synth.osc(b, Synth.SINE, 56.0, 20.0, 0.22, 1.0, 0.8, 2.4, 0.0, 0.0, 0.01)
			Synth.noise(b, Synth.BROWN, 0.5, 2.8, 0.85, 1.2, 700.0, 60.0, 25.0, r, 0.25)
			for k in 24:
				Synth.noise(b, Synth.WHITE, 0.15 + float(k) * r.range_f(0.05, 0.085), r.range_f(0.02, 0.06), r.range_f(0.1, 0.32), 38.0, r.range_f(1500.0, 3000.0), 600.0, 250.0, r, 0.001)
			Synth.saturate(b, 2.6)
			Synth.biquad(b, "lp", 7000.0, 0.7)
			Synth.reverb(b, 0.88, 0.5, 0.36)
			Synth.dc_block(b)
		"whoosh":
			# a heavy thing passing overhead
			b = Synth.make(0.95)
			Synth.noise(b, Synth.WHITE, 0.0, 0.85, 1.0, 0.0, 9000.0, 9000.0, 0.0, r, 0.05)
			Synth.biquad_sweep(b, "bp", 420.0, 3000.0, 1.1)
			Synth.curve(b, [[0.0, 0.0], [0.3, 1.0], [0.62, 0.45], [0.9, 0.0]])
			Synth.osc(b, Synth.SINE, 260.0, 105.0, 0.0, 0.7, 0.14, 4.0, 0.0, 0.0, 0.2)
			Synth.reverb(b, 0.35, 0.5, 0.1)
		"twang":
			# catapult rope let go: plucked string + wooden thump
			b = Synth.make(1.1)
			Synth.pluck(b, 148.0 + v * 12.0, 0.0, 1.0, 0.9, 0.9968, r)
			Synth.pluck(b, 296.0 + v * 24.0, 0.0, 0.8, 0.3, 0.9955, r)
			Synth.osc(b, Synth.SINE, 120.0, 55.0, 0.0, 0.12, 0.6, 24.0, 0.0, 0.0, 0.001)
			Synth.noise(b, Synth.WHITE, 0.0, 0.012, 0.5, 200.0, 3500.0, 1500.0, 400.0, r, 0.0004)
			Synth.biquad(b, "peak", 620.0, 1.0, 5.0)
			Synth.saturate(b, 1.3)
			Synth.reverb(b, 0.3, 0.45, 0.1)
		"creak":
			# stick-slip wooden creak: irregular pulse train through two resonances
			b = Synth.make(0.9)
			var raw: PackedFloat32Array = Synth.make(0.9)
			var tt: float = 0.02
			var rate: float = 0.016 + v * 0.004
			while tt < 0.78:
				var idx: int = int(tt * float(Synth.SR))
				if idx < raw.size():
					raw[idx] += r.range_f(0.5, 1.0)
				tt += rate * r.range_f(0.6, 1.4) * lerpf(1.0, 0.45, tt / 0.8)
			var a1: PackedFloat32Array = raw.duplicate()
			Synth.biquad(a1, "bp", 470.0 + v * 40.0, 7.0)
			var a2: PackedFloat32Array = raw.duplicate()
			Synth.biquad(a2, "bp", 1100.0, 9.0)
			for i in b.size():
				b[i] = a1[i] * 2.4 + a2[i] * 1.4
			Synth.osc(b, Synth.SAW, 62.0, 70.0, 0.0, 0.8, 0.05, 0.0, 6.0, 0.03, 0.2)
			Synth.curve(b, [[0.0, 0.0], [0.18, 1.0], [0.6, 0.8], [0.88, 0.0]])
			Synth.reverb(b, 0.3, 0.5, 0.1)
		"fire_loop":
			# low roar + random crackle pops, made seamless
			b = Synth.make(2.6)
			Synth.noise(b, Synth.BROWN, 0.0, 2.6, 0.9, 0.0, 800.0, 800.0, 55.0, r, 0.0)
			Synth.noise(b, Synth.PINK, 0.0, 2.6, 0.3, 0.0, 2600.0, 2600.0, 500.0, r, 0.0)
			for k in 38:
				Synth.noise(b, Synth.WHITE, r.range_f(0.0, 2.5), r.range_f(0.004, 0.022), r.range_f(0.25, 0.95), 140.0, r.range_f(2500.0, 7500.0), 1500.0, 900.0, r, 0.0003)
			b = Synth.loopify(b, 0.3)
		"splash":
			# water impact: bright rush, bubbles, low plop
			b = Synth.make(1.1)
			Synth.noise(b, Synth.WHITE, 0.0, 0.7, 1.0, 5.5, 7500.0 + v * 400.0, 1100.0, 250.0, r, 0.007)
			for k in 8:
				var f: float = r.range_f(380.0, 950.0)
				Synth.osc(b, Synth.SINE, f, f * r.range_f(1.8, 2.6), 0.03 + float(k) * 0.045 + r.range_f(0.0, 0.03), 0.07, r.range_f(0.15, 0.35), 38.0, 0.0, 0.0, 0.001)
			Synth.osc(b, Synth.SINE, 230.0, 68.0, 0.0, 0.18, 0.8, 16.0, 0.0, 0.0, 0.002)
			Synth.reverb(b, 0.45, 0.5, 0.16)
		"moo":
			# a cow, friendly and round: a soft cartoon tuba "muuuh" (no voice formants - those sounded creepy)
			var mdur: float = 1.0 + 0.12 * v
			var mp: float = 1.0 + 0.06 * (v - 1.0)
			b = Synth.make(mdur + 0.4)
			Synth.osc(b, Synth.SAW, 118.0 * mp, 104.0 * mp, 0.0, mdur, 0.55, 0.0, 4.6, 0.012, 0.09)
			Synth.osc(b, Synth.SAW, 118.6 * mp, 104.6 * mp, 0.0, mdur, 0.4, 0.0, 4.2, 0.012, 0.1)
			Synth.osc(b, Synth.SQUARE, 59.0 * mp, 52.0 * mp, 0.0, mdur, 0.25, 0.0, 0.0, 0.0, 0.1)
			Synth.biquad_sweep(b, "lp", 260.0, 1250.0, 0.9, 0.0, 0.35)
			Synth.biquad_sweep(b, "lp", 1250.0, 420.0, 0.9, 0.35, mdur - 0.35)
			Synth.biquad(b, "lp", 1600.0, 0.6)
			Synth.reverb(b, 0.25, 0.5, 0.06)
		"bawk":
			# chicken: a few quick, wooden "bok"s (short FM blips that fall in pitch)
			b = Synth.make(1.0)
			var cnum: int = 3 + int(v) % 2
			var cp: float = 1.0 + 0.08 * (v - 1.0)
			for k in cnum:
				var tk: float = float(k) * 0.13 + r.range_f(0.0, 0.02)
				Synth.fm(b, 720.0 * cp, 1.5, 2.2, 0.4, tk, 0.1, 0.8 - 0.1 * float(k), 26.0, 0.003, 470.0 * cp)
			Synth.biquad(b, "lp", 2600.0, 0.7)
			Synth.reverb(b, 0.2, 0.5, 0.05)
		"baa":
			# sheep: a soft, trembling kazoo-like bleat
			var bp: float = 1.0 + 0.08 * (v - 1.0)
			var bdur: float = 0.65 + 0.1 * v
			b = Synth.make(bdur + 0.3)
			Synth.osc(b, Synth.SAW, 330.0 * bp, 290.0 * bp, 0.0, bdur, 0.6, 0.0, 5.0, 0.012, 0.03, 24.0, 0.45)
			Synth.osc(b, Synth.TRI, 660.0 * bp, 580.0 * bp, 0.0, bdur, 0.2, 0.0, 5.0, 0.012, 0.03, 24.0, 0.45)
			Synth.biquad(b, "lp", 1700.0, 0.8)
			Synth.reverb(b, 0.2, 0.5, 0.05)
		"neigh":
			# horse: a playful slide-whistle whinny (rises, then wobbles down)
			var np: float = 1.0 + 0.08 * v
			b = Synth.make(1.3)
			Synth.osc(b, Synth.SINE, 520.0 * np, 1350.0 * np, 0.0, 0.3, 0.7, 0.0, 6.0, 0.01, 0.03)
			Synth.osc(b, Synth.SINE, 1350.0 * np, 760.0 * np, 0.3, 0.55, 0.6, 0.0, 9.0, 0.03, 0.01)
			Synth.osc(b, Synth.TRI, 260.0 * np, 380.0 * np, 0.0, 0.85, 0.15, 0.0, 6.0, 0.01, 0.05)
			Synth.biquad(b, "lp", 3200.0, 0.7)
			Synth.reverb(b, 0.25, 0.5, 0.06)
		"quack":
			# duck: two or three kazoo-like "quack"s that get quieter
			b = Synth.make(0.9)
			var qn: int = 2 + int(v) % 2
			var qp: float = 1.0 + 0.08 * (v - 1.0)
			for k in qn:
				var tq: float = float(k) * 0.2
				Synth.fm(b, 420.0 * qp, 1.0, 3.0, 1.0, tq, 0.15, 0.9 - 0.25 * float(k), 12.0, 0.004, 300.0 * qp)
			Synth.biquad(b, "lp", 2400.0, 0.7)
			Synth.reverb(b, 0.2, 0.5, 0.05)
		"honk":
			# goose: a toy trumpet "hoonk", twice
			b = Synth.make(1.0)
			var gp: float = 1.0 + 0.07 * (v - 0.5)
			_brass(b, 330.0 * gp, 0.0, 0.3, 0.55, 360.0 * gp)
			_brass(b, 300.0 * gp, 0.38, 0.26, 0.5, 330.0 * gp)
			Synth.reverb(b, 0.25, 0.5, 0.06)
		"squeak":
			b = Synth.make(0.3)
			Synth.fm(b, 1900.0, 2.0, 1.4, 0.15, 0.0, 0.2, 0.8, 10.0, 0.004, 3500.0)
			Synth.fm(b, 2600.0, 3.0, 0.8, 0.0, 0.0, 0.15, 0.3, 14.0, 0.004, 4200.0)
			Synth.reverb(b, 0.2, 0.5, 0.07)
		"bell":
			# church bell: classic minor-third partial set, strike noise, hum and a long hall tail
			b = Synth.make(4.8)
			var bell: Array = [[0.5, 0.7, 1.0], [1.0, 1.0, 1.4], [1.19, 0.6, 1.9], [1.56, 0.5, 2.3], [2.0, 0.5, 2.8], [2.5, 0.3, 3.6], [3.0, 0.25, 4.5], [4.2, 0.18, 6.2]]
			Synth.modal(b, 440.0, bell, 0.0, 0.8, 1.0, 0.0025)
			Synth.osc(b, Synth.SINE, 220.0, 219.0, 0.0, 3.4, 0.35, 1.0, 0.0, 0.0, 0.002)
			Synth.noise(b, Synth.WHITE, 0.0, 0.025, 0.5, 80.0, 7000.0, 2500.0, 800.0, r, 0.0005)
			Synth.reverb(b, 0.75, 0.3, 0.3)
		"scream":
			# comic settler "waaah": a slide-whistle-like rise and fall with a little wobble (no breathy voice)
			var base: float = r.range_f(480.0, 700.0)
			b = Synth.make(0.9)
			Synth.osc(b, Synth.SINE, base, base * 1.9, 0.0, 0.28, 0.7, 0.0, 8.0, 0.03, 0.02)
			Synth.osc(b, Synth.SINE, base * 1.9, base * 0.85, 0.28, 0.4, 0.6, 0.0, 10.0, 0.04, 0.01)
			Synth.osc(b, Synth.TRI, base * 0.5, base * 0.9, 0.0, 0.68, 0.12, 0.0, 8.0, 0.03, 0.04)
			Synth.biquad(b, "lp", 3600.0, 0.7)
			Synth.reverb(b, 0.2, 0.5, 0.05)
		"yeet":
			# launched into orbit: rising doppler whoosh with a cartoon "sproing" at the end
			b = Synth.make(1.0)
			Synth.osc(b, Synth.SAW, 170.0, 1500.0, 0.0, 0.6, 0.45, 1.2, 0.0, 0.0, 0.01)
			Synth.osc(b, Synth.SINE, 340.0, 3000.0, 0.0, 0.6, 0.25, 1.2, 0.0, 0.0, 0.01)
			Synth.noise(b, Synth.WHITE, 0.0, 0.6, 0.25, 2.0, 6000.0, 6000.0, 800.0, r, 0.05)
			Synth.biquad_sweep(b, "lp", 600.0, 6500.0, 1.0, 0.0, 0.6)
			Synth.curve(b, [[0.0, 0.35], [0.3, 1.0], [0.6, 0.0], [1.0, 0.0]])
			Synth.fm(b, 520.0, 1.0, 2.5, 0.2, 0.55, 0.4, 0.45, 7.0, 0.002, 260.0)
			Synth.reverb(b, 0.4, 0.5, 0.12)
		"boing":
			# spring: wobbling FM sweep
			b = Synth.make(0.8)
			Synth.fm(b, 340.0 + v * 30.0, 1.0, 3.2, 0.2, 0.0, 0.7, 0.9, 4.2, 0.002, 180.0 + v * 15.0)
			Synth.osc(b, Synth.SINE, 680.0 + v * 60.0, 380.0, 0.0, 0.5, 0.25, 6.0, 0.0, 0.0, 0.002)
			Synth.noise(b, Synth.WHITE, 0.0, 0.008, 0.4, 200.0, 5000.0, 2500.0, 900.0, r, 0.0003)
			Synth.reverb(b, 0.3, 0.5, 0.1)
		"buzz":
			# bees: detuned buzzing saws, fast amplitude modulation, light wobble
			b = Synth.make(1.8)
			for k in 4:
				Synth.osc(b, Synth.SAW, 195.0 * (1.0 + float(k) * 0.017), 195.0 * (1.0 + float(k) * 0.017), 0.0, 1.8, 0.3, 0.0, 3.0 + float(k), 0.012, 0.0, 28.0 + float(k) * 4.0, 0.6)
			Synth.noise(b, Synth.PINK, 0.0, 1.8, 0.12, 0.0, 3200.0, 3200.0, 500.0, r, 0.0)
			Synth.biquad(b, "peak", 850.0, 1.0, 6.0)
			Synth.biquad(b, "lp", 2600.0, 0.7)
			b = Synth.loopify(b, 0.2)
		"thunder":
			# crack, then long rolling rumbles
			b = Synth.make(5.2)
			Synth.noise(b, Synth.WHITE, 0.0, 0.18, 0.9, 16.0, 6500.0, 1400.0, 300.0, r, 0.001)
			Synth.noise(b, Synth.BROWN, 0.0, 4.5, 1.5, 0.8, 520.0, 48.0, 22.0, r, 0.14)
			for k in 6:
				Synth.noise(b, Synth.BROWN, 0.35 + float(k) * 0.55, 1.4, 0.6, 1.8, r.range_f(380.0, 600.0), 65.0, 22.0, r, 0.06)
			Synth.osc(b, Synth.SINE, 50.0, 27.0, 0.0, 3.8, 0.5, 0.8, 0.0, 0.0, 0.15)
			Synth.reverb(b, 0.88, 0.5, 0.3)
			Synth.dc_block(b)
		"zap":
			# electric arc
			b = Synth.make(0.45)
			Synth.fm(b, 2600.0 - v * 500.0, 0.5, 6.0, 0.0, 0.0, 0.25, 0.6, 11.0, 0.0008, 500.0)
			Synth.osc(b, Synth.SAW, 4200.0, 280.0, 0.0, 0.14, 0.5, 14.0, 0.0, 0.0, 0.0005)
			Synth.noise(b, Synth.WHITE, 0.0, 0.3, 0.8, 12.0, 12000.0, 5000.0, 1500.0, r, 0.0005)
			for k in 7:
				Synth.noise(b, Synth.WHITE, r.range_f(0.0, 0.28), 0.006, r.range_f(0.4, 0.9), 180.0, 9000.0, 4000.0, 1800.0, r, 0.0002)
			Synth.saturate(b, 2.0)
			Synth.reverb(b, 0.3, 0.3, 0.12)
		"rain_loop":
			b = Synth.make(2.8)
			Synth.noise(b, Synth.PINK, 0.0, 2.8, 0.8, 0.0, 9500.0, 9500.0, 900.0, r, 0.0)
			for k in 160:
				Synth.noise(b, Synth.WHITE, r.range_f(0.0, 2.75), 0.004, r.range_f(0.05, 0.3), 220.0, 6500.0, 3000.0, 2500.0, r, 0.0002)
			b = Synth.loopify(b, 0.3)
		"gust":
			# wind: two resonant bands breathing slowly (LFO periods divide the loop length exactly)
			b = Synth.make(3.4)
			var wind: PackedFloat32Array = Synth.gen_noise(3.4, Synth.PINK, r)
			var w1: PackedFloat32Array = wind.duplicate()
			Synth.biquad(w1, "bp", 480.0, 0.9)
			var w2: PackedFloat32Array = wind.duplicate()
			Synth.biquad(w2, "bp", 1250.0, 1.4)
			var total: float = 3.4
			for i in b.size():
				var tg: float = float(i) / float(Synth.SR)
				var l1: float = 0.5 + 0.5 * sin(TAU * tg * 2.0 / total)
				var l2: float = 0.5 + 0.5 * sin(TAU * tg * 3.0 / total + 1.3)
				b[i] = w1[i] * (0.25 + 0.75 * l1) * 2.6 + w2[i] * (0.15 + 0.85 * l2) * 1.4
			b = Synth.loopify(b, 0.35)
		"stinger_event":
			# brass chord stab + cymbal shimmer
			b = Synth.make(1.6)
			for f in [261.63, 329.63, 392.0, 523.25]:
				_brass(b, f as float, 0.0, 0.7, 0.35)
			Synth.noise(b, Synth.WHITE, 0.0, 1.0, 0.15, 3.5, 12000.0, 9000.0, 6500.0, r, 0.003)
			Synth.reverb(b, 0.6, 0.35, 0.25)
		"ui_click":
			b = Synth.make(0.12)
			Synth.modal(b, 1450.0, [[1.0, 1.0, 75.0], [2.4, 0.45, 120.0]], 0.0, 0.8)
			Synth.osc(b, Synth.SINE, 900.0, 650.0, 0.0, 0.03, 0.4, 70.0, 0.0, 0.0, 0.0005)
			Synth.noise(b, Synth.WHITE, 0.0, 0.006, 0.3, 300.0, 6000.0, 3000.0, 900.0, r, 0.0002)
		"ui_hover":
			b = Synth.make(0.08)
			Synth.modal(b, 2300.0, [[1.0, 1.0, 140.0], [2.7, 0.3, 200.0]], 0.0, 0.5)
		"turn_start":
			# two-note horn call
			b = Synth.make(1.6)
			_brass(b, 392.0, 0.0, 0.24, 0.55)
			_brass(b, 523.25, 0.22, 0.7, 0.65)
			Synth.reverb(b, 0.55, 0.35, 0.22)
		"victory":
			# fanfare with a timpani roll and a cymbal crash
			b = Synth.make(4.0)
			var seq: Array[float] = [261.63, 329.63, 392.0, 523.25, 392.0, 523.25, 659.25]
			var starts: Array[float] = [0.0, 0.18, 0.36, 0.54, 1.0, 1.18, 1.36]
			var lens: Array[float] = [0.18, 0.18, 0.18, 0.4, 0.18, 0.18, 1.7]
			for k in 7:
				_brass(b, seq[k], starts[k], lens[k], 0.5)
			for f2 in [392.0, 523.25, 783.99]:
				_brass(b, f2 as float, 1.36, 1.7, 0.3)
			for k in 12:
				Synth.osc(b, Synth.SINE, 120.0, 72.0, float(k) * 0.045, 0.2, 0.35 + float(k) * 0.03, 14.0, 0.0, 0.0, 0.001)
			Synth.osc(b, Synth.SINE, 98.0, 55.0, 1.36, 0.6, 0.8, 5.0, 0.0, 0.0, 0.001)
			Synth.noise(b, Synth.WHITE, 1.36, 2.2, 0.3, 2.0, 12000.0, 9000.0, 5500.0, r, 0.002)
			Synth.reverb(b, 0.75, 0.3, 0.28)
		"crate_epic":
			# the meteor crate arrives: low brass swell, rising chord, three timpani hits, cymbal
			b = Synth.make(4.2)
			_brass(b, 130.81, 0.0, 3.4, 0.4)
			_brass(b, 196.0, 0.0, 3.4, 0.3)
			_brass(b, 261.63, 1.1, 2.4, 0.45)
			_brass(b, 392.0, 1.8, 1.9, 0.5)
			_brass(b, 523.25, 2.5, 1.4, 0.6)
			for t0 in [0.0, 1.1, 2.5]:
				Synth.osc(b, Synth.SINE, 110.0, 55.0, t0 as float, 0.7, 0.9, 5.0, 0.0, 0.0, 0.001)
			Synth.noise(b, Synth.WHITE, 2.5, 1.6, 0.25, 2.0, 12000.0, 9000.0, 5500.0, r, 0.002)
			Synth.reverb(b, 0.8, 0.3, 0.3)
		"fanfare":
			# short triumphant fanfare when somebody hits the meteor crate
			b = Synth.make(2.8)
			var fs: Array[float] = [392.0, 523.25, 659.25, 783.99]
			for k in 4:
				_brass(b, fs[k], float(k) * 0.14, 0.14, 0.55)
			for f3 in [523.25, 659.25, 783.99, 1046.5]:
				_brass(b, f3 as float, 0.6, 1.8, 0.35)
			for k in 6:
				Synth.osc(b, Synth.SINE, 120.0, 72.0, float(k) * 0.05, 0.2, 0.4, 14.0, 0.0, 0.0, 0.001)
			Synth.osc(b, Synth.SINE, 98.0, 55.0, 0.6, 0.6, 0.8, 5.0, 0.0, 0.0, 0.001)
			Synth.noise(b, Synth.WHITE, 0.6, 1.8, 0.3, 2.0, 12000.0, 9000.0, 5500.0, r, 0.002)
			Synth.reverb(b, 0.7, 0.3, 0.26)
		"defeat":
			# sad trombone: falling slides with a wah
			b = Synth.make(3.4)
			_brass(b, 233.08, 0.0, 0.42, 0.55, 230.0, -300.0)
			_brass(b, 220.0, 0.45, 0.42, 0.55, 217.0, -300.0)
			_brass(b, 207.65, 0.9, 0.42, 0.55, 203.0, -300.0)
			_brass(b, 196.0, 1.35, 1.6, 0.6, 158.0, -350.0)
			Synth.reverb(b, 0.6, 0.4, 0.2)
		"splat":
			# wet smack + bubbling
			b = Synth.make(0.5)
			Synth.noise(b, Synth.WHITE, 0.0, 0.16, 1.0, 20.0, 4800.0 + v * 400.0, 650.0, 200.0, r, 0.003)
			Synth.osc(b, Synth.SINE, 215.0, 62.0, 0.0, 0.22, 0.9, 15.0, 0.0, 0.0, 0.001)
			for k in 4:
				var fb: float = r.range_f(300.0, 720.0)
				Synth.osc(b, Synth.SINE, fb, fb * 1.8, 0.06 + float(k) * 0.05, 0.05, 0.22, 42.0, 0.0, 0.0, 0.001)
			Synth.saturate(b, 1.6)
			Synth.reverb(b, 0.25, 0.5, 0.08)
		"fuse":
			# a burning fuse: a steady bright hiss with a crackle of tiny pops and now and then a spit
			b = Synth.make(1.7)
			Synth.noise(b, Synth.WHITE, 0.0, 1.7, 0.30, 0.0, 9500.0, 8500.0, 4200.0, r, 0.0)
			Synth.noise(b, Synth.PINK, 0.0, 1.7, 0.22, 0.0, 3200.0, 2600.0, 900.0, r, 0.0)
			for k in 70:
				Synth.noise(b, Synth.WHITE, r.range_f(0.0, 1.6), r.range_f(0.002, 0.012), r.range_f(0.35, 1.0), 120.0, r.range_f(5000.0, 11000.0), 3000.0, r.range_f(1200.0, 3800.0), r, 0.0002)
			for k2 in 7:
				Synth.noise(b, Synth.WHITE, r.range_f(0.0, 1.5), r.range_f(0.03, 0.08), r.range_f(0.4, 0.7), 40.0, 8000.0, 5000.0, 2500.0, r, 0.003)
			b = Synth.loopify(b, 0.25)
		"pop":
			b = Synth.make(0.2)
			Synth.osc(b, Synth.SINE, 720.0 - v * 100.0, 240.0, 0.0, 0.08, 1.0, 42.0, 0.0, 0.0, 0.0008)
			Synth.noise(b, Synth.WHITE, 0.0, 0.005, 0.4, 300.0, 6000.0, 3000.0, 1000.0, r, 0.0002)
			Synth.reverb(b, 0.2, 0.5, 0.06)
		_:
			b = Synth.make(0.05)
	if not is_looped(name):
		Synth.fade_in(b, 0.0008)
		Synth.fade_out(b, 0.012)
	Synth.normalize(b, float(LEVEL.get(name, 0.9)))
	return b
