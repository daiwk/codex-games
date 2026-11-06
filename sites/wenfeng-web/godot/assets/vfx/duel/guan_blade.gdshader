shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform bool vertical_tear = false;
uniform bool ground_wake = false;
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

void fragment() {
	vec3 ink = vec3(0.10, 0.25, 0.22);
	vec3 jade = vec3(0.31, 0.82, 0.72);
	vec3 pale = vec3(0.83, 1.0, 0.96);
	if (ground_wake) {
		float t = clamp(effect_age, 0.0, 1.0);
		float cloud = grain(vec2(UV.x * 8.0 - t * 3.0, UV.y * 5.0 + UV.x * 3.0));
		float outer = pow(max(0.0, sin(UV.x * 3.141593) * sin(UV.y * 3.141593)), 0.8);
		ALBEDO = mix(vec3(0.27, 0.33, 0.29), vec3(0.66, 0.81, 0.73), cloud);
		ALPHA = smoothstep(0.0, 0.15, t) * pow(1.0 - t, 1.2) * outer * cloud * 0.45;
	} else if (vertical_tear) {
		float age = clamp(effect_age, 0.0, 1.0);
		float edge = smoothstep(0.0, 0.016, UV.x);
		float height = smoothstep(0.0, 0.09, UV.y) * (1.0 - smoothstep(0.73, 1.0, UV.y));
		float flow = UV.y * 16.0 + UV.x * 5.0 + pow(UV.x, 1.8) * 6.0;
		float cloud = grain(vec2(UV.x * 5.6 - age * 5.0, flow));
		float filaments = pow(grain(vec2(UV.x * 2.6 - age * 3.1, flow * 2.4)), 2.2);
		float threads = exp(-pow((fract(flow * 0.71 + cloud * 0.23) - 0.5) * 9.0, 2.0));
		float mist = pow(1.0 - UV.x, 0.79) * (cloud * 0.43 + filaments * 0.56 + threads * 0.17);
		float seam = exp(-pow((UV.x - 0.030) * 34.0, 2.0)) * (0.82 + cloud * 0.18);
		float flare = exp(-pow((UV.y - 0.23 + UV.x * 0.19) * 8.0, 2.0)) * filaments;
		float life = smoothstep(0.0, 0.10, age) * pow(1.0 - age, 1.48);
		ALBEDO = mix(mix(ink, jade, 0.42 + cloud * 0.58), pale, clamp(seam + flare * 0.8, 0.0, 1.0));
		EMISSION = pale * (seam * 0.46 + flare * 0.20) * life;
		ALPHA = edge * height * clamp(mist + seam + flare * 0.43, 0.0, 1.0) * life;
	} else {
		float edge = exp(-pow((UV.x - 0.91) * 19.0, 2.0));
		float body = smoothstep(0.03, 0.72, UV.x) * (1.0 - smoothstep(0.92, 1.0, UV.x));
		float mist = grain(vec2(UV.y * 10.0 + UV.x * 1.7, UV.x * 6.0));
		ALBEDO = mix(mix(ink, jade, COLOR.r), pale, edge * mix(0.45, 0.94, COLOR.r));
		EMISSION = pale * edge * COLOR.a * 0.38;
		ALPHA = COLOR.a * min(1.0, body * (0.27 + mist * 0.50) + edge * 0.54);
	}
}
