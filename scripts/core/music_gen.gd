class_name MusicGen
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Synthesised medieval background music (no audio files): three long songs built from a small band - lute (Karplus-Strong), flute /
## recorder / fiddle, a drone like a hurdy-gurdy, frame drum, tambourine and a few bells. Every song is composed from a seed
## (modal scales: Dorian, Aeolian, Mixolydian; phrases of four bars that answer each other and end on the tonic), rendered section by
## section (each distinct section once, with its own reverb) and assembled with overlap-add, so a 3+ minute song costs only a few
## seconds of synthesis. Output: 16-bit mono 16 kHz AudioStreamWAV.

const MODES: Dictionary = {
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"aeolian": [0, 2, 3, 5, 7, 8, 10],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
}
const SR := 32000

## The songs: name, root note (Hz), mode, tempo (beats per minute), beats per bar, melody voice, extras, chord progression (scale degrees per bar)
const SONGS: Array[Dictionary] = [
	{"name": "Tavern Dance", "root": 146.83, "mode": "dorian", "bpm": 104, "beats": 4, "lead": "flute", "drums": true, "bells": false, "prog": [0, 0, 3, 4, 0, 5, 3, 4], "seed": 11},
	{"name": "Pilgrim's Road", "root": 110.0, "mode": "aeolian", "bpm": 78, "beats": 3, "lead": "fiddle", "drums": false, "bells": true, "prog": [0, 5, 3, 4, 0, 3, 4, 0], "seed": 23},
	{"name": "Castle Morning", "root": 196.0, "mode": "mixolydian", "bpm": 118, "beats": 3, "lead": "recorder", "drums": true, "bells": true, "prog": [0, 3, 4, 0, 5, 3, 4, 4], "seed": 37},
]
const TARGET_SECONDS := 200.0

static func song_count() -> int:
	return SONGS.size()

static func song_name(i: int) -> String:
	return str((SONGS[i] as Dictionary)["name"])

# ------------------------------------------------------------------ notes
static func _semi(mode: String, degree: int) -> int:
	var sc: Array = MODES[mode] as Array
	var oct: int = floori(float(degree) / 7.0)
	return int(sc[posmod(degree, 7)]) + 12 * oct

static func _hz(root: float, mode: String, degree: int) -> float:
	return root * pow(2.0, float(_semi(mode, degree)) / 12.0)

# ------------------------------------------------------------------ composition
## A phrase of `bars` bars: [[start_beat, length_beats, degree], ...]; ends on `end_deg` (long note)
static func _phrase(r: Rng, bars: int, beats: int, start_deg: int, end_deg: int, motif: Array) -> Array:
	var notes: Array = []
	var deg: int = start_deg
	var cells: Array = motif if not motif.is_empty() else [[1.0, 0.5, 0.5, 1.0, 1.0], [1.5, 0.5, 1.0, 1.0], [0.5, 0.5, 1.0, 0.5, 0.5, 1.0], [2.0, 1.0, 1.0]]
	for b in bars:
		var left: float = float(beats)
		var t: float = float(b * beats)
		while left > 0.01:
			var cell: Array = r.pick(cells) as Array
			for d in cell:
				var dur: float = minf(float(d), left)
				if dur < 0.01:
					break
				var last_note: bool = b == bars - 1 and left - dur < 0.01
				var step: int = int(r.pick([-2, -1, -1, 0, 1, 1, 2, -1, 1, 3, -3]))
				# stay inside one octave of the scale (0..7) and, at the end, move towards the cadence note
				if deg >= 7:
					step = -absi(step) - 1
				elif deg <= 0:
					step = absi(step)
				if b == bars - 1 and left <= float(beats) * 0.6:
					step = clampi(end_deg - deg, -2, 2)
				deg += step
				if last_note:
					deg = end_deg
					dur = left
				notes.append([t + (float(beats) - left), dur, deg])
				left -= dur
				if left < 0.01:
					break
	return notes

