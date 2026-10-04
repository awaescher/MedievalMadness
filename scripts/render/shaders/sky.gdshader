shader_type sky;

global uniform float gfx_style;
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
	int style = int(gfx_style + 0.5);
	vec3 tc = top_color;
	vec3 hc = horizon_color;
	vec3 gc = ground_color;
	if (style == 1) {
		tc = vec3(0.27, 0.42, 0.70);
		hc = vec3(0.98, 0.80, 0.60);
		gc = vec3(0.42, 0.46, 0.33);
	} else if (style == 3) {
		tc = vec3(0.18, 0.40, 0.92);
		hc = vec3(0.95, 0.85, 0.55);
	} else if (style == 4) {
		tc = vec3(0.33);
		hc = vec3(0.88);
		gc = vec3(0.3);
	} else if (style == 5) {
		tc = vec3(0.015, 0.0, 0.09);
		hc = vec3(0.62, 0.08, 0.5);
		gc = vec3(0.06, 0.0, 0.16);
	} else if (style == 6) {
		tc = vec3(0.62, 0.78, 0.95);
		hc = vec3(1.0, 0.97, 0.9);
		gc = vec3(0.8, 0.85, 0.9);
	}
	vec3 top = mix(tc, storm_top, storm_mix);
	vec3 hor = mix(hc, storm_horizon, storm_mix);
	float t = pow(clamp(h, 0.0, 1.0), 0.55);
	vec3 col = mix(hor, top, t);
	if (style == 3) {
		col = floor(col * 6.0 + 0.5) / 6.0;
	}
	if (h < 0.0) {
		col = mix(hor, gc, clamp(-h * 4.0, 0.0, 1.0));
	}
	// sun disc with toon edge
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float d = distance(dir, sun_dir);
	float disc = 1.0 - smoothstep(sun_size, sun_size + 0.006, d);
	if (style == 1) {
		disc = 1.0 - smoothstep(sun_size * 0.7, sun_size * 1.6, d);
	} else if (style == 5) {
		// synthwave sun: striped disc that gets sliced towards the bottom
		float stripe = step(0.0, sin((dir.y - sun_dir.y) * 160.0 + 1.5)) + step(0.0, dir.y - sun_dir.y + 0.02);
		disc *= clamp(stripe, 0.0, 1.0);
	}
	float halo = 1.0 - smoothstep(sun_size, sun_size * 4.0, d);
	col += LIGHT0_COLOR * halo * 0.18 * (1.0 - storm_mix);
	if (style == 1) {
		// golden hour: a wide warm glow around the low sun
		float wide = 1.0 - smoothstep(0.0, 1.1, d);
		col += LIGHT0_COLOR * (wide * wide * 0.55 + pow(wide, 6.0) * 0.5) * (1.0 - storm_mix);
	}
	vec3 sun_col = style == 5 ? vec3(1.0, 0.85, 0.2) : vec3(1.0, 0.97, 0.85);
	col = mix(col, sun_col, disc * (1.0 - storm_mix * 0.85));
	COLOR = col;
}
