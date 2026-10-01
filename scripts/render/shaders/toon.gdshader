shader_type spatial;
render_mode specular_disabled, cull_back;

// Toon shader (spec 16.1): light() quantizes NdotL * ATTENUATION into 4 hard steps.
// ALBEDO comes from vertex COLOR x albedo uniform x per-instance tint.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float step0 = 0.31;
uniform float step1 = 0.55;
uniform float step2 = 0.78;
uniform float step3 = 1.0;
uniform float emission_strength = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float terrain_noise = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float glow = 0.0;
instance uniform float wet = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = COLOR.rgb * albedo.rgb * tint.rgb;
	if (terrain_noise > 0.0) {
		float n = sin(world_pos.x * 0.9) * sin(world_pos.z * 1.1) + sin(world_pos.x * 2.3 + world_pos.z * 1.7) * 0.5;
		c *= 1.0 + n * 0.035 * terrain_noise;
	}
	c = mix(c, c * vec3(0.72, 0.8, 0.95), clamp(wet, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = emission_color.rgb * (emission_strength + glow) * (0.5 + 0.5 * COLOR.r);
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT) * ATTENUATION, 0.0, 1.0);
	float s = step0;
	if (nl > 0.72) {
		s = step3;
	} else if (nl > 0.42) {
		s = step2;
	} else if (nl > 0.12) {
		s = step1;
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * s * 0.3183;
}
