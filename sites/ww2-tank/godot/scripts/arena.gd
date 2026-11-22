extends Node3D

signal building_destroyed(at: Vector3)

const BuildingRubble = preload("res://scripts/building_rubble.gd")
const StageTerrain = preload("res://scripts/stage_terrain.gd")

const WALL_MODEL := "res://assets/stone-wall.glb"
const WALL_SIZE := Vector3(5.5, 1.65, 1.32)
const ARENA_HALF_SIZE := Vector2(41.0, 38.0)
const LAND_LIMIT := -33.0
const SPAWN_LAYOUTS := [
	{
		"player": [Vector2(-10, 31)],
		"friendly_tank": [Vector2(-22, 29), Vector2(1, 31), Vector2(-5, 35), Vector2(13, 31)],
		"friendly_infantry": [Vector2(-3, 22), Vector2(16, 24)],
		"friendly_aircraft": [Vector2(-25, 29), Vector2(23, 25)],
		"hostile_tank": [Vector2(8, -30), Vector2(-6, -29), Vector2(23, -29), Vector2(-22, -32)],
		"hostile_infantry": [Vector2(0, -22), Vector2(16, -24)],
		"hostile_aircraft": [Vector2(23, -28), Vector2(-24, -26)],
	},
	{
		"player": [Vector2(14, 29)],
		"friendly_tank": [Vector2(0, 34), Vector2(23, 33), Vector2(-16, 29), Vector2(-28, 30)],
		"friendly_infantry": [Vector2(10, 21), Vector2(27, 24)],
		"friendly_aircraft": [Vector2(-25, 27), Vector2(26, 26)],
		"hostile_tank": [Vector2(0, -30), Vector2(14, -32), Vector2(-15, -33), Vector2(30, -31)],
		"hostile_infantry": [Vector2(-5, -25), Vector2(20, -26)],
		"hostile_aircraft": [Vector2(24, -29), Vector2(-26, -28)],
	},
	{
		"player": [Vector2(0, 22)],
		"friendly_tank": [Vector2(-10, 24), Vector2(11, 26), Vector2(-22, 27), Vector2(24, 26)],
		"friendly_infantry": [Vector2(5, 16), Vector2(-14, 16)],
		"friendly_aircraft": [Vector2(-23, 24), Vector2(25, 22)],
		"hostile_tank": [Vector2(0, -26), Vector2(-12, -26), Vector2(12, -27), Vector2(24, -26)],
		"hostile_infantry": [Vector2(-24, -27), Vector2(30, -24)],
		"hostile_aircraft": [Vector2(25, -29), Vector2(-25, -30)],
	},
]

class Building extends RefCounted:
	var label: String
	var health: int
	var max_health: int
	var footprint: Vector2
	var cover: Rect2
	var collider: StaticBody3D
	var intact: Node3D
	var rubble: Node3D

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
var _region_variant := 0
var _campaign_height: Callable
var _permanent_cover: Array[Rect2] = []
var _buildings: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _wall_scene: PackedScene


func configure(stage_index: int) -> void:
	_stage_index = clampi(stage_index, 0, 2)


func configure_region(stage_index: int, origin_z: float, shared_height: Callable, variant := 0) -> void:
	configure(stage_index)
	position.z = origin_z
	_campaign_height = shared_height
	_region_variant = variant


func ground_height(at: Vector2) -> float:
	if _campaign_height.is_valid():
		return _campaign_height.call(at + Vector2(position.x, position.z))
	return StageTerrain.ground_height(_stage_index, at)


func is_ground_navigable(at: Vector2) -> bool:
	return absf(at.x) <= ARENA_HALF_SIZE.x and absf(at.y) <= ARENA_HALF_SIZE.y \
		and (_stage_index != 2 or at.y >= LAND_LIMIT)


func get_spawns(friendly: bool, kind: String) -> Array[Vector3]:
	var faction := "friendly_" if friendly else "hostile_"
	var key := kind if kind == "player" else faction + kind
	var positions: Array[Vector3] = []
	for field: Vector2 in SPAWN_LAYOUTS[_stage_index].get(key, []):
		var at := _on_ground(field)
		if kind == "aircraft":
			at.y += 9.0 + 0.75 * positions.size()
		positions.append(at)
	return positions


func _on_ground(at: Vector2, offset := 0.0) -> Vector3:
	return Vector3(at.x, ground_height(at) + offset, at.y)


func _ready() -> void:
	_random.seed = 527643 + _stage_index * 421 + _region_variant * 1349
	if ResourceLoader.exists(WALL_MODEL):
		_wall_scene = load(WALL_MODEL) as PackedScene
	if not _campaign_height.is_valid():
		add_child(StageTerrain.ground(_stage_index))
		_build_boundary()
	match _stage_index:
		1:
			_build_hill_cover()
		2:
			_build_coast_cover()
		_:
			_build_plain_cover()
	_permanent_cover.assign(cover_rects)
	_build_village()
	_build_grass()
	_build_trees()


