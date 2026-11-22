extends "res://scripts/battle_unit.gd"

const NEUTRAL_MUZZLE_HEIGHT := 1.545
const DEFAULT_RAW_MUZZLE := Vector3(-0.0037, 0.2915, 0.500)
var model_id: String
var max_speed := 6.3
var hull_turn_speed := 2.4
var turret_turn_speed := 5.8

var _speed := 0.0
var _hull_pose: Node3D
var _hull_shapes: Array[CollisionShape3D] = []
var _hull_shape_centers: Array[Vector3] = []
var _turret: Node3D
var _gun: Node3D
var _muzzle: Node3D


func configure(model_scene: PackedScene, is_player: bool, profile: Dictionary, team_layer: int) -> void:
	model_id = profile["id"]
	display_name = profile["name"]
	kind = "tank"
	max_health = profile["health"]
	health = max_health
	attack = profile["attack"]
	defense = profile["defense"]
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = team_layer
	collision_mask = GROUND_UNIT_MASK
	safe_margin = 0.008

	var model := model_scene.instantiate() as Node3D
	model.rotation.y = PI
	_hull_pose = Node3D.new()
	_hull_pose.name = "HullPose"
	_hull_pose.add_child(model)
	add_child(_hull_pose)
	var hull := model.get_node("Hull") as MeshInstance3D
	var turret := model.get_node("Turret") as MeshInstance3D
	_turret = turret
	_gun = _turret.get_node("Gun") as Node3D
	_muzzle = _gun.get_node_or_null("Muzzle") as Node3D
	if _muzzle == null:
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		_muzzle.position = DEFAULT_RAW_MUZZLE - _turret.position - _gun.position
		_gun.add_child(_muzzle)
	var raw_muzzle_height := _turret.position.y + _gun.position.y + _muzzle.position.y
	var model_scale := NEUTRAL_MUZZLE_HEIGHT / raw_muzzle_height
	model.scale = Vector3.ONE * model_scale

	var hull_bounds := hull.get_aabb()
	var hull_center := (hull.position + hull_bounds.get_center()) * model_scale
	var hull_size := hull_bounds.size * model_scale * 0.978
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(hull_size.x, 1.76, hull_size.z)
	collider.shape = box
	collider.position = Vector3(-hull_center.x, 0.91, -hull_center.z)
	add_child(collider)

	var turret_hitbox := CollisionShape3D.new()
	var turret_shape := CylinderShape3D.new()
	var turret_bounds := turret.get_aabb()
	turret_shape.height = maxf(0.65, turret_bounds.size.y * model_scale)
	turret_shape.radius = clampf(turret_bounds.size.x * model_scale * 0.5 + 0.06, 0.78, 1.12)
	turret_hitbox.shape = turret_shape
	var turret_center := (_turret.position + turret_bounds.get_center()) * model_scale
	turret_hitbox.position = Vector3(-turret_center.x, maxf(turret_center.y, 1.68), -turret_center.z)
	add_child(turret_hitbox)
	_hull_shapes.assign([collider, turret_hitbox])
	_hull_shape_centers.assign([collider.position, turret_hitbox.position])

	if is_player:
		turret_turn_speed = 14.0
	else:
		max_speed = 5.2
		hull_turn_speed = 2.0
		turret_turn_speed = 2.9
		reload_time = 2.15
		reload_left = 1.65


func drive(throttle: float, steer: float, delta: float) -> void:
	var steering := steer * hull_turn_speed * delta
	_try_hull_yaw(rotation.y + steering)

	var target_speed := throttle * max_speed
	if throttle < 0.0:
		target_speed *= 0.57
	var acceleration := 9.6 if not is_zero_approx(throttle) else 13.0
	_speed = move_toward(_speed, target_speed, acceleration * delta)
	velocity = global_basis * Vector3.FORWARD * _speed
	move_on_ground(delta)
	update_hull_pose(delta)
	var movement := get_real_velocity()
	if Vector2(movement.x, movement.z).length_squared() < 0.1 and absf(_speed) > 1.0:
		_speed = move_toward(_speed, 0.0, 15.0 * delta)


