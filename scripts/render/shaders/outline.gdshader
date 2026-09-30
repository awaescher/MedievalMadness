shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

// Inverted-hull outline (spec 16.1). CUSTOM0.xyz holds the pre-scaled outline offset
// direction per vertex (box corners expand uniformly, so hard-edged boxes stay closed).

uniform vec4 outline_color : source_color = vec4(0.10, 0.07, 0.13, 1.0);
uniform float width_scale = 1.0;

void vertex() {
	VERTEX += CUSTOM0.xyz * width_scale;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
