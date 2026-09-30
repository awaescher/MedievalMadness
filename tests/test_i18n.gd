extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Both language files must have identical key sets and no empty strings (spec 19).

const EN := preload("res://scripts/lang/en.gd")
const DE := preload("res://scripts/lang/de.gd")

static func _flatten(data: Dictionary, prefix: String = "") -> Dictionary:
	var out: Dictionary = {}
	for k in data:
		var full: String = str(k) if prefix == "" else prefix + "." + str(k)
		var v: Variant = data[k]
		if v is Dictionary:
			out.merge(_flatten(v as Dictionary, full))
		else:
			out[full] = v
	return out

func test_identical_key_sets() -> void:
	var en: Dictionary = _flatten(EN.DATA as Dictionary)
	var de: Dictionary = _flatten(DE.DATA as Dictionary)
	for k in en:
		TestBase.check(de.has(k), "German is missing key %s" % str(k))
	for k in de:
		TestBase.check(en.has(k), "English is missing key %s" % str(k))
	TestBase.check(en.size() > 200, "expected a rich string table (%d keys)" % en.size())

func test_no_empty_strings() -> void:
	for pair in [["en", EN.DATA], ["de", DE.DATA]]:
		var flat: Dictionary = _flatten(pair[1] as Dictionary)
		for k in flat:
			var v: Variant = flat[k]
			if v is String:
				TestBase.check((v as String).strip_edges() != "", "%s.%s is empty" % [str(pair[0]), str(k)])
			elif v is Array:
				TestBase.check(not (v as Array).is_empty(), "%s.%s is an empty list" % [str(pair[0]), str(k)])
				for line in (v as Array):
					TestBase.check(str(line).strip_edges() != "", "%s.%s has an empty line" % [str(pair[0]), str(k)])

func test_lists_have_equal_length() -> void:
	var en: Dictionary = _flatten(EN.DATA as Dictionary)
	var de: Dictionary = _flatten(DE.DATA as Dictionary)
	for k in en:
		if en[k] is Array and de.has(k) and de[k] is Array:
			TestBase.eq((en[k] as Array).size(), (de[k] as Array).size(), "list length of %s" % str(k))

func test_placeholders_match() -> void:
	var en: Dictionary = _flatten(EN.DATA as Dictionary)
	var de: Dictionary = _flatten(DE.DATA as Dictionary)
	var rx := RegEx.new()
	rx.compile("\\{[a-z_]+\\}")
	for k in en:
		if en[k] is String and de.has(k) and de[k] is String:
			var a: Array = []
			for m in rx.search_all(en[k] as String):
				a.append(m.get_string())
			var b: Array = []
			for m2 in rx.search_all(de[k] as String):
				b.append(m2.get_string())
			a.sort()
			b.sort()
			TestBase.eq(a, b, "placeholders of %s" % str(k))

func test_spec_content_present() -> void:
	# a few lines that the spec prescribes verbatim (12.5 / 12.7 / 12.8)
	var en: Dictionary = _flatten(EN.DATA as Dictionary)
	var elim: Array = en["banner.eliminated"] as Array
	TestBase.eq(elim.size(), 8, "eight elimination banners")
	TestBase.eq((en["speech.idle"] as Array).size(), 10, "ten idle lines")
	TestBase.eq((en["speech.panic"] as Array).size(), 8, "eight panic lines")
	TestBase.eq((en["loading.lines"] as Array).size(), 10, "ten loading lines")
	TestBase.eq((en["title.crown"] as Array).size(), 4, "four crown titles")
	TestBase.eq(str(en["ammo.meteor"]), "Meteor Marker", "meteor name")
	TestBase.eq(str((DE.DATA as Dictionary)["ammo"]["meteor"]), "Meteoriten-Markierung", "meteor name (de)")
