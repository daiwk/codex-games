extends Node3D
class_name RPGWorld

# The overworld deliberately has one continuous physical floor. Decoration,
# shallow water and the bridge never introduce steps into mounted traversal.
const START = Vector3(0, 0.05, 100)
const MAP_RADIUS = 155.0
const CAMERA_FAR = 450.0
const BOSS_POSITIONS = [Vector3(-52, 0, 70), Vector3(-92, 0, 8), Vector3(-25, 0, -45), Vector3(58, 0, -75), Vector3(102, 0, -5)]
const BOSS_IDS = ["machao", "xuchu", "zhangfei", "guanyu", "lubu"]
const ZONE_NAMES = ["西凉牧野", "古槐村", "长坂竹林", "青龙渡", "虎牢关"]
const STATIONS = [
	{"id": "camp", "name": "南山营地", "position": START},
	{"id": "west", "name": "古道西驿", "position": Vector3(-65, 0.05, 23)},
	{"id": "east", "name": "清溪东驿", "position": Vector3(54, 0.05, -8)},
]
const ROUTES = [
	[Vector3(0, 0, 100), Vector3(-24, 0, 88), Vector3(-52, 0, 70), Vector3(-66, 0, 42), Vector3(-65, 0, 23), Vector3(-92, 0, 8), Vector3(-72, 0, -12), Vector3(-44, 0, -30), Vector3(-25, 0, -45), Vector3(13, 0, -60), Vector3(58, 0, -75), Vector3(78, 0, -48), Vector3(92, 0, -24), Vector3(102, 0, -5), Vector3(76, 0, 0), Vector3(54, 0, -8), Vector3(28, 0, 27), Vector3(14, 0, 34), Vector3(12, 0, 53), Vector3(9, 0, 61), Vector3(0, 0, 100)],
	[Vector3(-65, 0, 23), Vector3(-28, 0, 18), Vector3(16, 0, 0), Vector3(54, 0, -8)],
	[Vector3(-28, 0, 18), Vector3(-15, 0, -13), Vector3(-25, 0, -45)],
	[Vector3(12, 0, 49), Vector3(15, 0, 42), Vector3(18, 0, 42), Vector3(56, 0, 42), Vector3(63, 0, 32), Vector3(54, 0, -8)],
]

var _rng = RandomNumberGenerator.new()
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _batches: Dictionary = {}
var _obstacles: StaticBody3D
var _road_material: ShaderMaterial
var _flag_shader: Shader
var _fires: Array[Node3D] = []
var _fire_lights: Array[OmniLight3D] = []
var _clock = 0.0
var _font: Font


func _ready() -> void:
	name = "RPGWorld"
	_rng.seed = 731428
	_font = load("res://assets/fonts/WenfengSerif.otf")
	_obstacles = StaticBody3D.new()
	_obstacles.name = "WorldObstacles"
	_obstacles.collision_layer = 1
	_obstacles.collision_mask = 0
	add_child(_obstacles)
	_build_lighting()
	_build_ground()
	_build_roads()
	_build_water_and_bridge()
	_build_stations()
	_build_boss_clearings()
	_build_village()
	_build_fields()
	_build_forests()
	_build_mountains()
	_flush_batches()
	call_deferred("_configure_camera")


func ground_height(_at: Vector3) -> float:
	return 0.0


func get_stations() -> Array:
	return STATIONS.duplicate(true)


func zone_at(at: Vector3) -> String:
	var flat = Vector3(at.x, 0, at.z)
	if flat.distance_to(Vector3(START.x, 0, START.z)) < 20.0:
		return "南山营地"
	for i in BOSS_POSITIONS.size():
		if flat.distance_to(BOSS_POSITIONS[i]) < 28.0:
			return ZONE_NAMES[i]
	if Vector2(at.x - 37.0, at.z - 42.0).length() < 24.0:
		return "清溪水畔"
	if at.x < -55.0:
		return "西山古道"
	if at.z < -30.0:
		return "北原松风"
	return "中原郊野"


func _configure_camera() -> void:
	var camera = get_viewport().get_camera_3d()
	if camera != null:
		camera.far = maxf(camera.far, CAMERA_FAR)


func _process(delta: float) -> void:
	_clock += delta
	for i in _fires.size():
		var pulse = sin(_clock * 8.0 + i * 2.3) * 0.09 + sin(_clock * 13.3 + i) * 0.04
		_fires[i].scale = Vector3(1.0 - pulse * 0.3, 1.0 + pulse, 1.0 - pulse * 0.3)
		_fire_lights[i].light_energy = 1.0 + pulse * 2.0