func _build_plain_cover() -> void:
	_build_cover(Vector2(-7, 8), 0.0)
	_build_cover(Vector2(-14, 2), 0.0)
	_build_cover(Vector2(4.2, -11), PI * 0.5)
	_build_cover(Vector2(17, -12), 0.0)
	_build_cover(Vector2(25, -8), 0.0)
	_build_cover(Vector2(20, 17), PI * 0.5)
	_build_cover(Vector2(29, 19), PI * 0.5)
	_build_cover(Vector2(-28, 21), PI * 0.5)
	_build_cover(Vector2(-19, -12), PI * 0.5)
	_build_bales()


func _build_hill_cover() -> void:
	if _region_variant == 1:
		_build_cover(Vector2(-20.0, 17.0), 0.11)
		_build_cover(Vector2(-10.5, 4.0), 0.04)
		_build_cover(Vector2(16.4, -11.5), PI * 0.5)
		_build_cover(Vector2(24.6, 0.8), -0.19)
		_build_cover(Vector2(-27.8, -16.6), PI * 0.5)
		_build_hill_boulders()
		return
	_build_cover(Vector2(5.1, 18.0), PI * 0.5)
	_build_cover(Vector2(-2.8, 11.0), PI * 0.5)
	_build_cover(Vector2(13, 7.0), PI * 0.5)
	_build_cover(Vector2(8.8, -6.4), PI * 0.5)
	_build_cover(Vector2(-9.2, -8.0), PI * 0.5)
	_build_cover(Vector2(-17.6, 8.0), PI * 0.5)
	_build_cover(Vector2(20.0, -14.0), PI * 0.5)
	_build_cover(Vector2(32.0, 14.0), PI * 0.5)
	_build_hill_boulders()


func _build_coast_cover() -> void:
	if not _campaign_height.is_valid():
		add_child(StageTerrain.sea())
		var water_barrier := _add_static_box(
			Vector3(0.0, -0.56, (LAND_LIMIT - ARENA_HALF_SIZE.y) * 0.5),
			Vector3(ARENA_HALF_SIZE.x * 2.0, 1.35, LAND_LIMIT + ARENA_HALF_SIZE.y)
		)
		water_barrier.name = "ShorelineLimit"

	var sandbags := _material(Color("#9c8965"))
	var covers := [
		[Vector2(-31, 2), 0.10, 9.1],
		[Vector2(-19, 0.5), -0.15, 7.7],
		[Vector2(-2.5, 3.5), 0.24, 7.1],
		[Vector2(10.5, 4.3), -0.28, 6.9],
		[Vector2(25, -0.5), -0.07, 7.8],
		[Vector2(35, 2.6), -0.26, 5.0],
		[Vector2(-24, 12.5), PI * 0.5, 6.0],
		[Vector2(24, 13.4), PI * 0.5, 6.0],
	]
	var bags: Array[Transform3D] = []
	var defense_shift := Vector2(0.0, -12.0) if _campaign_height.is_valid() else Vector2.ZERO
	for segment: Array in covers:
		_build_sandbag_wall(segment[0] + defense_shift, segment[1], segment[2], bags)
	var bag := CapsuleMesh.new()
	bag.radius = 0.24
	bag.height = 0.95
	bag.radial_segments = 8
	bag.rings = 3
	_draw_instances("SandbagBreastworks", bag, sandbags, bags)
	_build_beach_obstacles()
	_build_landings()


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
			rubble.basis = _ground_basis(Vector2(rubble.position.x, rubble.position.z), building.intact.basis)
			rubble.build(building.footprint, hash(building.label))
			building.rubble = rubble
			add_child(rubble)
		building.rubble.show()
		building_destroyed.emit(building.collider.global_position)
	return true


func _ground_basis(at: Vector2, heading: Basis) -> Basis:
	var along := heading.x
	var across := heading.z
	along.y = _ground_slope(at, along)
	across.y = _ground_slope(at, across)
	return Basis(along, across.cross(along), across).orthonormalized()


func _ground_slope(at: Vector2, axis: Vector3) -> float:
	var offset := Vector2(axis.x, axis.z) * 1.25
	return (ground_height(at + offset) - ground_height(at - offset)) / 2.5


func damage_buildings_in_area(center: Vector3, radius: float, damage: int) -> void:
	var local := to_local(center)
	var blast := Vector2(local.x, local.z)
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
			"x": at.x, "y": at.y, "z": at.z, "width": building.cover.size.x, "depth": building.cover.size.y,
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


