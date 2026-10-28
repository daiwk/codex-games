extends RefCounted

# Kenney Particle Pack (CC0). Every layer is a single batched mesh. Time comes
# from the pausable owner, never TIME, so pausing freezes smoke and sparks too.
const SMOKE = preload("res://assets/vfx/kenney/smoke_07.png")
const SPARK = preload("res://assets/vfx/kenney/trace_06.png")
const GLOW = preload("res://assets/vfx/kenney/star_05.png")
const TRACE = preload("res://assets/vfx/kenney/trace_02.png")
const SLASH = preload("res://assets/vfx/kenney/slash_02.png")
const SMOKE_SHAPES = ["slam_dust", "roar_dust", "rpg_dust", "rpg_wake_dust", "tex_step_dust", "tex_pressure", "tex_cut_mist", "tex_contact_dust", "tex_tiger_pressure", "tex_serpent_pressure", "tex_brute_pressure"]
const SPARK_SHAPES = ["slam_sparks", "roar_sparks", "rpg_embers", "rpg_impact_sparks", "tex_cast_sparks"]
const GATHER_SHAPES = ["rpg_gather", "tex_gather", "tex_dragon_prepare", "tex_tiger_prepare", "tex_crescent_prepare", "tex_serpent_prepare", "tex_halberd_prepare", "tex_brute_prepare"]
const GLOW_SHAPES = ["rpg_impact_flash", "tex_focus", "tex_release"]
const BLADE_SHAPES = ["tex_blade", "tex_lance", "tex_contact_cut", "tex_dragon_high", "tex_dragon_low", "tex_tiger_couch", "tex_tiger_breaker", "tex_crescent_low", "tex_crescent_draw", "tex_crescent_diagonal", "tex_crescent_revolve", "tex_serpent_counter", "tex_serpent_anchor", "tex_halberd_rise", "tex_halberd_orbit", "tex_halberd_fall", "tex_brute_close", "tex_brute_rebuke", "tex_brute_execution", "tex_serpent_roar"]
const THRUST_SHAPES = ["tex_lance", "tex_dragon_high", "tex_dragon_low", "tex_tiger_couch", "tex_tiger_breaker", "tex_serpent_counter", "tex_serpent_anchor"]
const THRUST_LAYOUT = {
	"tex_lance": Vector3(1.06, 0.17, 3.05), "tex_dragon_high": Vector3(1.26, 0.095, 3.05),
	"tex_dragon_low": Vector3(0.72, 0.085, 3.05), "tex_tiger_couch": Vector3(0.78, 0.24, 3.05),
	"tex_tiger_breaker": Vector3(0.98, 0.30, 3.05), "tex_serpent_counter": Vector3(1.08, 0.16, 3.05),
	"tex_serpent_anchor": Vector3(1.10, 0.12, 3.05),
}
const ARC_LAYOUT = {
	"tex_blade": {"r": 2.60, "y": 1.06, "a": -1.32, "b": 1.32, "w": 0.34, "tilt": 0.075},
	"tex_crescent_low": {"r": 2.60, "y": 0.48, "a": -1.70, "b": 1.15, "w": 0.32, "tilt": 0.02},
	"tex_crescent_draw": {"r": 2.60, "y": 0.96, "a": 1.40, "b": -1.35, "w": 0.30, "tilt": -0.12},
	"tex_crescent_diagonal": {"r": 2.60, "y": 1.18, "a": 1.28, "b": -1.28, "w": 0.36, "tilt": 0.34},
	"tex_crescent_revolve": {"r": 2.60, "y": 0.92, "a": -0.20, "b": TAU - 0.20, "w": 0.28, "tilt": 0.04},
	"tex_halberd_rise": {"r": 2.10, "y": 0.45, "a": -0.15, "b": 1.08, "w": 0.30, "vertical": true},
	"tex_halberd_orbit": {"r": 2.60, "y": 1.12, "a": -2.10, "b": 2.20, "w": 0.25, "tilt": -0.05},
	"tex_halberd_fall": {"r": 1.25, "y": 0.45, "a": 0.52, "b": -0.16, "w": 0.24, "vertical": true},
	"tex_brute_close": {"r": 2.15, "y": 1.08, "a": 1.08, "b": -1.10, "w": 0.42, "tilt": 0.36},
	"tex_brute_rebuke": {"r": 2.15, "y": 1.12, "a": -0.95, "b": 1.08, "w": 0.32, "tilt": -0.30},
	"tex_brute_execution": {"r": 1.25, "y": 0.46, "a": 0.52, "b": -0.18, "w": 0.30, "vertical": true},
}