func _mat(hex: String, metallic = 0.0, emission = false) -> StandardMaterial3D:
	var key = hex + str(metallic) + str(emission)
	if _materials.has(key):
		return _materials[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(hex)
	mat.roughness = 0.94 if metallic == 0.0 else 0.48
	mat.metallic = metallic
	if emission:
		mat.emission_enabled = true
		mat.emission = Color(hex)
		mat.emission_energy_multiplier = 1.3
	_materials[key] = mat
	return mat


func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"box":
			mesh = BoxMesh.new()
			mesh.size = Vector3.ONE
		"plane":
			mesh = PlaneMesh.new()
			mesh.size = Vector2.ONE
		"cone":
			mesh = CylinderMesh.new()
			mesh.bottom_radius = 1.0
			mesh.top_radius = 0.0
			mesh.height = 1.0
			mesh.radial_segments = 9
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = 1.0
			mesh.height = 2.0
			mesh.radial_segments = 9
			mesh.rings = 5
		"disk":
			mesh = CylinderMesh.new()
			mesh.bottom_radius = 1.0
			mesh.top_radius = 1.0
			mesh.height = 1.0
			mesh.radial_segments = 64
		_:
			mesh = CylinderMesh.new()
			mesh.bottom_radius = 1.0
			mesh.top_radius = 1.0
			mesh.height = 1.0
			mesh.radial_segments = 7
	_meshes[kind] = mesh
	return mesh


func _stamp(kind: String, mat: Material, at: Vector3, size: Vector3, yaw = 0.0, shadow = false) -> void:
	var mesh = _mesh(kind)
	var key = str(mesh.get_instance_id()) + ":" + str(mat.get_instance_id()) + ":" + str(shadow)
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "material": mat, "shadow": shadow, "transforms": []}
	var basis = Basis(Vector3.UP, yaw).scaled(size)
	_batches[key].transforms.append(Transform3D(basis, at))


func _flush_batches() -> void:
	for group in _batches.values():
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = group.mesh
		multimesh.instance_count = group.transforms.size()
		for i in group.transforms.size():
			multimesh.set_instance_transform(i, group.transforms[i])
		var instance = MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = group.material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if group.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	_batches.clear()


func _visual(mesh: Mesh, mat: Material, at: Vector3, size = Vector3.ONE, shadow = false) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	instance.scale = size
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _box_collider(at: Vector3, size: Vector3, yaw = 0.0) -> void:
	var shape = BoxShape3D.new()
	shape.size = size
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position = at
	collision.rotation.y = yaw
	_obstacles.add_child(collision)


func _trunk_collider(at: Vector3, radius: float, height: float) -> void:
	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position = at + Vector3.UP * height * 0.5
	_obstacles.add_child(collision)


func _build_lighting() -> void:
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6d9daf")
	sky_material.sky_horizon_color = Color("d6ded0")
	sky_material.ground_horizon_color = Color("bac6ac")
	sky_material.ground_bottom_color = Color("596e61")
	sky_material.sky_curve = 0.28
	var sky = Sky.new()
	sky.sky_material = sky_material
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d6e2d3")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("bdcfc7")
	env.fog_light_energy = 0.85
	env.fog_density = 0.0026
	var world_environment = WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -37, 0)
	sun.light_color = Color("ffebc3")
	sun.light_energy = 1.12
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65.0
	sun.shadow_bias = 0.035
	add_child(sun)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-26, 132, 0)
	fill.light_color = Color("a9c7d7")
	fill.light_energy = 0.20
	add_child(fill)


