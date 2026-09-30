extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Localization (autoload "I18n"): own nested-dictionary lookup, no TranslationServer.

const EN := preload("res://scripts/lang/en.gd")
const DE := preload("res://scripts/lang/de.gd")

var _lang: String = "en"

func set_lang(code: String) -> void:
	if code != "en" and code != "de":
		code = "en"
	if code == _lang:
		return
	_lang = code
	Settings.language = code
	Events.language_changed.emit()

func get_lang() -> String:
	return _lang

func _data(code: String) -> Dictionary:
	return (DE.DATA if code == "de" else EN.DATA) as Dictionary

static func lookup(data: Dictionary, key: String) -> Variant:
	var cur: Variant = data
	for part in key.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = (cur as Dictionary)[part]
		else:
			return null
	return cur

func _find(key: String) -> Variant:
	var v: Variant = lookup(_data(_lang), key)
	if v == null and _lang != "en":
		v = lookup(EN.DATA as Dictionary, key)
	return v

## Translate a key; placeholders like {name} are replaced from params.
func t(key: String, params: Dictionary = {}) -> String:
	var v: Variant = _find(key)
	var s: String
	if v is String:
		s = v
	elif v is Array and not (v as Array).is_empty():
		s = str((v as Array)[0])
	else:
		return key
	for k in params:
		s = s.replace("{" + str(k) + "}", str(params[k]))
	return s

## All lines for a key (Array of String). Empty array if missing.
func tr_list(key: String) -> Array:
	var v: Variant = _find(key)
	if v is Array:
		return (v as Array).duplicate()
	if v is String:
		return [v]
	return []

## Random line from a list key, formatted.
func pick(key: String, rng: Rng, params: Dictionary = {}) -> String:
	var lines: Array = tr_list(key)
	if lines.is_empty():
		return key
	var s: String = str(lines[int(rng.next_f() * lines.size()) % lines.size()])
	for k in params:
		s = s.replace("{" + str(k) + "}", str(params[k]))
	return s

func has_key(key: String) -> bool:
	return _find(key) != null

## Flatten a dictionary into dotted-key => leaf (used by tests)
static func flatten(data: Dictionary, prefix: String = "") -> Dictionary:
	var out: Dictionary = {}
	for k in data:
		var full: String = prefix + str(k) if prefix == "" else prefix + "." + str(k)
		var v: Variant = data[k]
		if v is Dictionary:
			out.merge(flatten(v as Dictionary, full))
		else:
			out[full] = v
	return out
