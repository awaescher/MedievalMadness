class_name MapGen
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Seeded map generation (spec section 7). Uses only Rng (mulberry32) + Noise.

static func map_radius_for(player_count: int) -> float:
	return 60.0 + 14.0 * float(player_count)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## hill_level 0 (flat), 1 gentle, 2 normal (default), 3 hilly, 4 mountainous (drastic). `layout_nonce`: see village sites below
static func generate(seed_str: String, player_count: int, hill_level: int = 2, layout_nonce: String = "") -> MapData:
	var rng := Rng.from_string(seed_str)
	var d := MapData.new()
	d.seed_str = seed_str
	d.seed_int = Rng.fnv1a(seed_str)
	d.player_count = player_count
	# every seed gets its own map size (0.9x - 1.9x of the base radius, capped by the 256-vertex terrain limit), so the
	# distance to the enemy - and with it the needed power - differs from map to map
	var R: float = minf(map_radius_for(player_count) * rng.range_f(1.3, 3.0), 300.0)
	d.map_radius = R
	d.side = 2.0 * R + 40.0
	d.cell = Cfg.TERRAIN_CELL
	d.n = mini(Cfg.TERRAIN_MAX_VERTS, int(ceil(d.side / d.cell)) + 1)
	d.cell = d.side / float(d.n - 1)
	d.origin = -d.side * 0.5
	var nseed: int = rng.next_u32() & 0xFFFF
	var nseed2: int = rng.next_u32() & 0xFFFF
	var water: float = Cfg.WATER_LEVEL

	# ---- rivers, canyons, dry gorges (0-3, some with a tributary) - every one different
	var river_count: int = rng.range_i(0, 3)
	for i in river_count:
		var roll: float = rng.next_f()
		var kind: String = "stream" if roll < 0.22 else ("river" if roll < 0.5 else ("canyon" if roll < 0.8 else "gorge"))
		var main: Dictionary = _make_river(rng, R, kind, Vector2.INF, 0.0, 1.0)
		d.rivers.append(main)
		if rng.chance(0.45):
			# a tributary leaves the main course at an angle
			var mpts: PackedVector2Array = main["pts"]
			var bi: int = rng.range_i(5, mpts.size() - 6)
			var bdir: Vector2 = (mpts[bi + 1] - mpts[bi]).normalized()
			var bang: float = bdir.angle() + rng.sign_f() * rng.range_f(0.7, 1.3)
			d.rivers.append(_make_river(rng, R, "stream" if kind != "canyon" else "canyon", mpts[bi], bang, rng.range_f(0.4, 0.7)))

	# ---- lakes (0-4): ponds, big irregular lakes, long lakes; the center may hold one more
	var lake_count: int = rng.range_i(0, 4)
	for i in lake_count:
		d.lakes.append(_make_lake(rng, rng.in_circle(R * 0.7), -1.0))
	d.center_kind = "ruin" if rng.chance(0.5) else "lake"
	if d.center_kind == "lake":
		d.lakes.append(_make_lake(rng, Vector2.ZERO, rng.range_f(9.0, 13.0)))

	# ---- height function (before village flattening)
	var hfun := func(x: float, z: float) -> float:
		var r: float = sqrt(x * x + z * z)
		var coast: float = (VNoise.fbm(x, z, nseed2, 3, 1.0 / 45.0) - 0.5) * 18.0
		var re: float = r + coast
		var mask: float = 1.0 - Util.smooth01((re - (R - 25.0)) / 25.0)
		# levels: flat, gentle, normal (default), hilly, mountainous (drastic)
		var lv: int = clampi(hill_level, 0, 4)
		var hill_amp: float = [2.0, 10.0, 26.0, 34.0, 44.0][lv]
		var broad: float = [0.0, 8.0, 32.0, 48.0, 70.0][lv]
		var land: float = 1.2 + VNoise.fbm(x, z, nseed, 4, 1.0 / 70.0) * hill_amp
		if broad > 0.0:
			# broad hills / valleys on top
			land += (VNoise.fbm(x, z, nseed2, 3, 1.0 / 130.0) - 0.5) * broad
		if lv == 4:
			# mountainous: sharp ridges and deep gorges on top of everything
			var ridge: float = 1.0 - absf(VNoise.fbm(x + 311.0, z - 97.0, nseed, 3, 1.0 / 110.0) * 2.0 - 1.0)
			land += ridge * ridge * 30.0 - 10.0
		if d.center_kind == "ruin":
			var cr: float = r / 16.0
			land += 3.2 * exp(-cr * cr)
		var h: float = lerpf(-3.5, land, mask)
		var p := Vector2(x, z)
		for rv in d.rivers:
			var bb: Rect2 = rv["bb"]
			if not bb.has_point(p):
				continue
			var pts: PackedVector2Array = rv["pts"]
			var ws: PackedFloat32Array = rv["ws"]
			var best: float = 1e9
			var wbest: float = 4.0
			for k in pts.size() - 1:
				var dk: float = _seg_dist(p, pts[k], pts[k + 1])
				if dk < best:
					best = dk
					wbest = (ws[k] + ws[k + 1]) * 0.5
			var bank: float = float(rv["bank"])
			var edge: float = wbest * 0.5 + bank
			if best < edge:
				var t: float = pow(Util.smooth01((edge - best) / bank), float(rv["prof"]))
				var floor_h: float = water + float(rv["dry"]) if bool(rv["is_dry"]) else water - float(rv["depth"])
				h = minf(h, lerpf(h, floor_h, t))
		for lk in d.lakes:
			var c: Vector2 = lk["c"]
			var lr: float = float(lk["r"])
			var bank_l: float = float(lk["bank"])
			if p.distance_to(c) > lr * float(lk["reach"]) + bank_l:
				continue
			var q: Vector2 = (p - c).rotated(-float(lk["rot"]))
			var sx: float = float(lk["sx"])
			var de: float = Vector2(q.x / sx, q.y * sx).length()
			var th: float = atan2(q.y, q.x)
			var wob: float = 1.0
			for w in (lk["wob"] as Array):
				wob += float((w as Array)[1]) * sin(float((w as Array)[0]) * th + float((w as Array)[2]))
			var rr: float = lr * wob
			if de < rr + bank_l:
				var t2: float = pow(Util.smooth01((rr + bank_l - de) / bank_l), float(lk["prof"]))
				h = minf(h, lerpf(h, water - float(lk["depth"]), t2))
		return h

	# ---- village sites (index i belongs to player i)
	# The map SEED decides the terrain only. The village layout comes from its own generator: seed + layout nonce. The game
	# draws a new nonce for every new match (so the same seed gives the same island but different village positions);
	# "play again on the same map" keeps the nonce. Villages are placed uniformly at random over the island, but never
	# (nearly) on one straight line.
	var lay: Rng = Rng.from_string(seed_str + "|layout|" + layout_nonce)
	var min_dist: float = 2.6 * Cfg.ZONE_RADIUS
	for i in player_count:
		var placed: bool = false
		for attempt in 500:
			var rad: float = R * 0.82 * sqrt(lay.next_f())
			var ang2: float = lay.range_f(0.0, TAU)
			var pos := Vector2(cos(ang2) * rad, sin(ang2) * rad)
			# terrain check: center + ring samples must be dry
			var ok: bool = float(hfun.call(pos.x, pos.y)) >= water + 1.0
			if ok:
				for k in 8:
					var a3: float = TAU * float(k) / 8.0
					var hh: float = float(hfun.call(pos.x + cos(a3) * Cfg.ZONE_RADIUS * 0.9, pos.y + sin(a3) * Cfg.ZONE_RADIUS * 0.9))
					if hh < water + 0.6:
						ok = false
						break
			if ok and d.center_kind == "lake" and pos.length() < 30.0:
				ok = false
			if ok:
				for s in d.sites:
					if Vector2(s.x, s.z).distance_to(pos) < min_dist:
						ok = false
						break
			# never put villages on (nearly) one line: every triangle of three villages keeps all angles >= 20 degrees
			if ok and attempt < 400 and d.sites.size() >= 2:
				for ia in d.sites.size():
					for ib in range(ia + 1, d.sites.size()):
						var sa := Vector2(d.sites[ia].x, d.sites[ia].z)
						var sb := Vector2(d.sites[ib].x, d.sites[ib].z)
						if _min_angle(sa, sb, pos) < deg_to_rad(20.0):
							ok = false
			if ok:
				d.sites.append(Vector3(pos.x, 0.0, pos.y))
				placed = true
				break
		if not placed:
			# last resort: the ring slot (of 24) that is farthest from every village placed so far
			var best_slot: Vector2 = Vector2(R * 0.4, 0.0)
			var best_d: float = -1.0
			for sl in 24:
				var a4: float = TAU * float(sl) / 24.0
				var sp := Vector2(cos(a4) * R * 0.45, sin(a4) * R * 0.45)
				var nearest: float = 1e9
				for s2 in d.sites:
					nearest = minf(nearest, Vector2(s2.x, s2.z).distance_to(sp))
				if nearest > best_d:
					best_d = nearest
					best_slot = sp
			d.sites.append(Vector3(best_slot.x, 0.0, best_slot.y))

	# ---- build heightfield (+ flatten village sites)
	d.heights.resize(d.n * d.n)
	for iz in d.n:
		for ix in d.n:
			var x: float = d.origin + float(ix) * d.cell
			var z: float = d.origin + float(iz) * d.cell
			d.heights[iz * d.n + ix] = float(hfun.call(x, z))
	var flat_seed: int = nseed ^ 0x5A5A
	for si in d.sites.size():
		var s: Vector3 = d.sites[si]
		# average height within the zone
		var sum: float = 0.0
		var cnt: int = 0
		var rr: float = Cfg.ZONE_RADIUS
		var gx: float = -rr
		while gx <= rr:
			var gz: float = -rr
			while gz <= rr:
				if gx * gx + gz * gz <= rr * rr:
					sum += d.height_at(s.x + gx, s.z + gz)
					cnt += 1
				gz += 3.0
			gx += 3.0
		var target: float = maxf(sum / float(maxi(cnt, 1)), 0.9)
		var band: float = 8.0
		var reach: float = rr + band
		var ix0: int = clampi(floori((s.x - reach - d.origin) / d.cell), 0, d.n - 1)
		var ix1: int = clampi(ceili((s.x + reach - d.origin) / d.cell), 0, d.n - 1)
		var iz0: int = clampi(floori((s.z - reach - d.origin) / d.cell), 0, d.n - 1)
		var iz1: int = clampi(ceili((s.z + reach - d.origin) / d.cell), 0, d.n - 1)
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var x2: float = d.origin + float(ix) * d.cell
				var z2: float = d.origin + float(iz) * d.cell
				var dist: float = Vector2(x2 - s.x, z2 - s.z).length()
				if dist > reach:
					continue
				var w: float = 1.0 if dist <= rr else 1.0 - Util.smooth01((dist - rr) / band)
				var undul: float = (VNoise.fbm(x2, z2, flat_seed, 2, 1.0 / 14.0) - 0.5) * 0.5
				var hcur: float = d.heights[iz * d.n + ix]
				d.heights[iz * d.n + ix] = lerpf(hcur, target + undul, w)
		d.sites[si] = Vector3(s.x, target, s.z)

	# ---- center + duck
	d.center = Vector3(0.0, d.height_at(0.0, 0.0), 0.0)
	var wet: Array[Vector3] = []
	for lk in d.lakes:
		var c2: Vector2 = lk["c"]
		wet.append(Vector3(c2.x, water, c2.y))
	for rv in d.rivers:
		var pts2: PackedVector2Array = rv["pts"]
		if pts2.size() > 3:
			var pm: Vector2 = pts2[pts2.size() / 2]
			wet.append(Vector3(pm.x, water, pm.y))
	if wet.size() > 0:
		d.duck_pos = wet[rng.range_i(0, wet.size() - 1)]
	return d