static func supports(shape: String) -> bool:
	return shape in SMOKE_SHAPES or shape in SPARK_SHAPES or shape in GATHER_SHAPES or shape in GLOW_SHAPES or shape in BLADE_SHAPES


static func is_smoke(shape: String) -> bool:
	return shape in SMOKE_SHAPES


static func ground_smoke(shape: String) -> bool:
	return shape in ["slam_dust", "roar_dust", "rpg_dust", "rpg_wake_dust", "tex_step_dust"]


static func is_thrust(shape: String) -> bool:
	return shape in THRUST_SHAPES


static func preparation_anchor(shape: String) -> Vector3:
	return {"tex_dragon_prepare": Vector3(0, 1.16, 1.12), "tex_tiger_prepare": Vector3(0, 0.80, 1.65),
		"tex_crescent_prepare": Vector3(0.75, 0.40, 0.90), "tex_serpent_prepare": Vector3(0, 1.10, 0.65),
		"tex_halberd_prepare": Vector3(0, 1.72, 0.42), "tex_brute_prepare": Vector3(0, 1.44, 0.28)}.get(shape, Vector3(0, 1.15, 0))


static func stroke_height(shape: String) -> float:
	if THRUST_LAYOUT.has(shape):
		return THRUST_LAYOUT[shape].x
	return float(ARC_LAYOUT.get(shape, {}).get("y", 1.06))


static func stroke_radius(shape: String) -> float:
	return float(ARC_LAYOUT.get(shape, {}).get("r", 2.60))


static func stroke_endpoint(shape: String) -> Vector3:
	if THRUST_LAYOUT.has(shape):
		var layout: Vector3 = THRUST_LAYOUT[shape]
		return Vector3(0, layout.x, layout.z)
	var layout: Dictionary = ARC_LAYOUT.get(shape, ARC_LAYOUT.tex_blade)
	return _arc_point(float(layout.b), float(layout.r), layout)


static func mode(shape: String) -> int:
	if shape in SMOKE_SHAPES:
		return 0
	if shape in SPARK_SHAPES:
		return 1
	if shape in GATHER_SHAPES:
		return 2
	if shape in BLADE_SHAPES:
		return 4
	return 3


static func texture_for(shape: String) -> Texture2D:
	if is_smoke(shape):
		return SMOKE
	if shape in SPARK_SHAPES:
		return SPARK
	if shape in GATHER_SHAPES:
		return GLOW
	if shape in BLADE_SHAPES:
		return TRACE
	return GLOW