func _build_ground() -> void:
	var shader = Shader.new()
	shader.code = """shader_type spatial;
varying vec3 world;
void vertex(){ world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
 vec2 p=world.xz; float patch=sin(p.x*.045+sin(p.y*.028))*sin(p.y*.039);
 float grain=hash(floor(p*3.2));
 ALBEDO=mix(vec3(.245,.305,.191),vec3(.375,.413,.257),patch*.5+.5)+vec3(grain*.026);
 ROUGHNESS=.98;
}"""
	var ground = ShaderMaterial.new()
	ground.shader = shader
	_visual(_mesh("disk"), ground, Vector3(0, -0.20, 0), Vector3(MAP_RADIUS, 0.40, MAP_RADIUS))
	_stamp("disk", _mat("768369"), Vector3(0, -0.55, 0), Vector3(205, 0.30, 205))
	var floor_body = StaticBody3D.new()
	floor_body.name = "ContinuousFloor"
	floor_body.collision_layer = 1
	var shape = CylinderShape3D.new()
	shape.radius = MAP_RADIUS + 1.0
	shape.height = 1.0
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = -0.5
	floor_body.add_child(collision)
	add_child(floor_body)
	for i in 72:
		var angle = TAU * float(i) / 72.0
		var at = Vector3(sin(angle), 0, cos(angle)) * (MAP_RADIUS + 0.6)
		_box_collider(at + Vector3.UP * 3.0, Vector3(14.1, 6.0, 1.2), angle)


func _build_roads() -> void:
	var shader = Shader.new()
	shader.code = """shader_type spatial;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float noise=fract(sin(dot(floor(world.xz*2.),vec2(39.3,71.7)))*4375.1);
 float edge=smoothstep(.36,.5,abs(UV.x-.5));
 float tracks=(1.-smoothstep(.018,.038,abs(UV.x-.28)))+(1.-smoothstep(.018,.038,abs(UV.x-.72)));
 vec3 dirt=mix(vec3(.49,.43,.31),vec3(.62,.56,.40),noise*.38);
 ALBEDO=mix(dirt-tracks*.035,vec3(.34,.39,.24),edge*.75); ROUGHNESS=.98;
}"""
	_road_material = ShaderMaterial.new()
	_road_material.shader = shader
	for route_index in ROUTES.size():
		var route: Array = ROUTES[route_index]
		var width = 6.4 if route_index == 0 else 4.4
		for i in route.size() - 1:
			var a: Vector3 = route[i]
			var b: Vector3 = route[i + 1]
			var length = a.distance_to(b)
			var yaw = atan2(b.x - a.x, b.z - a.z)
			_stamp("plane", _road_material, (a + b) * 0.5 + Vector3.UP * 0.014, Vector3(width, 1, length + 0.3), yaw)
			_stamp("disk", _mat("8a805c"), a + Vector3.UP * 0.006, Vector3(width * 0.49, 0.009, width * 0.49))
			# Worn pale stones are a ground-level visual route cue, not walls.
			for mark in int(length / 9.0):
				var p = a.lerp(b, (float(mark) + 0.5) / maxf(1.0, float(int(length / 9.0))))
				_stamp("box", _mat("beb18a"), p + Vector3.UP * 0.028, Vector3(0.09, 0.018, 0.75), yaw)
	_sign(Vector3(-23, 0, 84), "西凉牧野  古槐村", 0.2)
	_sign(Vector3(-59, 0, 20), "南山营地  长坂竹林", -0.5)
	_sign(Vector3(-26, 0, 11), "长坂竹林  青龙渡", 0.0)
	_sign(Vector3(51, 0, -2), "青龙渡  虎牢关", 0.5)
	_sign(Vector3(12, 0, 57), "清溪木桥  东驿", -0.35)


func _label(text: String, at: Vector3, color = Color("ead6a1"), size = 62, pixel = 0.009) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = Color("20332c")
	label.outline_size = 6
	label.position = at
	label.double_sided = true
	label.no_depth_test = false
	add_child(label)
	return label


func _sign(at: Vector3, text: String, yaw: float) -> void:
	var wood = _mat("423d2a")
	_stamp("cylinder", wood, at + Vector3.UP * 1.45, Vector3(0.10, 2.9, 0.10))
	_stamp("box", wood, at + Vector3.UP * 2.62, Vector3(4.6, 0.68, 0.16), yaw)
	var label = _label(text, at + Vector3.UP * 2.62 + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.095), Color("e3ce99"), 47, 0.007)
	label.rotation.y = yaw


