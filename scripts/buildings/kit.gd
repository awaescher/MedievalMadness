class_name Kit
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Helper functions for building blueprints (spec 9): boxes, walls of blocks, gable roofs,
## floors, crenellations... Local space: origin = ground center, +Y up, building front = +Z.

const NO_COLOR := Color(-1, -1, -1, 1)

static func pick_color(mat: String, rng: Rng) -> Color:
	var pal: Array[Color] = Materials.get_def(mat).palette
	if pal.is_empty():
		return Color.WHITE
	if rng == null:
		return pal[0]
	return Util.color_jitter(pal[rng.range_i(0, pal.size() - 1)], rng, 0.025)

static func _finish(p: PartDef, rng: Rng, color: Color) -> PartDef:
	p.color = color if color.r >= 0.0 else pick_color(p.material, rng)
	return p

static func box(r: BuildResult, mat: String, size: Vector3, pos: Vector3, rng: Rng = null, color: Color = NO_COLOR, anchor: bool = false, tag: String = "", rot: Vector3 = Vector3.ZERO) -> PartDef:
	var p := PartDef.new()
	p.material = mat
	p.size = size
	p.pos = pos
	p.rot = rot
	p.shape = "box"
	p.anchor = anchor
	p.tag = tag
	r.add(p)
	return _finish(p, rng, color)

static func cyl(r: BuildResult, mat: String, radius: float, height: float, pos: Vector3, rng: Rng = null, color: Color = NO_COLOR, anchor: bool = false, tag: String = "", rot: Vector3 = Vector3.ZERO) -> PartDef:
	var p := PartDef.new()
	p.material = mat
	p.size = Vector3(radius * 2.0, height, radius * 2.0)
	p.pos = pos
	p.rot = rot
	p.shape = "cyl"
	p.anchor = anchor
	p.tag = tag
	r.add(p)
	return _finish(p, rng, color)

static func sph(r: BuildResult, mat: String, radius: float, pos: Vector3, rng: Rng = null, color: Color = NO_COLOR, tag: String = "") -> PartDef:
	var p := PartDef.new()
	p.material = mat
	p.size = Vector3(radius * 2.0, radius * 2.0, radius * 2.0)
	p.pos = pos
	p.shape = "sphere"
	p.tag = tag
	r.add(p)
	return _finish(p, rng, color)

static func frustum(r: BuildResult, mat: String, r_bottom: float, r_top: float, height: float, pos: Vector3, rng: Rng = null, color: Color = NO_COLOR, anchor: bool = false, tag: String = "") -> PartDef:
	var p := PartDef.new()
	p.segs = 12
	p.material = mat
	p.size = Vector3(r_bottom * 2.0, height, r_top * 2.0)
	p.pos = pos
	p.shape = "frustum"
	p.anchor = anchor
	p.tag = tag
	r.add(p)
	return _finish(p, rng, color)

## Wall built from courses of blocks along the XZ segment a->b (running bond).
## openings: Array of Rect2 (x = u from a, y = v height above y0, size = width/height).
static func wall(r: BuildResult, mat: String, a: Vector2, b: Vector2, y0: float, height: float, thick: float, blen: float, bh: float, rng: Rng, openings: Array = [], anchor_bottom: bool = false, color: Color = NO_COLOR, tag: String = "") -> void:
	var dir2: Vector2 = b - a
	var length: float = dir2.length()
	if length < 0.05:
		return
	dir2 = dir2 / length
	var rows: int = maxi(1, roundi(height / bh))
	var rh: float = height / float(rows)
	var yaw: float = atan2(-dir2.y, dir2.x)
	for i in rows:
		var vy0: float = float(i) * rh
		var vy1: float = vy0 + rh
		var offset: float = blen * 0.5 if (i % 2 == 1) else 0.0
		var u: float = 0.0
		var first: bool = true
		while u < length - 0.02:
			var l: float = blen
			if first and offset > 0.05:
				l = offset
			first = false
			l = minf(l, length - u)
			if l < 0.12:
				break
			# a block touching an opening is cut at the opening's side edges; the pieces beside, above and below it stay
			var cuts: Array[float] = [u, u + l]
			for o in openings:
				var rc: Rect2 = o as Rect2
				if vy0 < rc.end.y - 0.01 and vy1 > rc.position.y + 0.01:
					for e: float in [rc.position.x, rc.end.x]:
						if e > u + 0.01 and e < u + l - 0.01:
							cuts.append(e)
			cuts.sort()
			for ci in cuts.size() - 1:
				var ua: float = cuts[ci]
				var sl: float = cuts[ci + 1] - ua
				if sl < 0.1:
					continue
				var um: float = ua + sl * 0.5
				var free: Array[Vector2] = [Vector2(vy0, vy1)]
				for o2 in openings:
					var rc2: Rect2 = o2 as Rect2
					if um > rc2.position.x and um < rc2.end.x:
						var next_free: Array[Vector2] = []
						for iv in free:
							if rc2.position.y > iv.x + 0.01:
								next_free.append(Vector2(iv.x, minf(iv.y, rc2.position.y)))
							if rc2.end.y < iv.y - 0.01:
								next_free.append(Vector2(maxf(iv.x, rc2.end.y), iv.y))
						free = next_free
				var c2: Vector2 = a + dir2 * um
				for iv2 in free:
					if iv2.y - iv2.x < 0.12:
						continue
					box(r, mat, Vector3(sl, iv2.y - iv2.x, thick), Vector3(c2.x, y0 + (iv2.x + iv2.y) * 0.5, c2.y), rng, color, anchor_bottom and i == 0 and iv2.x <= vy0 + 0.01, tag, Vector3(0, yaw, 0))
			u += l

