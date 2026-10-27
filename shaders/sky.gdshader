// The world's sky (WorldClock drives the uniforms): a day gradient that warms at dawn and dusk,
// the sun's disc, drifting clouds that thicken with the weather, and at night stars, a faint
// band of the Ribbon (the galaxy) and two moons, the white Lune and the small red Ember.
shader_type sky;

uniform float day = 1.0;              // 0 night .. 1 full day
uniform float dusk = 0.0;             // 0..1 how much dawn / dusk colour there is
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_dark : hint_range(0.0, 1.0) = 0.0;   // storm clouds
uniform float time_of_world = 0.0;    // hours since the game began, for cloud drift and moon phase
uniform float moon_phase = 0.5;       // WorldClock.get_moon_phase(): 0 new, 0.5 full
uniform vec3 moon_dir = vec3(0.3, 0.6, -0.7);
uniform vec3 moon2_dir = vec3(-0.6, 0.35, -0.5);
uniform vec3 day_top : source_color = vec3(0.28, 0.42, 0.62);
uniform vec3 day_horizon : source_color = vec3(0.68, 0.72, 0.74);
uniform vec3 night_top : source_color = vec3(0.012, 0.015, 0.03);
uniform vec3 night_horizon : source_color = vec3(0.04, 0.045, 0.06);
uniform vec3 dusk_horizon : source_color = vec3(0.85, 0.42, 0.22);
uniform vec3 ground : source_color = vec3(0.12, 0.11, 0.1);
// Morrowind's own clouds for the weather and its night sky (MwSky), when they have been imported
uniform bool mw_clouds_on = false;
uniform sampler2D mw_clouds : source_color, repeat_enable, filter_linear_mipmap;
uniform bool mw_stars_on = false;
uniform sampler2D mw_stars : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D mw_nebula : source_color, repeat_enable, filter_linear_mipmap;

// A hash without sin(), which loses precision on GPUs and shows up as square blocks
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
	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p * 2.03 + vec2(1.7, 9.2);  // turned, so no grid shows
		a *= 0.5;
	}
	return v;
}

vec3 moon(vec3 dir, vec3 at, float size, vec3 tint, float phase) {
	float d = distance(dir, normalize(at));
	float disc = smoothstep(size, size * 0.85, d);
	// the lit side: a second, offset disc carves the shadow
	vec3 side = normalize(cross(normalize(at), vec3(0.0, 1.0, 0.0)));
	float shade = smoothstep(size * 0.9, size * 1.1, distance(dir, normalize(at) + side * size * phase));
	float glow = exp(-d / size * 1.6) * 0.15;
	return tint * (disc * mix(0.15, 1.0, shade) + glow);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	float h = clamp(up, 0.0, 1.0);
	// Sky gradient: day and night, warmed near the horizon toward the sun at dawn and dusk
	vec3 top = mix(night_top, day_top, day);
	vec3 hor = mix(night_horizon, day_horizon, day);
	float toward_sun = clamp(dot(normalize(vec3(dir.x, 0.0, dir.z)), normalize(vec3(LIGHT0_DIRECTION.x, 0.0, LIGHT0_DIRECTION.z) + vec3(0.0001))) * 0.5 + 0.5, 0.0, 1.0);
	hor = mix(hor, dusk_horizon, dusk * (0.35 + 0.65 * toward_sun));
	vec3 col = mix(hor, top, pow(h, 0.55));
	// Below the horizon: dark ground haze
	col = mix(col, mix(ground * (0.2 + day), hor * 0.6, 0.5), smoothstep(0.0, -0.08, up));
	// Night: stars, the Ribbon, and the moons
	float night = 1.0 - day;
	if (night > 0.01 && up > 0.0) {
		if (mw_stars_on) {
			// Morrowind's star field and nebulae, laid over the dome
			vec2 uv = dir.xz / (up + 0.35) * 0.55 + vec2(time_of_world * 0.002, 0.0);
			col += texture(mw_stars, uv).rgb * night * smoothstep(0.0, 0.2, up) * 1.4;
			col += texture(mw_nebula, uv * 0.6 + vec2(0.3, 0.1)).rgb * night * smoothstep(0.0, 0.3, up) * 0.7;
		} else {
			vec2 sp = dir.xz / (up + 0.25) * 140.0;
			float star = step(0.9975, hash(floor(sp)));
			float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + hash(floor(sp) + 3.0) * 40.0);
			col += vec3(0.9, 0.92, 1.0) * star * twinkle * night * h;
			float band = exp(-pow(dot(dir, normalize(vec3(0.4, 0.3, 0.86))) * 4.0, 2.0));
			col += vec3(0.16, 0.13, 0.2) * band * fbm(dir.xz * 6.0) * night * 0.6;
		}
		// the shadow disc slides off as the moon waxes (0 new, 0.5 full) and back on the other side
		float phase = (moon_phase < 0.5 ? 1.0 : -1.0) * 2.2 * min(moon_phase, 1.0 - moon_phase) * 2.0;
		col += moon(dir, moon_dir, 0.035, vec3(0.92, 0.9, 0.84), phase) * night;
		col += moon(dir, moon2_dir, 0.018, vec3(0.9, 0.35, 0.25), -phase * 0.7) * night;
	}
	// The sun
	if (LIGHT0_ENABLED) {
		float sd = distance(dir, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * (smoothstep(0.03, 0.025, sd) * 4.0 + exp(-sd * 9.0) * 0.35 * (0.4 + dusk)) * day;
	}
	// Clouds: a drifting layer, lit by the day, dark under storms
	if (up > 0.0 && mw_clouds_on) {
		// Morrowind's cloud picture for this weather, drifting across a dome, lit by the time of day
		vec2 uv = dir.xz / (up + 0.18) * 0.35 + vec2(time_of_world * 0.012, time_of_world * 0.005);
		vec3 tex = texture(mw_clouds, uv).rgb;
		vec3 lit = mix(vec3(0.06, 0.065, 0.08), mix(vec3(1.0), dusk_horizon * 1.2, dusk * 0.55), day);
		float amount = smoothstep(0.0, 0.2, up) * clamp(0.55 + cloud_cover * 0.6, 0.0, 1.0);
		col = mix(col, tex * lit * mix(1.0, 0.45, cloud_dark), amount);
	} else if (up > 0.0) {
		vec2 cp = dir.xz / (up + 0.12) * 1.6 + vec2(time_of_world * 0.05, time_of_world * 0.02);
		float c = fbm(cp);
		float cover = smoothstep(1.0 - cloud_cover - 0.15, 1.0 - cloud_cover + 0.25, c);
		vec3 lit = mix(vec3(0.05, 0.055, 0.07), mix(vec3(0.85, 0.83, 0.8), dusk_horizon * 1.1, dusk * 0.6), day);
		lit = mix(lit, lit * 0.35, cloud_dark);
		col = mix(col, lit * (0.75 + 0.25 * c), cover * smoothstep(0.0, 0.15, up));
	}
	COLOR = col;
}