func _flag(at: Vector3, color: String, text: String, height = 5.8) -> void:
	_stamp("cylinder", _mat("786342"), at + Vector3.UP * height * 0.5, Vector3(0.065, height, 0.065))
	_stamp("box", _mat("ad9361"), at + Vector3.UP * (height - 0.24), Vector3(1.65, 0.08, 0.08))
	if _flag_shader == null:
		_flag_shader = Shader.new()
		_flag_shader.code = """shader_type spatial; render_mode cull_disabled;
uniform vec4 cloth_color:source_color;
void vertex(){VERTEX.z+=sin(TIME*1.7+VERTEX.y*3.1+VERTEX.x*2.2)*.12*(1.-UV.y);}
void fragment(){float border=step(.06,UV.x)*step(UV.x,.94)*step(.035,UV.y)*step(UV.y,.965);ALBEDO=mix(vec3(.68,.55,.29),cloth_color.rgb,border);ROUGHNESS=1.;}
"""
	var mat = ShaderMaterial.new()
	mat.shader = _flag_shader
	mat.set_shader_parameter("cloth_color", Color(color))
	var cloth = QuadMesh.new()
	cloth.size = Vector2(1.45, 2.55)
	_visual(cloth, mat, at + Vector3(0, height - 1.6, 0))
	_label(text, at + Vector3(0, height - 1.52, 0.13), Color("e5ce96"), 77, 0.010)


