extends Node3D
class_name DuelArena

var materials: Dictionary = {}

func _ready() -> void:
	_build_lighting()
	_build_court()
	_build_gate()
	_build_surroundings()
	_batch_static_meshes()

func _batch_static_meshes() -> void:
	var groups: Dictionary = {}
	for child in get_children():
		if child is MeshInstance3D and child.mesh != null and child.material_override != null:
			var key = child.mesh.get_class() + str(child.mesh.get_aabb()) + str(child.material_override.get_instance_id())
			if not groups.has(key):
				groups[key] = []
			groups[key].append(child)
	for group in groups.values():
		if group.size() < 3:
			continue
		var batch = MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = group[0].mesh
		batch.instance_count = group.size()
		for i in group.size():
			batch.set_instance_transform(i, group[i].transform)
		var instance = MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = group[0].material_override
		add_child(instance)
		for old in group:
			old.queue_free()

func material(color: Color, metallic = 0.0) -> StandardMaterial3D:
	var key = str(color) + str(metallic)
	if materials.has(key):
		return materials[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.86 if metallic == 0.0 else 0.42
	mat.metallic = metallic
	materials[key] = mat
	return mat

func mesh_at(mesh: Mesh, mat: Material, at: Vector3, parent: Node = null) -> MeshInstance3D:
	if parent == null:
		parent = self
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance

func box(at: Vector3, size: Vector3, color: Color, parent: Node = null) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	return mesh_at(mesh, material(color), at, parent)

func cylinder(at: Vector3, radius: float, height: float, color: Color, sides = 24) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	return mesh_at(mesh, material(color), at)

func ring(radius: float, tube: float, at: Vector3, color: Color) -> void:
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - tube
	mesh.outer_radius = radius + tube
	mesh.rings = 48
	mesh.ring_segments = 6
	mesh_at(mesh, material(color, 0.18), at)

func _build_lighting() -> void:
	var world = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("597b88")
	sky_mat.sky_horizon_color = Color("b8c6c3")
	sky_mat.ground_horizon_color = Color("a2ada5")
	sky_mat.ground_bottom_color = Color("465457")
	sky_mat.sky_curve = 0.20
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c9cc")
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color("a4b9bb")
	env.fog_light_energy = 0.72
	env.fog_density = 0.008
	world.environment = env
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -32, 0)
	sun.light_color = Color("ffe1ae")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 24
	sun.shadow_bias = 0.035
	add_child(sun)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-23, 145, 0)
	fill.light_color = Color("8ab4cb")
	fill.light_energy = 0.22
	add_child(fill)

func _build_court() -> void:
	box(Vector3(0, -0.64, 0), Vector3(65, 0.2, 65), Color("5b6966"))
	cylinder(Vector3(0, -0.36, 0), 8.65, 0.55, Color("696f69"), 96)
	var court = cylinder(Vector3(0, -0.10, 0), 8.25, 0.2, Color("b2aa96"), 96)
	var shader = Shader.new()
	shader.code = """shader_type spatial;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world.xz; vec2 tile=floor(p*0.78);
 float n=fract(sin(dot(tile,vec2(127.1,311.7)))*43758.5453);
 vec2 grid=abs(fract(p*0.78)-0.5);
 float seam=smoothstep(0.481,0.494,max(grid.x,grid.y));
 float r=length(p); float band=1.0-smoothstep(0.025,0.05,abs(r-5.7));
 float grit=fract(sin(dot(p,vec2(1587.6,3148.2)))*4237.3)*0.018;
 vec3 stone=mix(vec3(0.17,0.21,0.21),vec3(0.26,0.29,0.27),n*0.5+0.45);
 ALBEDO=stone*(1.0-0.22*seam)+vec3(grit*0.25)+band*vec3(0.08,0.06,0.025);
 ROUGHNESS=0.94;
}"""
	var floor_mat = ShaderMaterial.new()
	floor_mat.shader = shader
	court.material_override = floor_mat
	var body = StaticBody3D.new()
	body.collision_layer = 1
	var shape = CollisionShape3D.new()
	var floor_shape = BoxShape3D.new()
	floor_shape.size = Vector3(40, 0.5, 40)
	shape.shape = floor_shape
	shape.position.y = -0.25
	body.add_child(shape)
	add_child(body)
	ring(8.16, 0.035, Vector3(0, 0.012, 0), Color("c4b17e"))
	ring(7.75, 0.015, Vector3(0, 0.013, 0), Color("7a827a"))
	ring(1.4, 0.018, Vector3(0, 0.014, 0), Color("9c967f"))
	for i in 16:
		var angle = TAU * i / 16.0
		var mark = box(Vector3(sin(angle) * 8.0, 0.02, cos(angle) * 8.0), Vector3(0.045, 0.028, 0.28), Color("c0ac7b"))
		mark.rotation.y = angle
	for x in [-1, 1]:
		for z in [-1, 1]:
			for step in 3:
				box(Vector3(x * 5.8, -0.13 - step * 0.15, z * (6.0 + step * 0.33)), Vector3(2.3, 0.25, 0.65), Color("868b80"))

