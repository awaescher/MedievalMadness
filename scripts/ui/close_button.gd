class_name CloseButton
extends Button
## The one close button of every dialog: quiet glass with a dark cross, always in the top right corner.

var quit_style: bool = false          # red glass with a white cross (the Quit button of the menu)

func _init() -> void:
	theme_type_variation = "ParchButton"
	custom_minimum_size = Vector2(38, 34)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = I18n.t("net.close")
	resized.connect(queue_redraw)          # the icon is centred on the real size, also right after the layout pass

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = 6.0
	var col: Color = Color.WHITE if quit_style else UITheme.INK
	draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 2.6, true)
	draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, 2.6, true)
