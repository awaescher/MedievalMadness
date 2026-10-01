shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

// Soft glowing shell around a fireball: bright towards the middle of the disc, fading out at the rim.
uniform vec3 tint : source_color = vec3(1.0, 0.5, 0.15);
uniform float strength = 1.0;
uniform float pulse_speed = 9.0;

void fragment() {
	float d = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float a = pow(d, 1.6) * strength * (0.85 + 0.15 * sin(TIME * pulse_speed));
	ALBEDO = tint * a;
	ALPHA = a;
}
