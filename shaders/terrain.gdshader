// The ground. Each vertex carries its biome's colour (blended across borders by the terrain
// builder); here that colour becomes a surface: on flat ground grass or sand or ash with patches of
// bare earth and fine speckle, on slopes rock with horizontal strata, and the two blend by slope.
// Seasons tint green ground, snow settles on flat ground, rain darkens and wets everything.
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 season_tint = vec3(1.0);
uniform float snow = 0.0;
uniform float wetness = 0.0;
uniform vec3 rock_color : source_color = vec3(0.36, 0.34, 0.31);
uniform float detail : hint_range(0.0, 1.0) = 1.0;
uniform float mute : hint_range(0.0, 1.0) = 0.4;

// Morrowind's ground textures (MwSurfaces, project shader globals), when imported: their detail and shading on
// the biome's own colour
global uniform bool mw_surfaces;
global uniform sampler2D mw_grass : source_color, repeat_enable, filter_linear_mipmap;
global uniform sampler2D mw_earth : source_color, repeat_enable, filter_linear_mipmap;
global uniform sampler2D mw_rock : source_color, repeat_enable, filter_linear_mipmap;

// A texture's look without its overall brightness (so it shades a colour rather than replacing it)
vec3 mw_detail(sampler2D t, vec2 uv) {
	// against the texture's own average (its smallest mipmap): light and dark, and a little of its hue
	vec3 mean = max(textureLod(t, vec2(0.5), 16.0).rgb, vec3(0.03));
	vec3 d = texture(t, uv).rgb / mean;
	return clamp(mix(vec3(dot(d, vec3(0.3333))), d, 0.3), 0.25, 2.0);
}

varying vec3 world_n;
varying vec3 wpos;

// A hash without sin(): world positions run to thousands of meters, where sin() loses precision
float hash(vec2 p) {
	p = 50.0 * fract(p * 0.3183099 + vec2(0.71, 0.113));
	return fract(p.x * p.y * (p.x + p.y));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p = p * 2.07 + 3.1;
		a *= 0.5;
	}
	return v;
}

// The same texture looked up twice, turned and scaled against itself, and blended by a slow noise: the
// ground never shows one tile repeating in rows
vec3 mw_untiled(sampler2D t, vec2 p) {
	vec2 q = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799)) * p * 0.73 + vec2(0.31, 0.57);
	float w = smoothstep(0.3, 0.7, fbm(p * 0.09 + 5.0));
	return mix(mw_detail(t, p), mw_detail(t, q), w);
}

void vertex() {
	world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// the biome colours are chosen in sRGB: convert, so the ground is as dark and earthy as picked
	vec3 c = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, COLOR.rgb));
	// The art direction (Morrowind-like): muted, earthy, olive rather than bright green
	c = mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))), mute) * vec3(1.0, 0.95, 0.82) * 0.92;
	vec3 nrm = normalize(world_n);
	float green = clamp((c.g - max(c.r, c.b)) * 6.0, 0.0, 1.0);
	c = mix(c, c * season_tint, green);
	// Flat ground: big soft patches, bare earth showing through, fine speckle up close
	float big = fbm(wpos.xz * 0.045);
	float mid = fbm(wpos.xz * 0.35);
	float fine = noise(wpos.xz * 4.0);
	vec3 earth = mix(c, vec3(0.3, 0.24, 0.17), 0.55);
	float bare = smoothstep(0.58, 0.72, mid) * (0.4 + green * 0.6);
	vec3 flat_col = c * (0.82 + big * 0.36) * (0.92 + fine * 0.16);
	flat_col = mix(flat_col, earth * (0.85 + fine * 0.2), bare * detail);
	if (mw_surfaces) {
		vec3 g = mw_untiled(mw_grass, wpos.xz * 0.22);
		vec3 e = mw_untiled(mw_earth, wpos.xz * 0.22);
		flat_col *= mix(g, e, bare * detail);
	}
	// Slopes: the land's rock, tinted toward the biome, in layers
	vec3 rock = mix(rock_color, c * 0.7, 0.3);
	float strata = noise(vec2(wpos.y * 1.6 + fbm(wpos.xz * 0.08) * 3.0, 0.5));
	rock *= 0.78 + strata * 0.3 + noise(vec2(wpos.x + wpos.z, wpos.y) * 3.0) * 0.08;
	if (mw_surfaces) {
		vec2 ruv = nrm.y > 0.6 ? wpos.xz : (abs(nrm.x) > abs(nrm.z) ? wpos.zy : wpos.xy);
		rock *= mw_untiled(mw_rock, ruv * 0.18);
	}
	float slope = 1.0 - smoothstep(0.62, 0.8, nrm.y + (mid - 0.5) * 0.12);
	vec3 col = mix(flat_col, rock, slope * detail);
	// Snow on flat, upward faces
	float up = smoothstep(0.75, 0.92, nrm.y);
	col = mix(col, vec3(0.9, 0.92, 0.97), snow * up * clamp(green + 0.25, 0.0, 1.0));
	col *= 1.0 - wetness * 0.18;
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.95, 0.85, slope), 0.4, wetness);
	SPECULAR = 0.25 + wetness * 0.35;
}
