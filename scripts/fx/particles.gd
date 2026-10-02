class_name Fx
extends Node3D
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Pooled particle effect presets (spec 15.2 / 20). One pool per preset, `one_shot` emitters reused
## round-robin, a global live-particle budget, plus explosion helpers (fireball, shockwave, flash light)
## and continuous flame emitters for the fire system. Presets can be built as GPUParticles3D or
## CPUParticles3D (`Settings.cpu_particles`) with the same API.

class Preset extends RefCounted:
	var name: String = ""
	var amount: int = 16
	var life: float = 1.0
	var vmin: float = 1.0
	var vmax: float = 4.0
	var spread: float = 60.0
	var grav: float = 1.0            # multiplier of 9.81 (negative = rises)
	var smin: float = 0.1
	var smax: float = 0.2
	var additive: bool = false
	var grow: int = 0                # -1 shrink, 0 none, 1 grow
	var color: Color = Color.WHITE
	var hue: float = 0.0
	var damp: float = 0.0
	var radius: float = 0.2
	var pool: int = 8
	var alpha: float = 1.0

class Emitter extends RefCounted:
	var node: Node3D
	var mat: ParticleProcessMaterial
	var until: float = 0.0
	var amount: int = 0
	var preset: Preset
	var cpu: bool = false

class Flame extends RefCounted:
	var node: Node3D
	var light: OmniLight3D
	var em: Emitter
	var part: Part = null
	var local_pos: Vector3 = Vector3.ZERO
	var static_pos: Vector3 = Vector3.ZERO
	var active: bool = false
	var size: float = 1.0

static var inst: Fx

var _presets: Dictionary = {}
var _pools: Dictionary = {}
var _cursor: Dictionary = {}
var _now: float = 0.0
var _tex: GradientTexture2D
var _mat_alpha: StandardMaterial3D
var _mat_add: StandardMaterial3D
var _quad: QuadMesh
var _flames: Array[Flame] = []
var _free_flames: Array[Flame] = []
var _lights: Array[OmniLight3D] = []
var _fireballs: Array = []       # active fireball/shockwave visuals
var _sphere_mesh: Mesh
var _ring_mesh: Mesh
var _fb_mat_cache: Dictionary = {}
var live_particles: int = 0
var fire_light_budget: int = 0

func _enter_tree() -> void:
	inst = self

func _exit_tree() -> void:
	if inst == self:
		inst = null

func _ready() -> void:
	_define_presets()
	_tex = GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.78, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(0.5, 0.0)
	_tex.width = 64
	_tex.height = 64
	_mat_alpha = _make_draw_material(false)
	_mat_add = _make_draw_material(true)
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_sphere_mesh = MeshGen.sphere_mesh(1.0, 10, 16)
	_ring_mesh = MeshGen.ring_mesh(0.85, 1.0, 40)

func _make_draw_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	return m

func _p(pname: String, amount: int, life: float, vmin: float, vmax: float, spread: float, grav: float, smin: float, smax: float, col: String, additive: bool = false, grow: int = 0, pool: int = 8, radius: float = 0.2, damp: float = 0.0, alpha: float = 1.0) -> void:
	var p := Preset.new()
	p.name = pname
	p.amount = amount
	p.life = life
	p.vmin = vmin
	p.vmax = vmax
	p.spread = spread
	p.grav = grav
	p.smin = smin
	p.smax = smax
	p.color = Color.html(col)
	p.additive = additive
	p.grow = grow
	p.pool = pool
	p.radius = radius
	p.damp = damp
	p.alpha = alpha
	_presets[pname] = p

