shader_type sky;

uniform vec3 top_color : source_color = vec3(0.29, 0.66, 1.0);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.91, 0.72);
uniform vec3 storm_top : source_color = vec3(0.29, 0.33, 0.41);
uniform vec3 storm_horizon : source_color = vec3(0.54, 0.56, 0.60);
uniform float storm_mix = 0.0;
uniform float sun_size = 0.035;
uniform vec3 ground_color : source_color = vec3(0.35, 0.50, 0.62);

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, -1.0, 1.0);
	vec3 top = mix(top_color, storm_top, storm_mix);
	vec3 hor = mix(horizon_color, storm_horizon, storm_mix);
	float t = pow(clamp(h, 0.0, 1.0), 0.55);
	vec3 col = mix(hor, top, t);
	if (h < 0.0) {
		col = mix(hor, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}
	// sun disc with toon edge
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float d = distance(dir, sun_dir);
	float disc = 1.0 - smoothstep(sun_size, sun_size + 0.006, d);
	float halo = 1.0 - smoothstep(sun_size, sun_size * 4.0, d);
	col += LIGHT0_COLOR * halo * 0.18 * (1.0 - storm_mix);
	col = mix(col, vec3(1.0, 0.97, 0.85), disc * (1.0 - storm_mix * 0.85));
	COLOR = col;
}
