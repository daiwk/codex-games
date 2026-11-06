shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform bool vertical_tear = false;
uniform bool ground_wake = false;
uniform bool ground_crease = false;
uniform float effect_age = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1, 0)), f.x),
		mix(hash21(cell + vec2(0, 1)), hash21(cell + vec2(1)), f.x), f.y);
}

float ridge(float coord, float center, float width) {
	float d = (coord - center) * width;
	return exp(-d * d);
}

void vertex() {
	if (vertical_tear) {
		// The lip follows the cut plane. Only the distant fabric billows.
		float flutter = sin(UV.x * 5.2 + UV.y * 9.1 - effect_age * 8.5);
		VERTEX.x += flutter * UV.x * UV.x * 0.12;
	}
}

void fragment() {
	vec3 ink = vec3(0.10, 0.25, 0.22);
	vec3 jade = vec3(0.31, 0.82, 0.72);
	vec3 pale = vec3(0.83, 1.0, 0.96);
	if (ground_crease) {
		float t = clamp(effect_age, 0.0, 1.0);
		float ribbon = ridge(UV.x, 0.5 + sin(UV.y * 18.0) * 0.041, 11.4);
		float core = ridge(UV.x, 0.5 + sin(UV.y * 18.0) * 0.041, 34.0);
		float contact = smoothstep(0.0, 0.05, UV.y) * (1.0 - smoothstep(0.94, 1.0, UV.y));
		float fade = 1.0 - smoothstep(0.17, 0.63, t);
		ALBEDO = mix(jade, pale, core);
		EMISSION = pale * core * fade * 0.58;
		ALPHA = (ribbon * 0.52 + core * 0.34) * contact * fade;
	} else if (ground_wake) {
		float t = clamp(effect_age, 0.0, 1.0);
		float cloud = grain(vec2(UV.x * 9.0 - t * 3.0, UV.y * 6.0 + UV.x * 3.0));
		float wisps = grain(vec2(UV.x * 17.0 + t * 2.0, UV.y * 8.0 - t * 3.1));
		float outer = pow(max(0.0, sin(UV.x * 3.141593) * sin(UV.y * 3.141593)), 0.68);
		float ground_streak = ridge(UV.x, 0.50 + (cloud - 0.5) * 0.08, 12.0);
		float shove = ridge(UV.y, 0.83, 5.2) * ground_streak;
		ALBEDO = mix(vec3(0.20, 0.35, 0.30), vec3(0.62, 0.95, 0.83), cloud * 0.64 + shove * 0.36);
		ALPHA = smoothstep(0.0, 0.09, t) * (1.0 - smoothstep(0.42, 1.0, t))
			* outer * (cloud * 0.32 + wisps * 0.18 + shove * 0.26);
	} else if (vertical_tear) {
		float age = clamp(effect_age, 0.0, 1.0);
		float u = UV.x;
		float v = UV.y;
		// UV.x runs from the flying lip back toward the blade. Long wind
		// lanes flow out of that low tail into the broader cyan film.
		float center = 0.27 + u * 0.09 - u * u * 0.08;
		float fan = (v - center) / mix(1.0, 0.79, u);
		fan += sin(u * 6.5 + age * 5.1) * (0.012 + u * 0.025);
		float mist = grain(vec2(u * 4.1 + age * 4.8, fan * 9.0));
		float stream = grain(vec2(u * 2.6 + age * 7.1, fan * 21.0 + mist * 0.76));
		float bands = ridge(fan, -0.09, 20.0) * 0.63;
		bands += ridge(fan, 0.12, 12.0) * 0.87;
		bands += ridge(fan, 0.34, 14.5) * 0.66;
		bands += ridge(fan, 0.55, 12.5) * 0.77;
		bands += ridge(fan, 0.73, 18.0) * 0.43;
		float filament = pow(max(0.0, stream), 3.2);
		float core = (ridge(fan, 0.117, 41.0) + ridge(fan, 0.548, 45.0)) * (0.11 + mist * 0.17);
		float energy = clamp(bands * (0.46 + 0.44 * mist) + filament * 0.30 + core, 0.0, 1.0);
		float lip_sharpen = smoothstep(0.0, 0.25, age);
		float leading = ridge(u, mix(0.063, 0.013, lip_sharpen), mix(12.0, 66.0, lip_sharpen));
		float edge_glow = exp(-u * 17.0) * 0.36;
		float floor_glow = exp(-v * 10.0) * (1.0 - u) * 0.30;
		float edge_mask = smoothstep(0.0, 0.008, u);
		float whisker = smoothstep(0.48, 0.89, stream);
		float far_mask = 1.0 - smoothstep(0.83 + whisker * 0.09, 1.0, u + (mist - 0.5) * 0.073);
		float height_mask = smoothstep(0.0, 0.029, v) * (1.0 - smoothstep(0.90, 1.0, v));
		float ignition = 0.68 + 0.32 * smoothstep(0.0, 0.10, age);
		float film_life = ignition * (1.0 - smoothstep(0.49 - u * 0.13, 0.96 - u * 0.09, age));
		float lip_life = ignition * (1.0 - smoothstep(0.66, 1.0, age));
		vec3 film = mix(vec3(0.035, 0.40, 0.36), vec3(0.21, 0.90, 0.80), 0.25 + mist * 0.60);
		vec3 streak = vec3(0.77, 1.0, 0.96);
		float light = clamp(leading + edge_glow + energy + floor_glow, 0.0, 1.0);
		ALBEDO = mix(film, streak, light);
		EMISSION = vec3(0.15, 0.86, 0.75) * (energy * 0.29 + floor_glow) * film_life
			+ streak * (leading * 0.84 + edge_glow * 0.22) * lip_life;
		float coverage = far_mask * (0.55 + mist * 0.14 + energy * 0.28);
		ALPHA = edge_mask * height_mask * clamp(coverage * film_life + leading * lip_life, 0.0, 1.0);
	} else {
		float edge = ridge(UV.x, 0.91, 19.0);
		float body = smoothstep(0.03, 0.72, UV.x) * (1.0 - smoothstep(0.92, 1.0, UV.x));
		float mist = grain(vec2(UV.y * 10.0 + UV.x * 1.7, UV.x * 6.0));
		ALBEDO = mix(mix(ink, jade, COLOR.r), pale, edge * mix(0.45, 0.94, COLOR.r));
		EMISSION = pale * edge * COLOR.a * 0.38;
		ALPHA = COLOR.a * min(1.0, body * (0.27 + mist * 0.50) + edge * 0.54);
	}
}