func _build_cover(center: Vector2, yaw: float) -> void:
	var at := _on_ground(center)
	var slope := _ground_basis(center, Basis(Vector3.UP, yaw))
	for side in [-1.0, 1.0]:
		var end: Vector3 = slope.x * (side * WALL_SIZE.x * 0.5)
		var end_height := ground_height(center + Vector2(end.x, end.z)) - end.y
		at.y = minf(at.y, end_height)
	var shape_center := Vector3.UP * WALL_SIZE.y * 0.5
	var cover := _add_static_box(at, WALL_SIZE, shape_center)
	cover.name = "StoneWall"
	cover.basis = slope
	var projected_center := cover.transform * shape_center
	var projected_size := slope.x.abs() * WALL_SIZE.x + slope.y.abs() * WALL_SIZE.y + slope.z.abs() * WALL_SIZE.z
	var footprint := Vector2(projected_size.x, projected_size.z)
	cover_rects.append(Rect2(Vector2(projected_center.x, projected_center.z) - footprint * 0.5, footprint))
	if _wall_scene == null:
		_box_visual(cover, shape_center, WALL_SIZE, _material(Color("#807360")))
		return
	var model := _wall_scene.instantiate() as Node3D
	cover.add_child(model)
	var bounds := _model_bounds(model)
	if bounds.has_volume():
		model.scale = WALL_SIZE / bounds.size
		model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * model.scale


func _record_cover(center: Vector2, size: Vector2, yaw: float) -> Rect2:
	var cosine := absf(cos(yaw))
	var sine := absf(sin(yaw))
	var footprint := Vector2(size.x * cosine + size.y * sine, size.x * sine + size.y * cosine)
	var rect := Rect2(center - footprint * 0.5, footprint)
	cover_rects.append(rect)
	return rect


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
	for side in [-1.0, 1.0]:
		var side_wall := _add_static_box(
			Vector3(side * (edge_x + 0.25), 7.0, 0.0), Vector3(0.5, 25.0, edge_z * 2.0 + 1.0)
		)
		side_wall.name = "BattlefieldLimit"
		var end_wall := _add_static_box(
			Vector3(0.0, 7.0, side * (edge_z + 0.25)), Vector3(edge_x * 2.0, 25.0, 0.5)
		)
		end_wall.name = "BattlefieldLimit"
	if _stage_index != 0:
		return

	var fence := _material(Color("#77614a"))
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		for index in range(-12, 13):
			posts.append(_fence_post(_on_ground(Vector2(side * (edge_x + 0.15), index * 3.02))))
			posts.append(_fence_post(_on_ground(Vector2(index * 3.40, side * (edge_z + 0.15)))))
		for index in range(-12, 12):
			var a_side := _on_ground(Vector2(side * (edge_x + 0.15), index * 3.02))
			var b_side := _on_ground(Vector2(side * (edge_x + 0.15), (index + 1) * 3.02))
			var a_end := _on_ground(Vector2(index * 3.40, side * (edge_z + 0.15)))
			var b_end := _on_ground(Vector2((index + 1) * 3.40, side * (edge_z + 0.15)))
			for rail_height in [0.38, 0.78]:
				var offset: Vector3 = Vector3.UP * rail_height
				rails.append(_branch_transform(a_side + offset, b_side + offset, 0.115))
				rails.append(_branch_transform(a_end + offset, b_end + offset, 0.115))
	_draw_instances("FieldFencePosts", BoxMesh.new(), fence, posts)
	_draw_instances("FieldFenceRails", BoxMesh.new(), fence, rails)


func _build_bales() -> void:
	var straw := CylinderMesh.new()
	straw.top_radius = 0.77
	straw.bottom_radius = 0.79
	straw.height = 1.30
	straw.radial_segments = 14
	var straw_shell := _material(Color("#a0834b"))
	var twine := _material(Color("#78633d"))
	var bales: Array[Transform3D] = []
	var rings: Array[Transform3D] = []
	for field: Vector2 in [Vector2(12, -19), Vector2(21, -21), Vector2(30, -22), Vector2(18, 5),
		Vector2(27, 4), Vector2(33, 9), Vector2(13, 18), Vector2(25, 25), Vector2(33, 29)]:
		var yaw := _random.randf_range(-0.35, 0.37)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5)
		var at := _on_ground(field, 0.73)
		bales.append(Transform3D(basis, at))
		for y in [-0.41, 0.41]:
			rings.append(Transform3D(basis, at + basis.y * y))
		var body := _add_static_box(at, Vector3(1.35, 1.43, 1.48))
		body.name = "HayBale"
		body.rotation.y = yaw
		_record_cover(field, Vector2(1.35, 1.48), yaw)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.784
	ring.bottom_radius = 0.792
	ring.height = 0.055
	ring.radial_segments = 14
	_draw_instances("HarvestBales", straw, straw_shell, bales)
	_draw_instances("BaleTwine", ring, twine, rings)