## One section: bars of melody + accompaniment as events
static func _section(song: Dictionary, kind: String, r: Rng) -> Dictionary:
	var beats: int = int(song["beats"])
	var prog: Array = song["prog"] as Array
	var bars: int = 8
	var melody: Array = []
	var motif_a: Array = [[1.0, 0.5, 0.5, 1.0, 1.0] if beats == 4 else [1.0, 0.5, 0.5, 1.0]]
	match kind:
		"intro":
			bars = 4
		"outro":
			bars = 4
		"A", "A2":
			var p1: Array = _phrase(r, 4, beats, 4, 2, [])
			var p2: Array = _phrase(r, 4, beats, 3, 0, [])
			melody = p1.duplicate(true)
			for n in p2:
				melody.append([float(n[0]) + float(4 * beats), n[1], n[2]])
		"B":
			var q1: Array = _phrase(r, 4, beats, 5, 4, [])
			var q2: Array = _phrase(r, 4, beats, 5, 0, [])
			melody = q1.duplicate(true)
			for n in q2:
				melody.append([float(n[0]) + float(4 * beats), n[1], n[2]])
		"C":
			var c1: Array = _phrase(r, 4, beats, 3, 4, [[2.0, 1.0, 1.0], [1.5, 1.5, 1.0]])
			var c2: Array = _phrase(r, 4, beats, 4, 0, [[2.0, 1.0, 1.0], [1.5, 1.5, 1.0]])
			melody = c1.duplicate(true)
			for n in c2:
				melody.append([float(n[0]) + float(4 * beats), n[1], n[2]])
	var _unused: Array = motif_a
	return {"kind": kind, "bars": bars, "melody": melody, "prog": prog}

# ------------------------------------------------------------------ instruments (all ADD into buf)
## lute / harp: Karplus-Strong pluck
static func _lute(buf: PackedFloat32Array, f: float, t0: float, dur: float, amp: float, r: Rng) -> void:
	Synth.pluck(buf, f, t0, dur, amp, 0.9965 if f > 200.0 else 0.9985, r)

## flute / recorder / fiddle: a smooth voice with vibrato, breath and a slow attack
static func _lead(buf: PackedFloat32Array, kind: String, f: float, t0: float, dur: float, amp: float, r: Rng) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = mini(int(dur * float(SR)), buf.size() - start)
	if n <= 0:
		return
	var att: float = 0.05 if kind != "fiddle" else 0.09
	var rel: float = 0.12
	var ph: float = 0.0
	var vph: float = 0.0
	var inv: float = 1.0 / float(SR)
	var vib_hz: float = 5.0 if kind != "fiddle" else 5.8
	var vib_depth: float = 0.004 if kind != "fiddle" else 0.009
	var noise_lp: float = 0.0
	for i in n:
		var t: float = float(i) * inv
		var env: float = minf(t / att, 1.0)
		var left: float = dur - t
		if left < rel:
			env *= maxf(left / rel, 0.0)
		vph += TAU * vib_hz * inv
		var fr: float = f * (1.0 + sin(vph) * vib_depth * minf(t * 3.0, 1.0))
		ph += fr * inv
		ph -= floorf(ph)
		var s: float
		match kind:
			"fiddle":
				# a gentle saw (sum of a few partials) for a bowed sound
				s = sin(TAU * ph) + 0.5 * sin(TAU * ph * 2.0) + 0.33 * sin(TAU * ph * 3.0) + 0.2 * sin(TAU * ph * 4.0)
				s *= 0.55
			"recorder":
				s = sin(TAU * ph) + 0.18 * sin(TAU * ph * 2.0) + 0.06 * sin(TAU * ph * 3.0)
			_:
				s = sin(TAU * ph) + 0.28 * sin(TAU * ph * 2.0) + 0.1 * sin(TAU * ph * 3.0)
		noise_lp = noise_lp * 0.8 + (r.next_f() * 2.0 - 1.0) * 0.2
		s += noise_lp * (0.10 if kind != "fiddle" else 0.05) * minf(t * 8.0, 1.0)
		buf[start + i] += s * amp * env

## drone (hurdy-gurdy): the root and the fifth, slowly breathing
static func _drone(buf: PackedFloat32Array, f: float, t0: float, dur: float, amp: float) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = mini(int(dur * float(SR)), buf.size() - start)
	var inv: float = 1.0 / float(SR)
	var p1: float = 0.0
	var p2: float = 0.0
	for i in n:
		var t: float = float(i) * inv
		var env: float = minf(t / 0.6, 1.0) * minf((dur - t) / 0.8, 1.0)
		var breath: float = 0.8 + 0.2 * sin(TAU * 0.17 * t)
		p1 += f * inv
		p2 += f * 1.5 * inv
		p1 -= floorf(p1)
		p2 -= floorf(p2)
		var s: float = (sin(TAU * p1) + 0.5 * sin(TAU * p1 * 2.0) + 0.25 * sin(TAU * p1 * 3.0)) * 0.7 + sin(TAU * p2) * 0.25
		buf[start + i] += s * amp * env * breath

