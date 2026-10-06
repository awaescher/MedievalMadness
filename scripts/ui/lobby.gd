class_name Lobby
extends Control
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Online lobby overlay (spec 19): host a game (gets a room code) or join one with a code. The match settings stay in the
## main menu; the host starts the game there once everybody is in.

signal dismissed

var _panel: PanelContainer
var _name_edit: LineEdit
var _relay_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _box: VBoxContainer
var _roster_box: VBoxContainer
var _code_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.build()
	Glass.watch(self)
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.30)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	Glass.dialog(_panel)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	Net.joined.connect(func(_c: String) -> void: _build())
	Net.roster_changed.connect(_refresh_roster)
	Net.closed.connect(func(reason: String) -> void:
		_build()
		_set_status(_err_text(reason)))
	Events.language_changed.connect(_build)

func open() -> void:
	visible = true
	_step = "start"
	_build()

func _err_text(reason: String) -> String:
	var key: String = "net.err_" + reason
	var t: String = I18n.t(key)
	return t if t != key else I18n.t("net.err_closed")

func _set_status(t: String, ok: bool = false) -> void:
	if _status != null:
		_status.text = t
		_status.visible = t != ""
		_status.add_theme_color_override("font_color", Color("#2e7d32") if ok else Color("#a02818"))

func _default_name() -> String:
	if Settings.net_name != "":
		return Settings.net_name
	var rows: Array = Settings.players
	if not rows.is_empty() and rows[0] is Dictionary:
		return str((rows[0] as Dictionary).get("name", ""))
	return "Player"

var _step: String = "start"          # start (name + host / join) | join (room code)
var _relay_open: bool = false

func _build() -> void:
	if _box != null:
		_box.queue_free()
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_panel.add_child(_box)
	# header: title left, (relay cog) and the red close button top right
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_box.add_child(head)
	var title: Label = UITheme.label(I18n.t("net.relay_help_title") if _step == "help" else I18n.t("net.title"), 30, UITheme.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not Net.active and _step == "start":
		var gear := GearButton.new()
		gear.tooltip_text = I18n.t("net.own_relay")
		gear.button_pressed = _relay_open
		gear.marked = Settings.relay_url != Cfg.DEFAULT_RELAY
		gear.toggled.connect(func(on: bool) -> void:
			_relay_open = on
			_build())
		head.add_child(gear)
	var close := CloseButton.new()
	close.pressed.connect(func() -> void:
		if _step == "help":
			_step = "start"
			_build()
		else:
			_dismiss())
	head.add_child(close)
	if Net.active:
		_build_room()
	elif _step == "help":
		_build_help()
	elif _step == "join":
		_build_join()
	else:
		_build_start()
	_status = UITheme.label("", 15, Color("#a02818"))
	_status.visible = false
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_status)

func _field(label_text: String, value: String, hint: String = "") -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l: Label = UITheme.label(label_text, 17, UITheme.INK, true)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = hint
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 38)
	row.add_child(e)
	_box.add_child(row)
	return e

## Step 1: name, then host and join as two equal big buttons side by side
func _build_start() -> void:
	_name_edit = _field(I18n.t("net.your_name"), _default_name() if not is_instance_valid(_name_edit) else _name_edit.text)
	if _relay_open:
		_build_relay_row()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_box.add_child(row)
	var host_btn: Button = UITheme.dialog_button(I18n.t("net.host"), "GreenButton")
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host)
	row.add_child(host_btn)
	var join_btn: Button = UITheme.dialog_button(I18n.t("net.join"), "GoldButton")
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(func() -> void:
		_remember_name()
		_step = "join"
		_build())
	row.add_child(join_btn)

