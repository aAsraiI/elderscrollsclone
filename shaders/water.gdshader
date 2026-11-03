// The sea, lakes and rivers. Clear near the shore and dark where deep (read from the depth of the
// ground behind it), small ripples moving across it, the sky in it at a low angle. Rain roughens it.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.22, 0.38, 0.36);
uniform vec3 deep : source_color = vec3(0.05, 0.13, 0.2);
// Meters of water before it looks fully deep
uniform float depth_range = 4.5;
uniform float wetness = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 wpos;

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

float waves(vec2 p, float t) {
	return noise(p * 0.55 + vec2(t * 0.35, t * 0.2)) * 0.6 + noise(p * 1.7 - vec2(t * 0.5, -t * 0.3)) * 0.3 + noise(p * 4.1 + t) * 0.1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float e = 0.15;
	float h0 = waves(wpos.xz, t);
	float hx = waves(wpos.xz + vec2(e, 0.0), t);
	float hz = waves(wpos.xz + vec2(0.0, e), t);
	float strength = 0.35 + wetness * 0.4;
	vec3 n = normalize(vec3((h0 - hx) * strength / e * 0.1, 1.0, (h0 - hz) * strength / e * 0.1));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// how much water lies between this surface and the ground behind it
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	behind.xyz /= behind.w;
	float thick = max(VERTEX.z - behind.z, 0.0);
	float d = clamp(thick / depth_range, 0.0, 1.0);
	ALBEDO = mix(shallow, deep, d);
	ALPHA = clamp(0.35 + d * 0.6, 0.0, 0.93) * smoothstep(0.0, 0.35, thick);
	ROUGHNESS = 0.06 + wetness * 0.1;
	METALLIC = 0.1;
	SPECULAR = 0.6;
}