static func shader_code(additive: bool) -> String:
	return """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, %s, fog_disabled;
uniform sampler2D sprite_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D grain_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float effect_alpha = 1.0;
uniform float effect_time = 0.0;
uniform float effect_lifetime = 1.0;
uniform int sprite_mode = 0;
uniform int ribbon_kind = 0;
uniform float ribbon_power = 0.72;
uniform float ribbon_width = 1.0;
uniform float particle_scale = 1.0;
uniform vec3 gather_anchor = vec3(0.0, 1.15, 0.0);
uniform int gather_mode = 0;
varying float particle_alpha;
void vertex() {
	float phase = UV2.y;
	float delay = sprite_mode == 3 || sprite_mode == 4 ? 0.0 : fract(phase * 0.618) * min(effect_lifetime * 0.12, 0.06);
	float age = max(effect_time - delay, 0.0);
	float t = clamp(age / max(effect_lifetime - delay, 0.01), 0.0, 1.0);
	vec3 centre = VERTEX;
	float size = UV2.x * particle_scale;
	vec2 card = UV * 2.0 - 1.0;
	float angle = phase;
	if (sprite_mode == 4) {
		// Blade masks already have world-space swept geometry and real UVs.
		POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(centre, 1.0);
		particle_alpha = pow(1.0 - t, 0.75);
	} else {
		if (sprite_mode == 0) {
			centre += NORMAL * age * 0.68 + vec3(0.0, age * 0.22, 0.0);
			size *= 0.65 + t * 1.25;
			angle += t * 0.32;
			particle_alpha = smoothstep(0.0, 0.12, t) * pow(1.0 - t, 1.25);
		} else if (sprite_mode == 1) {
			centre += NORMAL * age * (1.6 + fract(phase * 0.73) * 2.0);
			centre.y -= age * age * 1.5;
			vec3 view_direction = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
			angle = atan(view_direction.y, view_direction.x) - 1.570796;
			card *= vec2(0.90, 1.0 + t * 0.7);
			particle_alpha = (1.0 - t) * smoothstep(0.0, 0.035, age);
		} else if (sprite_mode == 2) {
			float turn = t * 1.7;
			vec3 relative = centre - gather_anchor;
			vec2 p = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * relative.xz;
			centre = gather_mode == 0 ? gather_anchor + vec3(p.x * (1.0 - t * 0.82), relative.y * (1.0 - t), p.y * (1.0 - t * 0.82)) : mix(centre, gather_anchor, t * 0.85);
			size *= 0.55 + sin(t * 3.14159) * 0.45;
			particle_alpha = sin(t * 3.14159);
		} else {
			size *= 0.72 + t * 0.50;
			particle_alpha = pow(1.0 - t, 2.0);
		}
		card = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * card;
		vec4 view_position = MODELVIEW_MATRIX * vec4(centre, 1.0);
		view_position.xy += card * size;
		POSITION = PROJECTION_MATRIX * view_position;
	}
}
void fragment() {
	if (sprite_mode == 4) {
		float t = clamp(effect_time / max(effect_lifetime, 0.01), 0.0, 1.0);
		// UV 1 is the actual blade tip, resolved from the final skeleton pose.
		// Keep the visible head there: a second UV sweep lagged behind the
		// weapon and put vertical cleaves above the camera during their hit.
		float tail = mix(0.02, 0.62, t);
		float wake = smoothstep(tail, tail + 0.18, UV.x);
		float lead = exp(-pow((UV.x - 0.98) / 0.19, 2.0));
		float across = max(0.0, sin(UV.y * 3.14159));
		// The default preserves shared RPG materials. Duel's smaller mask
		// leaves a narrow edge around the real weapon without moving its tip.
		if (ribbon_width < 0.999) {
			float transverse = abs(UV.y * 2.0 - 1.0) / max(ribbon_width, 0.05);
			across = max(0.0, cos(min(transverse, 1.0) * 1.570796));
		}
		float grain = texture(grain_texture, vec2(UV.x * 2.5 - effect_time * 0.8, UV.y * 0.65 + 0.15)).a;
		float erosion = smoothstep(t * 0.65 - 0.12, t * 0.65 + 0.14, grain + across * 0.45);
		float core = pow(across, ribbon_kind == 1 ? 11.0 : mix(10.0, 5.5, ribbon_power));
		vec3 ink = COLOR.rgb * 0.12;
		vec3 saturated = mix(COLOR.rgb * 0.62, COLOR.rgb, core);
		ALBEDO = mix(ink, saturated, smoothstep(0.05, 0.72, across));
		ALBEDO = mix(ALBEDO, vec3(0.92, 0.97, 0.95), core * lead * 0.32);
		ALPHA = pow(across, 0.55) * erosion * max(wake * 0.82, lead * mix(0.8, 1.0, ribbon_power)) * COLOR.a * effect_alpha * particle_alpha;
	} else {
		vec4 mask = texture(sprite_texture, UV);
		ALBEDO = COLOR.rgb * mask.rgb;
		ALPHA = mask.a * COLOR.a * effect_alpha * particle_alpha;
	}
}
""" % ("blend_add" if additive else "blend_mix")


