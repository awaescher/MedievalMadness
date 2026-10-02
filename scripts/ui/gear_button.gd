class_name GearButton
extends Button
## Small cog wheel button (settings that most people never need). `marked` adds a dot: something custom is active.

var marked: bool = false:
	set(v):
		marked = v
		queue_redraw()

func _init() -> void:
	theme_type_variation = "ParchButton"
	custom_minimum_size = Vector2(46, 38)
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	resized.connect(queue_redraw)          # the icon is centred on the real size, also right after the layout pass

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var ink := Color("#3b2a1a")
	var pts := PackedVector2Array()
	var teeth: int = 8
	for i in teeth * 4:
		var a: float = TAU * float(i) / float(teeth * 4)
		var phase: int = (i % 4)
		var rr: float = 11.0 if phase == 1 or phase == 2 else 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, ink)
	draw_circle(c, 3.6, Color("#f4e4bc"))
	if marked:
		draw_circle(Vector2(size.x - 9.0, 9.0), 5.0, Color("#e74c3c"))