func _roof(at: Vector3, width: float, depth: float, yaw = 0.0) -> void:
	if not _meshes.has("roof"):
		var tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners = [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
		var ridge_a = Vector3(-0.31, 0.26, 0)
		var ridge_b = Vector3(0.31, 0.26, 0)
		for triangle in [[corners[0], ridge_a, ridge_b], [corners[0], ridge_b, corners[1]], [corners[1], ridge_b, corners[2]], [corners[2], ridge_b, ridge_a], [corners[2], ridge_a, corners[3]], [corners[3], ridge_a, corners[0]]]:
			for vertex in triangle:
				tool.add_vertex(vertex)
		tool.generate_normals()
		_meshes["roof"] = tool.commit()
	_stamp("roof", _mat("314c4b"), at, Vector3(width, width * 0.65, depth), yaw, true)
	_stamp("roof", _mat("4d6660"), at + Vector3.UP * 0.12, Vector3(width * 0.89, width * 0.65, depth * 0.86), yaw, true)
	_stamp("box", _mat("263f3c"), at, Vector3(width, 0.16, depth), yaw, true)


func _gate(at: Vector3, text: String, width = 10.0, yaw = 0.0, stone = false) -> void:
	var basis = Basis(Vector3.UP, yaw)
	var pillar = _mat("7b8471") if stone else _mat("3c4940")
	for side in [-1.0, 1.0]:
		var p = at + basis * Vector3(side * width * 0.5, 0, 0)
		_stamp("box", _mat("8b8d77"), p + Vector3.UP * 0.25, Vector3(1.2, 0.5, 1.2), yaw, true)
		_stamp("box", pillar, p + Vector3.UP * 2.8, Vector3(0.58, 5.6, 0.58), yaw, true)
		_box_collider(p + Vector3.UP * 2.8, Vector3(0.72, 5.6, 0.72), yaw)
	_stamp("box", pillar, at + Vector3.UP * 5.2, Vector3(width + 1.2, 0.36, 0.58), yaw, true)
	_roof(at + Vector3.UP * 5.5, width + 2.0, 2.4, yaw)
	_stamp("box", _mat("233e3c"), at + Vector3.UP * 4.7 + basis * Vector3(0, 0, 0.37), Vector3(3.7, 0.82, 0.15), yaw)
	var label = _label(text, at + Vector3.UP * 4.7 + basis * Vector3(0, 0, 0.46), Color("d9c38c"), 76, 0.009)
	label.rotation.y = yaw


func _build_stations() -> void:
	for i in STATIONS.size():
		var at: Vector3 = STATIONS[i].position
		at.y = 0.0
		_stamp("disk", _mat("9a8b65"), at + Vector3.UP * 0.009, Vector3(10.0 if i == 0 else 7.8, 0.014, 10.0 if i == 0 else 7.8))
		_tent(at + (Vector3(-10, 0, -9) if i == 2 else Vector3(-10, 0, 3)), 0.1, "866749")
		_tent(at + Vector3(7, 0, 7), -0.3, "796b4c")
		_campfire(at + Vector3(4.4, 0, -1.0))
		_flag(at + Vector3(-5.8, 0, -3.7), "315f5d", "营" if i == 0 else "驿", 5.6)
		_sign(at + Vector3(5.0, 0, -5.5), String(STATIONS[i].name), 0.0)
		for j in 4:
			_stamp("box", _mat("766146"), at + Vector3(-6.0 + j * 0.8, 0.35, 8.0), Vector3(0.67, 0.7, 0.65), float(j) * 0.2)
	_gate(Vector3(-9.5, 0, 94.0), "南山营", 10.5, -0.9)


func _tent(at: Vector3, yaw: float, color: String) -> void:
	# A-frame canvas with open-looking dark front and a physical occupied core.
	var basis = Basis(Vector3.UP, yaw)
	var roof = _roof_mesh_tent()
	var instance = _visual(roof, _mat(color), at, Vector3(4.8, 3.0, 5.1), true)
	instance.rotation.y = yaw
	_stamp("box", _mat("423f30"), at + basis * Vector3(0, 1.15, 2.43), Vector3(2.2, 2.3, 0.06), yaw)
	for side in [-1.0, 1.0]:
		_stamp("cylinder", _mat("675b3c"), at + basis * Vector3(0, 1.55, side * 2.55), Vector3(0.06, 3.1, 0.06))
	_box_collider(at + Vector3.UP * 1.0, Vector3(4.0, 2.0, 4.5), yaw)


func _roof_mesh_tent() -> Mesh:
	if _meshes.has("tent"):
		return _meshes.tent
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in [[Vector3(-0.5, 0, -0.5), Vector3(0, 1, -0.5), Vector3(0, 1, 0.5)], [Vector3(-0.5, 0, -0.5), Vector3(0, 1, 0.5), Vector3(-0.5, 0, 0.5)], [Vector3(0, 1, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5)], [Vector3(0, 1, -0.5), Vector3(0.5, 0, 0.5), Vector3(0, 1, 0.5)]]:
		for vertex in [triangle[0], triangle[2], triangle[1]]:
			tool.add_vertex(vertex)
	tool.generate_normals()
	_meshes.tent = tool.commit()
	return _meshes.tent


func _campfire(at: Vector3) -> void:
	for i in 9:
		var angle = TAU * float(i) / 9.0
		_stamp("sphere", _mat("737966"), at + Vector3(sin(angle) * 0.8, 0.17, cos(angle) * 0.8), Vector3(0.24, 0.18, 0.28), angle)
	for i in 3:
		_stamp("box", _mat("423429"), at + Vector3.UP * (0.10 + i * 0.10), Vector3(1.15, 0.17, 0.22), i * 1.8)
	var flame = _visual(_mesh("cone"), _mat("e8a74b", 0.0, true), at + Vector3.UP * 0.55, Vector3(0.39, 0.95, 0.39))
	var pivot = Node3D.new()
	pivot.position = flame.position
	add_child(pivot)
	flame.reparent(pivot, true)
	_fires.append(pivot)
	var light = OmniLight3D.new()
	light.position = at + Vector3.UP * 0.9
	light.light_color = Color("ffbc62")
	light.omni_range = 6.0
	light.shadow_enabled = false
	add_child(light)
	_fire_lights.append(light)


func _build_boss_clearings() -> void:
	var colors = ["866c44", "78533d", "334c48", "456c5d", "843e37"]
	var names = ["马 超", "许 褚", "张 飞", "关 羽", "吕 布"]
	for i in BOSS_POSITIONS.size():
		var at: Vector3 = BOSS_POSITIONS[i]
		_stamp("disk", _mat("9a9276"), at + Vector3.UP * 0.018, Vector3(13.5, 0.024, 13.5))
		_stamp("disk", _mat("b0a17c"), at + Vector3.UP * 0.033, Vector3(10.7, 0.012, 10.7))
		for radius in [10.85, 12.8]:
			var ring = TorusMesh.new()
			ring.inner_radius = radius - 0.055
			ring.outer_radius = radius + 0.055
			ring.rings = 64
			ring.ring_segments = 5
			_visual(ring, _mat("d0bd87", 0.15), at + Vector3.UP * 0.047, Vector3(1, 0.2, 1))
		for j in 12:
			var angle = TAU * float(j) / 12.0
			_stamp("box", _mat("756b51"), at + Vector3(sin(angle) * 11.6, 0.045, cos(angle) * 11.6), Vector3(0.18, 0.02, 0.65), angle)
		_gate(at + Vector3(0, 0, -16.0), ZONE_NAMES[i], 9.5 if i < 4 else 12.0, 0.0, i == 4)
		_flag(at + Vector3(-13.5, 0, -5), colors[i], String(names[i]).replace(" ", "\n"), 7.2)
		_flag(at + Vector3(13.5, 0, -5), colors[i], "锋", 6.6)
		_label(ZONE_NAMES[i], at + Vector3(0, 5.7, -15.35), Color("e9d39a"), 70, 0.012)
		if i == 4:
			for side in [-1.0, 1.0]:
				var p = at + Vector3(side * 19.0, 0, -15.5)
				_stamp("box", _mat("69766d"), p + Vector3.UP * 3.0, Vector3(4.2, 6.0, 4.5), 0, true)
				_roof(p + Vector3.UP * 6.0, 5.6, 5.8)
				_box_collider(p + Vector3.UP * 3.0, Vector3(4.2, 6.0, 4.5))
		elif i == 3:
			_pavilion(at + Vector3(17, 0, 10), 0.0)


func _build_water_and_bridge() -> void:
	var shader = Shader.new()
	shader.code = """shader_type spatial;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 float wave=sin(world.x*1.6+TIME*.8)*sin(world.z*1.1-TIME*.65);
 float glint=pow(max(0.,sin(world.x*2.8+world.z*1.9+TIME*.55)),18.);
 ALBEDO=mix(vec3(.15,.32,.30),vec3(.30,.47,.40),wave*.17+.42)+glint*.055;
 ROUGHNESS=.34; METALLIC=.18;
 NORMAL=normalize(vec3(cos(world.x*1.6+TIME*.8)*.035,1.,sin(world.z*1.1-TIME*.65)*.035));
}"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	var at = Vector3(37, 0, 42)
	_stamp("disk", _mat("8a916f"), at + Vector3.UP * 0.005, Vector3(18.2, 0.006, 11.0))
	_visual(_mesh("disk"), mat, at + Vector3.UP * 0.012, Vector3(17.2, 0.008, 9.9))
	for i in 34:
		var angle = TAU * float(i) / 34.0
		var p = at + Vector3(cos(angle) * 17.8, 0.16, sin(angle) * 10.5)
		if absf(p.z - 42.0) < 3.2:
			continue
		_stamp("sphere", _mat("858d78"), p, Vector3(_rng.randf_range(0.6, 1.4), 0.28, _rng.randf_range(0.6, 1.3)), angle)
	# A level wooden causeway: the sole traversable physical surface stays Y=0.
	for i in 63:
		_stamp("box", _mat("8d7955"), Vector3(18.2 + i * 0.61, 0.031, 42.0), Vector3(0.57, 0.024, 4.3))
	for side in [-1.0, 1.0]:
		_stamp("box", _mat("655b41"), Vector3(37.0, 0.95, 42.0 + side * 2.3), Vector3(38.6, 0.15, 0.14), 0, true)
		_box_collider(Vector3(37.0, 0.57, 42.0 + side * 2.3), Vector3(38.6, 1.14, 0.18))
		for i in 14:
			_stamp("box", _mat("5e5942"), Vector3(18.2 + i * 2.9, 0.65, 42.0 + side * 2.3), Vector3(0.18, 1.3, 0.18), 0, true)
	_sign(Vector3(24.0, 0, 46.0), "清溪木桥", 0.2)
	for i in 28:
		var angle = _rng.randf() * TAU
		var p = at + Vector3(cos(angle) * 18.5, 0, sin(angle) * 11.3)
		if absf(p.z - 42.0) < 3.0:
			continue
		_stamp("cone", _mat("737d4e"), p + Vector3.UP * 0.55, Vector3(0.26, 1.1, 0.26))


func _pavilion(at: Vector3, yaw: float) -> void:
	var basis = Basis(Vector3.UP, yaw)
	_stamp("box", _mat("929780"), at + Vector3.UP * 0.09, Vector3(5.0, 0.18, 5.0), yaw)
	for x in [-1.8, 1.8]:
		for z in [-1.8, 1.8]:
			var p = at + basis * Vector3(x, 0, z)
			_stamp("cylinder", _mat("4b5142"), p + Vector3.UP * 1.9, Vector3(0.16, 3.8, 0.16), 0, true)
			_trunk_collider(p, 0.20, 3.8)
	_roof(at + Vector3.UP * 3.8, 6.0, 6.0, yaw)


func _build_village() -> void:
	for entry in [[Vector3(-112, 0, 31), 0.1], [Vector3(-99, 0, 41), -0.25], [Vector3(-117, 0, 12), 0.1], [Vector3(-119, 0, -8), 0.35], [Vector3(-102, 0, -15), -0.2]]:
		_house(entry[0], entry[1])
	_pavilion(Vector3(-104, 0, 24), 0.15)
	_stamp("cylinder", _mat("818a79"), Vector3(-103, 0.45, 15), Vector3(0.95, 0.90, 0.95))
	_stamp("cylinder", _mat("304842"), Vector3(-103, 0.91, 15), Vector3(0.68, 0.04, 0.68))
	_trunk_collider(Vector3(-103, 0, 15), 0.98, 1.0)
	_sign(Vector3(-105, 0, 34), "古槐村", -0.15)
	_tree(Vector3(-109, 0, 23), 1.55, false)


func _house(at: Vector3, yaw: float) -> void:
	var basis = Basis(Vector3.UP, yaw)
	_stamp("box", _mat("b0a58a"), at + Vector3.UP * 1.6, Vector3(5.8, 3.2, 5.2), yaw, true)
	_stamp("box", _mat("7c8472"), at + Vector3.UP * 0.18, Vector3(6.2, 0.36, 5.6), yaw)
	_box_collider(at + Vector3.UP * 1.7, Vector3(6.0, 3.4, 5.4), yaw)
	for side in [-1.0, 1.0]:
		_stamp("box", _mat("4a4c3d"), at + basis * Vector3(side * 2.7, 1.7, 2.66), Vector3(0.21, 3.4, 0.16), yaw)
		_stamp("box", _mat("38483e"), at + basis * Vector3(side * 1.75, 1.9, 2.64), Vector3(0.92, 0.92, 0.10), yaw)
		for j in 3:
			_stamp("box", _mat("7a775b"), at + basis * Vector3(side * 1.75 - 0.29 + j * 0.29, 1.9, 2.72), Vector3(0.045, 0.92, 0.04), yaw)
	_stamp("box", _mat("53513a"), at + basis * Vector3(0, 1.25, 2.65), Vector3(1.25, 2.5, 0.13), yaw)
	_roof(at + Vector3.UP * 3.2, 7.5, 6.6, yaw)
	for i in 3:
		_stamp("cylinder", _mat("8b7850"), at + basis * Vector3(3.7, 0.50, -1.0 + i * 1.0), Vector3(0.43, 1.0, 0.43))


func _build_fields() -> void:
	for plot in [Vector3(28, 0, 79), Vector3(49, 0, 62), Vector3(-18, 0, 61)]:
		_stamp("plane", _mat("726e44"), plot + Vector3.UP * 0.008, Vector3(17, 1, 13))
		for row in 7:
			_stamp("box", _mat("8c8352"), plot + Vector3(-7.4 + row * 2.4, 0.025, 0), Vector3(0.34, 0.018, 12.0))
			for j in 5:
				var p: Vector3 = plot + Vector3(-7.4 + row * 2.4, 0, -4.8 + j * 2.4)
				if _distance_to_roads(p) < 5.0:
					continue
				_stamp("cone", _mat("a99a53"), p + Vector3.UP * 0.45, Vector3(0.34, 0.90, 0.34), _rng.randf() * TAU)
				_stamp("cone", _mat("c1ac66"), p + Vector3(0.17, 0.48, 0.15), Vector3(0.25, 0.96, 0.25))
		for side in [-1.0, 1.0]:
			_stamp("box", _mat("706a45"), plot + Vector3(side * 8.7, 0.62, 0), Vector3(0.08, 0.10, 13.2))
			for j in 5:
				_stamp("box", _mat("706a45"), plot + Vector3(side * 8.7, 0.43, -6 + j * 3.0), Vector3(0.12, 0.86, 0.12))


func _distance_to_roads(at: Vector3) -> float:
	var p = Vector2(at.x, at.z)
	var best = 999.0
	for route in ROUTES:
		for i in route.size() - 1:
			var a = Vector2(route[i].x, route[i].z)
			var b = Vector2(route[i + 1].x, route[i + 1].z)
			var ab = b - a
			var t = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best


func _can_grow(at: Vector3) -> bool:
	if Vector2(at.x, at.z).length() > MAP_RADIUS - 5.0 or _distance_to_roads(at) < 5.5:
		return false
	for station in STATIONS:
		var p: Vector3 = station.position
		if Vector2(at.x - p.x, at.z - p.z).length() < 15.0:
			return false
	for boss in BOSS_POSITIONS:
		if at.distance_to(boss) < 18.0:
			return false
	if Vector2((at.x - 37.0) / 21.0, (at.z - 42.0) / 14.0).length() < 1.0:
		return false
	if at.x < -96 and at.x > -126 and at.z > -22 and at.z < 49:
		return false
	return true


func _build_forests() -> void:
	var planted = 0
	for attempt in 1700:
		if planted >= 145:
			break
		var at = Vector3(_rng.randf_range(-145, 145), 0, _rng.randf_range(-142, 142))
		if not _can_grow(at):
			continue
		_tree(at, _rng.randf_range(0.85, 1.55), at.x > 25.0 or at.z < -65.0)
		planted += 1
	# Denser planting frames the camp without enclosing its exits.
	for at in [Vector3(-19, 0, 108), Vector3(20, 0, 113), Vector3(16, 0, 94), Vector3(-23, 0, 98), Vector3(7, 0, 122), Vector3(-11, 0, 121)]:
		_tree(at, _rng.randf_range(1.1, 1.5), false)
	for i in 82:
		var at = Vector3(_rng.randf_range(-61, -5), 0, _rng.randf_range(-76, -24))
		if _can_grow(at):
			_bamboo(at, _rng.randf_range(4.5, 7.4))
	for i in 95:
		var at = Vector3(_rng.randf_range(-145, 145), 0, _rng.randf_range(-145, 145))
		if _can_grow(at):
			_stamp("sphere", _mat("7b8870"), at + Vector3.UP * 0.26, Vector3(_rng.randf_range(0.5, 1.35), _rng.randf_range(0.3, 0.7), _rng.randf_range(0.4, 1.1)), _rng.randf() * TAU)
	for i in 180:
		var at = Vector3(_rng.randf_range(-145, 145), 0, _rng.randf_range(-145, 145))
		if _can_grow(at):
			_stamp("cone", _mat("697b45"), at + Vector3.UP * 0.23, Vector3(0.33, 0.46, 0.33), _rng.randf() * TAU)


func _tree(at: Vector3, size: float, pine: bool) -> void:
	var height = (6.3 if pine else 5.1) * size
	_stamp("cylinder", _mat("62583d"), at + Vector3.UP * height * 0.4, Vector3(0.23 * size, height * 0.8, 0.23 * size))
	_trunk_collider(at, 0.30 * size, height * 0.72)
	if pine:
		for i in 3:
			var radius = (2.3 - i * 0.48) * size
			_stamp("cone", _mat("3f6050" if i % 2 == 0 else "52705a"), at + Vector3.UP * (3.3 + i * 1.45) * size, Vector3(radius, 3.1 * size, radius), _rng.randf() * TAU)
	else:
		_stamp("sphere", _mat("627b4a"), at + Vector3.UP * height, Vector3(2.65, 1.6, 2.35) * size, _rng.randf() * TAU)
		_stamp("sphere", _mat("7b8d52"), at + Vector3(1.5, height - 0.55, 0.4) * Vector3(size, 1, size), Vector3(1.9, 1.4, 2.0) * size, _rng.randf() * TAU)


func _bamboo(at: Vector3, height: float) -> void:
	_stamp("cylinder", _mat("64764b"), at + Vector3.UP * height * 0.5, Vector3(0.075, height, 0.075))
	for y in [0.35, 0.62, 0.88]:
		_stamp("cylinder", _mat("a0a171"), at + Vector3.UP * height * y, Vector3(0.09, 0.045, 0.09))
		_stamp("sphere", _mat("506e49"), at + Vector3(0.25, height * y + 0.18, 0.2), Vector3(1.1, 0.20, 0.65), _rng.randf() * TAU)


func _build_mountains() -> void:
	for layer in 3:
		var color = ["607d75", "78958e", "97afa6"][layer]
		for i in 17:
			var angle = TAU * (float(i) + layer * 0.36) / 17.0
			var radius = 188.0 + layer * 43.0
			var height = _rng.randf_range(28, 57) + layer * 11.0
			var at = Vector3(sin(angle) * radius, height * 0.5 - 1.0, cos(angle) * radius)
			_stamp("cone", _mat(color), at, Vector3(_rng.randf_range(31, 47), height, _rng.randf_range(26, 43)), angle)
			_stamp("cone", _mat(color), at + Vector3(19, -height * 0.12, 12), Vector3(26, height * 0.76, 24), angle + 0.4)
