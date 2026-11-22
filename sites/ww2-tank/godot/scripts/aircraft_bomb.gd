extends Node3D

const WORLD_MASK := 1
const DROP_SPEED := 17.5
const DROP_ACCELERATION := 24.0

static var _visual_mesh: ArrayMesh

var team: int
var _drop_speed := 7.5


func _ready() -> void:
	if _visual_mesh == null:
		_visual_mesh = _build_visual_mesh()
	var visual := MeshInstance3D.new()
	visual.mesh = _visual_mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)


func advance(delta: float) -> Dictionary:
	if delta <= 0.0:
		return {}
	_drop_speed = move_toward(_drop_speed, DROP_SPEED, DROP_ACCELERATION * delta)
	var start := global_position
	var end := start + Vector3.DOWN * _drop_speed * delta
	var query := PhysicsRayQueryParameters3D.create(start, end, WORLD_MASK)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	global_position = hit.get("position", end)
	return hit


static func _build_visual_mesh() -> ArrayMesh:
	var body := CapsuleMesh.new()
	body.height = 0.69
	body.radius = 0.125
	body.radial_segments = 10
	body.rings = 3
	var fin := BoxMesh.new()
	fin.size = Vector3(0.39, 0.19, 0.042)
	var fins_center := Vector3.UP * 0.61
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3.UP * 0.345))
	surface.append_from(fin, 0, Transform3D(Basis.IDENTITY, fins_center))
	surface.append_from(fin, 0, Transform3D(Basis(Vector3.UP, PI * 0.5), fins_center))
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#505347")
	paint.roughness = 0.75
	surface.set_material(paint)
	return surface.commit()
