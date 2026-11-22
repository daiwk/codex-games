extends Node3D

const MASONRY_OUTLINE := [
	Vector2(-0.49, -0.33), Vector2(-0.31, -0.49), Vector2(0.25, -0.46), Vector2(0.48, -0.28),
	Vector2(0.46, 0.24), Vector2(0.25, 0.47), Vector2(-0.28, 0.43), Vector2(-0.46, 0.19),
]
const STONE_COLORS := [
	Color("#9d907b"), Color("#82776a"), Color("#766a59"), Color("#b4a58d"),
	Color("#96846c"), Color("#62574a"), Color("#b4a89b"),
]
const WOOD_COLORS := [Color("#594939"), Color("#71604b"), Color("#473d31")]
const TILE_COLORS := [Color("#7e6250"), Color("#695247"), Color("#534c44")]

var _random := RandomNumberGenerator.new()


func build(size: Vector2, seed_value: int) -> void:
	name = "CollapsedBuilding"
	_random.seed = seed_value
	_add_dust(size)
	var stones: Array[Transform3D] = []
	var stone_colors: Array[Color] = []
	_add_foundation(size, stones, stone_colors)
	_add_scatter(size, stones, stone_colors)
	_place_batch("StoneFragments", _stone_mesh(), stones, stone_colors)

	var beams: Array[Transform3D] = []
	var beam_colors: Array[Color] = []
	for index in range(13):
		var at := _scatter_position(size * 0.39)
		var length := _random.randf_range(0.65, 2.7)
		var width := _random.randf_range(0.085, 0.19)
		at.y = _random.randf_range(0.09, 0.26)
		var angle := _random.randf_range(0.0, TAU)
		var tilt := _random.randf_range(-0.13, 0.13)
		var basis := Basis.from_euler(Vector3(tilt, angle, tilt * 0.5))
		beams.append(Transform3D(basis.scaled_local(Vector3(width, width, length)), at))
		beam_colors.append(WOOD_COLORS[index % WOOD_COLORS.size()])
	_place_batch("BrokenTimbers", BoxMesh.new(), beams, beam_colors)


func _add_dust(size: Vector2) -> void:
	var outline: Array[Vector3] = []
	for index in range(16):
		var angle := TAU * float(index) / 16.0
		var x := cos(angle)
		var z := sin(angle)
		var rim := Vector2(signf(x) * pow(absf(x), 0.49), signf(z) * pow(absf(z), 0.49))
		rim *= size * _random.randf_range(0.49, 0.55)
		outline.append(Vector3(rim.x, 0.016, rim.y))
	var floor_mesh := SurfaceTool.new()
	floor_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in outline.size():
		floor_mesh.set_color(Color("#635747"))
		floor_mesh.add_vertex(Vector3(0.0, 0.016, 0.0))
		floor_mesh.set_color(Color("#786852"))
		floor_mesh.add_vertex(outline[index])
		floor_mesh.add_vertex(outline[(index + 1) % outline.size()])
	floor_mesh.generate_normals()
	var dust := MeshInstance3D.new()
	dust.name = "MasonryDust"
	dust.mesh = floor_mesh.commit()
	dust.material_override = _fragment_material()
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)


func _add_foundation(size: Vector2, stones: Array[Transform3D], colors: Array[Color]) -> void:
	for axis in range(2):
		var along: float = size[axis]
		var across: float = size[1 - axis]
		var segments := maxi(4, floori(along / 0.76))
		for side in [-1.0, 1.0]:
			for index in segments:
				if _random.randf() < 0.28:
					continue
				var edge := -along * 0.48 + (float(index) + 0.5) * (along * 0.96 / segments)
				var offset: float = side * across * 0.43 + _random.randf_range(-0.2, 0.2)
				var position := Vector3(edge, 0.0, offset) if axis == 0 else Vector3(offset, 0.0, edge)
				var dim := Vector3(_random.randf_range(0.53, 0.96), _random.randf_range(0.23, 0.53), _random.randf_range(0.37, 0.67))
				var heading := PI * 0.5 * axis + _random.randf_range(-0.22, 0.22)
				_append_stone(stones, colors, position, dim, heading, STONE_COLORS)


func _add_scatter(size: Vector2, stones: Array[Transform3D], colors: Array[Color]) -> void:
	var count := roundi(size.x * size.y * 0.86)
	var fallen_center := Vector2(size.x * 0.16, -size.y * 0.13)
	for index in count:
		var concentrated := index < count / 3
		var at := _scatter_position(size * (0.19 if concentrated else 0.51))
		if concentrated:
			at += Vector3(fallen_center.x, _random.randf_range(0.04, 0.17), fallen_center.y)
		var large := _random.randf() < 0.22
		var scale_factor := 1.46 if large else 0.83
		var dim := Vector3(_random.randf_range(0.32, 0.92), _random.randf_range(0.11, 0.40), _random.randf_range(0.28, 0.74)) * scale_factor
		var palette := TILE_COLORS if not large and index % 6 == 0 else STONE_COLORS
		_append_stone(stones, colors, at, dim, _random.randf_range(0.0, TAU), palette)


func _append_stone(
	placements: Array[Transform3D], colors: Array[Color], at: Vector3, dim: Vector3,
	yaw: float, palette: Array
) -> void:
	var tilt := _random.randf_range(-0.14, 0.14)
	var pose := Basis.from_euler(Vector3(tilt, yaw, -tilt * 0.7)).scaled_local(dim)
	placements.append(Transform3D(pose, at + Vector3.UP * dim.y * 0.46))
	colors.append(palette[_random.randi_range(0, palette.size() - 1)])


func _scatter_position(half_size: Vector2) -> Vector3:
	return Vector3(_random.randf_range(-half_size.x, half_size.x), 0, _random.randf_range(-half_size.y, half_size.y))


func _stone_mesh() -> ArrayMesh:
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for index in MASONRY_OUTLINE.size():
		var edge: Vector2 = MASONRY_OUTLINE[index]
		bottom.append(Vector3(edge.x * 0.91, -0.45 + 0.04 * sin(index * 2.2), edge.y * 0.94))
		top.append(Vector3(edge.x * 0.78 + 0.04, 0.44 + 0.055 * sin(index * 3.5), edge.y * 0.84 - 0.02))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for index in MASONRY_OUTLINE.size():
		var next := (index + 1) % MASONRY_OUTLINE.size()
		_triangle(tool, bottom[index], bottom[next], top[next])
		_triangle(tool, bottom[index], top[next], top[index])
		_triangle(tool, Vector3(0.025, 0.49, 0.045), top[index], top[next])
		_triangle(tool, Vector3(0.0, -0.47, 0.0), bottom[next], bottom[index])
	tool.generate_normals()
	return tool.commit()


func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


func _place_batch(
	node_name: String, mesh: Mesh, placements: Array[Transform3D], colors: Array[Color]
) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = placements.size()
	for index in placements.size():
		batch.set_instance_transform(index, placements[index])
		batch.set_instance_color(index, colors[index])
	var fragments := MultiMeshInstance3D.new()
	fragments.name = node_name
	fragments.multimesh = batch
	fragments.material_override = _fragment_material()
	add_child(fragments)


func _fragment_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.97
	return material