## frame drum: a round thump with a bit of skin noise
static func _drum(buf: PackedFloat32Array, t0: float, amp: float, r: Rng, high: bool) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = mini(int(0.22 * float(SR)), buf.size() - start)
	var ph: float = 0.0
	var inv: float = 1.0 / float(SR)
	for i in n:
		var t: float = float(i) * inv
		var f: float = (170.0 if high else 90.0) * (1.0 + 1.2 * exp(-t * 28.0))
		ph += f * inv
		var env: float = exp(-t * (26.0 if high else 18.0))
		buf[start + i] += (sin(TAU * ph) * 0.9 + (r.next_f() * 2.0 - 1.0) * 0.18 * exp(-t * 60.0)) * env * amp

## tambourine / shaker: a short burst of bright noise
static func _shaker(buf: PackedFloat32Array, t0: float, amp: float, r: Rng) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = mini(int(0.06 * float(SR)), buf.size() - start)
	var prev: float = 0.0
	for i in n:
		var x: float = r.next_f() * 2.0 - 1.0
		var hp: float = x - prev
		prev = x
		buf[start + i] += hp * amp * exp(-float(i) / float(SR) * 55.0)

## a small bell (struck bar): inharmonic partials with a long decay
static func _bell(buf: PackedFloat32Array, f: float, t0: float, amp: float) -> void:
	var start: int = int(t0 * float(SR))
	var n: int = mini(int(2.2 * float(SR)), buf.size() - start)
	var inv: float = 1.0 / float(SR)
	var parts: Array = [[1.0, 1.0, 2.2], [2.76, 0.5, 3.4], [5.4, 0.25, 5.0]]
	for p in parts:
		var pf: float = f * float((p as Array)[0])
		var pa: float = float((p as Array)[1])
		var dec: float = float((p as Array)[2])
		var ph: float = 0.0
		for i in n:
			var t: float = float(i) * inv
			ph += pf * inv
			buf[start + i] += sin(TAU * ph) * pa * amp * exp(-t * dec)

# ------------------------------------------------------------------ rendering
static func _render_section(song: Dictionary, sec: Dictionary, r: Rng, rich: bool) -> PackedFloat32Array:
	var bpm: float = float(song["bpm"])
	var beats: int = int(song["beats"])
	var root: float = float(song["root"])
	var mode: String = str(song["mode"])
	var lead_kind: String = str(song["lead"])
	var beat_s: float = 60.0 / bpm
	var bars: int = int(sec["bars"])
	var kind: String = str(sec["kind"])
	var prog: Array = sec["prog"] as Array
	var length_s: float = float(bars * beats) * beat_s
	var buf: PackedFloat32Array = Synth.make(length_s + 2.6)
	var quiet: bool = kind == "C" or kind == "intro" or kind == "outro"
	# drone under everything
	_drone(buf, root * 0.5, 0.0, length_s + 1.0, 0.16 if not quiet else 0.2)
	# bar by bar: bass note and lute arpeggio
	for b in bars:
		var deg: int = int(prog[b % prog.size()])
		var t_bar: float = float(b * beats) * beat_s
		_lute(buf, _hz(root, mode, deg - 7), t_bar, beat_s * float(beats) * 0.95, 0.5, r)
		var chord: Array = [deg, deg + 2, deg + 4, deg + 7]
		var steps: int = beats * 2
		for s in steps:
			var pat: Array = [0, 1, 2, 1] if beats == 4 else [0, 2, 1, 3, 2, 1]
			var note: int = int(chord[int(pat[s % pat.size()])])
			if kind == "outro" and b == bars - 1 and s > 0:
				continue
			_lute(buf, _hz(root, mode, note), t_bar + float(s) * beat_s * 0.5, beat_s * 1.2, 0.17 if not quiet else 0.2, r)
	# melody
	for n in sec["melody"] as Array:
		var nd: Array = n as Array
		var f: float = _hz(root, mode, int(nd[2]) + 7 + (2 if kind == "B" else 0))          # the lead sings one octave above the root
		var t0: float = float(nd[0]) * beat_s
		var dur: float = float(nd[1]) * beat_s
		_lead(buf, lead_kind, f, t0, dur * 0.97, 0.22 if kind != "C" else 0.17, r)
		if rich and kind != "C":
			_lead(buf, "recorder" if lead_kind == "flute" else "flute", f * 0.5, t0 + 0.015, dur * 0.95, 0.07, r)       # a quieter lower double
	# percussion
	if bool(song["drums"]) and (kind == "A2" or kind == "B") :
		for b in bars:
			for k in beats:
				var tt: float = float(b * beats + k) * beat_s
				_drum(buf, tt, 0.34 if k == 0 else 0.2, r, k != 0)
				_shaker(buf, tt + beat_s * 0.5, 0.05, r)
	elif bool(song["drums"]) and kind == "A":
		for b in bars:
			_drum(buf, float(b * beats) * beat_s, 0.22, r, false)
	# bells on the first beat of every second bar in the calm parts and the bridge
	if bool(song["bells"]) and (kind == "C" or kind == "intro" or kind == "B"):
		for b in range(0, bars, 2):
			var dg: int = int(prog[b % prog.size()])
			_bell(buf, _hz(root, mode, dg + 7) * 2.0, float(b * beats) * beat_s, 0.05)
	Synth.reverb(buf, 0.62, 0.45, 0.32)
	return buf

