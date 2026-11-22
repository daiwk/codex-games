extends Node3D

signal building_destroyed(at: Vector3)

const BuildingRubble = preload("res://scripts/building_rubble.gd")
const StageTerrain = preload("res://scripts/stage_terrain.gd")

const WALL_MODEL := "res://assets/stone-wall.glb"
const WALL_SIZE := Vector3(5.5, 1.65, 1.32)
const ARENA_HALF_SIZE := Vector2(41.0, 38.0)
const PLAYER_SPAWN := Vector3(-6.0, 0.0, 30.0)
const ENEMY_SPAWN := Vector3(6.0, 0.0, -30.0)
const LAND_LIMIT := 32.0

class Building extends RefCounted:
	var label: String
	var health: int
	var max_health: int
	var cover: Rect2
	var collider: StaticBody3D
	var intact: Node3D
	var rubble: Node3D

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform int stage_index = 0;
varying vec2 ground_pos;

float hash_at(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(
		mix(hash_at(cell), hash_at(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_at(cell + vec2(0.0, 1.0)), hash_at(cell + vec2(1.0)), blend.x),
		blend.y
	);
}

""" + StageTerrain.COAST_PROFILE + """
float field_height(vec2 p) {
	vec2 outside = abs(p) - vec2(41.0, 38.0);
	float rim = smoothstep(3.0, 42.0, max(outside.x, outside.y));
	float ridge = grain(vec2(p.x * 0.026 - p.y * 0.013, p.y * 0.033));
	float loft = grain(p * 0.059);
	float elevation = rim * (0.45 + 8.0 * ridge * ridge + 1.9 * loft);
	if (stage_index == 1) {
		elevation *= 1.36;
	}
	if (stage_index == 2) {
		float shore = coast_distance(p);
		elevation = elevation * (1.0 - smoothstep(-21.0, -8.0, shore)) - 2.35 * smoothstep(-2.3, 6.1, shore);
	}
	return elevation;
}

void vertex() {
	ground_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float elevation = field_height(ground_pos);
	VERTEX.y += elevation;
	if (abs(elevation) > 0.001) {
		float slope_x = (field_height(ground_pos + vec2(0.8, 0.0)) - elevation) / 0.8;
		float slope_z = (field_height(ground_pos + vec2(0.0, 0.8)) - elevation) / 0.8;
		NORMAL = normalize(vec3(-slope_x, 1.0, -slope_z));
	}
}

void fragment() {
	vec2 p = ground_pos;
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float broad = grain(p * 0.21);
	float fine = mix(grain(p * 7.0), 0.5, smoothstep(0.033, 0.19, footprint));
	float grit = mix(grain(p * 24.0), 0.5, smoothstep(0.012, 0.061, footprint));
	float verge = 0.65 * grain(p * 1.12) + 0.40 * broad;
	float main_lane = abs(p.x + 1.5 - 1.8 * sin(p.y * 0.088));
	float cross_lane = abs(p.y + 0.8 * sin(p.x * 0.14));
	float village_lane = abs(p.x + 24.6 - 0.7 * sin(p.y * 0.109));
	float field_lane = abs(p.x - 24.8 + 1.3 * sin(p.y * 0.096));
	float loop_lane = abs(abs(p.y) - 24.0 + 0.65 * sin(p.x * 0.2));
	if (stage_index == 1) {
		main_lane = abs(p.x + 8.9 - 1.8 * sin(p.y * 0.113));
		cross_lane = abs(abs(p.y) - 16.5 + 0.65 * sin(p.x * 0.17));
		field_lane = abs(p.x - 20.9 + 1.35 * sin(p.y * 0.12));
	}
	if (stage_index == 2) {
		main_lane = abs(p.x + 3.6 - 2.0 * sin(p.y * 0.072));
		cross_lane = abs(p.y + 4.7 + 0.9 * sin(p.x * 0.11));
		field_lane = abs(p.x - 26.2 + 1.04 * sin(p.y * 0.09));
		village_lane = abs(p.x + 21.1 - 0.7 * sin(p.y * 0.078));
	}
	float wheel_way = 1.0 - smoothstep(2.1, 3.75, main_lane + verge);
	float cross_way = 1.0 - smoothstep(1.65, 3.35, cross_lane + verge);
	float field_way = (1.0 - smoothstep(1.25, 2.95, field_lane + verge)) * (1.0 - smoothstep(25.0, 32.0, abs(p.y)));
	float loop_way = (1.0 - smoothstep(1.0, 2.35, loop_lane + verge)) *
		smoothstep(-4.0, 1.0, p.x) * (1.0 - smoothstep(26.0, 30.0, p.x));
	float village_way = (1.0 - smoothstep(2.0, 3.65, village_lane + verge)) *
		(1.0 - smoothstep(27.0, 34.0, abs(p.y)));
	float dirt = max(max(wheel_way, cross_way * 0.83), max(field_way, loop_way) * 0.72);
	dirt *= 1.0 - smoothstep(35.0, 52.0, max(abs(p.x), abs(p.y)));
	float ruts = (1.0 - smoothstep(0.18, 0.65, abs(main_lane - 1.13))) * wheel_way;

	vec3 meadow = mix(vec3(0.235, 0.265, 0.128), vec3(0.40, 0.407, 0.222), broad);
	float cropped = smoothstep(8.0, 14.0, p.x + 2.2 * (broad - 0.5)) *
		(1.0 - smoothstep(31.0, 38.0, p.x)) * (1.0 - smoothstep(27.0, 34.0, abs(p.y)));
	if (stage_index != 0) {
		cropped *= 0.27;
	}
	float furrow = sin((p.y + p.x * 0.18 + grain(p * 0.14) * 0.15) * 5.4);
	furrow *= 1.0 - smoothstep(0.24, 0.67, footprint);
	vec3 stubble = mix(vec3(0.40, 0.359, 0.19), vec3(0.53, 0.466, 0.283), broad);
	meadow = mix(meadow, stubble * (1.0 + 0.077 * furrow), cropped * 0.84);
	vec3 track = mix(vec3(0.43, 0.347, 0.238), vec3(0.59, 0.482, 0.335), broad);
	track *= 1.0 - 0.12 * ruts;
	vec3 ground = mix(meadow, track, dirt);
	vec3 stone_lane = mix(vec3(0.385, 0.359, 0.31), vec3(0.55, 0.51, 0.433), fine * 0.6 + broad * 0.4);
	ground = mix(ground, stone_lane, village_way);
	float field_zone = grain(vec2(p.x + p.y * 0.42, p.y - p.x * 0.35) * 0.075);
	vec3 farmland = mix(vec3(0.294, 0.329, 0.207), vec3(0.452, 0.428, 0.271), smoothstep(0.29, 0.68, field_zone));
	ground = mix(ground, farmland, smoothstep(40.0, 62.0, max(abs(p.x), abs(p.y))));
	if (stage_index == 2) {
		float shore = coast_distance(p);
		float sand_mask = smoothstep(-15.0, -7.2, shore + broad * 2.7);
		vec3 sand = mix(vec3(0.54, 0.475, 0.345), vec3(0.69, 0.618, 0.477), broad);
		sand *= 1.0 - 0.25 * smoothstep(-2.0, 1.3, shore);
		ground = mix(ground, sand, sand_mask);
	}
	ALBEDO = ground * (0.91 + 0.12 * fine + 0.04 * grit);
	ROUGHNESS = 1.0;
}
"""

const BUILDING_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 paint : source_color;
uniform bool tiled_roof = false;
varying vec3 built_at;

float stone_cell(vec2 p) {
	return fract(sin(dot(p, vec2(101.9, 243.2))) * 19642.467);
}

void vertex() {
	built_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 facade = vec2(built_at.y, built_at.x + built_at.z);
	vec2 metric = tiled_roof ? vec2(11.4, 3.5) : vec2(3.8, 2.0);
	vec2 masonry = facade * metric;
	masonry.y += 0.43 * mod(floor(masonry.x), 2.0);
	vec2 grout = fract(masonry);
	float seam = max(
		1.0 - smoothstep(0.017, 0.09, min(grout.x, 1.0 - grout.x)),
		1.0 - smoothstep(0.017, 0.07, min(grout.y, 1.0 - grout.y))
	);
	float fade = 1.0 - smoothstep(0.28, 1.05, max(fwidth(masonry.x), fwidth(masonry.y)));
	float tint = (stone_cell(floor(masonry)) - 0.5) * fade;
	float low_stain = 1.0 - smoothstep(0.12, 0.86, built_at.y);
	float variation = 1.0 + 0.16 * tint - 0.12 * seam * fade - 0.14 * low_stain;
	ALBEDO = paint.rgb * variation;
	ROUGHNESS = 0.95;
}
"""

var cover_rects: Array[Rect2] = []
var _stage_index := 0
var _permanent_cover: Array[Rect2] = []
var _buildings: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _wall_scene: PackedScene


func configure(stage_index: int) -> void:
	_stage_index = clampi(stage_index, 0, 2)


func _ready() -> void:
	_random.seed = 527643 + _stage_index * 421
	if ResourceLoader.exists(WALL_MODEL):
		_wall_scene = load(WALL_MODEL) as PackedScene
	_build_ground()
	match _stage_index:
		1:
			_build_hill_cover()
		2:
			_build_coast_cover()
		_:
			_build_plain_cover()
	_permanent_cover.assign(cover_rects)
	_build_village()
	_build_boundary()
	_build_grass()
	_build_hedgerows()
	_add_farm_buildings()


func _build_plain_cover() -> void:
	_build_cover(Vector2(5.8, 6.2), false)
	_build_cover(Vector2(-9.5, -7.3), false)
	_build_cover(Vector2(18.8, -15.5), false)
	_build_cover(Vector2(14.8, 13.7), true)
	_build_cover(Vector2(32.4, 7.9), true)
	_build_cover(Vector2(-36.0, 17.8), false)
	_build_cover(Vector2(-12.8, 26.3), true)


func _build_hill_cover() -> void:
	_add_hill(Vector2(6.35, 1.0), Vector2(16.0, 23.8), 9.8, 0.2)
	_add_hill(Vector2(-27.8, -6.0), Vector2(12.6, 17.6), 8.1, 2.2)
	_add_hill(Vector2(33.3, -11.5), Vector2(11.8, 17.0), 9.1, 4.1)
	_build_cover(Vector2(-14.0, 3.0), true)
	_build_cover(Vector2(-10.8, -16.4), true)
	_build_cover(Vector2(25.0, 13.4), true)
	_build_cover(Vector2(-34.0, 6.6), false)
	_build_cover(Vector2(-10.0, 18.5), true)


func _add_hill(center: Vector2, size: Vector2, height: float, phase: float) -> void:
	add_child(StageTerrain.hill(center, size, height, phase))
	cover_rects.append(Rect2(center - size * 0.5, size))


func _build_coast_cover() -> void:
	add_child(StageTerrain.sea())
	var shore_width := ARENA_HALF_SIZE.x - LAND_LIMIT
	var barrier := _add_static_box(
		Vector3(LAND_LIMIT + shore_width * 0.5, 0.14, 0.0),
		Vector3(shore_width, 0.28, ARENA_HALF_SIZE.y * 2.0)
	)
	barrier.name = "ShorelineLimit"
	cover_rects.append(Rect2(LAND_LIMIT, -ARENA_HALF_SIZE.y, shore_width, ARENA_HALF_SIZE.y * 2.0))
	_build_cover(Vector2(3.0, -7.0), false)
	_build_cover(Vector2(-13.0, 7.0), true)
	_build_cover(Vector2(20.0, -9.0), false)
	_build_cover(Vector2(-30.5, -21.0), true)
	_build_cover(Vector2(7.2, 13.7), false)
	_build_cover(Vector2(-26.0, 20.5), false)
	_build_shore_edge()


func damage_building(collider: Object, damage: int) -> bool:
	var building := _buildings.get(collider) as Building
	if building == null:
		return false
	if building.health == 0 or damage <= 0:
		return true

	building.health = maxi(0, building.health - damage)
	if building.health == 0:
		building.collider.collision_layer = 0
		building.intact.hide()
		cover_rects.erase(building.cover)
		if building.rubble == null:
			var rubble := BuildingRubble.new()
			rubble.position = building.intact.position
			rubble.rotation = building.intact.rotation
			rubble.build(building.cover.size, hash(building.label))
			building.rubble = rubble
			add_child(rubble)
		building.rubble.show()
		building_destroyed.emit(building.collider.global_position)
	return true


func damage_buildings_in_area(center: Vector3, radius: float, damage: int) -> void:
	var blast := Vector2(center.x, center.z)
	for collider: StaticBody3D in _buildings:
		var building := _buildings[collider] as Building
		if building.health == 0:
			continue
		var nearest := blast.clamp(building.cover.position, building.cover.end)
		var distance := blast.distance_to(nearest)
		if distance < radius:
			damage_building(collider, roundi(damage * (1.0 - distance / radius)))


func building_info(collider: Object) -> Dictionary:
	var building := _buildings.get(collider) as Building
	if building == null:
		return {}
	return {"name": building.label, "health": building.health, "max_health": building.max_health}


func building_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for collider: StaticBody3D in _buildings:
		var building := _buildings[collider] as Building
		var at := collider.global_position
		snapshots.append({
			"name": building.label, "health": building.health, "max_health": building.max_health,
			"x": at.x, "z": at.z, "width": building.cover.size.x, "depth": building.cover.size.y,
			"destroyed": building.health == 0,
		})
	return snapshots


func reset_buildings() -> void:
	cover_rects.assign(_permanent_cover)
	for building: Building in _buildings.values():
		building.health = building.max_health
		building.collider.collision_layer = 1
		building.intact.show()
		if building.rubble != null:
			building.rubble.hide()
		cover_rects.append(building.cover)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(288, 288)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("stage_index", _stage_index)
	var ground := MeshInstance3D.new()
	ground.name = "Meadow"
	ground.mesh = plane
	ground.material_override = material
	add_child(ground)
	_add_static_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))