func _build_hill_boulders() -> void:
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	var rock_material := _material(Color.WHITE)
	rock_material.vertex_color_use_as_albedo = true
	var stones: Array[Transform3D] = []
	var tints: Array[Color] = []
	for field: Vector2 in [Vector2(-35, 20), Vector2(-31, -10), Vector2(-34, -22),
		Vector2(-14, -3), Vector2(-19, 15), Vector2(-17, -18), Vector2(16, 14),
		Vector2(21, 21), Vector2(23, 7), Vector2(34, -5), Vector2(37, -16), Vector2(9, -20)]:
		var at := _on_ground(field, 0.40)
		var size := Vector3(_random.randf_range(1.55, 2.15), _random.randf_range(1.4, 1.85), _random.randf_range(1.43, 2.20))
		var yaw := _random.randf_range(-0.8, 0.8)
		var tilt := Basis.from_euler(Vector3(0.23, yaw, 0.34))
		stones.append(Transform3D(tilt.scaled_local(size), at))
		stones.append(Transform3D(tilt.scaled_local(size * 0.56), at + Vector3(-size.x * 0.57, -0.25, 0.38)))
		tints.append(Color("#827d70").lerp(Color("#a4947d"), _random.randf()))
		tints.append(Color("#817a6b"))
		var body := _add_static_box(at, size * 0.86)
		body.name = "Boulder"
		body.rotation.y = yaw
		_record_cover(field, Vector2(size.x, size.z) * 0.86, yaw)
	_draw_instances("ExposedRock", rock, rock_material, stones, tints)


func _build_sandbag_wall(center: Vector2, yaw: float, length: float, bags: Array[Transform3D]) -> void:
	var axis := Vector2(cos(yaw), -sin(yaw))
	var count := maxi(2, roundi(length / 0.77))
	for layer in 3:
		var rows := count - (1 if layer == 1 else 0)
		for index in rows:
			var at := _on_ground(center + axis * (float(index) - (rows - 1) * 0.5) * 0.76, 0.20 + layer * 0.31)
			var turn := Basis(Vector3.UP, yaw + _random.randf_range(-0.082, 0.082))
			var shape := turn * Basis(Vector3.FORWARD, PI * 0.5)
			bags.append(Transform3D(shape.scaled_local(Vector3(0.92, 1.0, 1.30)), at))
	# Divide the collider into short segments so it follows the dunes at each end.
	var blocks := ceili(length / 2.5)
	var width := length / blocks
	for block in blocks:
		var field := center + axis * (block * width + width * 0.5 - length * 0.5)
		var barrier := _add_static_box(_on_ground(field, 0.35), Vector3(width + 0.025, 1.16, 0.72))
		barrier.name = "SandbagWall"
		barrier.rotation.y = yaw
		_record_cover(field, Vector2(width + 0.025, 0.72), yaw)


func _build_beach_obstacles() -> void:
	var bars: Array[Transform3D] = []
	var bolts: Array[Transform3D] = []
	for field: Vector2 in [Vector2(-35, -13), Vector2(-23, -18), Vector2(-16, -12),
		Vector2(-5, -17), Vector2(7, -15), Vector2(18, -17), Vector2(25, -12), Vector2(35, -16)]:
		var base := _on_ground(field, 0.70)
		var yaw := _random.randf_range(0.0, TAU)
		var orient := Basis(Vector3.UP, yaw)
		for direction: Vector3 in [Vector3(1, 1, 0.45), Vector3(-0.23, 1, -1), Vector3(-1, 1, 0.68)]:
			var beam_axis := orient * direction.normalized()
			bars.append(_branch_transform(base - 1.18 * beam_axis, base + 1.18 * beam_axis, 0.25))
			bolts.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.5, 0.33, 0.5)), base))
		var body := _add_static_box(base - Vector3.UP * 0.10, Vector3(1.43, 1.41, 1.43))
		body.name = "SteelBeachObstacle"
		_record_cover(field, Vector2(1.43, 1.43), 0.0)
	_draw_instances("SteelBeachObstacles", BoxMesh.new(), _material(Color("#534c3d")), bars)
	_draw_instances("ObstacleJoints", BoxMesh.new(), _material(Color("#77715f")), bolts)


func _build_landings() -> void:
	var steel := _material(Color("#525c56"))
	var planks := _material(Color("#6d6a55"))
	var rim := _material(Color("#6d7665"))
	var frame := _material(Color("#414b48"))
	_add_landing_craft(Vector3(-16.0, -0.87, -38.4), 0.13, steel, planks, rim, frame)
	_add_landing_craft(Vector3(16.0, -0.88, -39.9), -0.20, steel, planks, rim, frame)
	_add_landing_craft(Vector3(-35.5, -0.88, -48.2), 0.39, steel, planks, rim, frame)
	_add_landing_craft(Vector3(35.0, -0.88, -51.0), -0.26, steel, planks, rim, frame)