## Rectangle of 4 walls around a footprint (centered at c, half extents hx,hz). front = +Z side has openings list.
static func house_walls(r: BuildResult, mat: String, c: Vector2, hx: float, hz: float, y0: float, height: float, thick: float, blen: float, bh: float, rng: Rng, front_open: Array = [], back_open: Array = [], left_open: Array = [], right_open: Array = [], color: Color = NO_COLOR, tag: String = "") -> void:
	# walls run corner to corner; corner overlap avoided by shortening side walls
	wall(r, mat, Vector2(c.x - hx, c.y + hz), Vector2(c.x + hx, c.y + hz), y0, height, thick, blen, bh, rng, front_open, false, color, tag)
	wall(r, mat, Vector2(c.x + hx, c.y - hz), Vector2(c.x - hx, c.y - hz), y0, height, thick, blen, bh, rng, back_open, false, color, tag)
	wall(r, mat, Vector2(c.x - hx, c.y - hz + thick), Vector2(c.x - hx, c.y + hz - thick), y0, height, thick, blen, bh, rng, left_open, false, color, tag)
	wall(r, mat, Vector2(c.x + hx, c.y + hz - thick), Vector2(c.x + hx, c.y - hz + thick), y0, height, thick, blen, bh, rng, right_open, false, color, tag)

## Ring of foundation blocks (anchored)
static func foundation(r: BuildResult, mat: String, c: Vector2, hx: float, hz: float, h: float, thick: float, blen: float, rng: Rng, y0: float = 0.0) -> void:
	var pts: Array[Vector2] = [Vector2(c.x - hx, c.y + hz), Vector2(c.x + hx, c.y + hz), Vector2(c.x + hx, c.y - hz), Vector2(c.x - hx, c.y - hz), Vector2(c.x - hx, c.y + hz)]
	for i in 4:
		wall(r, mat, pts[i], pts[i + 1], y0, h, thick, blen, h, rng, [], true, NO_COLOR, "foundation")

## Wooden floor slab made of planks along X
static func floor_planks(r: BuildResult, mat: String, c: Vector2, w: float, d: float, y: float, plank_d: float, thick: float, rng: Rng, anchor: bool = false, tag: String = "floor") -> void:
	var n: int = maxi(1, roundi(d / plank_d))
	var pd: float = d / float(n)
	for i in n:
		box(r, mat, Vector3(w, thick, pd), Vector3(c.x, y, c.y - d * 0.5 + (float(i) + 0.5) * pd), rng, NO_COLOR, anchor, tag)

## Gable roof: ridge along Z, slopes toward +-X.
static func gable_roof(r: BuildResult, mat: String, c: Vector2, y_base: float, half_w: float, half_d: float, rise: float, thick: float, panel: float, rng: Rng, overhang: float = 0.3, color: Color = NO_COLOR, tag: String = "roof") -> void:
	var theta: float = atan2(rise, half_w)
	var slope_len: float = sqrt(half_w * half_w + rise * rise) + overhang
	var n_s: int = maxi(1, roundi(slope_len / panel))
	var plen: float = slope_len / float(n_s)
	var depth: float = half_d * 2.0 + overhang * 2.0
	var n_r: int = maxi(1, roundi(depth / panel))
	var pdz: float = depth / float(n_r)
	for side in [-1.0, 1.0]:
		var s: float = side as float
		for i in n_s:
			var d: float = (float(i) + 0.5) * plen - overhang * 0.0
			# distance from the ridge along the slope
			var x: float = s * d * cos(theta)
			var y: float = y_base + rise - d * sin(theta) + thick * 0.5
			for j in n_r:
				var z: float = c.y - half_d - overhang + (float(j) + 0.5) * pdz
				box(r, mat, Vector3(plen * 1.02, thick, pdz * 1.02), Vector3(c.x + x, y, z), rng, color, false, tag, Vector3(0, 0, -s * theta))
	# ridge cap
	box(r, "wood", Vector3(0.28, 0.16, depth), Vector3(c.x, y_base + rise + 0.05, c.y), rng, NO_COLOR, false, tag)

## Filled triangular gable end wall at z (thin planks stacked, narrowing upward)
static func gable_end(r: BuildResult, mat: String, c: Vector2, z: float, y_base: float, half_w: float, rise: float, thick: float, rng: Rng, color: Color = NO_COLOR, row_h: float = 0.55) -> void:
	var rows: int = maxi(1, roundi(rise / row_h))
	var rh: float = rise / float(rows)
	for k in rows:
		var hmid: float = (float(k) + 0.5) * rh
		var w: float = 2.0 * half_w * (1.0 - hmid / rise)
		if w < 0.3:
			continue
		box(r, mat, Vector3(w, rh, thick), Vector3(c.x, y_base + hmid, z), rng, color, false, "wall")

