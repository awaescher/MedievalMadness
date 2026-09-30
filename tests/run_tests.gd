extends SceneTree
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Headless test entry (spec 21):  godot --headless --path . --script res://tests/run_tests.gd
## Discovers tests/test_*.gd, runs every `func test_*()` and prints a summary; exit code 1 on any failure.
## Only logic without autoload dependencies is tested here; the physics/gameplay scenarios run in-scene:
##   godot --path . -- --autotest=units

func _init() -> void:
	TestBase.reset()
	var dir: DirAccess = DirAccess.open("res://tests")
	var files: Array[String] = []
	if dir != null:
		dir.list_dir_begin()
		var f: String = dir.get_next()
		while f != "":
			if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd":
				files.append(f)
			f = dir.get_next()
		dir.list_dir_end()
	files.sort()
	var t0: int = Time.get_ticks_msec()
	for file in files:
		var script: GDScript = load("res://tests/" + file) as GDScript
		if script == null:
			print("Could not load ", file)
			TestBase.failed += 1
			continue
		var inst: Object = script.new()
		print("== ", file)
		for m in inst.get_method_list():
			var mname: String = str(m["name"])
			if mname.begins_with("test_"):
				TestBase.current = file.trim_suffix(".gd") + "." + mname
				inst.call(mname)
	print("---- %d passed, %d failed (%.1f s)" % [TestBase.passed, TestBase.failed, float(Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if TestBase.failed > 0 else 0)