## Composes and renders song `i` completely: PackedFloat32Array at 32 kHz
static func render_song(i: int) -> AudioStreamWAV:
	var song: Dictionary = SONGS[i] as Dictionary
	var r := Rng.new(int(song["seed"]) * 7919 + 13)
	var beat_s: float = 60.0 / float(song["bpm"])
	var beats: int = int(song["beats"])
	# the order of the sections: intro, then A / B with a bridge, until the song is long enough
	var order: Array[String] = ["intro", "A", "A2", "B", "A2", "C", "A", "B", "A2", "B"]
	var total: float = 0.0
	var cache: Dictionary = {}
	var seq: Array[String] = []
	var idx: int = 0
	while true:
		var kind: String = order[idx] if idx < order.size() else (["A2", "B", "A", "C"][(idx - order.size()) % 4] as String)
		seq.append(kind)
		var bars: int = 4 if kind == "intro" else 8
		total += float(bars * beats) * beat_s
		idx += 1
		if total >= TARGET_SECONDS and kind != "intro":
			break
	seq.append("outro")
	total += 4.0 * float(beats) * beat_s
	var out: PackedFloat32Array = Synth.make(total + 3.0)
	var offset: float = 0.0
	for kind2 in seq:
		if not cache.has(kind2):
			var base_kind: String = "A" if kind2 == "A2" else kind2
			var rr := Rng.new(int(song["seed"]) * 131 + base_kind.unicode_at(0) * 17 + (3 if kind2 == "A2" else 0))
			var sec: Dictionary = _section(song, base_kind, Rng.new(int(song["seed"]) * 131 + base_kind.unicode_at(0) * 17))
			sec["kind"] = kind2
			cache[kind2] = _render_section(song, sec, rr, kind2 == "A2" or kind2 == "B")
		var sb: PackedFloat32Array = cache[kind2] as PackedFloat32Array
		Synth.mix_into(out, sb, 1.0, offset)
		var bars2: int = 4 if (kind2 == "intro" or kind2 == "outro") else 8
		offset += float(bars2 * beats) * beat_s
	Synth.dc_block(out)
	Synth.fade_in(out, 1.5)
	Synth.fade_out(out, 3.0)
	Synth.normalize(out, 0.55)
	return _to_stream_16k(out)

## 16 kHz, 16 bit: music does not need more, and three songs stay small in memory
static func _to_stream_16k(buf: PackedFloat32Array) -> AudioStreamWAV:
	var n: int = buf.size() / 2
	var data := PackedByteArray()
	data.resize(n * 2)
	for k in n:
		var v: float = (buf[2 * k] + buf[2 * k + 1]) * 0.5
		data.encode_s16(k * 2, clampi(int(v * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR / 2
	s.stereo = false
	s.data = data
	return s
