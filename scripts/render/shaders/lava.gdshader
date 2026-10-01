shader_type spatial;
render_mode unshaded, cull_back;

// Molten meteor rock: a dark crust with glowing cracks that crawl over the surface, a hot rim (fresnel) and a flicker.
uniform float heat = 1.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float cracks(vec3 p, float t) {
	float a = sin(p.x * 1.7 + sin(p.y * 1.3 + t * 0.7) * 1.4) * sin(p.y * 1.9 + sin(p.z * 1.5 - t * 0.5) * 1.3);
	float b = sin(p.z * 2.1 + sin(p.x * 1.1 + t * 0.4) * 1.5) * sin(p.x * 1.3 + p.y * 0.9 - t * 0.3);
	float c = sin((p.x + p.y + p.z) * 1.1 + sin(p.z * 2.0) * 1.2);
	float v = 1.0 - abs(a * 0.6 + b * 0.5 + c * 0.35);
	return smoothstep(0.78, 0.97, v);
}

void fragment() {
	float t = TIME;
	float crack = cracks(lp * 1.15, t);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	vec3 crust = mix(vec3(0.07, 0.04, 0.03), vec3(0.20, 0.07, 0.03), 0.5 + 0.5 * sin(lp.x * 2.0 + lp.y * 3.0));
	vec3 lava = mix(vec3(1.0, 0.25, 0.03), vec3(1.0, 0.85, 0.35), crack);
	float flick = 0.85 + 0.15 * sin(t * 17.0 + lp.x * 3.0);
	vec3 col = crust + lava * crack * 3.0 * flick * heat + vec3(1.0, 0.45, 0.1) * fres * 1.8 * heat;
	ALBEDO = col;
}