static func mesh_for(shape: String, palette: Array) -> ArrayMesh:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var sizes = PackedVector2Array()
	var sprite_mode = mode(shape)
	if sprite_mode == 4:
		_blade_geometry(shape, palette, vertices, colors, normals, uvs, sizes)
	else:
		var count = 1 if sprite_mode == 3 else (12 if sprite_mode == 0 else 24)
		if shape == "tex_step_dust":
			count = 6
		elif shape in ["rpg_embers", "tex_cast_sparks"]:
			count = 12
		elif shape in ["tex_pressure", "tex_cut_mist", "tex_contact_dust"]:
			count = 8
		elif shape.ends_with("_prepare"):
			count = 12
		var radius = 3.0 if shape in ["slam_dust", "slam_sparks"] else (2.2 if shape in ["roar_dust", "roar_sparks"] else 0.8)
		for i in count:
			var phase = float(i) * 2.399963
			var direction = Vector3(sin(phase), 0.0, cos(phase))
			var centre = Vector3.ZERO
			var size = 0.075 + float(i % 4) * 0.025
			var color: Color = palette[0].lerp(palette[1], float(i % 3) * 0.24)
			if sprite_mode == 0:
				centre = direction * radius * (0.48 + float(i % 5) * 0.095) + Vector3.UP * (0.12 + float(i % 3) * 0.09)
				size = 0.32 + float(i % 4) * 0.075
				color = Color("8c7c65").lerp(Color("c2ae8d"), float(i % 3) * 0.25)
				color.a = 0.52
				if shape in ["rpg_wake_dust", "tex_step_dust"]:
					centre = Vector3(sin(phase) * 0.34, 0.12, -0.15 - float(i) * 0.12)
					size *= 0.64
				elif shape == "tex_pressure":
					centre = Vector3(sin(phase) * 0.17, 1.03 + cos(phase) * 0.10, 0.45 + float(i) * 0.34)
					direction = Vector3(sin(phase) * 0.22, 0.03, 0.9).normalized()
					size = 0.14 + float(i % 3) * 0.035
					color = palette[0].darkened(0.46)
					color.a = 0.24
				elif shape == "tex_cut_mist":
					var angle = -1.20 + float(i) * 0.33
					centre = Vector3(sin(angle) * 2.30, 1.03 + float(i % 3) * 0.045, cos(angle) * 2.30)
					direction = Vector3(cos(angle), 0.08, -sin(angle)).normalized()
					size = 0.19 + float(i % 3) * 0.045
					color = palette[0].darkened(0.50)
					color.a = 0.28
				elif shape == "tex_contact_dust":
					centre = direction * (0.06 + float(i % 4) * 0.025)
					direction = Vector3(sin(phase) * 0.36, 0.15 + float(i % 3) * 0.08, 0.75).normalized()
					size = 0.16 + float(i % 3) * 0.045
					color = Color("6a6156").lerp(Color("a28e71"), float(i % 3) * 0.18)
					color.a = 0.44
				elif shape == "tex_tiger_pressure":
					centre = Vector3(sin(phase) * 0.24, 0.76 + cos(phase) * 0.12, 0.35 + float(i % 9) * 0.33)
					direction = Vector3(sin(phase) * 0.25, 0.06, 1.0).normalized()
					size = 0.23 + float(i % 3) * 0.055
					color = palette[2].darkened(0.30)
					color.a = 0.40
				elif shape == "tex_serpent_pressure":
					centre = Vector3(-0.15 if i % 2 == 0 else 0.15, 1.04, 0.8 + float(i % 9) * 0.30)
					direction = Vector3(0, 0.03, 1)
					size = 0.13 + float(i % 3) * 0.025
					color = palette[0].darkened(0.40)
					color.a = 0.27
				elif shape == "tex_brute_pressure":
					centre = Vector3(sin(phase) * 0.50, 0.45 + float(i % 4) * 0.20, 0.55 + float(i % 4) * 0.31)
					direction = Vector3(sin(phase) * 0.4, -0.05, 0.8).normalized()
					size = 0.28 + float(i % 3) * 0.055
					color = Color("6e5840").lerp(palette[2], 0.25)
					color.a = 0.40
			elif sprite_mode == 1:
				centre = direction * radius * (0.07 + float(i % 4) * 0.11)
				direction.y = 0.30 + float(i % 5) * 0.12
				direction = direction.normalized()
				if shape == "rpg_embers" or shape == "tex_cast_sparks":
					centre += Vector3(0, 1.0, 2.0)
					direction = Vector3(sin(phase) * 0.45, 0.1 + float(i % 4) * 0.14, 0.70).normalized()
					color.a = 0.40
			elif sprite_mode == 2:
				centre = direction * (0.55 + float(i % 5) * 0.14) + Vector3.UP * (0.18 + fmod(float(i) * 0.217, 1.55))
				size = 0.025 + float(i % 3) * 0.012
				if shape == "tex_dragon_prepare":
					centre = Vector3(sin(phase) * 0.18, 1.16 + cos(phase) * 0.13, 0.4 + float(i) * 0.14)
				elif shape == "tex_tiger_prepare":
					centre = Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.14, 0.80, 0.25 + float(i) * 0.19)
					size *= 1.3
				elif shape == "tex_crescent_prepare":
					var angle = -1.1 + float(i) * 0.19
					centre = Vector3(sin(angle) * 1.45, 0.18 + float(i % 3) * 0.08, cos(angle) * 1.45)
				elif shape == "tex_serpent_prepare":
					centre = Vector3(-0.24 if i % 2 == 0 else 0.24, 0.60 + float(i / 2) * 0.18, 0.65)
				elif shape == "tex_halberd_prepare":
					centre = Vector3(sin(phase) * 0.20, 0.75 + float(i) * 0.13, 0.42)
				elif shape == "tex_brute_prepare":
					centre = Vector3(sin(phase) * 0.34, 0.08 + float(i) * 0.07, 0.25 + cos(phase) * 0.18)
					color = palette[2].lerp(palette[0], 0.30)
					size *= 1.25
			else:
				centre = Vector3.ZERO if shape == "rpg_impact_flash" else Vector3(0, 1.1, 0.48)
				size = 0.24 if shape == "rpg_impact_flash" else (0.24 if shape == "tex_focus" else 0.35)
				color = palette[1]
				color.a = 0.85 if shape == "rpg_impact_flash" else 0.62
			_append_card(centre, direction, color, Vector2(size, phase), vertices, colors, normals, uvs, sizes)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = sizes
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Quad offsets and ballistic motion happen in the vertex shader.
	mesh.custom_aabb = AABB(Vector3(-4.5, -0.5, -4.5), Vector3(9.0, 5.0, 9.0))
	return mesh


