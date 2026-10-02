class_name Arsenal
extends RefCounted
## Starting arsenal presets. A preset is a dictionary ammo id -> number of shots at the start of the match (-1 = unlimited);
## weapons that are not in it start at 0 and are earned during the match as usual (unlocks work in every preset).
## The stone is always unlimited. "custom" is the player's own selection, kept on the machine (Settings.arsenal_custom).

const PRESETS: Array[String] = ["standard", "powerplay", "quarry", "chaos", "custom"]

static func counts(preset: String, custom: Dictionary) -> Dictionary:
	match preset:
		"powerplay":
			return {"quad": 4, "boulder": 2, "log": 2}
		"chaos":
			var out: Dictionary = {}
			for id in AmmoDef.earnable_ids():
				if id != "meteor":
					out[id] = 2
			out["boulder"] = 5          # lots of rocks
			out["log"] = 3
			return out
		"quarry":
			return {"quad": -1, "chain": 5, "boulder": 3, "log": 6}
		"custom":
			var c: Dictionary = {}
			for id2 in AmmoDef.earnable_ids():
				var n: int = int(custom.get(id2, 0))
				if n != 0:
					c[id2] = n
			return c
	return {}

## "Stone ∞ · Stone Hail x4 ..." for the menu
static func describe(arsenal: Dictionary) -> String:
	var parts: Array[String] = [I18n.t("ammo.stone") + " ∞"]
	for a in AmmoDef.all():
		if a.earnable and arsenal.has(a.id) and int(arsenal[a.id]) != 0:
			parts.append("%s %s" % [I18n.t("ammo." + a.id), "∞" if int(arsenal[a.id]) < 0 else "×" + str(int(arsenal[a.id]))])
	return " · ".join(parts)