func _define_presets() -> void:
	_p("splinter", 14, 0.9, 3.0, 9.0, 80.0, 1.6, 0.10, 0.22, "#8a5a2a", false, 0, 12)
	_p("dust", 14, 1.3, 1.0, 4.5, 75.0, -0.05, 0.7, 1.5, "#9a9a9a", false, 1, 12, 0.4, 0.6, 0.75)
	_p("straw", 18, 1.4, 2.0, 6.0, 85.0, 0.6, 0.10, 0.2, "#e0c060", false, 0, 8)
	_p("spark", 16, 0.6, 4.0, 11.0, 70.0, 1.0, 0.06, 0.12, "#ffd27a", true, -1, 8)
	_p("glitter", 18, 1.0, 2.0, 6.0, 80.0, 1.0, 0.06, 0.11, "#bfefff", true, -1, 6)
	_p("smoke", 12, 2.4, 0.6, 2.2, 35.0, -0.32, 0.9, 2.0, "#4a4a52", false, 1, 14, 0.5, 0.3, 0.8)
	_p("flame", 10, 0.7, 0.5, 2.5, 35.0, -0.9, 0.7, 1.3, "#ff8a2a", true, -1, 16, 0.3)
	_p("steam", 12, 1.6, 1.0, 3.0, 45.0, -0.45, 0.7, 1.5, "#f0f4f8", false, 1, 8, 0.4, 0.4, 0.6)
	_p("splash", 22, 0.9, 3.0, 9.0, 55.0, 1.6, 0.12, 0.26, "#a8dcff", false, 0, 12)
	_p("feather", 10, 1.5, 1.0, 4.5, 80.0, 0.35, 0.12, 0.2, "#ffffff", false, 0, 6)
	_p("wool", 8, 1.5, 1.0, 4.0, 80.0, 0.5, 0.16, 0.26, "#f3ead6", false, 0, 6)
	_p("bee", 20, 1.2, 1.0, 5.0, 180.0, 0.0, 0.07, 0.11, "#ffcc00", false, 0, 4)
	_p("stink", 14, 2.6, 0.3, 1.2, 60.0, -0.2, 0.8, 1.7, "#7ed957", false, 1, 6, 0.6, 0.2, 0.5)
	_p("confetti", 60, 3.2, 5.0, 14.0, 60.0, 0.55, 0.11, 0.17, "#ffffff", false, 0, 4, 0.5)
	_p("leaf", 10, 2.2, 1.0, 4.0, 90.0, 0.4, 0.12, 0.2, "#4caf50", false, 0, 6)
	_p("ash", 12, 1.8, 0.5, 2.0, 60.0, -0.1, 0.1, 0.25, "#3a3a3a", false, -1, 8)
	_p("beer", 20, 1.4, 5.0, 10.0, 25.0, 0.9, 0.12, 0.22, "#f0c040", true, 0, 8)
	_p("coin", 8, 1.2, 3.0, 6.0, 40.0, 1.0, 0.09, 0.14, "#ffd700", true, 0, 4)
	_p("cheese", 24, 1.6, 4.0, 10.0, 60.0, 0.9, 0.12, 0.25, "#ffd54a", false, 0, 6)
	_p("droplet", 30, 1.2, 4.0, 10.0, 40.0, 1.5, 0.1, 0.2, "#7cc8ff", false, 0, 8)
	_p("puff", 8, 0.8, 0.5, 2.0, 60.0, -0.1, 0.5, 1.0, "#ffffff", false, 1, 8, 0.2, 0.5, 0.8)

func has_preset(pname: String) -> bool:
	return _presets.has(pname)

# ------------------------------------------------------------------ emitters
func _make_emitter(p: Preset, looping: bool = false) -> Emitter:
	var e := Emitter.new()
	e.preset = p
	e.amount = p.amount
	e.cpu = Settings.cpu_particles
	if e.cpu:
		var c := CPUParticles3D.new()
		c.amount = p.amount
		c.lifetime = p.life
		c.one_shot = not looping
		c.explosiveness = 0.95 if not looping else 0.0
		c.local_coords = false
		c.direction = Vector3.UP
		c.spread = p.spread
		c.initial_velocity_min = p.vmin
		c.initial_velocity_max = p.vmax
		c.gravity = Vector3(0, -9.81 * p.grav, 0)
		c.scale_amount_min = p.smin
		c.scale_amount_max = p.smax
		c.damping_min = p.damp
		c.damping_max = p.damp
		c.color = Color(p.color.r, p.color.g, p.color.b, p.alpha)
		c.color_ramp = _alpha_gradient(p)
		c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		c.emission_sphere_radius = p.radius
		c.mesh = _quad
		c.material_override = _mat_add if p.additive else _mat_alpha
		c.emitting = false
		c.visibility_aabb = AABB(Vector3(-25, -8, -25), Vector3(50, 50, 50))
		e.node = c
	else:
		var g := GPUParticles3D.new()
		g.amount = p.amount
		g.lifetime = p.life
		g.one_shot = not looping
		g.explosiveness = 0.95 if not looping else 0.0
		g.local_coords = false
		g.emitting = false
		g.visibility_aabb = AABB(Vector3(-25, -8, -25), Vector3(50, 50, 50))
		var m := ParticleProcessMaterial.new()
		m.direction = Vector3.UP
		m.spread = p.spread
		m.initial_velocity_min = p.vmin
		m.initial_velocity_max = p.vmax
		m.gravity = Vector3(0, -9.81 * p.grav, 0)
		m.scale_min = p.smin
		m.scale_max = p.smax
		m.damping_min = p.damp
		m.damping_max = p.damp
		m.color = Color(p.color.r, p.color.g, p.color.b, p.alpha)
		m.color_ramp = _alpha_ramp(p)
		if p.grow != 0:
			m.scale_curve = _scale_curve(p.grow)
		if p.hue > 0.0 or p.name == "confetti":
			m.hue_variation_min = -1.0
			m.hue_variation_max = 1.0
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = p.radius
		g.process_material = m
		g.draw_pass_1 = _quad
		g.material_override = _mat_add if p.additive else _mat_alpha
		g.draw_passes = 1
		e.node = g
		e.mat = m
	add_child(e.node)
	return e