func drive_direction(direction: Vector3, reverse: bool, delta: float) -> void:
	var horizontal := Vector3(direction.x, 0.0, direction.z).limit_length()
	var has_input := horizontal.length_squared() > 0.0001
	var acceleration := 9.6 if has_input else 13.0
	var speed_limit := max_speed * (0.57 if reverse else 1.0)
	velocity = velocity.move_toward(horizontal * speed_limit, acceleration * delta)

	if has_input:
		var heading := velocity if velocity.dot(horizontal) > 0.0 else horizontal
		if reverse:
			heading = -heading
		var previous_yaw := rotation.y
		_try_hull_yaw(rotate_toward(previous_yaw, yaw_towards(heading), hull_turn_speed * delta))
		_turret.rotation.y = wrapf(_turret.rotation.y - angle_difference(previous_yaw, rotation.y), -PI, PI)
	move_on_ground(delta)
	update_hull_pose(delta)


func resume_ai() -> void:
	turret_turn_speed = 2.9
	_speed = clampf(velocity.dot(-global_basis.z), -max_speed * 0.57, max_speed)


func _try_hull_yaw(yaw: float) -> void:
	if is_equal_approx(yaw, rotation.y):
		return
	var turning := global_transform
	turning.basis = Basis(Vector3.UP, yaw)
	if not test_move(turning, Vector3.ZERO, null, safe_margin, true):
		rotation.y = wrapf(yaw, -PI, PI)


func aim_at(point: Vector3, delta: float) -> bool:
	var direction := point - _turret.global_position
	var horizontal := Vector2(direction.x, direction.z).length()
	if horizontal < 0.2:
		return false
	var pitch := atan2(direction.y, horizontal)
	var residual := point_gun(yaw_towards(direction), clampf(pitch, -0.55, 0.92), delta)
	var to_target := (point - _muzzle.global_position).normalized()
	return residual < 0.08 and to_target.dot(muzzle_direction()) > 0.985


func point_gun(world_yaw: float, pitch: float, delta: float) -> float:
	var world_direction := Basis(Vector3.UP, world_yaw) * Vector3(0.0, sin(pitch), -cos(pitch))
	var local_direction := _hull_pose.global_basis.transposed() * world_direction
	var offset := yaw_towards(local_direction)
	_turret.rotation.y = rotate_toward(_turret.rotation.y, offset, turret_turn_speed * delta)
	_gun.rotation.x = move_toward(_gun.rotation.x, -asin(clampf(local_direction.y, -1.0, 1.0)), 10.0 * delta)
	return absf(angle_difference(_turret.rotation.y, offset))


func muzzle_position() -> Vector3:
	return _muzzle.global_position + muzzle_direction() * 0.075


func muzzle_direction() -> Vector3:
	return _gun.global_basis.z.normalized()


func gun_pivot_position() -> Vector3:
	return _gun.global_position


func shot_origin() -> Vector3:
	return muzzle_position()


func shot_direction() -> Vector3:
	return muzzle_direction()


func target_point() -> Vector3:
	return _hull_pose.to_global(Vector3.UP * NEUTRAL_MUZZLE_HEIGHT)


func update_hull_pose(delta: float) -> void:
	if not terrain_height.is_valid():
		return
	var center := global_position
	var fore := global_basis.z * 2.0
	var side := global_basis.x * 1.25
	var slope_z := (ground_height_at(center + fore) - ground_height_at(center - fore)) / 4.0
	var slope_x := (ground_height_at(center + side) - ground_height_at(center - side)) / 2.5
	var up := Vector3(-slope_x, 1.0, -slope_z).normalized()
	var forward := Vector3(0.0, slope_z, 1.0).normalized()
	var pose := Basis(up.cross(forward), up, forward).orthonormalized()
	var weight := minf(delta * 12.0, 1.0)
	_hull_pose.basis = _hull_pose.basis.slerp(pose, weight).orthonormalized()
	for index in _hull_shapes.size():
		_hull_shapes[index].transform = Transform3D(_hull_pose.basis, _hull_pose.basis * _hull_shape_centers[index])


static func yaw_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
