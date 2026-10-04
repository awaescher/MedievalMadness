shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

// Inverted-hull outline (spec 16.1). CUSTOM0.xyz holds the pre-scaled outline offset
// direction per vertex (box corners expand uniformly, so hard-edged boxes stay closed).
// gfx_style (global): noir draws thick ink lines, neon thin glowing ones, retro pure black.

global uniform float gfx_style;
uniform vec4 outline_color : source_color = vec4(0.10, 0.07, 0.13, 1.0);
uniform float width_scale = 1.0;

varying vec3 wp;

void vertex() {
	float k = 1.0;
	if (gfx_style > 3.5 && gfx_style < 4.5) {
		k = 1.7;
	} else if (gfx_style > 4.5 && gfx_style < 5.5) {
		k = 0.55;
	} else if (gfx_style > 6.5) {
		k = 3.6;
	}
	VERTEX += CUSTOM0.xyz * width_scale * k;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = outline_color.rgb;
	if (gfx_style > 2.5 && gfx_style < 3.5) {
		col = vec3(0.0);
	} else if (gfx_style > 3.5 && gfx_style < 4.5) {
		col = vec3(0.01);
	} else if (gfx_style > 6.5) {
		col = vec3(0.015, 0.01, 0.02);
	} else if (gfx_style > 4.5 && gfx_style < 5.5) {
		col = mix(vec3(2.4, 0.2, 1.7), vec3(0.2, 2.0, 2.6), 0.5 + 0.5 * sin(wp.x * 0.06 + wp.z * 0.045 + wp.y * 0.1));
	}
	ALBEDO = col;
}