func _alpha_gradient(p: Preset) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.65, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0 if p.grow == 1 else 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	return g

func _alpha_ramp(p: Preset) -> GradientTexture1D:
	var t := GradientTexture1D.new()
	t.gradient = _alpha_gradient(p)
	return t

func _scale_curve(mode: int) -> CurveTexture:
	var c := Curve.new()
	if mode > 0:
		c.add_point(Vector2(0, 0.35))
		c.add_point(Vector2(1, 1.0))
	else:
		c.add_point(Vector2(0, 1.0))
		c.add_point(Vector2(1, 0.15))
	var t := CurveTexture.new()
	t.curve = c
	return t

func _pool_for(pname: String) -> Array:
	if _pools.has(pname):
		return _pools[pname] as Array
	var p: Preset = _presets.get(pname) as Preset
	if p == null:
		p = _presets["puff"] as Preset
	var arr: Array = []
	for i in p.pool:
		arr.append(_make_emitter(p))
	_pools[pname] = arr
	_cursor[pname] = 0
	return arr

func _update_live() -> void:
	var live: int = 0
	for k in _pools:
		for e in (_pools[k] as Array):
			var em: Emitter = e as Emitter
			if em.until > _now:
				live += int(float(em.amount) * (em.node.get("amount_ratio") if not em.cpu else 1.0))
	live_particles = live

func _burst(pname: String, pos: Vector3, color: Color, scale_amt: float, dir: Vector3) -> void:
	var pool: Array = _pool_for(pname)
	var idx: int = -1
	var oldest: int = 0
	var oldest_until: float = 1e18
	for i in pool.size():
		var em: Emitter = pool[i] as Emitter
		if em.until <= _now:
			idx = i
			break
		if em.until < oldest_until:
			oldest_until = em.until
			oldest = i
	if idx < 0:
		idx = oldest
	var e: Emitter = pool[idx] as Emitter
	var ratio: float = clampf(scale_amt, 0.1, 1.0)
	# particle budget
	if e.until <= _now:
		_update_live()
		if live_particles + int(float(e.amount) * ratio) > Quality.particle_cap:
			return
	var p: Preset = e.preset
	e.node.global_position = pos
	if e.cpu:
		var c: CPUParticles3D = e.node as CPUParticles3D
		c.direction = dir
		if color.a >= 0.0:
			c.color = Color(color.r, color.g, color.b, p.alpha)
		c.amount_ratio = ratio
		c.restart()
		c.emitting = true
	else:
		var g: GPUParticles3D = e.node as GPUParticles3D
		e.mat.direction = dir
		if color.a >= 0.0:
			e.mat.color = Color(color.r, color.g, color.b, p.alpha)
		g.amount_ratio = ratio
		g.restart()
		g.emitting = true
	e.until = _now + p.life + 0.2

## Public API ----------------------------------------------------------------
static func burst(pname: String, pos: Vector3, color: Color = Color(0, 0, 0, -1), scale_amt: float = 1.0, dir: Vector3 = Vector3.UP) -> void:
	if inst != null:
		inst._burst(pname, pos, color, scale_amt, dir)

static func comic_kind(kind: String, pos: Vector3) -> void:
	ComicText.spawn_kind(kind, pos)

static func comic_text_glug(pos: Vector3) -> void:
	ComicText.spawn_kind("water", pos + Vector3.UP * 1.5)

# ------------------------------------------------------------------ flames (fire system)
func acquire_flame(size: float = 1.0) -> Flame:
	var f: Flame
	if not _free_flames.is_empty():
		f = _free_flames.pop_back() as Flame
	else:
		if _flames.size() >= Quality.fire_emitters:
			return null
		f = Flame.new()
		var p: Preset = _presets["flame"] as Preset
		f.em = _make_emitter(p, true)
		f.node = f.em.node
		# looping flame: many small particles, additive
		var sm := _make_emitter(_presets["smoke"] as Preset, true)
		sm.node.reparent(f.node, false)
		f.em.node.set("amount", 14)
		_flames.append(f)
		f.light = null
	f.active = true
	f.size = size
	f.node.visible = true
	_set_flame_emitting(f, true)
	return f

func _set_flame_emitting(f: Flame, on: bool) -> void:
	f.node.set("emitting", on)
	for c in f.node.get_children():
		c.set("emitting", on)

