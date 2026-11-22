extends Node3D

const Mission = preload("res://scripts/campaign_mission.gd")
const DISPLAY_DISTANCE := 96.0
const SEGMENTS := 48

var _markers: Dictionary[Vector2, Node3D] = {}


func build(ground_height: Callable) -> void:
	for index in Mission.SUPPLY_POINTS.size():
		_add_marker(Mission.SUPPLY_POINTS[index], Mission.SUPPLY_RADIUS,
			"补给点 %d" % (index + 1), Color("#a6e6be"), ground_height)
	_add_marker(Mission.DEFENSE_POINT, Mission.DEFENSE_RADIUS,
		"滩头防线", Color("#ffd58a"), ground_height)


func show_destination(destination: Vector2, advancing: bool) -> void:
	for point in _markers:
		_markers[point].visible = advancing and point == destination


func _add_marker(at: Vector2, radius: float, title: String, tint: Color, ground_height: Callable) -> void:
	var group := Node3D.new()
	var height: float = ground_height.call(at)
	group.position = Vector3(at.x, height, at.y)
	add_child(group)
	_markers[at] = group

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(tint, 0.88)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var rim_vertices := PackedVector3Array()
	for index in SEGMENTS:
		var bearing := TAU * index / SEGMENTS
		var radial := Vector2(cos(bearing), sin(bearing))
		for distance in [radius, radius - 0.22]:
			var offset: Vector2 = radial * distance
			var floor_height: float = ground_height.call(at + offset)
			rim_vertices.append(Vector3(offset.x, floor_height - height + 0.12, offset.y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in SEGMENTS:
		var first := index * 2
		var following := ((index + 1) % SEGMENTS) * 2
		for vertex in [first, first + 1, following, following, first + 1, following + 1]:
			surface.add_vertex(rim_vertices[vertex])
	var rim := MeshInstance3D.new()
	rim.mesh = surface.commit()
	rim.material_override = material
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.visibility_range_end = DISPLAY_DISTANCE
	group.add_child(rim)

	var signal_mesh := CylinderMesh.new()
	signal_mesh.height = 6.4
	signal_mesh.top_radius = 0.07
	signal_mesh.bottom_radius = 0.16
	signal_mesh.radial_segments = 10
	var signal_post := MeshInstance3D.new()
	signal_post.mesh = signal_mesh
	signal_post.material_override = material
	signal_post.position.y = 3.2
	signal_post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	signal_post.visibility_range_end = DISPLAY_DISTANCE
	group.add_child(signal_post)

	var label := Label3D.new()
	label.text = title
	label.font = preload("res://assets/fonts/StonewallSans.otf")
	label.font_size = 52
	label.pixel_size = 0.022
	label.outline_size = 11
	label.modulate = tint
	label.outline_modulate = Color("#21271d")
	label.position.y = 7.25
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = DISPLAY_DISTANCE
	group.add_child(label)