func _add_landing_craft(
	at: Vector3, yaw: float, steel: Material, planks: Material, rim: Material, frame: Material
) -> void:
	var craft := Node3D.new()
	craft.name = "LandingCraft"
	craft.position = at
	craft.rotation.y = yaw
	add_child(craft)
	_box_visual(craft, Vector3(0, 0.15, -0.3), Vector3(4.05, 0.48, 8.9), steel)
	_box_visual(craft, Vector3(0, 0.42, -0.51), Vector3(3.65, 0.13, 8.35), planks)
	_box_visual(craft, Vector3(0, 1.0, -4.6), Vector3(4.07, 1.1, 0.53), steel)
	for side in [-1.0, 1.0]:
		var panel := _box_visual(craft, Vector3(side * 1.90, 1.03, -0.43), Vector3(0.38, 1.3, 8.39), steel)
		panel.rotation.z = side * -0.085
		_box_visual(craft, Vector3(side * 1.93, 1.70, -0.43), Vector3(0.34, 0.11, 8.55), rim)
		for slot in 5:
			_box_visual(craft, Vector3(side * 2.055, 1.0, -3.72 + slot * 1.66), Vector3(0.14, 1.18, 0.09), frame)
	var ramp := _box_visual(craft, Vector3(0, 0.55, 4.53), Vector3(3.60, 0.24, 3.18), steel)
	ramp.rotation.x = 0.14
	for offset in range(5):
		_box_visual(ramp, Vector3(0, 0.14, -1.2 + offset * 0.6), Vector3(3.43, 0.07, 0.12), frame)
	_box_visual(craft, Vector3(-1.04, 1.32, -3.52), Vector3(1.35, 1.50, 1.53), steel)
	_box_visual(craft, Vector3(-1.04, 1.82, -2.74), Vector3(0.85, 0.39, 0.05), frame)
	_box_visual(craft, Vector3(-1.02, 2.10, -3.55), Vector3(1.42, 0.17, 1.65), rim)


func _fence_post(base: Vector3) -> Transform3D:
	var height := _random.randf_range(0.96, 1.18)
	var upright := Basis(Vector3.UP, _random.randf_range(-0.21, 0.21))
	return Transform3D(upright.scaled_local(Vector3(0.21, height, 0.21)), base + Vector3.UP * height * 0.5)


func _build_grass() -> void:
	var blades := SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	for yaw in [0.0, PI * 0.42, PI * 0.76]:
		var across := Vector3(cos(yaw), 0.0, sin(yaw))
		blades.set_color(Color("#74834d"))
		blades.add_vertex(-across * 0.11)
		blades.add_vertex(across * 0.11)
		blades.set_color(Color("#9fa276"))
		blades.add_vertex(Vector3.UP * 0.33 + across * 0.059)
	blades.generate_normals()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	var clumps: Array[Transform3D] = []
	var colors: Array[Color] = []
	var density := 2700 if _stage_index == 2 else 5100
	if _campaign_height.is_valid():
		density = roundi(density * 0.72)
	for index in density:
		var field := Vector2(_random.randf_range(-45, 45), _random.randf_range(-42, 42))
		if StageTerrain.road_factor(_stage_index, field) < 1.0:
			continue
		if _campaign_height.is_valid() and absf(field.x - StageTerrain.campaign_road(field.y + position.z)) < 3.7:
			continue
		var in_crop := _stage_index == 0 and field.x + 0.16 * field.y > 10.0 and field.x < 34.5 and absf(field.y) < 29.0
		var near_shore := _stage_index == 2 and StageTerrain.coast_distance(field) > -29.0
		if near_shore and (field.y < -12.0 or _random.randf() < 0.59):
			continue
		var scale := _random.randf_range(0.38, 1.34)
		var tint := Color("#d7a869") if in_crop else Color.WHITE
		if near_shore:
			tint = Color("#dbc290")
			scale *= 0.80
		var basis := Basis(Vector3.UP, _random.randf_range(0.0, TAU)).scaled(Vector3(scale, scale, scale))
		clumps.append(Transform3D(basis, _on_ground(field, 0.006)))
		colors.append(tint)
	_draw_instances("FieldGrass", blades.commit(), material, clumps, colors, false)


func _build_trees() -> void:
	match _stage_index:
		1:
			_build_pines()
		2:
			_build_coastal_scrub()
		_:
			_build_orchard()


func _build_orchard() -> void:
	var crowns: Array[Transform3D] = []
	var limbs: Array[Transform3D] = []
	for index in range(21):
		var row := -34.0 + index * 3.43
		for side in [-1.0, 1.0]:
			_shrub_transforms(_on_ground(Vector2(side * _random.randf_range(42.2, 45.4), row)), crowns)
	for index in range(18):
		var column := -37.0 + index * 4.15
		for side in [-1.0, 1.0]:
			var field := Vector2(column, side * _random.randf_range(39.4, 44.0))
			var road := StageTerrain.campaign_road(field.y + position.z) if _campaign_height.is_valid() else -2.0
			if absf(field.x - road) > 5.0:
				_shrub_transforms(_on_ground(field), crowns)
	for side in [-1.0, 1.0]:
		for field: Vector2 in [Vector2(44, -30), Vector2(47, -12), Vector2(44, 7), Vector2(45, 22), Vector2(46, 35)]:
			_broadleaf_tree(_on_ground(Vector2(field.x * side, field.y)), crowns, limbs, 5.1)
	for row in range(3):
		for column in range(4):
			var field := Vector2(-37 + column * 4.7, -31 + row * 4.3)
			_broadleaf_tree(_on_ground(field), crowns, limbs, 3.0)
	_draw_woodland(crowns, limbs, [Color("#4d582f"), Color("#64734a"), Color("#67683a"), Color("#8f7845")])


