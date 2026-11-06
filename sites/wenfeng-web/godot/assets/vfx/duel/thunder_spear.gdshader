shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float halo = pow(max(0.0, 1.0 - across), 2.4);
	float core = 1.0 - smoothstep(0.045, 0.20, across);
	ALBEDO = mix(COLOR.rgb, vec3(1.0, 0.95, 0.81), core * UV.y);
	ALPHA = COLOR.a * max(halo * 0.70, core * UV.y);
}