## One river / canyon / gorge as a wandering polyline with varying width.
## kinds: stream (narrow, shallow), river (wide, meandering, gentle banks), canyon (narrow, deep, steep walls),
## gorge (dry ravine: its floor stays above the water). `start` INF = random inner point.
static func _make_river(rng: Rng, R: float, kind: String, start: Vector2, heading: float, len_k: float) -> Dictionary:
	var width: float
	var depth: float = 0.6
	var bank: float
	var prof: float = 1.2
	var bend: float
	var dry: float = 0.0
	match kind:
		"stream":
			width = rng.range_f(2.5, 4.5)
			depth = rng.range_f(0.5, 0.9)
			bank = rng.range_f(3.0, 5.0)
			bend = rng.range_f(0.18, 0.32)
		"river":
			width = rng.range_f(7.0, 13.0)
			depth = rng.range_f(1.2, 2.2)
			bank = rng.range_f(7.0, 13.0)
			prof = rng.range_f(1.3, 1.8)
			bend = rng.range_f(0.26, 0.42)
		"canyon":
			width = rng.range_f(3.5, 6.5)
			depth = rng.range_f(4.0, 7.5)
			bank = rng.range_f(2.2, 3.6)
			prof = rng.range_f(0.45, 0.7)
			bend = rng.range_f(0.1, 0.2)
		_:
			width = rng.range_f(4.0, 8.0)
			bank = rng.range_f(2.6, 4.5)
			prof = rng.range_f(0.5, 0.8)
			bend = rng.range_f(0.14, 0.26)
			dry = rng.range_f(1.2, 2.2)
	var pos: Vector2 = start if start.x < 1e8 else rng.in_circle(R * 0.5)
	var ang: float = heading if start.x < 1e8 else rng.range_f(0.0, TAU)
	var steps: int = 22
	var step_len: float = R * rng.range_f(1.0, 1.7) * len_k / float(steps)
	var pts := PackedVector2Array()
	var ws := PackedFloat32Array()
	var ph: float = rng.range_f(0.0, TAU)
	var curv: float = 0.0
	# the river may start in the middle of the map and runs both ways: first walk backwards a little
	pts.append(pos)
	ws.append(width)
	for s in steps:
		curv = lerpf(curv, rng.gauss() * bend, 0.45)
		ang += curv
		if kind == "canyon" and rng.chance(0.14):
			ang += rng.sign_f() * rng.range_f(0.35, 0.75)      # sharp zigzags
		pos += Vector2(cos(ang), sin(ang)) * step_len
		pts.append(pos)
		ws.append(width * (1.0 + 0.32 * sin(float(s) * 0.65 + ph) + rng.range_f(-0.08, 0.08)))
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var margin: float = width * 1.3 + bank + 2.0
	return {"pts": pts, "ws": ws, "width": width, "depth": depth, "bank": bank, "prof": prof, "dry": dry, "is_dry": kind == "gorge",
		"kind": kind, "bb": Rect2(lo - Vector2(margin, margin), (hi - lo) + Vector2(margin, margin) * 2.0)}