func _broadleaf_tree(base: Vector3, crowns: Array[Transform3D], limbs: Array[Transform3D], height: float) -> void:
	var spread := _random.randf_range(0.77, 1.14) * sqrt(height / 4.7)
	var top := base + Vector3(_random.randf_range(-0.59, 0.59), height, _random.randf_range(-0.57, 0.57))
	limbs.append(_branch_transform(base, top, height * 0.049))
	for index in range(5):
		var angle := TAU / 5.0 * index + _random.randf_range(-0.22, 0.22)
		var offset := Vector3(cos(angle) * spread, _random.randf_range(-0.77, 0.30), sin(angle) * spread)
		var radius := _random.randf_range(1.65, 2.55) * spread
		crowns.append(_crown_transform(top + offset, Vector3(radius, radius * 0.87, radius)))
		if index % 2 == 0:
			limbs.append(_branch_transform(base.lerp(top, 0.58), top + offset * 1.2, height * 0.021))
	crowns.append(_crown_transform(top + Vector3.UP * 0.67, Vector3(2.1, 2.35, 2.1) * spread))


func _build_pines() -> void:
	var crowns: Array[Transform3D] = []
	var limbs: Array[Transform3D] = []
	var colors: Array[Color] = []
	var cypress_tones: Array[Color] = [Color("#3d4b36"), Color("#506044"), Color("#485c40"), Color("#657057")]
	for index in range(100):
		var field := Vector2(_random.randf_range(-59, 59), _random.randf_range(-48, 48))
		if _campaign_height.is_valid() and absf(field.x - StageTerrain.campaign_road(field.y + position.z)) < 5.1:
			continue
		var on_flank := absf(field.x) > 34 or absf(field.y) > 39
		var on_spur := absf(field.x) > 15 and StageTerrain.road_factor(_stage_index, field) > 2.2
		if not on_flank and (not on_spur or index % 3 != 0):
			continue
		var at := _on_ground(field)
		var height := _random.randf_range(4.2, 7.7)
		limbs.append(_branch_transform(at, at + Vector3.UP * height * 0.95, height * 0.042))
		var tint := cypress_tones[_random.randi_range(0, cypress_tones.size() - 1)]
		for tier in 4:
			var width := height * (0.43 - tier * 0.081)
			var rotation := Basis(Vector3.UP, _random.randf_range(0.0, TAU))
			var loft := height * (0.34 + 0.17 * tier)
			crowns.append(Transform3D(rotation.scaled_local(Vector3(width, height * 0.37, width)), at + Vector3.UP * loft))
			colors.append(tint.lightened(0.025 * tier))
	var pine := CylinderMesh.new()
	pine.radial_segments = 7
	pine.top_radius = 0.0
	pine.bottom_radius = 0.55
	pine.height = 1.0
	var needles := _material(Color.WHITE)
	needles.vertex_color_use_as_albedo = true
	_draw_instances("MountainPines", pine, needles, crowns, colors)
	_draw_trunks(limbs)


func _build_coastal_scrub() -> void:
	var crowns: Array[Transform3D] = []
	var limbs: Array[Transform3D] = []
	for index in 46:
		var field := Vector2(_random.randf_range(-49, 49), _random.randf_range(-4, 49))
		if _campaign_height.is_valid() and absf(field.x - StageTerrain.campaign_road(field.y + position.z)) < 4.6:
			continue
		if absf(field.x) < 36.0 and field.y < 33.0 and index % 3 != 0:
			continue
		_shrub_transforms(_on_ground(field) - Vector3.UP * 0.12, crowns)
	for field: Vector2 in [Vector2(-43, 1), Vector2(-44, 16), Vector2(-47, 33), Vector2(-37, 39), Vector2(32, 40), Vector2(41, 38)]:
		_broadleaf_tree(_on_ground(field), crowns, limbs, 3.25)
	_draw_woodland(crowns, limbs, [Color("#70704d"), Color("#757b53"), Color("#686849"), Color("#85805d")])


func _draw_woodland(crowns: Array[Transform3D], limbs: Array[Transform3D], leaves: Array[Color]) -> void:
	var colors: Array[Color] = []
	for index in crowns.size():
		colors.append(leaves[_random.randi_range(0, leaves.size() - 1)])
	var foliage := _material(Color.WHITE)
	foliage.vertex_color_use_as_albedo = true
	_draw_instances("LeafClusters", _canopy_mesh(), foliage, crowns, colors)
	_draw_trunks(limbs)


