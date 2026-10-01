shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.9, 0.2, 0.2, 1.0);
uniform float strength = 1.0;

void vertex() {
	float t = TIME * 5.0;
	float x = VERTEX.x;
	VERTEX.z += sin(x * 4.2 - t) * 0.09 * strength * x;
	VERTEX.y += sin(x * 3.0 - t * 1.3) * 0.03 * strength * x;
}

void fragment() {
	ALBEDO = albedo.rgb * (0.85 + 0.15 * sin(UV.x * 20.0));
	ROUGHNESS = 1.0;
}

void light() {
	float nl = clamp(abs(dot(NORMAL, LIGHT)) * ATTENUATION, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * (0.55 + 0.45 * step(0.4, nl)) * 0.3183;
}
