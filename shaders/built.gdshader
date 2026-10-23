// What everything built is painted with (StaticBatch's merged boxes and POIBuilder's materials):
// the box's colour picks the surface. Grey becomes stone blocks with dark mortar, brown becomes wood
// with grain and plank seams, the rest (cloth, plaster, metal) gets a worn, mottled look. Everything
// gets grime and a little colour variation, projected from the three axes so it needs no UVs.
// The look is Morrowind-like: muted, earthy, a bit dirty, not photo-real.
shader_type spatial;
render_mode diffuse_burley;

uniform bool use_vertex_color = true;
uniform vec3 base_color : source_color = vec3(0.5);
uniform float detail : hint_range(0.0, 1.0) = 1.0;
uniform float wetness = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

// A hash without sin(): world positions run to thousands of meters, where sin() loses precision
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

// Stone blocks on a face: u runs along the wall, v up it
float blocks(vec2 uv) {
	vec2 b = uv / vec2(1.1, 0.5);
	b.x += mod(floor(b.y), 2.0) * 0.5;
	vec2 f = fract(b);
	float edge = min(min(f.x, 1.0 - f.x) * 1.1, min(f.y, 1.0 - f.y) * 0.5);
	return smoothstep(0.0, 0.035, edge);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// vertex colours come in sRGB (like StandardMaterial3D with vertex_color_is_srgb)
	vec3 srgb = use_vertex_color ? COLOR.rgb : pow(base_color, vec3(1.0 / 2.2));
	vec3 c = use_vertex_color ? mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, COLOR.rgb)) : base_color;
	vec3 hsv = rgb2hsv(srgb);  // the surface is picked by the colour as you chose it
	vec3 n = abs(wnrm);
	// The face's own 2D coordinates (pick the axis the face looks along)
	vec2 uv = n.y > 0.6 ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
	float grime = fbm(wpos * 1.3);
	float fine = noise(wpos * 9.0);
	float k = 1.0;
	float rough = 0.92;
	bool stone = hsv.y < 0.16 && hsv.z > 0.18;
	bool wood = !stone && hsv.x > 0.03 && hsv.x < 0.13 && hsv.y > 0.25 && hsv.z < 0.62;
	if (stone) {
		float bl = blocks(uv);
		float per_block = hash(floor(vec3(uv / vec2(1.1, 0.5) + vec2(mod(floor(uv.y / 0.5), 2.0) * 0.5, 0.0), 0.0)));
		k = mix(0.55, 1.0, bl) * (0.88 + per_block * 0.2) * (0.85 + fine * 0.2);
		if (n.y > 0.6) {
			k = (0.82 + grime * 0.3) * (0.9 + fine * 0.15);  // floors and tops: flagstone mottling
		}
	} else if (wood) {
		vec2 g = n.y > 0.6 ? wpos.xz : uv;
		float grain = noise(vec3(g.x * 1.5, g.y * 22.0, 0.0)) * 0.6 + noise(vec3(g.x * 0.4, g.y * 60.0, 3.0)) * 0.4;
		float plank = 1.0 - smoothstep(0.9, 0.97, abs(fract(g.y / 0.24) - 0.5) * 2.0);  // 0 at the seams
		k = (0.78 + grain * 0.35) * mix(0.65, 1.0, plank);
		rough = 0.85;
	} else {
		k = 0.82 + grime * 0.3 + fine * 0.06;
		rough = 0.9 - hsv.z * 0.2;
	}
	// Grime collects low down and in the hollows; a little colour drift breaks up flat boxes
	k *= mix(1.0, 0.8 + grime * 0.25, detail);
	vec3 drift = vec3(1.0) + (vec3(noise(wpos * 0.15), noise(wpos * 0.15 + 7.0), noise(wpos * 0.15 + 13.0)) - 0.5) * 0.08;
	vec3 col = c * mix(1.0, k, detail) * mix(vec3(1.0), drift, detail);
	col *= 1.0 - wetness * 0.2;
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.35, wetness);
	SPECULAR = 0.3;
}
