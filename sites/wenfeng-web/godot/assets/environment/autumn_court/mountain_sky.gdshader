shader_type sky;

// The generated 3:1 landscape is a scenic panorama, not an equirectangular
// photograph. Set its ridge height explicitly and overlap its different ends.
uniform sampler2D mountain_panorama : source_color, filter_linear_mipmap, repeat_disable;
uniform float panorama_energy = 0.82;
uniform float horizon_v = 0.58;
uniform float overlap = 0.10;
uniform float longitude_offset = 0.0;

vec3 continuous_panorama(float longitude, float v) {
	float u = fract(longitude);
	float keep = 1.0 - overlap;
	float source_u = overlap * 0.5 + u * keep;
	float band = overlap * 0.5 / keep;
	vec3 base = texture(mountain_panorama, vec2(source_u, v)).rgb;
	// Both sides reach exactly the same 50/50 sample of image U=.05/.95.
	// smoothstep has zero derivative at the seam and overlap boundaries, so
	// neither the colour nor its first derivative jumps during a full orbit.
	if (u < band) {
		vec3 previous = texture(mountain_panorama, vec2(source_u + keep, v)).rgb;
		return mix(previous, base, 0.5 + 0.5 * smoothstep(0.0, band, u));
	}
	if (u > 1.0 - band) {
		vec3 next = texture(mountain_panorama, vec2(source_u - keep, v)).rgb;
		return mix(next, base, 0.5 + 0.5 * smoothstep(0.0, band, 1.0 - u));
	}
	return base;
}

void sky() {
	// Looking toward the gate (-Z) samples the centre of the mountain valley.
	float longitude = atan(EYEDIR.x, -EYEDIR.z) / TAU + 0.5 + longitude_offset;
	float elevation = asin(clamp(EYEDIR.y, -1.0, 1.0));
	float v = clamp(horizon_v - elevation * (0.80 / PI), 0.02, 0.98);
	vec3 panorama = continuous_panorama(longitude, v);
	// A single zenith colour avoids pinching the non-spherical source image at
	// the pole. Its influence is confined above 63 degrees, outside combat view.
	vec3 zenith = continuous_panorama(0.5, 0.04);
	panorama = mix(panorama, zenith, smoothstep(0.89, 0.995, EYEDIR.y));
	COLOR = panorama * panorama_energy;
}
