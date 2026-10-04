shader_type canvas_item;

// Full-screen look of the graphics style (see GfxStyle): film grain / pixelation / halftone / tilt-shift on the finished 3D image.
// 0 toon: untouched (the layer is hidden), 1 photo, (2 is unused), 3 retro, 4 noir, 5 neon, 6 watercolor, 7 colour comic.

global uniform float gfx_style;
uniform sampler2D scr : hint_screen_texture, repeat_disable, filter_linear;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[idx] / 16.0;
}

float vn2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float lumi(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 sat(vec3 c, float s) {
	return mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, s);
}

void fragment() {
	int style = int(gfx_style + 0.5);
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 cc = uv - 0.5;
	vec3 col = texture(scr, uv).rgb;
	if (style == 1) {
		// photo: chromatic fringe, unsharp mask, S-curve, grain, vignette
		float r2 = dot(cc, cc);
		vec3 ca = vec3(texture(scr, uv + cc * r2 * 0.005).r, col.g, texture(scr, uv - cc * r2 * 0.005).b);
		vec3 blur = (texture(scr, uv + vec2(px.x, 0.0) * 1.5).rgb + texture(scr, uv - vec2(px.x, 0.0) * 1.5).rgb
				+ texture(scr, uv + vec2(0.0, px.y) * 1.5).rgb + texture(scr, uv - vec2(0.0, px.y) * 1.5).rgb) * 0.25;
		col = ca + (ca - blur) * 0.55;
		col = mix(col, col * col * (3.0 - 2.0 * col), 0.35);
		col *= 1.0 - r2 * 0.75;
		// grade: warm highlights, cool shadows, slightly lifted blacks (like film)
		float gl_ = lumi(col);
		col = mix(col, col * vec3(1.07, 1.0, 0.9), smoothstep(0.4, 0.9, gl_));
		col = mix(col, col * vec3(0.9, 0.98, 1.1), 1.0 - smoothstep(0.08, 0.45, gl_));
		col = col * 0.97 + 0.015;
		col += (hash12(uv / px + fract(TIME) * 61.0) - 0.5) * 0.035;
	} else if (style == 3) {
		// retro: finer pixel grid, 15-bit colour, ordered dither, then a curved CRT: barrel distortion, scan lines, shadow mask, glow
		vec2 q = uv * 2.0 - 1.0;
		q *= 1.0 + dot(q, q) * 0.045;
		vec2 cuv = q * 0.5 + 0.5;
		vec2 cells = vec2(640.0, 640.0 / aspect);
		vec2 g = (floor(cuv * cells) + 0.5) / cells;
		col = texture(scr, g).rgb;
		float d = bayer4(floor(cuv * cells));
		col = floor(col * 31.0 + 0.5 + (d - 0.5) * 0.5) / 31.0;
		// phosphor glow: a little of the neighbouring pixels bleeds in (brightness only, no colour fringes)
		vec3 gl = (texture(scr, g + vec2(1.5, 0.0) / cells).rgb + texture(scr, g - vec2(1.5, 0.0) / cells).rgb) * 0.5;
		col = mix(col, max(col, gl), 0.2);
		// scan lines and a neutral aperture grille: luminance only, so the colours between the pixels stay clean
		float sl = 0.5 + 0.5 * cos(cuv.y * cells.y * 6.2831853);
		col *= 0.88 + 0.12 * sl;
		float mx = fract(uv.x / px.x / 3.0);
		col *= 0.94 + 0.06 * step(0.333, mx);
		// punchier picture: a gentle S-curve and a bit more saturation
		col = mix(col, col * col * (3.0 - 2.0 * col), 0.6);
		col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, 1.12);
		col *= 1.0 + 0.004 * sin(TIME * 7.0);
		// every few seconds a faint bright band rolls down the screen
		float roll = fract(TIME / 7.0) * 1.6 - 0.3;
		col *= 1.0 + 0.09 * smoothstep(0.12, 0.0, abs(uv.y - roll)) * step(roll, 1.1);
		vec2 e = abs(q);
		float inside = step(max(e.x, e.y), 1.0);
		col *= 1.0 - dot(q, q) * 0.28;
		// rounded screen corners and black bezel
		float corner = smoothstep(1.0, 0.985, max(e.x, e.y));
		col = col * corner * inside;
	} else if (style == 4) {
		// noir comic: black ink halftone dots on yellowed paper
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		vec2 p = uv / vec2(px.x, px.y) / 6.0;
		float ca = 0.7071;
		vec2 rp = vec2(p.x * ca - p.y * ca, p.x * ca + p.y * ca);
		float dist = length(fract(rp) - 0.5) * 2.0;
		float dots = smoothstep(0.0, 0.15, (1.0 - dist) - (1.0 - clamp(l * 1.2, 0.0, 1.0)) * 1.15 + 0.05);
		float ink = mix(dots, 1.0, smoothstep(0.55, 0.85, l));
		vec3 paper = vec3(0.93, 0.89, 0.78);
		col = mix(vec3(0.07, 0.06, 0.07), paper, clamp(ink, 0.0, 1.0));
		col *= 1.0 - dot(cc, cc) * 0.6;
	} else if (style == 5) {
		// neon: split toning, scan lines, RGB shift
		float sh = 0.0006 + dot(cc, cc) * 0.0035;
		col = vec3(texture(scr, uv + vec2(sh, 0.0)).r, col.g, texture(scr, uv - vec2(sh, 0.0)).b);
		col = sat(col, 1.2);
		col = mix(col, col * vec3(0.9, 0.85, 1.25), 0.35);
		col *= 0.93 + 0.07 * sin(uv.y / px.y * 1.8);
		col *= 1.0 - dot(cc, cc) * 0.9;
	}
	if (style == 6) {
		// watercolor: soft wash, pigment pooling at edges, paper grain
		vec3 blur = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			blur += texture(scr, uv + vec2(cos(a), sin(a)) * px * 3.0).rgb;
		}
		blur /= 8.0;
		col = mix(col, blur, 0.65);
		float edge = abs(lumi(texture(scr, uv + vec2(px.x, 0.0) * 2.0).rgb) - lumi(texture(scr, uv - vec2(px.x, 0.0) * 2.0).rgb))
				+ abs(lumi(texture(scr, uv + vec2(0.0, px.y) * 2.0).rgb) - lumi(texture(scr, uv - vec2(0.0, px.y) * 2.0).rgb));
		col *= 1.0 - clamp(edge * 1.8, 0.0, 0.5);
		vec2 pp = uv / px;
		float paper = vn2(pp * 0.35) * 0.5 + vn2(pp * 0.9) * 0.3 + hash12(pp) * 0.2;
		col *= 0.9 + 0.14 * paper;
		col = mix(col, vec3(0.97, 0.95, 0.9), 0.1);
		col *= 1.0 - dot(cc, cc) * 0.35;
	}
	if (style == 7) {
		// colour comic: no dots any more, just a warm paper tone and a soft vignette (the look comes from the thick outlines)
		col = mix(col, col * vec3(1.04, 1.0, 0.93), 0.5);
		col *= 1.0 - dot(cc, cc) * 0.35;
	}
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