func _build_cover(center: Vector2, turned: bool) -> void:
	var cover := _add_static_box(
		Vector3(center.x, 0, center.y), WALL_SIZE, Vector3.UP * WALL_SIZE.y * 0.5
	)
	cover.name = "StoneWall"
	if turned:
		cover.rotation.y = PI * 0.5
	var footprint := Vector2(WALL_SIZE.x, WALL_SIZE.z)
	if turned:
		footprint = Vector2(footprint.y, footprint.x)
	cover_rects.append(Rect2(center - footprint * 0.5, footprint))

	if _wall_scene == null:
		_box_visual(cover, Vector3.UP * WALL_SIZE.y * 0.5, WALL_SIZE, _material(Color("#807360")))
		return

	var model := _wall_scene.instantiate() as Node3D
	cover.add_child(model)
	var bounds := _model_bounds(model)
	if bounds.has_volume():
		model.scale = WALL_SIZE / bounds.size
		model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * model.scale


func _model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var model_from_world := model.global_transform.affine_inverse()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var transformed := (model_from_world * mesh.global_transform) * mesh.get_aabb()
		bounds = bounds.merge(transformed) if bounds.has_volume() else transformed
	return bounds


func _build_boundary() -> void:
	var edge_x := ARENA_HALF_SIZE.x
	var edge_z := ARENA_HALF_SIZE.y
	var visible_east := LAND_LIMIT if _stage_index == 2 else edge_x
	var span := visible_east + edge_x
	var center := (visible_east - edge_x) * 0.5
	var fence := _material(Color("#786353"))
	var posts: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		_add_static_box(Vector3(side * (edge_x + 0.25), 1.0, 0.0), Vector3(0.5, 2.0, edge_z * 2.0 + 1.0))
		_add_static_box(Vector3(0.0, 1.0, side * (edge_z + 0.25)), Vector3(edge_x * 2.0, 2.0, 0.5))
		for rail_y in [0.37, 0.76]:
			if _stage_index != 2 or side < 0.0:
				_box_visual(self, Vector3(side * edge_x, rail_y, 0), Vector3(0.11, 0.13, edge_z * 2.0), fence)
			_box_visual(self, Vector3(center, rail_y, side * edge_z), Vector3(span, 0.13, 0.11), fence)
		for index in range(-12, 13):
			if _stage_index != 2 or side < 0.0:
				posts.append(_fence_post(Vector3(side * edge_x, 0, index * 3.0)))
			if index * 3.17 < visible_east - 0.4:
				posts.append(_fence_post(Vector3(index * 3.17, 0, side * edge_z)))
		for corner_x in [-edge_x, visible_east]:
			posts.append(_fence_post(Vector3(corner_x, 0, side * edge_z)))
	_draw_instances("FencePosts", BoxMesh.new(), fence, posts)


