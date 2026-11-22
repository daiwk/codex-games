extends RefCounted

const COAST_PROFILE := """
float coast_distance(vec2 p) {
	float east = p.x - 36.1 - 1.05 * sin(p.y * 0.14) - 0.62 * cos(p.y * 0.042);
	float north = -p.y - 45.6 + 1.15 * sin(p.x * 0.10) + 0.75 * sin(p.x * 0.23);
	return max(east, north);
}
"""

const HILL_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

varying vec3 hillside;
varying vec3 hillside_normal;

float ridge_noise(vec2 p) {
	vec2 q = floor(p);
	vec2 b = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	vec2 turn = vec2(61.7, 151.9);
	return mix(
		mix(fract(sin(dot(q, turn)) * 15731.33), fract(sin(dot(q + vec2(1, 0), turn)) * 15731.33), b.x),
		mix(fract(sin(dot(q + vec2(0, 1), turn)) * 15731.33), fract(sin(dot(q + vec2(1, 1), turn)) * 15731.33), b.x),
		b.y
	);
}

void vertex() {
	hillside = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hillside_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	float steep = 1.0 - abs(normalize(hillside_normal).y);
	float broad = ridge_noise(hillside.xz * 0.41);
	float fissure = sin(hillside.y * 5.6 + hillside.x * 0.8 + broad * 2.9);
	float fine = ridge_noise(vec2(hillside.x + hillside.z * 0.31, hillside.y) * 4.1);
	float rockiness = smoothstep(0.24, 0.50, steep + 0.17 * broad);
	vec3 green = mix(vec3(0.249, 0.284, 0.156), vec3(0.376, 0.387, 0.232), broad);
	vec3 stone = mix(vec3(0.373, 0.326, 0.282), vec3(0.50, 0.451, 0.379), broad);
	stone *= 0.93 + 0.06 * fissure + fine * 0.12;
	ALBEDO = mix(green, stone, rockiness);
	ROUGHNESS = 0.97;
}
"""

const SEA_SHADER := """
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

varying vec2 sea_at;
""" + COAST_PROFILE + """
void vertex() {
	sea_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float swell = sin(sea_at.x * 0.33 + sea_at.y * 0.30 + TIME * 1.45);
	VERTEX.y += 0.045 * swell + 0.031 * sin(sea_at.y * 0.53 - sea_at.x * 0.19 - TIME * 1.14);
}

void fragment() {
	float edge = coast_distance(sea_at);
	if (edge < -3.0) {
		discard;
	}
	float swash = sin(edge * 3.55 - TIME * 2.3 + 0.52 * sin(sea_at.y * 1.2 + sea_at.x * 0.22));
	float near_foam = (1.0 - smoothstep(1.3, 4.5, edge)) * smoothstep(0.70, 0.99, swash);
	float ripple = sin(sea_at.x * 0.89 + sea_at.y * 1.53 - TIME * 1.65)
		* cos(sea_at.y * 0.87 - sea_at.x * 0.37 + TIME * 1.21);
	float water_grain = 1.0 - smoothstep(0.36, 1.12, max(fwidth(sea_at.x), fwidth(sea_at.y)));
	float deep = smoothstep(2.0, 22.0, edge);
	vec3 water = mix(vec3(0.101, 0.335, 0.353), vec3(0.058, 0.201, 0.276), deep);
	water *= 1.0 + 0.08 * ripple * water_grain;
	float foam = max(near_foam * 0.65, smoothstep(0.91, 0.99, ripple) * 0.12 * water_grain);
	ALBEDO = mix(water, vec3(0.73, 0.79, 0.71), foam);
	ROUGHNESS = 0.38 + 0.44 * foam;
	SPECULAR = 0.47;
}
"""


static func hill(center: Vector2, size: Vector2, height: float, phase: float) -> StaticBody3D:
	var hill_body := StaticBody3D.new()
	hill_body.name = "RockRidge"
	hill_body.collision_layer = 1
	hill_body.collision_mask = 0
	hill_body.position = Vector3(center.x, -0.018, center.y)
	var ridge := _hill_mesh(size, height, phase)
	var visual := MeshInstance3D.new()
	visual.mesh = ridge
	visual.material_override = _shader_material(HILL_SHADER)
	hill_body.add_child(visual)

	var terrain := CollisionShape3D.new()
	terrain.shape = ridge.create_trimesh_shape()
	hill_body.add_child(terrain)

	# The foothill stops horizontal-only ground vehicles before contact can lift them.
	var base := CollisionShape3D.new()
	var base_box := BoxShape3D.new()
	base_box.size = Vector3(size.x, 0.38, size.y)
	base.shape = base_box
	base.position.y = 0.17
	hill_body.add_child(base)
	return hill_body


static func sea() -> MeshInstance3D:
	var surface := MeshInstance3D.new()
	surface.name = "TidalWater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(355.0, 330.0)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	surface.mesh = plane
	surface.material_override = _shader_material(SEA_SHADER)
	surface.position = Vector3(25.0, -0.25, -29.0)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return surface


static func _hill_mesh(size: Vector2, height: float, phase: float) -> ArrayMesh:
	const STEPS := 22
	var vertices := PackedVector3Array()
	for z in range(STEPS + 1):
		for x in range(STEPS + 1):
			var p := Vector2(float(x) / STEPS * 2.0 - 1.0, float(z) / STEPS * 2.0 - 1.0)
			var margin := Vector2.ONE - Vector2(pow(absf(p.x), 2.25), pow(absf(p.y), 2.65))
			var silhouette := pow(maxf(0.0, margin.x * margin.y), 1.24)
			var crest := 0.86 + 0.09 * sin(p.y * 4.1 + p.x * 5.7 + phase)
			var erosion := 0.047 * sin(p.x * 17.0 - p.y * 8.1 + phase) + 0.035 * sin(p.y * 13.7 + p.x * 8.8)
			vertices.append(Vector3(p.x * size.x * 0.5, height * silhouette * (crest + erosion), p.y * size.y * 0.5))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in STEPS:
		for x in STEPS:
			var a := z * (STEPS + 1) + x
			var b := a + 1
			var c := a + STEPS + 1
			var d := c + 1
			for index in [a, b, d, a, d, c]:
				tool.add_vertex(vertices[index])
	tool.generate_normals()
	tool.index()
	return tool.commit()


static func _shader_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
