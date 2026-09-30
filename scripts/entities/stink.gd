class_name Stink
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Green stink clouds left by the Holy Cheese (spec 6.4): 10 s of green particles, settlers gag.

class Cloud extends RefCounted:
	var pos: Vector3
	var t: float = 0.0
	var dur: float = 10.0
	var emit: float = 0.0
	var gag: float = 0.0
	var radius: float = 11.0
	var source: Dictionary = {}

static var clouds: Array[Cloud] = []

static func reset() -> void:
	clouds.clear()

static func spawn(pos: Vector3, duration: float = 10.0, source: Dictionary = {}) -> void:
	var c := Cloud.new()
	c.pos = pos
	c.source = source
	c.dur = duration
	clouds.append(c)

static func tick(dt: float) -> void:
	var i: int = clouds.size() - 1
	while i >= 0:
		var c: Cloud = clouds[i]
		c.t += dt
		if c.t >= c.dur:
			clouds.remove_at(i)
			i -= 1
			continue
		c.emit -= dt
		if c.emit <= 0.0:
			c.emit = 0.9
			Fx.burst("stink", c.pos + Vector3.UP * 0.5, Color(0, 0, 0, -1), 1.0)
		c.gag -= dt
		if c.gag <= 0.0:
			c.gag = 0.5
			for st in Settler.all:
				if st.state != Settler.State.DEAD and st.state != Settler.State.GONE and st.state != Settler.State.RAGDOLL and Util.dist_xz(st.global_pos(), c.pos) < c.radius:
					st.gag(1.5)
					st.hurt(2.0, c.source, Vector3.ZERO, false, true)
		i -= 1