## Own relay server (behind the cog): address + "Standard" + a short hint
func _build_relay_row() -> void:
	var custom: bool = Settings.relay_url != Cfg.DEFAULT_RELAY
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var l: Label = UITheme.label(I18n.t("net.relay"), 17, UITheme.INK, true)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	_relay_edit = LineEdit.new()
	_relay_edit.text = Settings.relay_url if custom else ""
	_relay_edit.placeholder_text = "wss://..."
	_relay_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relay_edit.custom_minimum_size = Vector2(0, 38)
	row.add_child(_relay_edit)
	var reset: Button = UITheme.option_button(I18n.t("net.relay_default"), "ParchButton", 100.0)
	reset.pressed.connect(func() -> void: _relay_edit.text = "")
	row.add_child(reset)
	var help: Button = UITheme.option_button("?", "GoldButton", 34.0)
	help.tooltip_text = I18n.t("net.relay_help_title")
	help.pressed.connect(func() -> void:
		_step = "help"
		_build())
	row.add_child(help)
	var hint: Label = UITheme.label(I18n.t("net.relay_hint"), 13, Color("#6b4a2a"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(hint)

## Help for people who want their own relay: what it is, how to get one, and copy buttons for the spec and the template
func _build_help() -> void:
	for key in ["net.relay_help_1", "net.relay_help_2", "net.relay_help_3"]:
		var p: Label = UITheme.label(I18n.t(key), 15, UITheme.INK)
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.custom_minimum_size = Vector2(400, 0)
		_box.add_child(p)
	for item in [["net.copy_spec", "spec"], ["net.copy_template", "relay_node"], ["net.copy_check", "check"]]:
		var file: String = str(item[1])
		var b: Button = UITheme.dialog_button(I18n.t(str(item[0])), "ParchButton")
		b.pressed.connect(func() -> void:
			var txt: String = FileAccess.get_file_as_string("res://assets/relay_help/%s.txt" % file)
			if txt == "":
				_set_status(I18n.t("net.copy_failed"))
				return
			DisplayServer.clipboard_set(txt)
			_set_status(I18n.t("net.copied"), true))
		_box.add_child(b)

## Step 2 of joining: the room code, big
func _build_join() -> void:
	var l: Label = UITheme.label(I18n.t("net.code_prompt"), 18, UITheme.INK, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(l)
	_code_edit = LineEdit.new()
	_code_edit.max_length = 4
	_code_edit.placeholder_text = "K7QP"
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.custom_minimum_size = Vector2(0, 64)
	_code_edit.add_theme_font_size_override("font_size", 38)
	_code_edit.text_changed.connect(func(t: String) -> void:
		var up: String = t.to_upper()
		if up != t:
			_code_edit.text = up
			_code_edit.caret_column = up.length())
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join())
	_box.add_child(_code_edit)
	_code_edit.call_deferred("grab_focus")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_box.add_child(row)
	var back: Button = UITheme.dialog_button(I18n.t("net.back"), "ParchButton")
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void:
		_step = "start"
		_build())
	row.add_child(back)
	var go: Button = UITheme.dialog_button(I18n.t("net.join"), "GoldButton")
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_on_join)
	row.add_child(go)

## In a room: the code on the left, the players on the right, "leave" below (close is top right)
func _build_room() -> void:
	var cols := VBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	_box.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var share: Label = UITheme.label(I18n.t("net.share") if Net.is_host else I18n.t("net.room"), 16, UITheme.INK)
	share.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(share)
	_code_label = UITheme.label(Net.code, 56 if Net.is_host else 44, Color("#a02818"), true)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_code_label)
	if not Net.is_host:
		var w: Label = UITheme.label(I18n.t("net.waiting"), 16, UITheme.INK)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size = Vector2(240, 0)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(w)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	right.add_child(UITheme.label(I18n.t("net.players"), 18, UITheme.INK, true))
	_roster_box = VBoxContainer.new()
	right.add_child(_roster_box)
	_refresh_roster()
	# the dialog only closes; the room is ended / left with the "Close lobby" button of the main menu
	var ok: Button = UITheme.dialog_button(I18n.t("menu.ok"), "GreenButton")
	ok.pressed.connect(_dismiss)
	_box.add_child(ok)

func _refresh_roster() -> void:
	if _roster_box == null or not is_instance_valid(_roster_box):
		return
	for c in _roster_box.get_children():
		c.queue_free()
	var ids: Array = Net.roster.keys()
	ids.sort()
	for id in ids:
		var tag: String = ""
		if int(id) == 1:
			tag = " " + I18n.t("net.host_tag")
		if int(id) == Net.my_id:
			tag += " " + I18n.t("net.you")
		_roster_box.add_child(UITheme.label("%d. %s%s" % [int(id), Net.peer_name(int(id)), tag], 18, UITheme.INK))

## The relay to use: the custom address if one is entered behind the cog, else the saved / built-in one
func _relay_url() -> String:
	if not _relay_open or not is_instance_valid(_relay_edit):
		return Settings.relay_url
	var t: String = _relay_edit.text.strip_edges()
	return t if t != "" else Cfg.DEFAULT_RELAY

func _remember_name() -> void:
	if is_instance_valid(_name_edit):
		Settings.net_name = _name_edit.text.strip_edges()

func _remember() -> void:
	_remember_name()
	if is_instance_valid(_relay_edit) and _relay_open:
		Settings.relay_url = _relay_url()
	Settings.save_settings()

func _on_host() -> void:
	_remember()
	_set_status(I18n.t("net.connecting"))
	Net.host_game(Settings.relay_url, Settings.net_name if Settings.net_name != "" else "Host")

func _on_join() -> void:
	if _code_edit.text.strip_edges().length() < 4:
		_set_status(I18n.t("net.need_code"))
		return
	_remember()
	_set_status(I18n.t("net.connecting"))
	Net.join_game(Settings.relay_url, _code_edit.text.strip_edges(), Settings.net_name if Settings.net_name != "" else "Player")

func _dismiss() -> void:
	visible = false
	dismissed.emit()
