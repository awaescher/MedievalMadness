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
	# a cog: 8 trapezoid teeth on a round body with an axle hole
	var c: Vector2 = size * 0.5
	var ink := Color("#3b2a1a")
	var teeth: int = 8
	var pitch: float = TAU / float(teeth)
	var root: float = 8.6
	var tip: float = 12.2
	var pts := PackedVector2Array()
	for i in teeth:
		var a0: float = float(i) * pitch
		for q in [[-0.30, root], [-0.15, tip], [0.15, tip], [0.30, root], [0.5, root]]:
			var ang: float = a0 + float((q as Array)[0]) * pitch
			pts.append(c + Vector2(cos(ang), sin(ang)) * float((q as Array)[1]))
	draw_colored_polygon(pts, ink)
	draw_circle(c, 3.9, Color(0.96, 0.93, 0.85))
	draw_arc(c, 3.9, 0.0, TAU, 20, ink, 1.4, true)
	if marked:
		draw_circle(Vector2(size.x - 9.0, 9.0), 5.0, Color("#e74c3c"))
