shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

// Billboard bar (hp bars). instance uniform "fill" 0..1.

uniform vec4 col_full : source_color = vec4(0.25, 0.9, 0.3, 1.0);
uniform vec4 col_empty : source_color = vec4(0.95, 0.2, 0.15, 1.0);
uniform vec4 col_back : source_color = vec4(0.08, 0.05, 0.1, 0.85);
instance uniform float fill = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV;
	float border = 0.07;
	vec4 c = col_back;
	if (uv.x > border && uv.x < 1.0 - border && uv.y > border * 1.8 && uv.y < 1.0 - border * 1.8) {
		float x = (uv.x - border) / (1.0 - 2.0 * border);
		if (x <= fill) {
			c = vec4(mix(col_empty.rgb, col_full.rgb, clamp(fill * 1.3, 0.0, 1.0)), 1.0);
		} else {
			c = vec4(0.22, 0.16, 0.2, 0.9);
		}
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
