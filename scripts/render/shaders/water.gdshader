shader_type spatial;
render_mode cull_disabled, specular_disabled, depth_draw_never;

// Cheap toon-ish water: sine vertex waves, banded color, shoreline foam via depth texture.

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
	// banded (toon) depth color
	float band = floor(t * 4.0) / 4.0;
	vec4 col = mix(shallow_color, deep_color, band);
	// animated shoreline foam (hard toon edge)
	float wob = sin(world_pos.x * 1.7 + TIME * 1.3) * 0.12 + sin(world_pos.z * 2.1 - TIME * 1.1) * 0.10;
	float foam = 1.0 - smoothstep(foam_width * 0.9 + wob, foam_width * 0.9 + wob + 0.02, water_depth);
	foam *= 1.0 - smoothstep(170.0, 300.0, -VERTEX.z);
	// crest highlights
	float cs = sin(world_pos.x * 0.8 + TIME) * sin(world_pos.z * 0.7 - TIME * 0.7) + sin(world_pos.x * 0.31 - world_pos.z * 0.47 + TIME * 0.6) * 0.6;
	float crest = smoothstep(1.28, 1.36, cs) * crest_strength;
	col.rgb = mix(col.rgb, foam_color.rgb, max(foam, crest));
	col.a = max(col.a, foam);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 1.0;
	EMISSION = col.rgb * 0.25;
}
