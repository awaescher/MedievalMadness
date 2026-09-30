extends SceneTree
## Dev tool: renders top-down height maps (water blue, land by height, steep slopes darker) of several seeds to
## /tmp/mm_maps/*.png and prints generation time and the river kinds. Usage: --script res://tests/map_render.gd
func _init() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/mm_maps")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var level: int = 2
	if args.size() > 0:
		level = int(args[0])
	for k in 8:
		var t0: int = Time.get_ticks_msec()
		var m: MapData = MapGen.generate("mapview-%d" % k, 3, level)
		var ms: int = Time.get_ticks_msec() - t0
		var kinds: Array[String] = []
		for rv in m.rivers:
			kinds.append(str((rv as Dictionary)["kind"]))
		var img := Image.create(m.n, m.n, false, Image.FORMAT_RGB8)
		var hmax: float = 1.0
		for hv in m.heights:
			hmax = maxf(hmax, hv)
		for iz in m.n:
			for ix in m.n:
				var x: float = m.origin + float(ix) * m.cell
				var z: float = m.origin + float(iz) * m.cell
				var h: float = m.heights[iz * m.n + ix]
				var col: Color
				if h < Cfg.WATER_LEVEL:
					col = Color(0.15, 0.35, 0.75).lerp(Color(0.4, 0.6, 0.9), clampf((h + 3.5) / 3.0, 0.0, 1.0))
				else:
					col = Color(0.35, 0.65, 0.25).lerp(Color(0.85, 0.8, 0.6), clampf(h / maxf(hmax, 8.0), 0.0, 1.0))
					var sl: float = m.slope_deg_at(x, z)
					col = col.lerp(Color(0.25, 0.15, 0.1), clampf((sl - 20.0) / 30.0, 0.0, 0.8))
				img.set_pixel(ix, iz, col)
		for s in m.sites:
			var px: int = int((s.x - m.origin) / m.cell)
			var pz: int = int((s.z - m.origin) / m.cell)
			for dx in range(-3, 4):
				for dz in range(-3, 4):
					if px + dx >= 0 and px + dx < m.n and pz + dz >= 0 and pz + dz < m.n:
						img.set_pixel(px + dx, pz + dz, Color(1, 0.2, 0.2))
		img.save_png("/tmp/mm_maps/map_%d.png" % k)
		print("seed %d: R=%.0f  %d ms  rivers: %s  lakes: %d" % [k, m.map_radius, ms, ", ".join(kinds), m.lakes.size()])
	quit()