func _draw_trunks(limbs: Array[Transform3D]) -> void:
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
	node_name: String, mesh: Mesh, material: Material, placements: Array[Transform3D],
	colors: Array[Color] = [], shadows := true
) -> void:
	if placements.is_empty():
		return
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
	if _campaign_height.is_valid():
		foliage.visibility_range_end = 146.0
		foliage.visibility_range_end_margin = 12.0
	if not shadows:
		foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foliage)


func _build_village() -> void:
	var shader := Shader.new()
	shader.code = BUILDING_SHADER
	var limestone := _building_material(shader, Color("#958472"))
	var plaster := _building_material(shader, Color("#b4a68b"))
	var rubble := _building_material(shader, Color("#76706b"))
	var slate := _building_material(shader, Color("#51585b"), true)
	var tile := _building_material(shader, Color("#7b5845"), true)
	var timber := _material(Color("#493f32"))
	if _stage_index == 1:
		if _region_variant == 1:
			_add_barn(_on_ground(Vector2(-25, 12)), -0.21, Vector2(6.2, 7.7), limestone, slate, timber, 4.2, 108, "山路仓房")
			_add_barn(_on_ground(Vector2(17, 5)), 0.27, Vector2(6.7, 7.3), rubble, slate, timber, 3.7, 106, "山坡谷仓")
			_add_barn(_on_ground(Vector2(36, -14)), -0.14, Vector2(4.4, 5.3), plaster, tile, timber, 2.8, 94, "北侧谷仓")
			return
		_add_barn(_on_ground(Vector2(-32, 9)), -0.21, Vector2(5.4, 6.3), rubble, slate, timber, 3.8, 100, "谷地农舍")
		_add_barn(_on_ground(Vector2(-7, -2)), -0.20, Vector2(5.6, 6.1), limestone, slate, timber, 3.4, 102, "山坡谷仓")
		_add_barn(_on_ground(Vector2(19, 2.5)), 0.18, Vector2(5.1, 6.6), rubble, slate, timber, 4.2, 98, "东侧石屋")
		_add_barn(_on_ground(Vector2(-25, -15)), 0.13, Vector2(5.5, 6.8), rubble, slate, timber, 4.0, 108, "山北民居")
		_add_barn(_on_ground(Vector2(35, 4)), -0.2, Vector2(5.7, 6.4), plaster, slate, timber, 2.8, 94, "山路仓房")
		_add_barn(_on_ground(Vector2(-25, 20)), -0.34, Vector2(4.4, 5.3), plaster, tile, timber, 2.8, 90, "山南工棚")
		return
	if _stage_index == 2:
		var defense_shift := Vector2(0.0, -11.0) if _campaign_height.is_valid() else Vector2.ZERO
		_add_bunker(Vector2(-24.5, 5.8) + defense_shift, -0.14, Vector2(8.0, 5.6), rubble, slate, 136, "西湾碉堡")
		_add_bunker(Vector2(26.2, 6.6) + defense_shift, 0.12, Vector2(8.8, 5.6), rubble, slate, 144, "东岸碉堡")
		var interior := Vector2(10.5, 7.5) if _campaign_height.is_valid() else Vector2(2.1, 10.0)
		_add_bunker(interior + defense_shift, 0.02, Vector2(5.7, 4.2), rubble, slate, 110, "海岸掩体")
		_add_barn(_on_ground(Vector2(-29, 24)), -0.16, Vector2(5.0, 6.3), plaster, slate, timber, 3.6, 98, "西湾仓库")
		_add_barn(_on_ground(Vector2(18, 18.5)), 0.13, Vector2(5.1, 5.9), limestone, tile, timber, 2.7, 90, "岸边仓房")
		_add_barn(_on_ground(Vector2(33, 23)), -0.30, Vector2(5.1, 6.3), plaster, tile, timber, 3.3, 96, "海湾小屋")
		return
	_add_barn(_on_ground(Vector2(-31, -11)), -0.22, Vector2(7.6, 9.0), plaster, tile, timber, 4.6, 106, "石砌农舍")
	_add_barn(_on_ground(Vector2(-33, 7)), 0.19, Vector2(6.5, 8.0), limestone, tile, timber, 3.7, 98, "西侧牲口棚")
	_add_barn(_on_ground(Vector2(-19, 12)), -0.17, Vector2(6.7, 7.8), plaster, tile, timber, 4.0, 100, "村口大屋")
	_add_barn(_on_ground(Vector2(-12, -20)), 0.18, Vector2(6.1, 6.9), limestone, slate, timber, 3.6, 94, "北侧谷仓")
	_add_barn(_on_ground(Vector2(31, 13)), 0.23, Vector2(4.5, 5.9), plaster, tile, timber, 2.9, 90, "田边工棚")
	_add_grain_mill(Vector2(-19, -5.5), limestone, slate, timber)


