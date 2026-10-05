class_name RewardPopup
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Weapon reward (crate, destroyed building, ...): the weapon icon with its count floats up from the place where it was earned
## and fades out. Listens to Events.reward; a world position is projected to the screen every frame.

const LIFE := 3.2
const RISE := 4.5                 # metres the popup climbs in the world

var cam: CameraRig
var _items: Array[Dictionary] = []

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.reward.connect(_on_reward)

func clear() -> void:
	for it in _items:
		(it["node"] as Control).queue_free()
	_items.clear()

func _on_reward(player_id: int, ammo_id: String, n: int, pos: Vector3) -> void:
	var def: AmmoDef = AmmoDef.get_def(ammo_id)
	if def == null or cam == null:
		return
	var p: PlayerData = Game.player(player_id)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	# parchment disc behind the icon so it reads on any background
	var icon := Hud.AmmoSlot.new()
	icon.ammo = def
	icon.icon_only = true
	icon.custom_minimum_size = Vector2(76, 76)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var cnt: Label = UITheme.label("+%d" % n, 40, Color("#ffd93b"), true, 8)
	cnt.add_theme_font_override("font", ComicText.comic_font())
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cnt)
	box.add_child(row)
	var who: String = p.name if p != null else ""
	var nm: Label = UITheme.label((who + ": " if who != "" else "") + I18n.t("ammo." + ammo_id), 18, Color.WHITE, true, 5)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(nm)
	box.pivot_offset = Vector2.ZERO
	add_child(box)
	# several rewards at once (one shot, one place) are stacked side by side instead of lying on top of each other
	var slot: int = 0
	for it in _items:
		if (it["pos"] as Vector3).distance_to(pos) < 6.0 and float(it["t"]) < 1.0:
			slot += 1
	_items.append({"node": box, "pos": pos, "t": 0.0, "slot": slot})

func _process(delta: float) -> void:
	if _items.is_empty():
		return
	var vp: Vector2 = get_viewport_rect().size
	var ui_k: float = clampf(minf(vp.x / 1280.0, vp.y / 720.0), 0.6, 1.4)
	var i: int = _items.size() - 1
	while i >= 0:
		var it: Dictionary = _items[i]
		var t: float = float(it["t"]) + delta
		it["t"] = t
		var node: Control = it["node"] as Control
		if t >= LIFE or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_items.remove_at(i)
			i -= 1
			continue
		var k: float = t / LIFE
		var eased: float = 1.0 - pow(1.0 - k, 2.0)
		var wp: Vector3 = (it["pos"] as Vector3) + Vector3(0, 1.0 + RISE * eased, 0)
		var sp: Vector2 = cam.project(wp)
		if cam.is_behind(wp):
			sp = Vector2(vp.x * 0.5, vp.y * 0.35)
		node.size = node.get_combined_minimum_size()
		var pop: float = minf(t / 0.25, 1.0)
		var sc: float = ui_k * (0.4 + 0.6 * pop + 0.18 * sin(minf(t / 0.35, 1.0) * PI))
		node.scale = Vector2(sc, sc)
		node.pivot_offset = node.size * 0.5
		var half: Vector2 = node.size * sc * 0.5
		sp += Vector2(float(it["slot"]) * (node.size.x * sc + 8.0), float(it["slot"]) * 0.0)
		sp.x = clampf(sp.x, half.x + 8.0, vp.x - half.x - 8.0)
		sp.y = clampf(sp.y, half.y + 70.0, vp.y - half.y - 110.0)
		node.position = sp - node.size * 0.5
		node.modulate.a = 1.0 if k < 0.75 else (1.0 - k) / 0.25
		i -= 1