func release_flame(f: Flame) -> void:
	if f == null or not f.active:
		return
	f.active = false
	f.part = null
	_set_flame_emitting(f, false)
	_free_flames.append(f)

func active_flame_count() -> int:
	return _flames.size() - _free_flames.size()

func update_flames() -> void:
	for f in _flames:
		if not f.active:
			continue
		if f.part != null:
			f.node.global_position = f.part.xf.origin + Vector3(0, f.part.size.y * 0.35, 0)
		else:
			f.node.global_position = f.static_pos

# ------------------------------------------------------------------ explosion visuals
func _fb_material(col: Color) -> ShaderMaterial:
	var key: String = col.to_html()
	if _fb_mat_cache.has(key):
		return _fb_mat_cache[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = Toon.toon_shader()
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("emission_strength", 2.0)
	m.set_shader_parameter("emission_color", col)
	_fb_mat_cache[key] = m
	return m

func _spawn_fireball(pos: Vector3, radius: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh
	mi.material_override = _fb_material(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = Vector3.ONE * 0.2
	add_child(mi)
	_fireballs.append({"node": mi, "t": 0.0, "dur": 0.42, "max": radius, "kind": "fb"})

func _spawn_ring(pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.material_override = Toon.unlit(Color(1, 1, 1, 0.7), true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(pos.x, Terrain.h(pos.x, pos.z) + 0.15, pos.z)
	mi.scale = Vector3.ONE * 0.5
	add_child(mi)
	_fireballs.append({"node": mi, "t": 0.0, "dur": 0.55, "max": radius * 1.3, "kind": "ring"})

func _spawn_flash(pos: Vector3, radius: float, col: Color) -> void:
	if Quality.max_lights <= 0:
		return
	var count: int = 0
	for fb in _fireballs:
		if str(fb["kind"]) == "light":
			count += 1
	if count >= Quality.max_lights:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 6.0
	l.omni_range = maxf(radius * 3.0, 8.0)
	l.shadow_enabled = false
	l.light_bake_mode = Light3D.BAKE_DISABLED
	l.light_volumetric_fog_energy = 0.0        # fire / flashes must not turn the (blocky) volumetric fog into a yellow haze
	l.position = pos + Vector3.UP * 1.5
	add_child(l)
	_fireballs.append({"node": l, "t": 0.0, "dur": 0.4, "max": 6.0, "kind": "light"})

static func explosion_visual(pos: Vector3, radius: float, col: Color = Color("#ffb347"), big: bool = false) -> void:
	if inst == null:
		return
	inst._spawn_fireball(pos + Vector3.UP * radius * 0.25, radius * 0.75, col)
	inst._spawn_ring(pos, radius)
	inst._spawn_flash(pos, radius, col)
	var sc: float = clampf(radius / 6.0, 0.5, 1.0)
	inst._burst("smoke", pos + Vector3.UP * radius * 0.3, Color(0, 0, 0, -1), sc, Vector3.UP)
	inst._burst("spark", pos + Vector3.UP * 0.5, Color(0, 0, 0, -1), sc, Vector3.UP)
	inst._burst("dust", pos + Vector3.UP * 0.3, Color(0, 0, 0, -1), sc, Vector3.UP)
	if big:
		inst._burst("smoke", pos + Vector3.UP * radius * 0.9, Color(0, 0, 0, -1), 1.0, Vector3.UP)
		inst._burst("flame", pos + Vector3.UP * 0.6, Color(0, 0, 0, -1), 1.0, Vector3.UP)

func _process(delta: float) -> void:
	_now += delta
	update_flames()
	var i: int = _fireballs.size() - 1
	while i >= 0:
		var fb: Dictionary = _fireballs[i]
		var node: Node3D = fb["node"] as Node3D
		fb["t"] = float(fb["t"]) + delta
		var t: float = float(fb["t"]) / float(fb["dur"])
		if t >= 1.0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_fireballs.remove_at(i)
		else:
			var k: String = str(fb["kind"])
			var mx: float = float(fb["max"])
			if k == "fb":
				var s: float = mx * Util.ease_out_cubic(t) * (1.0 - t * 0.25)
				node.scale = Vector3.ONE * maxf(s, 0.05)
				var mi: MeshInstance3D = node as MeshInstance3D
				mi.transparency = clampf((t - 0.55) / 0.45, 0.0, 1.0)
			elif k == "ring":
				var s2: float = mx * Util.ease_out_cubic(t)
				node.scale = Vector3(s2, 1.0, s2)
				var mi2: MeshInstance3D = node as MeshInstance3D
				mi2.transparency = clampf(t, 0.0, 1.0)
			elif k == "light":
				(node as OmniLight3D).light_energy = mx * (1.0 - t) * (1.0 - t)
		i -= 1
