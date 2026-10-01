class_name DebugOverlay
extends Label
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## F3 debug overlay (spec 15.2): FPS, frame ms, physics/our body counts, draw calls, particles, memory.

var extra: Callable = Callable()
var _acc: float = 0.0
var frame_ms: float = 0.0

func _ready() -> void:
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color(1, 1, 0.6))
	add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_theme_constant_override("outline_size", 4)
	position = Vector2(10, 90)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	frame_ms = lerpf(frame_ms, delta * 1000.0, 0.1)
	if not visible:
		return
	_acc += delta
	if _acc < 0.25:
		return
	_acc = 0.0
	var lines: PackedStringArray = []
	lines.append("FPS %d   frame %.1f ms   quality %s" % [Engine.get_frames_per_second(), frame_ms, Quality.current_id])
	lines.append("physics active objs %d   our bodies %d (awake %d)" % [
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), PhysWorld.bodies.size(), PhysWorld.awake_count()])
	lines.append("draw calls %d   objects in frame %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	lines.append("memory %.1f MB   nodes %d   orphans %d   objects %d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))])
	if extra.is_valid():
		lines.append(str(extra.call()))
	text = "\n".join(lines)