func _build_shore_edge() -> void:
	var frame := _material(Color("#7a6956"))
	var sun_bleached := _material(Color("#97846b"))
	var posts: Array[Transform3D] = []
	for index in range(-12, 13):
		posts.append(_fence_post(Vector3(LAND_LIMIT, 0.0, index * 3.0)))
	for height in [0.26, 0.63]:
		_box_visual(self, Vector3(LAND_LIMIT, height, 0.0), Vector3(0.16, 0.17, ARENA_HALF_SIZE.y * 2.0), sun_bleached)
	_draw_instances("ShorePosts", BoxMesh.new(), frame, posts)
	for z in [-21.0, 18.0]:
		_box_visual(self, Vector3(39.0, 0.12, z), Vector3(10.2, 0.28, 0.46), frame)
		for index in range(6):
			var height := 0.63 - 0.075 * index
			var x := 34.5 + index * 1.75
			_box_visual(self, Vector3(x, height * 0.17, z), Vector3(0.28, height, 0.34), sun_bleached)


func _fence_post(base: Vector3) -> Transform3D:
	var height := _random.randf_range(0.96, 1.18)
	var upright := Basis(Vector3.UP, _random.randf_range(-0.21, 0.21))
	return Transform3D(upright.scaled_local(Vector3(0.21, height, 0.21)), base + Vector3.UP * height * 0.5)


