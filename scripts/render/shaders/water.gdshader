shader_type spatial;
render_mode cull_disabled, depth_draw_never;

// Cheap toon-ish water: sine vertex waves, banded color, shoreline foam via depth texture.

global uniform float gfx_style;
uniform vec4 shallow_color : source_color = vec4(0.25, 0.75, 0.98, 0.55);
uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.72, 0.92);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wave_height = 0.12;
uniform float wave_speed = 1.2;
uniform float foam_width = 0.55;
uniform float depth_range = 3.0;
uniform float crest_strength = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
instance uniform float level_offset = 0.0;

varying vec3 world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wp.x * 0.45 + TIME * wave_speed) * cos(wp.z * 0.38 + TIME * wave_speed * 0.8);
	w += sin((wp.x + wp.z) * 0.9 - TIME * wave_speed * 1.6) * 0.4;
	VERTEX.y += w * wave_height;
	world_pos = wp;
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float water_depth = max(scene_depth + VERTEX.z, 0.0);
	if (depth < 0.00001) {
		water_depth = depth_range * 4.0;
	}
	float t = clamp(water_depth / depth_range, 0.0, 1.0);
	// banded (toon) depth color; the realistic styles blend smoothly
	bool smooth_water = (gfx_style > 0.5 && gfx_style < 1.5) || (gfx_style > 5.5 && gfx_style < 6.5);
	float band = smooth_water ? smoothstep(0.0, 1.0, t) : floor(t * 4.0) / 4.0;
	if (gfx_style > 2.5 && gfx_style < 3.5) {
		band = floor(t * 3.0) / 3.0;
	}
	vec4 col = mix(shallow_color, deep_color, band);
	// animated shoreline foam (hard toon edge)
	float wob = sin(world_pos.x * 1.7 + TIME * 1.3) * 0.12 + sin(world_pos.z * 2.1 - TIME * 1.1) * 0.10;
	float foam = 1.0 - smoothstep(foam_width * 0.9 + wob, foam_width * 0.9 + wob + 0.02, water_depth);
	foam *= 1.0 - smoothstep(170.0, 300.0, -VERTEX.z);
	// crest highlights
	float cs = sin(world_pos.x * 0.8 + TIME) * sin(world_pos.z * 0.7 - TIME * 0.7) + sin(world_pos.x * 0.31 - world_pos.z * 0.47 + TIME * 0.6) * 0.6;
	float crest = smoothstep(1.28, 1.36, cs) * crest_strength;
	if (gfx_style > 0.5 && gfx_style < 1.5) {
		foam *= 0.55 * (0.6 + 0.4 * sin(world_pos.x * 1.1 + world_pos.z * 0.9 + TIME * 1.0));
		crest = 0.0;
	}
	col.rgb = mix(col.rgb, foam_color.rgb, max(foam, crest));
	col.a = max(col.a, foam);
	float refl = 0.0;
	if (gfx_style > 0.5 && gfx_style < 1.5) {
		// photo: ripple normals so the sky and the sun mirror in the surface
		// large, slow swell plus a gentle second layer: broad ripples instead of a fine checker pattern
		vec2 w1 = world_pos.xz * 0.18 + vec2(TIME * 0.05, TIME * 0.035);
		vec2 w2 = world_pos.xz * 0.07 + vec2(-TIME * 0.03, TIME * 0.04);
		vec2 d = vec2(sin(w1.x * 2.0 + sin(w1.y * 1.3)) * 0.5 + cos(w2.y * 2.7 - w2.x), cos(w1.x * 1.7 + w2.y) * sin(w1.y * 2.1 + w2.x * 0.7)) * 0.09;
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(d.x, 1.0, d.y)), 0.0)).xyz);
		refl = 1.0;
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = mix(1.0, 0.06, refl);
	SPECULAR = refl * 0.9;
	METALLIC = 0.0;
	EMISSION = col.rgb * mix(0.25, 0.06, refl);
	if (gfx_style > 4.5 && gfx_style < 5.5) {
		EMISSION = col.rgb * 0.9 + vec3(0.05, 0.4, 0.55) * max(foam, crest) * 2.0;
	}
}
