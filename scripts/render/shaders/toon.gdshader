shader_type spatial;
render_mode cull_back;

// Toon shader (spec 16.1): light() quantizes NdotL * ATTENUATION into 4 hard steps.
// ALBEDO comes from vertex COLOR x albedo uniform x per-instance tint.
// gfx_style (global, see GfxStyle) switches the look: 0 toon, 1 photo, (2 is unused), 3 retro, 4 noir, 5 neon, 6 watercolor, 7 colour comic.

global uniform float gfx_style;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float step0 = 0.31;
uniform float step1 = 0.55;
uniform float step2 = 0.78;
uniform float step3 = 1.0;
uniform float emission_strength = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float terrain_noise = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float glow = 0.0;
instance uniform float wet = 0.0;
instance uniform float mat_id = 0.0;     // texture layer + 1 for meshes of one material (0: use the per-vertex UV.x)

// photo style: real material textures, projected triplanar (the meshes have no UVs). See GfxTextures.
global uniform sampler2DArray gfx_tex_c;
global uniform sampler2DArray gfx_tex_n;
global uniform sampler2D gfx_tex_avg;
const float TSCALE[12] = float[12](1.3, 1.5, 0.9, 1.6, 1.1, 3.2, 2.0, 1.1, 0.7, 6.5, 1.1, 1.8);

varying vec3 world_pos;
varying vec3 lpos;
varying vec3 lnrm;
varying float vmat;
varying float vlayer;     // texture layer of the part (-1: none), 9 = foliage

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// cellular noise: xyz = vector from the nearest cell point to p, w = distance to the cell border (0 on the seams between clumps)
vec4 worley(vec3 p, out float cell_id) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	vec3 off = vec3(0.0);
	cell_id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 r = g + hash33(ip + g) - fp;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
					off = -r;
					cell_id = hash13(ip + g);
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec4(off, sqrt(d2) - sqrt(d1));
}

vec4 tsamp(sampler2DArray t, vec2 uv, float layer) {
	return textureGrad(t, vec3(fract(uv), layer), dFdx(uv), dFdy(uv));
}

// like tsamp, but without visible repetition: a second sample, rotated and at another scale, takes over in patches
vec4 tsamp2(sampler2DArray t, vec2 uv, float layer) {
	const mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 uv2 = rot * uv * 0.61 + vec2(0.37, 0.19);
	float m = smoothstep(0.3, 0.7, vnoise(vec3(uv * 0.23, layer)));
	return mix(tsamp(t, uv, layer), tsamp(t, uv2, layer), m);
}

// triplanar colour (rgb, relative to the layer's average colour), roughness and a normal offset in object space
void tri_tex(float layer, vec3 p, vec3 n, out vec3 detail, out vec3 real, out float rough, out vec3 nperturb) {
	vec3 w = pow(abs(n), vec3(5.0));
	w /= (w.x + w.y + w.z);
	vec3 q = p * TSCALE[int(layer)];
	vec4 cx = tsamp2(gfx_tex_c, q.zy, layer);
	vec4 cy = tsamp2(gfx_tex_c, q.xz, layer);
	vec4 cz = tsamp2(gfx_tex_c, q.xy, layer);
	vec4 c = cx * w.x + cy * w.y + cz * w.z;
	vec3 avg = texelFetch(gfx_tex_avg, ivec2(int(layer), 0), 0).rgb;
	detail = c.rgb / max(avg, vec3(0.03));
	real = c.rgb;
	rough = c.a;
	vec3 tx = tsamp2(gfx_tex_n, q.zy, layer).xyz * 2.0 - 1.0;
	vec3 ty = tsamp2(gfx_tex_n, q.xz, layer).xyz * 2.0 - 1.0;
	vec3 tz = tsamp2(gfx_tex_n, q.xy, layer).xyz * 2.0 - 1.0;
	nperturb = vec3(0.0, tx.y, tx.x * sign(n.x)) * w.x + vec3(ty.x * sign(n.y), 0.0, ty.y) * w.y + vec3(tz.x * sign(n.z), tz.y, 0.0) * w.z;
}

float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.13) * 0.28 + vnoise(p * 4.7) * 0.15 + vnoise(p * 11.3) * 0.07;
}