## A lake with an irregular outline (harmonic wobble), optional stretching and its own depth / bank softness.
static func _make_lake(rng: Rng, c: Vector2, forced_r: float) -> Dictionary:
	var roll: float = rng.next_f()
	var r: float
	var depth: float
	var bank: float
	var stretch: float = 1.0
	var prof: float = 1.0
	if forced_r > 0.0:
		r = forced_r
		depth = rng.range_f(1.2, 2.4)
		bank = rng.range_f(3.0, 6.0)
	elif roll < 0.4:
		r = rng.range_f(5.0, 9.0)               # pond
		depth = rng.range_f(0.5, 1.0)
		bank = rng.range_f(2.5, 4.0)
	elif roll < 0.75:
		r = rng.range_f(12.0, 24.0)             # big lake
		depth = rng.range_f(1.8, 3.4)
		bank = rng.range_f(4.0, 8.0)
		prof = rng.range_f(0.8, 1.4)
	else:
		r = rng.range_f(10.0, 18.0)             # long lake
		depth = rng.range_f(1.2, 2.4)
		bank = rng.range_f(3.0, 6.0)
		stretch = rng.range_f(1.8, 3.2)
	var wob: Array = []
	for k in [2, 3, 5]:
		wob.append([float(k), rng.range_f(0.04, 0.3) / float(k) * 2.0, rng.range_f(0.0, TAU)])
	var sx: float = sqrt(stretch)
	return {"c": c, "r": r, "depth": depth, "bank": bank, "prof": prof, "rot": rng.range_f(0.0, PI), "sx": sx, "wob": wob,
		"reach": stretch * 1.8}

## Smallest interior angle (radians) of the triangle a-b-c
static func _min_angle(a: Vector2, b: Vector2, c: Vector2) -> float:
	var best: float = PI
	for tri in [[a, b, c], [b, c, a], [c, a, b]]:
		var v1: Vector2 = ((tri as Array)[1] as Vector2) - ((tri as Array)[0] as Vector2)
		var v2: Vector2 = ((tri as Array)[2] as Vector2) - ((tri as Array)[0] as Vector2)
		if v1.length() < 0.001 or v2.length() < 0.001:
			return 0.0
		best = minf(best, absf(v1.angle_to(v2)))
	return best
