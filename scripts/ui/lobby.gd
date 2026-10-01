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
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(660, 0)
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
	_build()

func _err_text(reason: String) -> String:
	var key: String = "net.err_" + reason
	var t: String = I18n.t(key)
	return t if t != key else I18n.t("net.err_closed")

func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t

func _default_name() -> String:
	if Settings.net_name != "":
		return Settings.net_name
	var rows: Array = Settings.players
	if not rows.is_empty() and rows[0] is Dictionary:
		return str((rows[0] as Dictionary).get("name", ""))
	return "Player"

func _build() -> void:
	if _box != null:
		_box.queue_free()
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	_box.add_child(UITheme.label(I18n.t("net.title"), 30, UITheme.INK, true))
	if Net.active:
		_build_room()
	else:
		_build_idle()
	_status = UITheme.label("", 15, Color("#a02818"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)

func _field(label_text: String, value: String, hint: String = "") -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l: Label = UITheme.label(label_text, 17, UITheme.INK, true)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = hint
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 36)
	row.add_child(e)
	_box.add_child(row)
	return e

func _build_idle() -> void:
	_name_edit = _field(I18n.t("net.your_name"), _default_name())
	_relay_edit = _field(I18n.t("net.relay"), Settings.relay_url, "wss://...")
	var hint: Label = UITheme.label(I18n.t("net.relay_hint"), 13, Color("#6b4a2a"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(hint)
	var host_btn: Button = UITheme.button(I18n.t("net.host"), "GreenButton", Vector2(0, 50), 20)
	host_btn.pressed.connect(_on_host)
	_box.add_child(host_btn)
	_code_edit = _field(I18n.t("net.code"), "", I18n.t("net.code_hint"))
	_code_edit.max_length = 4
	_code_edit.text_changed.connect(func(t: String) -> void:
		var up: String = t.to_upper()
		if up != t:
			_code_edit.text = up
			_code_edit.caret_column = up.length())
	var join_btn: Button = UITheme.button(I18n.t("net.join"), "GoldButton", Vector2(0, 50), 20)
	join_btn.pressed.connect(_on_join)
	_box.add_child(join_btn)
	var back: Button = UITheme.button(I18n.t("net.close"), "ParchButton", Vector2(0, 40), 16)
	back.pressed.connect(_dismiss)
	_box.add_child(back)

func _build_room() -> void:
	if Net.is_host:
		_box.add_child(UITheme.label(I18n.t("net.share"), 17, UITheme.INK))
		_code_label = UITheme.label(Net.code, 64, Color("#a02818"), true)
		_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(_code_label)
	else:
		_code_label = UITheme.label(Net.code, 40, Color("#a02818"), true)
		_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(_code_label)
		_box.add_child(UITheme.label(I18n.t("net.waiting"), 17, UITheme.INK))
	_box.add_child(UITheme.label(I18n.t("net.players"), 18, UITheme.INK, true))
	_roster_box = VBoxContainer.new()
	_box.add_child(_roster_box)
	_refresh_roster()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back: Button = UITheme.button(I18n.t("net.close"), "GreenButton", Vector2(0, 44), 17)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_dismiss)
	row.add_child(back)
	var leave: Button = UITheme.button(I18n.t("net.leave"), "RedButton", Vector2(0, 44), 17)
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.pressed.connect(func() -> void:
		Net.leave()
		_build())
	row.add_child(leave)
	_box.add_child(row)

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

func _remember() -> void:
	Settings.net_name = _name_edit.text.strip_edges()
	Settings.relay_url = _relay_edit.text.strip_edges()
	Settings.save_settings()

func _on_host() -> void:
	if _relay_edit.text.strip_edges() == "":
		_set_status(I18n.t("net.need_relay"))
		return
	_remember()
	_set_status(I18n.t("net.connecting"))
	Net.host_game(Settings.relay_url, Settings.net_name if Settings.net_name != "" else "Host")

func _on_join() -> void:
	if _relay_edit.text.strip_edges() == "":
		_set_status(I18n.t("net.need_relay"))
		return
	if _code_edit.text.strip_edges().length() < 4:
		_set_status(I18n.t("net.need_code"))
		return
	_remember()
	_set_status(I18n.t("net.connecting"))
	Net.join_game(Settings.relay_url, _code_edit.text.strip_edges(), Settings.net_name if Settings.net_name != "" else "Player")

func _dismiss() -> void:
	visible = false
	dismissed.emit()