void vertex() {
	vlayer = (mat_id > 0.5 ? mat_id : UV.x) - 1.0;
	// texture space: the part itself (so debris keeps its texture), shifted per instance so equal parts do not look alike
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 shift = fract(org * vec3(0.137, 0.291, 0.173)) * 17.0;
	vec3 vtx = VERTEX;
	if (gfx_style > 0.5 && gfx_style < 1.5 && vlayer > 8.5 && vlayer < 9.5) {
		// photo foliage: crowns get a ragged, clumpy silhouette instead of a smooth ball
		float wid;
		vec4 wv = worley((VERTEX + shift) * 1.15, wid);
		float bulge = 1.0 - clamp(length(wv.xyz), 0.0, 1.0);
		vtx += NORMAL * (bulge - 0.45) * 0.75 + NORMAL * (vnoise((VERTEX + shift) * 3.1) - 0.5) * 0.18;
	}
	world_pos = (MODEL_MATRIX * vec4(vtx, 1.0)).xyz;
	lpos = vtx + shift;
	lnrm = NORMAL;
	vmat = UV.x;
	// POSITION is written for every style (a shader that sets it in only one branch leaves it at 0 in the others)
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(vtx, 1.0));
	if (gfx_style > 2.5 && gfx_style < 3.5) {
		// retro: vertices snap to a coarse screen grid (the wobble of early 3D consoles)
		vec2 grid = vec2(480.0, 270.0);
		clip.xy = floor(clip.xy / clip.w * grid + 0.5) / grid * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	int style = int(gfx_style + 0.5);
	vec3 c = COLOR.rgb * albedo.rgb * tint.rgb;
	if (terrain_noise > 0.0) {
		float n = sin(world_pos.x * 0.9) * sin(world_pos.z * 1.1) + sin(world_pos.x * 2.3 + world_pos.z * 1.7) * 0.5;
		c *= 1.0 + n * 0.035 * terrain_noise;
	}
	c = mix(c, c * vec3(0.72, 0.8, 0.95), clamp(wet, 0.0, 1.0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec3 emis = emission_color.rgb * (emission_strength + glow) * (0.5 + 0.5 * COLOR.r);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	if (style == 1) {
		// photo: surfaces get a real material (textures) or, where none is assigned, grain and micro bumps
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float layer = -1.0;
		if (terrain_noise > 0.0) {
			// ground: grass on the green parts of the vertex colours, stone on grey, soil elsewhere
			float gw = clamp((COLOR.g - COLOR.r) * 7.0, 0.0, 1.0);
			float sat_ = max(COLOR.r, max(COLOR.g, COLOR.b)) - min(COLOR.r, min(COLOR.g, COLOR.b));
			float sw = (1.0 - gw) * clamp(1.0 - sat_ * 9.0, 0.0, 1.0);
			float dw = 1.0 - gw - sw;
			float cobm = smoothstep(0.5, 0.62, fbm(world_pos * 0.1 + 11.0));      // cobbled patches in the trodden earth
			vec3 avg_c = vec3(0.0);
			vec3 nacc = vec3(0.0);
			vec3 real_c = vec3(0.0);
			float rough_acc = 0.0;
			for (int k = 0; k < 4; k++) {
				float lw = k == 0 ? gw : (k == 1 ? sw : (k == 2 ? dw * (1.0 - cobm) : dw * cobm));
				if (lw > 0.01) {
					float ly = k == 0 ? 7.0 : (k == 1 ? 2.0 : (k == 2 ? 8.0 : 11.0));
					float sc = TSCALE[int(ly)];
					vec2 uv1 = world_pos.xz * sc;
					vec2 uv2 = world_pos.xz * sc * 0.27 + vec2(0.37, 0.71);
					vec4 t1 = tsamp(gfx_tex_c, uv1, ly);
					vec4 t2 = tsamp(gfx_tex_c, uv2, ly);
					vec4 tc = mix(t1, t2, 0.45);
					vec3 av = texelFetch(gfx_tex_avg, ivec2(int(ly), 0), 0).rgb;
					avg_c += lw * tc.rgb / max(av, vec3(0.03));
					real_c += lw * tc.rgb;
					rough_acc += lw * tc.a;
					vec3 tn = mix(tsamp(gfx_tex_n, uv1, ly).xyz, tsamp(gfx_tex_n, uv2, ly).xyz, 0.45) * 2.0 - 1.0;
					nacc += lw * vec3(tn.x, 0.0, tn.y);
					vec3 tn3 = tsamp(gfx_tex_n, world_pos.xz * 3.1, ly).xyz * 2.0 - 1.0;
					nacc += lw * vec3(tn3.x, 0.0, tn3.y) * 0.8;
				}
			}
			// the vertex colours are cartoon-saturated: pull them towards the real ground colour and add large-scale patchiness
			vec3 cv = mix(vec3(lum), c, 0.7);
			c = mix(cv * mix(vec3(dot(avg_c, vec3(0.333))), avg_c, 0.7), real_c * real_c, 0.55);
			float macro = fbm(world_pos * 0.045) * 0.7 + fbm(world_pos * 0.2) * 0.3;
			c *= mix(vec3(0.8, 0.85, 0.7), vec3(1.08, 1.06, 0.97), macro);
			if (gw > 0.01) {
				// grass: its own colour (not the cartoon vertex colour): olive/yellow patches, tufts, and the blade texture at two scales
				vec3 gav = texelFetch(gfx_tex_avg, ivec2(7, 0), 0).rgb;
				float gl = dot(gav, vec3(0.333));
				float gd = (dot(tsamp(gfx_tex_c, world_pos.xz * 0.7, 7.0).rgb, vec3(0.333)) / gl) * (dot(tsamp(gfx_tex_c, world_pos.xz * 3.1, 7.0).rgb, vec3(0.333)) / gl);
				float patch2 = fbm(world_pos * 0.09 + 3.7);
				vec3 gbase = mix(vec3(0.1, 0.17, 0.04), vec3(0.26, 0.32, 0.08), patch2 * 0.8 + macro * 0.2);
				float tuft = vnoise(world_pos * vec3(2.4, 0.0, 2.4)) * 0.6 + vnoise(world_pos * 8.0) * 0.4;
				vec3 gcol = gbase * (0.5 + 1.0 * tuft) * clamp(pow(gd, 1.6), 0.4, 2.0);
				c = mix(c, gcol, gw);
			}
			ROUGHNESS = clamp(rough_acc, 0.5, 1.0);
			vec3 nobj = normalize(wn + nacc * 0.9 * vec3(1.0, 0.0, 1.0));
			NORMAL = normalize((VIEW_MATRIX * vec4(nobj, 0.0)).xyz);
		} else {
			layer = vlayer;
			if (layer > 8.5 && layer < 9.5) {
				// foliage: leafy detail, strong bumps, darker inside and below the crown, a little sheen
				vec3 detail;
				vec3 real;
				float rough;
				vec3 npert;
				tri_tex(layer, lpos, normalize(lnrm), detail, real, rough, npert);
				detail = pow(detail, vec3(1.9));
				// leaf clumps: each cell is a rounded lump, dark in the creases between lumps
				vec3 pw = lpos * 1.5 + (vec3(vnoise(lpos * 3.0), vnoise(lpos * 3.0 + 7.1), vnoise(lpos * 3.0 + 13.3)) - 0.5) * 0.8;
				float cid;
				vec4 wc = worley(pw, cid);
				float crease = smoothstep(0.0, 0.5, wc.w);
				// single leaves: small cells with their own brightness, dark gaps between them and a slight tilt each
				float lid;
				vec4 wl = worley(lpos * 5.5 + (vec3(vnoise(lpos * 9.0), vnoise(lpos * 9.0 + 5.3), vnoise(lpos * 9.0 + 9.7)) - 0.5) * 1.1, lid);
				float lgap = smoothstep(0.0, 0.3, wl.w);
				float inner = mix(0.45, 1.0, clamp(wn.y * 0.5 + 0.55, 0.0, 1.0));
				float patch_ = 0.75 + 0.5 * vnoise(lpos * 0.8);
				vec3 leafc = mix(c * mix(vec3(dot(detail, vec3(0.333))), detail, 0.85), real * real, 0.25);
				leafc *= mix(vec3(0.7, 0.8, 0.6), vec3(1.15, 1.1, 0.8), clamp(wn.y * 0.6 + 0.3, 0.0, 1.0) * crease);   // sunlit tops turn yellow-green
				leafc *= vec3(1.1, 1.05, 0.62);
				leafc *= mix(vec3(0.8, 0.95, 0.7), vec3(1.2, 1.1, 0.85), lid) * (0.8 + 0.4 * lid);                      // every leaf a little different
				c = leafc * inner * patch_ * mix(0.55, 1.0, crease) * mix(0.72, 1.0, lgap);
				vec3 no = normalize(normalize(lnrm) + npert * 1.1 + wc.xyz * 0.55 * smoothstep(0.0, 0.3, wc.w) + wl.xyz * 0.6 * smoothstep(0.0, 0.3, wl.w));
				NORMAL = normalize((VIEW_MATRIX * vec4(mat3(MODEL_MATRIX) * no, 0.0)).xyz);
				ROUGHNESS = 0.75;
			} else if (layer > -0.5) {
				vec3 detail;
				vec3 real;
				float rough;
				vec3 npert;
				tri_tex(layer, lpos, normalize(lnrm), detail, real, rough, npert);
				detail = pow(detail, vec3(layer > 1.5 && layer < 2.5 ? 2.4 : 1.45));
				c = mix(c * mix(vec3(dot(detail, vec3(0.333))), detail, 0.8), real * real, (layer > 1.5 && layer < 2.5) ? 0.2 : 0.4);
				if (layer > 3.5 && layer < 4.5) {
					// thatch: bundles of straw laid in rows down the slope, each row shadowing the one below, fine strands along the slope
					vec3 down = vec3(0.0, -1.0, 0.0) - wn * dot(wn, vec3(0.0, -1.0, 0.0));
					down = length(down) > 0.05 ? normalize(down) : vec3(1.0, 0.0, 0.0);
					vec3 across = normalize(cross(wn, down));
					float u = dot(world_pos, across);
					float vv = dot(world_pos, down);
					float rowf = vv * 2.4 + vnoise(vec3(u * 1.6, 0.0, 3.1)) * 0.25;
					float rowi = floor(rowf);
					float rowp = fract(rowf);
					float bundle = hash13(vec3(floor(u * 2.8 + hash13(vec3(rowi, 1.0, 2.0)) * 5.0), rowi, 7.0));
					float strand = vnoise(vec3(u * 46.0, vv * 2.6, rowi)) * 0.6 + vnoise(vec3(u * 120.0, vv * 5.0, rowi + 3.0)) * 0.4;
					float lip = smoothstep(0.0, 0.18, rowp) * (1.0 - 0.35 * smoothstep(0.55, 1.0, rowp));      // dark under the lip of every row
					vec3 straw = c * (0.55 + 0.9 * strand) * (0.78 + 0.4 * bundle);
					c = mix(c, straw, 0.9) * (0.45 + 0.65 * lip);
					vec3 bump = down * ((rowp - 0.5) * 0.7) + across * ((strand - 0.5) * 0.5);
					vec3 nw = normalize(wn + bump);
					NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
					ROUGHNESS = 0.95;
				}
				if (layer > 1.5 && layer < 2.5) {
					// stone: moss and ivy in vertical streaks, mostly on the weather side and near the ground
					float streak = vnoise(vec3(world_pos.x * 0.9, world_pos.y * 0.12, world_pos.z * 0.9)) * 0.65 + vnoise(world_pos * 3.0) * 0.35;
					float moss = smoothstep(0.52, 0.72, streak);
					c = mix(c, vec3(0.07, 0.13, 0.03) * (0.6 + 0.8 * detail.g), moss * 0.6);
				}
				ROUGHNESS = clamp(rough, 0.25, 1.0);
				vec3 no = normalize(normalize(lnrm) + npert * 0.9);
				NORMAL = normalize((VIEW_MATRIX * vec4(mat3(MODEL_MATRIX) * no, 0.0)).xyz);
			} else {
				float n = fbm(world_pos * 1.7);
				c *= 0.85 + 0.3 * n;
				ROUGHNESS = 0.85;
			}
		}
		c = mix(vec3(lum), c, 0.88);
		SPECULAR = (layer > 8.5 && layer < 9.5) ? 0.12 : 0.28;
	} else if (style == 6) {
		// watercolor: pale, washed pigment with uneven density
		float w = fbm(world_pos * 0.9);
		c = mix(vec3(lum), c, 0.85);
		c = mix(c, vec3(1.0), 0.22) * (0.9 + 0.2 * w);
	} else if (style == 7) {
		// colour comic: punchy flat colours in a few steps
		c = mix(vec3(lum), c, 1.1);
	} else if (style == 3) {
		// retro: few colours, hard dither-like quantisation
		c = floor(c * 8.0 + 0.5) / 8.0;
	} else if (style == 4) {
		// noir: high-contrast grey ink
		float l = clamp((lum - 0.25) * 1.5 + 0.28, 0.0, 1.0);
		c = vec3(l);
	} else if (style == 5) {
		// neon: dark bodies with glowing rims
		vec3 vn = normalize(NORMAL);
		float rim = pow(1.0 - clamp(dot(vn, normalize(VIEW)), 0.0, 1.0), 2.6);
		vec3 rc = mix(vec3(1.0, 0.1, 0.75), vec3(0.1, 0.9, 1.0), 0.5 + 0.5 * sin(world_pos.x * 0.06 + world_pos.z * 0.045 + world_pos.y * 0.1));
		c = mix(vec3(lum), c, 1.4) * 0.22;
		if (terrain_noise > 0.0) {
			// the ground is dark with a glowing grid, like the floor of a synthwave sunset
			vec2 gr = abs(fract(world_pos.xz * 0.2) - 0.5);
			float line = 1.0 - smoothstep(0.0, 0.035, min(gr.x, gr.y));
			emis += rc * (rim * 0.25 + line * 1.5);
			c *= 0.5;
		} else {
			emis += rc * rim * 1.9 + c * 0.25;
		}
	}
	ALBEDO = c;
	EMISSION = emis;
}

void light() {
	int style = int(gfx_style + 0.5);
	float ndl = dot(NORMAL, LIGHT);
	float nl = clamp(ndl * ATTENUATION, 0.0, 1.0);
	if (style == 1 && vlayer > 8.5 && vlayer < 9.5) {
		// photo foliage: wrapped diffuse (leaves are thin) plus light shining through when the sun is behind them
		float wrap = clamp((ndl + 0.4) / 1.4, 0.0, 1.0);
		float trans = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 2.0) * (1.0 - clamp(ndl, 0.0, 1.0));
		DIFFUSE_LIGHT += LIGHT_COLOR * (wrap * 0.3183 + trans * 0.3) * ATTENUATION;
	} else if (style == 1) {
		// photo: plain Lambert + Blinn-Phong sheen, soft and physically plausible
		DIFFUSE_LIGHT += LIGHT_COLOR * nl * 0.3183;
		float nh = clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0);
		float shin = mix(6.0, 140.0, pow(1.0 - ROUGHNESS, 1.5));
		SPECULAR_LIGHT += LIGHT_COLOR * pow(nh, shin) * (shin + 8.0) * 0.0398 * 0.06 * clamp(ndl, 0.0, 1.0) * ATTENUATION;
	} else if (style == 6) {
		// watercolor: wrapped light, no hard terminator
		float wrap = clamp((ndl + 0.45) / 1.45, 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * wrap * wrap * ATTENUATION * 0.3183 * 1.05;
	} else {
		float s = step0;
		if (style == 3) {
			s = nl > 0.5 ? 1.0 : (nl > 0.1 ? 0.6 : 0.35);
		} else if (style == 7) {
			s = nl > 0.55 ? 1.0 : (nl > 0.2 ? 0.64 : 0.36);
		} else if (style == 4) {
			s = nl > 0.55 ? 1.0 : (nl > 0.12 ? 0.5 : 0.12);
		} else if (style == 5) {
			s = nl > 0.3 ? 0.7 : 0.25;
		} else if (nl > 0.72) {
			s = step3;
		} else if (nl > 0.42) {
			s = step2;
		} else if (nl > 0.12) {
			s = step1;
		}
		DIFFUSE_LIGHT += LIGHT_COLOR * s * 0.3183;
	}
}