func _add_grain_mill(center: Vector2, stone: Material, roof: Material, wood: Material) -> void:
	var mill := Node3D.new()
	mill.name = "GrainMill"
	mill.position = _on_ground(center)
	add_child(mill)
	var tower := CylinderMesh.new()
	tower.top_radius = 1.18
	tower.bottom_radius = 1.45
	tower.height = 4.98
	tower.radial_segments = 12
	_place_mesh(mill, tower, stone, Vector3.UP * 2.26)
	var roof_mesh := CylinderMesh.new()
	roof_mesh.top_radius = 0.12
	roof_mesh.bottom_radius = 1.30
	roof_mesh.height = 1.27
	roof_mesh.radial_segments = 12
	_place_mesh(mill, roof_mesh, roof, Vector3.UP * 5.36)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 4.42, 1.54)
	rotor.rotation.z = 0.40
	mill.add_child(rotor)
	for blade in 4:
		var boom := Node3D.new()
		boom.rotation.z = blade * PI * 0.5
		rotor.add_child(boom)
		_box_visual(boom, Vector3(0, 1.28, 0), Vector3(0.13, 2.62, 0.13), wood)
		_box_visual(boom, Vector3(0.5, 1.70, 0), Vector3(0.11, 1.95, 0.09), wood)
		for spar in range(5):
			_box_visual(boom, Vector3(0.24, 0.75 + spar * 0.48, 0), Vector3(0.55, 0.09, 0.08), wood)
	_register_building(mill, Vector2(2.95, 2.95), 6.0, 108, "石砌风车")


func _add_bunker(
	center: Vector2, yaw: float, size: Vector2, concrete: Material, slab: Material, health: int, label: String
) -> void:
	var bunker := Node3D.new()
	bunker.name = "CoastalBunker"
	bunker.position = _on_ground(center)
	bunker.rotation.y = yaw
	add_child(bunker)
	var bite := _material(Color("#383832"))
	var strip := size.x * 0.66
	_box_visual(bunker, Vector3(0, -0.32, 0), Vector3(size.x, 1.95, size.y), concrete)
	_box_visual(bunker, Vector3(0, 1.24, size.y * 0.12), Vector3(size.x, 1.17, size.y * 0.68), concrete)
	_box_visual(bunker, Vector3(0, 1.20, -size.y * 0.49), Vector3(strip, 0.61, 0.09), bite)
	for side in [-1.0, 1.0]:
		_box_visual(bunker, Vector3(side * size.x * 0.42, 1.21, -size.y * 0.41), Vector3(size.x * 0.16, 1.23, size.y * 0.17), concrete)
	var deck := _box_visual(bunker, Vector3(0, 1.84, 0), Vector3(size.x + 0.58, 0.46, size.y + 0.63), slab)
	deck.rotation.x = -0.025
	_box_visual(bunker, Vector3(0, 0.38, size.y * 0.51), Vector3(1.18, 1.65, 0.095), bite)
	_register_building(bunker, size + Vector2(0.48, 0.44), 2.13, health, label)


func _building_material(shader: Shader, color: Color, tiled := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("paint", color)
	material.set_shader_parameter("tiled_roof", tiled)
	return material


func _add_barn(
	at: Vector3, yaw: float, size: Vector2, walls: Material, roof: Material, timber: Material,
	eave: float, health: int, label: String
) -> void:
	var barn := Node3D.new()
	barn.name = "VillageBuilding"
	barn.position = at
	barn.rotation.y = yaw
	add_child(barn)
	var bed := _foundation_depth(barn, size)
	_box_visual(barn, Vector3.DOWN * bed * 0.50, Vector3(size.x, bed, size.y), walls)
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
	_add_building_trim(barn, size, eave, rise, walls, roof, timber)
	_register_building(barn, size + Vector2(0.30, 0.42), eave + rise, health, label)


func _foundation_depth(structure: Node3D, size: Vector2) -> float:
	var depth := 0.26
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var at := structure.transform * Vector3(corner.x * size.x * 0.5, 0, corner.y * size.y * 0.5)
		depth = maxf(depth, structure.position.y - ground_height(Vector2(at.x, at.z)) + 0.16)
	return depth


func _register_building(visual: Node3D, footprint: Vector2, height: float, health: int, label: String) -> void:
	var at := visual.position
	var foundation := _foundation_depth(visual, footprint)
	var collider := _add_static_box(
		at, Vector3(footprint.x, height + foundation, footprint.y), Vector3.UP * (height - foundation) * 0.5
	)
	collider.name = "BuildingCollision"
	collider.rotation.y = visual.rotation.y
	var building := Building.new()
	building.label = label
	building.health = health
	building.max_health = health
	building.footprint = footprint
	building.cover = _record_cover(Vector2(at.x, at.z), footprint, visual.rotation.y)
	building.collider = collider
	building.intact = visual
	_buildings[collider] = building


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