func _build_gate() -> void:
	var wood = Color("263e41")
	var stone = Color("7c8984")
	for x in [-9.0, -4.4, 4.4, 9.0]:
		box(Vector3(x, 0.05, -12.1), Vector3(1.0, 0.8, 1.0), stone)
		box(Vector3(x, 2.1, -12.1), Vector3(0.38, 4.0, 0.38), wood)
		box(Vector3(x, 3.75, -12.1), Vector3(0.76, 0.18, 0.75), Color("9b9b81"))
	box(Vector3(0, 3.7, -12.1), Vector3(19.2, 0.40, 0.55), wood)
	box(Vector3(0, 4.18, -12.1), Vector3(19.7, 0.22, 1.45), Color("31494c"))
	box(Vector3(0, 4.37, -12.1), Vector3(18.3, 0.18, 1.12), Color("3c5253"))
	box(Vector3(0, 4.53, -12.1), Vector3(17.0, 0.13, 0.8), Color("415658"))
	for i in 39:
		box(Vector3(-9.5 + i * 0.5, 4.32, -11.37), Vector3(0.13, 0.13, 0.23), Color("4d6564"))
	box(Vector3(0, 3.24, -11.76), Vector3(2.7, 0.78, 0.13), Color("132e34"))
	var plaque = Label3D.new()
	plaque.text = "问  锋"
	plaque.font = load("res://assets/fonts/WenfengSerif.otf")
	plaque.font_size = 84
	plaque.pixel_size = 0.007
	plaque.modulate = Color("d1bb83")
	plaque.position = Vector3(0, 3.23, -11.65)
	plaque.no_depth_test = false
	add_child(plaque)
	for x in [-7, -2.4, 2.4, 7]:
		_lantern(Vector3(x, 2.9, -12.0))
	for side in [-1, 1]:
		var wall = box(Vector3(side * 12.4, 0.9, -1.0), Vector3(0.55, 2.7, 23), Color("7d8d88"))
		box(wall.position + Vector3(0, 1.45, 0), Vector3(0.95, 0.23, 23.4), Color("354f52"))
		for z in [-9, -4, 1, 6, 10]:
			box(Vector3(side * 12.3, 1.7, z), Vector3(0.75, 3.5, 0.65), stone)

func _lantern(at: Vector3) -> void:
	cylinder(at + Vector3.UP * 0.34, 0.014, 0.8, Color("a9946e"), 6)
	var mesh = SphereMesh.new()
	mesh.radius = 0.29
	mesh.height = 0.60
	mesh.radial_segments = 12
	mesh.rings = 6
	var mat = material(Color("a94f37")).duplicate()
	mat.emission_enabled = true
	mat.emission = Color("dc9c4b")
	mat.emission_energy_multiplier = 0.5
	mesh_at(mesh, mat, at)
	cylinder(at + Vector3.DOWN * 0.3, 0.18, 0.06, Color("bd9e62"), 12)
	var light = OmniLight3D.new()
	light.position = at
	light.light_color = Color("ffb966")
	light.light_energy = 0.45
	light.omni_range = 3.3
	add_child(light)

func _build_surroundings() -> void:
	for i in 12:
		var angle = TAU * i / 12.0
		var p = Vector3(sin(angle) * 9.35, 0, cos(angle) * 9.35)
		cylinder(p + Vector3.UP * 0.08, 0.38, 0.5, Color("707f79"), 8)
		cylinder(p + Vector3.UP * 0.75, 0.20, 1.0, Color("88928a"), 8)
		cylinder(p + Vector3.UP * 1.27, 0.32, 0.13, Color("a1aa9a"), 8)
	for side in [-1, 1]:
		for z in [-8, 7.5]:
			var x = side * 10.3
			cylinder(Vector3(x, 1.8, z), 0.04, 4.4, Color("ad9766"), 8)
			box(Vector3(x, 3.8, z), Vector3(1.25, 0.055, 0.055), Color("c0a56f"))
			var cloth = QuadMesh.new()
			cloth.size = Vector2(1.0, 2.2)
			var shader = Shader.new()
			shader.code = """shader_type spatial; render_mode cull_disabled;
uniform vec4 cloth_color:source_color=vec4(0.12,0.30,0.31,1.0);
void vertex(){VERTEX.z+=sin(TIME*1.8+VERTEX.y*2.6+VERTEX.x*3.0)*0.07*(1.0-UV.y);}
void fragment(){float edge=step(0.055,UV.x)*step(UV.x,0.945); ALBEDO=mix(vec3(0.58,0.48,0.26),cloth_color.rgb,edge); ROUGHNESS=1.0;}
"""
			var mat = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("cloth_color", Color("2c595a") if side < 0 else Color("945c47"))
			mesh_at(cloth, mat, Vector3(x, 2.58, z))
	# Layered continuous ridges stay quiet behind the fighting silhouettes.
	for layer in 3:
		var vertices = PackedVector3Array()
		var indices = PackedInt32Array()
		for i in 41:
			var x = (i - 20) * 3.0
			var height = 4.7 + layer * 0.55 + sin(i * 0.65 + layer * 2.1) * 1.9 + sin(i * 1.4 + layer) * 1.2
			vertices.append(Vector3(x, height, -31.0 - layer * 8.0))
			vertices.append(Vector3(x, -2.0, -31.0 - layer * 8.0))
			if i > 0:
				var k = i * 2
				indices.append_array(PackedInt32Array([k - 2, k, k - 1, k, k + 1, k - 1]))
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		var ridge = ArrayMesh.new()
		ridge.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var ridge_mat = material(Color("526e76").lerp(Color("91aaab"), layer / 3.0)).duplicate()
		ridge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ridge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_at(ridge, ridge_mat, Vector3.ZERO)
