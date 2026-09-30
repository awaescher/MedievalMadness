extends SceneTree
## Dev tool: distance between the two villages of 2-player maps over many seeds (should vary a lot)
func _init() -> void:
	var ds: Array[float] = []
	for k in 40:
		var m: MapData = MapGen.generate("probe-%d" % k, 2)
		ds.append(Util.dist_xz(m.sites[0], m.sites[1]))
	for k2 in 40:
		var m2: MapData = MapGen.generate("probe-%d" % k2, 2)
		if Util.dist_xz(m2.sites[0], m2.sites[1]) < 57.0:
			print("close pair: seed %d -> %.0f m, sites %s %s, R %.0f" % [k2, Util.dist_xz(m2.sites[0], m2.sites[1]), str(m2.sites[0]), str(m2.sites[1]), m2.map_radius])
	ds.sort()
	var mean: float = 0.0
	for d in ds:
		mean += d
	mean /= float(ds.size())
	var dummy: int = 0
	print("2-player village distance over 40 seeds: min %.0f  median %.0f  max %.0f  mean %.0f m" % [ds[0], ds[20], ds[39], mean])
	quit()
