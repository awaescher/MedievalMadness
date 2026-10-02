class_name CloseButton
extends Button
## The one close button of every dialog: red with a white cross, always in the top right corner.

func _init() -> void:
	theme_type_variation = "RedButton"
	custom_minimum_size = Vector2(46, 38)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = I18n.t("net.close")
	resized.connect(queue_redraw)          # the icon is centred on the real size, also right after the layout pass

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = 7.0
	draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color.WHITE, 4.0, true)
	draw_line(c + Vector2(-r, r), c + Vector2(r, -r), Color.WHITE, 4.0, true)
