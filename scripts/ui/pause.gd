class_name PauseMenu
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Pause menu (Esc): Resume, Restart (same seed), Quit to menu, Options.

signal resume
signal restart
signal restart_new_map
signal quit_to_menu

var panel: PanelContainer
var _options: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.build()
	Glass.watch(self)
	visible = false
	Events.language_changed.connect(func() -> void:
		if visible:
			_build())

func open() -> void:
	_options = false
	visible = true
	_build()

func close() -> void:
	visible = false

func _build() -> void:
	for c in get_children():
		if not (c is SettingsDialog):          # the settings dialog (language switch!) must survive the rebuild
			c.queue_free()
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.03, 0.08, 0.34)
	add_child(dim)
	panel = PanelContainer.new()
	Glass.dialog(panel, 22, Vector2(26, 20))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(300, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t: Label = UITheme.label(I18n.t("pause.title"), 34, UITheme.INK, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if not _options:
		var b1: Button = UITheme.dialog_button(I18n.t("pause.resume"), "GreenButton")
		b1.pressed.connect(func() -> void: resume.emit())
		v.add_child(b1)
		var b2: Button = UITheme.dialog_button(I18n.t("pause.options"), "ParchButton")
		b2.pressed.connect(func() -> void:
			if not has_node("Settings"):
				var dlg := SettingsDialog.new()
				dlg.name = "Settings"
				add_child(dlg))
		v.add_child(b2)
		var b3: Button = UITheme.dialog_button(I18n.t("pause.restart"), "ParchButton")
		b3.pressed.connect(func() -> void: restart.emit())
		b3.visible = not Net.active
		v.add_child(b3)
		var b3n: Button = UITheme.dialog_button(I18n.t("pause.restart_new"), "ParchButton")
		b3n.pressed.connect(func() -> void: restart_new_map.emit())
		b3n.visible = not Net.active
		v.add_child(b3n)
		var b4: Button = UITheme.dialog_button(I18n.t("pause.quit"), "RedButton")
		b4.pressed.connect(func() -> void: quit_to_menu.emit())
		v.add_child(b4)
	# the seed of this map, always visible under the menu (to share a map or to come back to it)
	var sl: Label = UITheme.label(I18n.t("pause.seed", {"seed": Game.seed_str}), 13, Color("#6b4a2a"))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(240, 0)
	v.add_child(sl)
	var dlg: Node = get_node_or_null("Settings")
	if dlg != null:
		move_child(dlg, get_child_count() - 1)          # stays on top after a rebuild