func _build_grass() -> void:
	var blades := SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	for yaw in [0.0, PI * 0.42, PI * 0.76]:
		var across := Vector3(cos(yaw), 0.0, sin(yaw))
		blades.set_color(Color("#6a7541"))
		blades.add_vertex(-across * 0.12)
		blades.add_vertex(across * 0.12)
		blades.set_color(Color("#92985b"))
		blades.add_vertex(Vector3.UP * 0.36 + across * 0.065)
	blades.generate_normals()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	var grass_mesh := blades.commit()
	grass_mesh.surface_set_material(0, material)
	var clumps: Array[Transform3D] = []
	var colors: Array[Color] = []
	for index in range(4750):
		var field := Vector2(_random.randf_range(-45, 45), _random.randf_range(-42, 42))
		var road_center := -1.5 + 1.8 * sin(field.y * 0.088)
		var cross_center := -0.8 * sin(field.x * 0.14)
		var village_center := -24.6 + 0.7 * sin(field.y * 0.109)
		var field_center := 24.8 - 1.3 * sin(field.y * 0.096)
		match _stage_index:
			1:
				road_center = -8.9 + 1.8 * sin(field.y * 0.113)
				cross_center = signf(field.y) * (16.5 - 0.65 * sin(field.x * 0.17))
				field_center = 20.9 - 1.35 * sin(field.y * 0.12)
			2:
				if field.x > 27.0 or field.y < -37.0:
					continue
				road_center = -3.6 + 2.0 * sin(field.y * 0.072)
				cross_center = -4.7 - 0.9 * sin(field.x * 0.11)
				village_center = -21.1 + 0.7 * sin(field.y * 0.078)
				field_center = 26.2 - 1.04 * sin(field.y * 0.09)
		if absf(field.x - road_center) < 3.55 or absf(field.y - cross_center) < 2.85:
			continue
		if absf(field.x - village_center) < 3.65 and absf(field.y) < 28:
			continue
		if absf(field.x - field_center) < 2.65 and absf(field.y) < 27:
			continue
		if absf(absf(field.y) - 24.0 + 0.65 * sin(field.x * 0.2)) < 2.25 and field.x > 0 and field.x < 28:
			continue
		var height := _random.randf_range(0.35, 1.18)
		var in_crop := _stage_index == 0 and field.x > 11 and field.x < 33 and absf(field.y) < 30
		if in_crop:
			height *= 0.68
		var blade_basis := Basis(Vector3.UP, _random.randf_range(0.0, TAU)).scaled(Vector3(height, height, height))
		clumps.append(Transform3D(blade_basis, Vector3(field.x, 0.01, field.y)))
		colors.append(Color("#f8c47e") if in_crop else Color.WHITE)
	var grass := MultiMesh.new()
	grass.transform_format = MultiMesh.TRANSFORM_3D
	grass.use_colors = true
	grass.mesh = grass_mesh
	grass.instance_count = clumps.size()
	for index in clumps.size():
		grass.set_instance_transform(index, clumps[index])
		grass.set_instance_color(index, colors[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "MeadowGrass"
	instance.multimesh = grass
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _build_hedgerows() -> void:
	var crowns: Array[Transform3D] = []
	var crown_colors: Array[Color] = []
	var limbs: Array[Transform3D] = []
	var leaves: Array[Color] = [
		Color("#49573b"), Color("#62704a"), Color("#556442"), Color("#6a7252")
	]
	for side in [-1.0, 1.0]:
		for index in range(22):
			var base := Vector3(side * _random.randf_range(42.2, 45.4), 0, -36.0 + index * 3.43)
			if _stage_index != 2 or side < 0.0:
				_shrub_transforms(base, crowns)
		for index in range(19):
			var base := Vector3(-38.0 + index * 4.15, 0, side * _random.randf_range(39.4, 44.0))
			if absf(base.x + 2.0) > 4.1 and (_stage_index != 2 or (side > 0.0 and base.x < 25.0)):
				_shrub_transforms(base, crowns)

	var trees: Array[Vector3] = [
		Vector3(-43, 0, -28), Vector3(-47, 0, -24), Vector3(-45, 0, -6),
		Vector3(-44, 0, 14), Vector3(-46, 0, 29), Vector3(-43, 0, 34),
		Vector3(11, 0, -41), Vector3(-14, 0, -40), Vector3(-23, 0, -42),
		Vector3(9, 0, 41), Vector3(15, 0, 44), Vector3(-15, 0, 42),
	]
	for index in range(16):
		var bank := _random.randf_range(42.8, 48.0)
		var row := -35.0 + index * 4.75
		trees.append(Vector3(bank, 0, row + _random.randf_range(-1.1, 1.1)))
	for base in trees:
		if _stage_index == 2 and (base.x > 27.0 or base.z < -35.0):
			continue
		var height := _random.randf_range(4.4, 7.2)
		var spread := _random.randf_range(0.8, 1.45)
		var top := base + Vector3(_random.randf_range(-0.7, 0.7), height, _random.randf_range(-0.7, 0.7))
		limbs.append(_branch_transform(base, top, height * 0.044))
		for index in range(7):
			var angle := TAU / 7.0 * index + _random.randf_range(-0.22, 0.22)
			var offset := Vector3(cos(angle) * spread, _random.randf_range(-0.85, 0.35), sin(angle) * spread)
			var radius := _random.randf_range(2.05, 3.55)
			crowns.append(_crown_transform(top + offset, Vector3(radius * spread, radius * 0.83, radius * spread)))
			if index % 2 == 0:
				var fork := base.lerp(top, _random.randf_range(0.36, 0.63))
				limbs.append(_branch_transform(fork, top + offset * 1.2, height * 0.019))
		crowns.append(_crown_transform(top + Vector3.UP * 0.96, Vector3(2.6 * spread, 3.18, 2.6 * spread)))

	for index in crowns.size():
		crown_colors.append(leaves[_random.randi_range(0, leaves.size() - 1)])
	var leaf_material := _material(Color.WHITE)
	leaf_material.vertex_color_use_as_albedo = true
	_draw_instances("LeafClusters", _canopy_mesh(), leaf_material, crowns, crown_colors)

	var branch := CylinderMesh.new()
	branch.top_radius = 0.37
	branch.bottom_radius = 1.0
	branch.height = 1.0
	branch.radial_segments = 7
	_draw_instances("TreeTrunks", branch, _material(Color("#5c5040")), limbs)


func _shrub_transforms(base: Vector3, crowns: Array[Transform3D]) -> void:
	for index in range(3):
		var offset := Vector3(_random.randf_range(-0.65, 0.65), _random.randf_range(0.15, 0.55), _random.randf_range(-0.70, 0.70))
		var spread := _random.randf_range(1.0, 2.28)
		crowns.append(_crown_transform(base + offset, Vector3(spread, spread * 0.83, spread)))


func _crown_transform(at: Vector3, size: Vector3) -> Transform3D:
	var rotation := Vector3(_random.randf_range(-0.30, 0.30), _random.randf_range(0.0, TAU), _random.randf_range(-0.32, 0.32))
	return Transform3D(Basis.from_euler(rotation).scaled_local(size), at)


func _branch_transform(start: Vector3, finish: Vector3, width: float) -> Transform3D:
	var span := finish - start
	var basis := Basis(Quaternion(Vector3.UP, span.normalized()))
	return Transform3D(basis.scaled_local(Vector3(width, span.length(), width)), (start + finish) * 0.5)


func _canopy_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 15
	sphere.rings = 8
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 141
	noise.frequency = 8.1
	for index in vertices.size():
		var vertex := vertices[index]
		vertices[index] = vertex * (1.0 + 0.37 * noise.get_noise_3dv(vertex))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _draw_instances(
	node_name: String, mesh: Mesh, material: Material, placements: Array[Transform3D], colors: Array[Color] = []
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = placements.size()
	for index in placements.size():
		multimesh.set_instance_transform(index, placements[index])
		if multimesh.use_colors:
			multimesh.set_instance_color(index, colors[index])
	var foliage := MultiMeshInstance3D.new()
	foliage.name = node_name
	foliage.multimesh = multimesh
	foliage.material_override = material
	add_child(foliage)


func _build_village() -> void:
	var shader := Shader.new()
	shader.code = BUILDING_SHADER
	var limestone := _building_material(shader, Color("#988878"))
	var plaster := _building_material(shader, Color("#b1a690"))
	var rubble := _building_material(shader, Color("#837765"))
	var slate := _building_material(shader, Color("#4e5355"), true)
	var tile := _building_material(shader, Color("#735849"), true)
	var timber := _material(Color("#51483b"))
	if _stage_index == 1:
		_add_barn(Vector3(-26.0, 0, 16.5), 0.0, Vector2(6.2, 7.3), rubble, slate, timber, 3.2, 96, "谷地农舍")
		_add_barn(Vector3(-29.0, 0, -22.0), 0.0, Vector2(7.2, 7.8), limestone, tile, timber, 4.6, 104, "山北民居")
		_add_barn(Vector3(1.5, 0, -20.3), 0.0, Vector2(5.6, 6.8), plaster, slate, timber, 3.5, 94, "山路仓房")
		_add_barn(Vector3(32.0, 0, -29.0), 0.0, Vector2(6.4, 6.1), rubble, slate, timber, 3.6, 96, "山坡谷仓")
		_add_barn(Vector3(29.0, 0, 17.0), 0.0, Vector2(6.4, 8.0), limestone, tile, timber, 4.0, 102, "东侧石屋")
		_add_barn(Vector3(8.9, 0, 22.2), 0.0, Vector2(5.4, 5.8), plaster, tile, timber, 2.8, 88, "山南工棚")
		return
	if _stage_index == 2:
		_add_barn(Vector3(-28.0, 0, -5.0), 0.0, Vector2(8.0, 8.1), limestone, slate, timber, 4.7, 104, "西湾仓库")
		_add_barn(Vector3(-21.6, 0, 11.1), 0.0, Vector2(7.0, 9.4), plaster, tile, timber, 4.2, 102, "盐场民居")
		_add_barn(Vector3(-12.0, 0, -21.0), 0.0, Vector2(5.8, 7.4), rubble, tile, timber, 3.3, 94, "海湾小屋")
		_add_barn(Vector3(9.0, 0, -19.0), 0.0, Vector2(5.8, 6.6), plaster, slate, timber, 4.5, 98, "北岸农舍")
		_add_barn(Vector3(20.6, 0, 7.1), 0.0, Vector2(5.8, 8.4), limestone, tile, timber, 3.5, 96, "岸边仓房")
		_add_barn(Vector3(18.0, 0, 20.7), 0.0, Vector2(4.6, 5.2), rubble, slate, timber, 2.7, 88, "沙地工棚")
		return
	_add_barn(Vector3(-34.0, 0, -13.0), 0.0, Vector2(7.6, 10.0), limestone, slate, timber, 4.9, 104, "石砌农舍")
	_add_barn(Vector3(-34.5, 0, 8.3), 0.0, Vector2(7.0, 9.4), rubble, tile, timber, 3.2, 94, "西侧牲口棚")
	_add_barn(Vector3(-31.9, 0, 24.5), 0.0, Vector2(6.2, 7.5), plaster, slate, timber, 3.6, 92, "南侧民居")
	_add_barn(Vector3(-15.1, 0, -18.5), 0.0, Vector2(7.4, 8.6), rubble, slate, timber, 3.4, 96, "北侧谷仓")
	_add_barn(Vector3(-15.7, 0, 8.2), 0.0, Vector2(7.6, 9.8), plaster, tile, timber, 4.6, 102, "村口大屋")
	_add_barn(Vector3(31.5, 0, 21.5), 0.0, Vector2(6.0, 5.0), limestone, tile, timber, 2.8, 88, "田边工棚")


func _building_material(shader: Shader, color: Color, tiled := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("paint", color)
	material.set_shader_parameter("tiled_roof", tiled)
	return material


func _add_farm_buildings() -> void:
	var plaster := _material(Color("#a29a82"))
	var slate := _material(Color("#5b5550"))
	var timber := _material(Color("#625344"))
	if _stage_index != 2:
		_add_barn(Vector3(51, 0, -40), 0.38, Vector2(7.6, 8.5), plaster, slate, timber, 3.5)
	_add_barn(Vector3(-46, 0, 48), -0.76, Vector2(7.0, 8.0), plaster, slate, timber, 3.2)


func _add_barn(
	at: Vector3, yaw: float, size: Vector2, walls: Material, roof: Material, timber: Material,
	eave: float, health := 0, label := ""
) -> void:
	var playable := health > 0
	var barn := Node3D.new()
	barn.name = "VillageBuilding" if playable else "DistantFarm"
	barn.position = at
	barn.rotation.y = yaw
	add_child(barn)
	var rise := size.x * 0.23
	var pitch := atan2(rise, size.x * 0.5)
	var panel_length := Vector2(rise, size.x * 0.5).length() + 0.22
	_box_visual(barn, Vector3.UP * eave * 0.5, Vector3(size.x, eave, size.y), walls)
	var gables := SurfaceTool.new()
	gables.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var panel := _box_visual(
			barn, Vector3(side * size.x * 0.25, eave + rise * 0.5, 0),
			Vector3(panel_length, 0.16, size.y + 0.37), roof
		)
		panel.rotation.z = -side * pitch
		var end: float = side * size.y * 0.5
		gables.add_vertex(Vector3(-side * size.x * 0.5, eave, end))
		gables.add_vertex(Vector3(0, eave + rise, end))
		gables.add_vertex(Vector3(side * size.x * 0.5, eave, end))
		_box_visual(barn, Vector3(0, 1.05, end + side * 0.035), Vector3(2.0, 2.1, 0.10), timber)
	gables.generate_normals()
	_place_mesh(barn, gables.commit(), walls, Vector3.ZERO)
	if playable:
		_add_building_trim(barn, size, eave, rise, walls, roof, timber)
		var footprint := size + Vector2(0.30, 0.42)
		var solid_height := eave + rise
		var solid := _add_static_box(at, Vector3(footprint.x, solid_height, footprint.y), Vector3.UP * solid_height * 0.5)
		solid.name = "BuildingCollision"
		var building := Building.new()
		building.label = label
		building.health = health
		building.max_health = health
		building.cover = Rect2(Vector2(at.x, at.z) - footprint * 0.5, footprint)
		building.collider = solid
		building.intact = barn
		_buildings[solid] = building
		cover_rects.append(building.cover)


func _add_building_trim(
	building: Node3D, size: Vector2, eave: float, rise: float, walls: Material, roof: Material, timber: Material
) -> void:
	var side := 1.0 if building.position.x < -24.0 else -1.0
	var edge := size.x * 0.5 * side
	var frame_x := edge + side * 0.047
	_box_visual(building, Vector3(edge, 0.24, 0.0), Vector3(0.10, 0.48, size.y), timber)
	_box_visual(building, Vector3(frame_x, 1.03, -size.y * 0.26), Vector3(0.11, 2.06, 1.35), timber)
	var dark_glass := _material(Color("#333b35"))
	for z in [-size.y * 0.02, size.y * 0.28]:
		_add_window(building, frame_x, z, 1.80, 0.81, timber, dark_glass)
		if eave > 4.2:
			_add_window(building, frame_x, z, 3.46, 0.74, timber, dark_glass)
	if eave > 3.55:
		var stack_y := eave + rise * 0.75
		var offset := Vector3(-side * size.x * 0.22, stack_y, size.y * 0.32)
		_box_visual(building, offset, Vector3(0.62, 1.78, 0.70), walls)
		_box_visual(building, offset + Vector3.UP * 0.93, Vector3(0.78, 0.16, 0.86), roof)


func _add_window(
	building: Node3D, x: float, z: float, y: float, height: float, timber: Material, glass: Material
) -> void:
	var outward := signf(x)
	_box_visual(building, Vector3(x, y, z), Vector3(0.13, height + 0.12, 1.16), timber)
	_box_visual(building, Vector3(x + outward * 0.056, y, z), Vector3(0.04, height, 0.74), glass)
	_box_visual(building, Vector3(x + outward * 0.081, y, z), Vector3(0.04, height + 0.005, 0.044), timber)


func _add_static_box(at: Vector3, size: Vector3, shape_offset := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	var box := BoxShape3D.new()
	box.size = size
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = shape_offset
	body.add_child(collision)
	add_child(body)
	return body


func _box_visual(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _place_mesh(parent, box, material, at)


func _place_mesh(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	return material
