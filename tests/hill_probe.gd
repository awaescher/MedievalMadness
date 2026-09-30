extends SceneTree
## Dev tool: terrain character per hilliness level (slope statistics, village sites dry, flat village zones)
func _init() -> void:
	for lv in 5:
		var steep: float = 0.0
		var very: float = 0.0
		var cells: float = 0.0
		var wet_sites: int = 0
		var hmax: float = -99.0
		for k in 6:
			var m: MapData = MapGen.generate("hill-%d" % k, 3, lv)
			for s in m.sites:
				if s.y < Cfg.WATER_LEVEL + 0.8:
					wet_sites += 1
			var n: int = m.n
			for iz in range(2, n - 2, 3):
				for ix in range(2, n - 2, 3):
					var x: float = m.origin + float(ix) * m.cell
					var z: float = m.origin + float(iz) * m.cell
					if Vector2(x, z).length() > m.map_radius * 0.8:
						continue
					var sl: float = m.slope_deg_at(x, z)
					cells += 1.0
					if sl > 25.0:
						steep += 1.0
					if sl > 36.0:
						very += 1.0
					hmax = maxf(hmax, m.height_at(x, z))
		print("level %d: slope>25: %4.1f%%  slope>36 (landslide-able): %4.1f%%  max height %.0f m  wet sites %d" % [lv, 100.0 * steep / cells, 100.0 * very / cells, hmax, wet_sites])
	quit()