static func _append_card(centre: Vector3, normal: Vector3, color: Color, size: Vector2,
		vertices: PackedVector3Array, colors: PackedColorArray, normals: PackedVector3Array,
		uvs: PackedVector2Array, sizes: PackedVector2Array) -> void:
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		vertices.append(centre)
		colors.append(color)
		normals.append(normal)
		uvs.append(uv)
		sizes.append(size)


static func _blade_geometry(shape: String, palette: Array, vertices: PackedVector3Array,
		colors: PackedColorArray, normals: PackedVector3Array, uvs: PackedVector2Array, sizes: PackedVector2Array) -> void:
	var tint: Color = palette[0]
	tint.a = 0.92
	if ARC_LAYOUT.has(shape):
		var layout: Dictionary = ARC_LAYOUT[shape]
		var segments = 64 if absf(float(layout.b) - float(layout.a)) > 5.0 else 36
		for index in segments:
			var t0 = float(index) / float(segments)
			var t1 = float(index + 1) / float(segments)
			var a0 = lerpf(float(layout.a), float(layout.b), t0)
			var a1 = lerpf(float(layout.a), float(layout.b), t1)
			var w0 = 0.12 + pow(maxf(0.0, sin(PI * t0)), 0.65) * float(layout.w)
			var w1 = 0.12 + pow(maxf(0.0, sin(PI * t1)), 0.65) * float(layout.w)
			var radius: float = layout.r
			var points = [_arc_point(a0, radius - w0, layout), _arc_point(a0, radius, layout), _arc_point(a1, radius, layout), _arc_point(a1, radius - w1, layout)]
			_append_blade_quad(points, [Vector2(t0, 0), Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0)], tint, vertices, colors, normals, uvs, sizes)
	elif is_thrust(shape):
		var layout: Vector3 = THRUST_LAYOUT[shape]
		for axis in [Vector3.RIGHT, Vector3.UP]:
			for index in 16:
				var t0 = float(index) / 16.0
				var t1 = float(index + 1) / 16.0
				var p0 = Vector3(0, layout.x, lerpf(0.35, layout.z, t0))
				var p1 = Vector3(0, layout.x, lerpf(0.35, layout.z, t1))
				var w0 = axis * layout.y * (1.1 - t0 * 0.45)
				var w1 = axis * layout.y * (1.1 - t1 * 0.45)
				_append_blade_quad([p0 - w0, p0 + w0, p1 + w1, p1 - w1], [Vector2(t0, 0), Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0)], tint, vertices, colors, normals, uvs, sizes)
	elif shape == "tex_serpent_roar":
		# Four broken pressure fans, not a luminous annulus around the actor.
		for side in 4:
			var angle = float(side) * TAU / 4.0
			var direction = Vector3(sin(angle), 0, cos(angle))
			for index in 12:
				var t0 = float(index) / 12.0
				var t1 = float(index + 1) / 12.0
				var p0 = direction * lerpf(0.25, 2.35, t0) + Vector3.UP * (0.42 + sin(t0 * PI) * 0.26)
				var p1 = direction * lerpf(0.25, 2.35, t1) + Vector3.UP * (0.42 + sin(t1 * PI) * 0.26)
				var width = Vector3.UP * 0.15
				_append_blade_quad([p0 - width, p0 + width, p1 + width, p1 - width], [Vector2(t0, 0), Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0)], tint, vertices, colors, normals, uvs, sizes)
	else:
		for index in 12:
			var t0 = float(index) / 12.0
			var t1 = float(index + 1) / 12.0
			var p0 = Vector3(lerpf(-0.32, 0.32, t0), lerpf(-0.24, 0.24, t0), 0)
			var p1 = Vector3(lerpf(-0.32, 0.32, t1), lerpf(-0.24, 0.24, t1), 0)
			var across = Vector3(-0.052, 0.070, 0)
			_append_blade_quad([p0 - across, p0 + across, p1 + across, p1 - across], [Vector2(t0, 0), Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0)], tint, vertices, colors, normals, uvs, sizes)


static func _arc_point(angle: float, radius: float, layout: Dictionary) -> Vector3:
	if layout.get("vertical", false):
		return Vector3(0, float(layout.y) + sin(angle) * radius, 0.35 + cos(angle) * radius)
	var x = sin(angle) * radius
	return Vector3(x, float(layout.y) + x * float(layout.get("tilt", 0.0)), cos(angle) * radius)


static func _append_blade_quad(points: Array, corners: Array, tint: Color,
		vertices: PackedVector3Array, colors: PackedColorArray, normals: PackedVector3Array,
		uvs: PackedVector2Array, sizes: PackedVector2Array) -> void:
	for index in [0, 1, 2, 0, 2, 3]:
		vertices.append(points[index])
		colors.append(tint)
		normals.append(Vector3.UP)
		uvs.append(corners[index])
		sizes.append(Vector2.ONE)