## Square pyramid roof (4-sided frustum rotated 45 degrees so faces align with the axes)
static func pyramid_roof(r: BuildResult, mat: String, c: Vector2, y_base: float, half_w: float, rise: float, rng: Rng, color: Color = NO_COLOR, tag: String = "roof") -> PartDef:
	var rb: float = half_w * 1.414 + 0.25
	var p: PartDef = frustum(r, mat, rb, 0.05, rise, Vector3(c.x, y_base + rise * 0.5, c.y), rng, color, false, tag)
	p.segs = 4
	p.rot = Vector3(0, PI * 0.25, 0)
	return p

## Crenellations (alternating merlons) along a rectangle perimeter at height y
static func crenellations(r: BuildResult, mat: String, c: Vector2, hx: float, hz: float, y: float, merlon: Vector3, gap: float, rng: Rng) -> void:
	var pts: Array[Vector2] = [Vector2(c.x - hx, c.y + hz), Vector2(c.x + hx, c.y + hz), Vector2(c.x + hx, c.y - hz), Vector2(c.x - hx, c.y - hz), Vector2(c.x - hx, c.y + hz)]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var length: float = a.distance_to(b)
		if length < 0.05:
			continue
		var dir2: Vector2 = (b - a) / length
		var yaw: float = atan2(-dir2.y, dir2.x)
		var n: int = maxi(1, int(length / (merlon.x + gap)))
		var step: float = length / float(n)
		for k in n:
			var u: float = (float(k) + 0.5) * step
			var p2: Vector2 = a + dir2 * u
			box(r, mat, merlon, Vector3(p2.x, y + merlon.y * 0.5, p2.y), rng, NO_COLOR, false, "crenel", Vector3(0, yaw, 0))

## Circular ring of blocks (for round towers, wells, tanks). Blocks tangent to the ring.
static func ring(r: BuildResult, mat: String, c: Vector2, radius: float, y0: float, height: float, thick: float, seg: int, bh: float, rng: Rng, anchor_bottom: bool = false, gap_angle: Array = [], color: Color = NO_COLOR, tag: String = "") -> void:
	var rows: int = maxi(1, roundi(height / bh))
	var rh: float = height / float(rows)
	var chord: float = 2.0 * radius * sin(PI / float(seg)) * 1.03
	for i in rows:
		for k in seg:
			var a: float = (float(k) + (0.5 if i % 2 == 1 else 0.0)) / float(seg) * TAU
			var skip: bool = false
			for g in gap_angle:
				var ga: Vector2 = g as Vector2
				if absf(Util.angle_diff(a, ga.x)) < ga.y and float(i) * rh < 2.2:
					skip = true
			if skip:
				continue
			var p2 := Vector2(c.x + cos(a) * radius, c.y + sin(a) * radius)
			box(r, mat, Vector3(chord, rh, thick), Vector3(p2.x, y0 + (float(i) + 0.5) * rh, p2.y), rng, color, anchor_bottom and i == 0, tag, Vector3(0, -a + PI * 0.5, 0))

## Vertical post
static func post(r: BuildResult, mat: String, pos_base: Vector3, height: float, thick: float, rng: Rng, tag: String = "post", anchor: bool = false) -> PartDef:
	return box(r, mat, Vector3(thick, height, thick), pos_base + Vector3(0, height * 0.5, 0), rng, NO_COLOR, anchor, tag)

static func door(r: BuildResult, c2: Vector2, y: float, w: float, h: float, yaw: float, rng: Rng) -> void:
	box(r, "wood", Vector3(w, h, 0.14), Vector3(c2.x, y + h * 0.5, c2.y), rng, Color("#7a4a25"), false, "door", Vector3(0, yaw, 0))

static func window(r: BuildResult, c2: Vector2, y: float, w: float, h: float, yaw: float, rng: Rng, frame_color: Color = NO_COLOR) -> void:
	box(r, "glass", Vector3(w, h, 0.07), Vector3(c2.x, y + h * 0.5, c2.y), rng, Color("#9fe0ff"), false, "window", Vector3(0, yaw, 0))
	# window frame (thin planks)
	box(r, "plank", Vector3(w + 0.16, 0.1, 0.12), Vector3(c2.x, y + h + 0.05, c2.y), rng, frame_color, false, "frame", Vector3(0, yaw, 0))

## Bounding radius helper for extents
static func max_radius(r: BuildResult) -> float:
	var m: float = 0.0
	for p in r.parts:
		m = maxf(m, Vector2(p.pos.x, p.pos.z).length() + maxf(p.size.x, p.size.z) * 0.5)
	return m

static func max_height(r: BuildResult) -> float:
	var m: float = 0.0
	for p in r.parts:
		m = maxf(m, p.pos.y + p.size.y * 0.5)
	return m
