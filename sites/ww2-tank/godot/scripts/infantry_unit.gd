extends "res://scripts/battle_unit.gd"

const ALLY_MODEL := preload("res://assets/us-soldier.glb")
const ENEMY_MODEL := preload("res://assets/en-soldier.glb")
const RIFLE_MODEL := preload("res://assets/lee-enfield.glb")
const HEIGHT := 1.77
const MOVE_SPEED := 4.2
const RIFLE_GRIP := Vector3(0.103, 0.72, -0.035)
const RIFLE_TIP := Vector3(0.0, 0.014, -0.76)
const REPATH_DELAY := 0.45
const SHOT_RANGE := 34.0
const FORMATION_STOP_DISTANCE := 1.6
const ESCORT_ENGAGEMENT_DISTANCE_SQUARED := 48.0 * 48.0

class StrideJoint:
	var index: int
	var rest_rotation: Quaternion
	var pitch_axis: Vector3

var _visual: Node3D
var _skeleton: Skeleton3D
var _rifle: Node3D
var _stride_joints: Array[StrideJoint] = []
var _stride := 0.0
var _pace := 0.0
var _fire_direction := Vector3.FORWARD
var _route := PackedVector2Array()
var _route_cursor := 0
var _route_target_id := 0
var _repath_left := 0.0


func configure(layer: int, strength: float, title: String) -> void:
	kind = "infantry"
	display_name = title
	max_health = maxi(1, roundi(72.0 * strength))
	health = max_health
	attack = maxi(1, roundi(21.0 * strength))
	defense = 2
	reload_time = 0.72 if layer == FRIENDLY_LAYER else 0.91
	reload_left = 0.0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = layer
	collision_mask = GROUND_UNIT_MASK
	safe_margin = 0.006

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.70
	capsule.radius = 0.25
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	add_child(collision)

	_visual = Node3D.new()
	_visual.scale = Vector3.ONE * HEIGHT
	add_child(_visual)
	var soldier := (ENEMY_MODEL if layer == HOSTILE_LAYER else ALLY_MODEL).instantiate() as Node3D
	soldier.rotation.y = PI
	_visual.add_child(soldier)
	var skeletons := soldier.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D


func _ready() -> void:
	_rifle = RIFLE_MODEL.instantiate() as Node3D
	_rifle.name = "Rifle"
	_rifle.position = RIFLE_GRIP
	_rifle.rotation.z = -0.07
	_rifle.scale = Vector3.ONE / HEIGHT
	_visual.add_child(_rifle)
	_pose_hands()
	_prepare_stride()


func drive_player(axes: Vector2, yaw: float, pitch: float, delta: float) -> void:
	var yaw_basis := Basis(Vector3.UP, yaw)
	_aim(yaw, pitch)
	_move(yaw_basis * Vector3(axes.x, 0.0, axes.y), delta)


func resume_ai() -> void:
	_route_target_id = 0
	_route.clear()
	_route_cursor = 0
	_repath_left = 0.0


func update_ai(opponents: Array[BattleUnit], grid: AStarGrid2D, delta: float) -> bool:
	_repath_left = maxf(0.0, _repath_left - delta)
	var target := _preferred_opponent(opponents)
	if target == null:
		_follow_formation(grid, delta)
		return false

	var point := target.target_point()
	var offset := point - global_position
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	var open_range := 13.0 if target.kind == "infantry" else 19.0
	var blocker := _ray(target_point(), point).get("collider") as Node3D
	var movement := Vector3.ZERO
	if blocker != null and blocker != target:
		if blocker is BattleUnit and horizontal.length_squared() > 0.05:
			var side := 1.0 if get_instance_id() % 2 == 0 else -1.0
			movement = Vector3.UP.cross(horizontal).normalized() * side
		else:
			movement = _route_direction(target.global_position, grid, target.get_instance_id())
	elif horizontal.length_squared() > open_range * open_range:
		movement = horizontal.normalized()
	_move(movement, delta)

	var aim := point - target_point()
	var bearing := rotation.y
	if horizontal.length_squared() > 0.001:
		bearing = atan2(-horizontal.x, -horizontal.z)
	var desired_pitch := atan2(aim.y, Vector2(aim.x, aim.z).length())
	_aim(rotate_toward(rotation.y, bearing, 9.0 * delta), desired_pitch)
	var muzzle := shot_origin()
	var final_offset := point - muzzle
	if final_offset.length_squared() > 0.0001:
		_fire_direction = final_offset.normalized()
	if reload_left > 0.0 or final_offset.length_squared() > SHOT_RANGE * SHOT_RANGE:
		return false
	if absf(angle_difference(rotation.y, bearing)) > 0.13:
		return false
	var muzzle_block := _ray(target_point(), muzzle).get("collider") as Node3D
	if muzzle_block != null and muzzle_block != target:
		return false
	var hit := _ray(muzzle, point).get("collider") as Node3D
	return hit == null or hit == target or muzzle_block == target


func shot_origin() -> Vector3:
	return _rifle.to_global(RIFLE_TIP)


func shot_direction() -> Vector3:
	return _fire_direction


func target_point() -> Vector3:
	return global_position + Vector3.UP * 1.23


func _move(direction: Vector3, delta: float, speed_scale := 1.0) -> void:
	velocity = velocity.move_toward(direction.limit_length() * MOVE_SPEED * speed_scale, 19.0 * delta)
	move_on_ground(delta)
	var target_pace := clampf(get_real_velocity().length() / MOVE_SPEED, 0.0, 1.0)
	if is_zero_approx(_pace) and is_zero_approx(target_pace):
		return
	_pace = move_toward(_pace, target_pace, 7.0 * delta)
	_stride += delta * (4.0 + 7.0 * _pace)
	_pose_stride()


func _follow_formation(grid: AStarGrid2D, delta: float) -> void:
	if not formation_goal.is_finite():
		_move(Vector3.ZERO, delta)
		return
	var toward := formation_goal - global_position
	toward.y = 0.0
	var distance := toward.length()
	if distance <= FORMATION_STOP_DISTANCE:
		_move(Vector3.ZERO, delta)
		return
	var direction := toward / distance
	var eyes := target_point()
	var probe_height := Vector3.UP * 0.52
	var blocker := _ray(global_position + probe_height, formation_goal + probe_height, COVER_LAYER)
	if not blocker.is_empty():
		direction = _route_direction(formation_goal, grid)
	var ahead := _ray(eyes, eyes + direction * 2.3, FRIENDLY_LAYER)
	if not ahead.is_empty():
		var side := 1.0 if get_instance_id() % 2 == 0 else -1.0
		direction = (direction * 0.55 + Vector3.UP.cross(direction) * side).normalized()
	var yaw := atan2(-direction.x, -direction.z)
	if not direction.is_zero_approx():
		_aim(rotate_toward(rotation.y, yaw, 9.0 * delta), 0.0)
	_move(direction, delta, lerpf(0.45, 1.66, smoothstep(FORMATION_STOP_DISTANCE, 18.0, distance)))


func _aim(yaw: float, pitch: float) -> void:
	rotation.y = yaw
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	_fire_direction = forward * cos(pitch) + Vector3.UP * sin(pitch)
	var rig_pitch := clampf(pitch, -0.28, 0.65)
	if absf(_rifle.rotation.x - rig_pitch) > 0.045:
		_rifle.rotation.x = rig_pitch
		_pose_hands()


func _preferred_opponent(opponents: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit
	var best_score := INF
	var escorting := formation_goal.is_finite()
	for opponent in opponents:
		if not is_instance_valid(opponent) or opponent.health <= 0:
			continue
		var score := global_position.distance_squared_to(opponent.global_position)
		if escorting and score > ESCORT_ENGAGEMENT_DISTANCE_SQUARED:
			continue
		if opponent.kind != "infantry":
			score += 100.0 if escorting else 1000000.0
		if score < best_score:
			best_score = score
			best = opponent
	return best


func _route_direction(goal: Vector3, grid: AStarGrid2D, target_id := 0) -> Vector3:
	if grid == null or not grid.region.has_area():
		return Vector3.ZERO
	if _route_target_id != target_id or _repath_left <= 0.0:
		_route_target_id = target_id
		_repath_left = REPATH_DELAY + (0.20 + float(get_instance_id() % 17) * 0.025 if target_id == 0 else 0.0)
		_route_cursor = 0
		var start := _open_cell(global_position, grid)
		var finish := _open_cell(goal, grid)
		_route.clear()
		if not grid.is_point_solid(start) and not grid.is_point_solid(finish):
			_route = grid.get_point_path(start, finish, true)
			var current := Vector2(global_position.x, global_position.z)
			if _route.size() > 1 and current.distance_squared_to(_route[0]) < 0.55:
				_route_cursor = 1
	while _route_cursor < _route.size():
		var next := _route[_route_cursor]
		var direction := Vector3(next.x - global_position.x, 0.0, next.y - global_position.z)
		if direction.length_squared() > 0.21:
			return direction.normalized()
		_route_cursor += 1
	return Vector3.ZERO


func _open_cell(point: Vector3, grid: AStarGrid2D) -> Vector2i:
	var horizontal := Vector2(point.x, point.z)
	var cell := Vector2i(((horizontal - grid.offset) / grid.cell_size).round())
	cell = cell.clamp(grid.region.position, grid.region.end - Vector2i.ONE)
	if not grid.is_point_solid(cell):
		return cell
	var closest := cell
	var distance := INF
	for z in range(-5, 6):
		for x in range(-5, 6):
			var candidate := cell + Vector2i(x, z)
			if not grid.region.has_point(candidate) or grid.is_point_solid(candidate):
				continue
			var score := horizontal.distance_squared_to(grid.get_point_position(candidate))
			if score < distance:
				distance = score
				closest = candidate
	return closest


func _ray(start: Vector3, finish: Vector3, mask := BATTLE_MASK) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, finish, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _pose_hands() -> void:
	var left_grip := _rifle.transform * Vector3(0.0, -0.038, -0.22)
	_pose_arm("Right", RIFLE_GRIP + Vector3(0.029, -0.044, 0.021), RIFLE_GRIP)
	_pose_arm("Left", left_grip + Vector3(-0.04, -0.018, 0.048), left_grip)


func _pose_arm(side: String, wrist: Vector3, palm: Vector3) -> void:
	if _skeleton == null:
		return
	var prefix := "mixamorig_" + side
	var upper := _skeleton.find_bone(prefix + "Arm")
	var fore := _skeleton.find_bone(prefix + "ForeArm")
	var hand := _skeleton.find_bone(prefix + "Hand")
	if mini(upper, mini(fore, hand)) < 0:
		return
	var start := _skeleton.get_bone_global_pose(upper).origin
	var elbow := _skeleton.get_bone_global_pose(fore).origin
	var finish := _skeleton.get_bone_global_pose(hand).origin
	var upper_length := start.distance_to(elbow)
	var lower_length := elbow.distance_to(finish)
	var desired := _skeleton.to_local(_visual.to_global(wrist)) - start
	var direction := desired.normalized()
	var span := clampf(desired.length(), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
	var along := (span * span + upper_length * upper_length - lower_length * lower_length) / (2.0 * span)
	var elbow_drop := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var pole := Vector3(0.7 if side == "Right" else -0.7, -1.0, 0.28)
	pole = _skeleton.global_basis.inverse() * _visual.global_basis * pole
	pole = (pole - direction * direction.dot(pole)).normalized()
	_point_bone(upper, fore, start + direction * along + pole * elbow_drop)
	_point_bone(fore, hand, start + direction * span)
	var finger := _skeleton.find_bone(prefix + "HandMiddle1")
	if finger >= 0:
		_point_bone(hand, finger, _skeleton.to_local(_visual.to_global(palm)))


func _point_bone(bone: int, child: int, goal: Vector3) -> void:
	var current := _skeleton.get_bone_global_pose(bone)
	var from := (_skeleton.get_bone_global_pose(child).origin - current.origin).normalized()
	var to := (goal - current.origin).normalized()
	if from.is_zero_approx() or to.is_zero_approx():
		return
	var parent := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(bone))
	var local_basis := parent.basis.inverse() * Basis(Quaternion(from, to)) * current.basis
	_skeleton.set_bone_pose_rotation(bone, local_basis.orthonormalized().get_rotation_quaternion())
	_skeleton.force_update_all_bone_transforms()


func _prepare_stride() -> void:
	if _skeleton == null:
		return
	var pitch := _skeleton.global_basis.inverse() * _visual.global_basis * Vector3.RIGHT
	for name_suffix in ["LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]:
		var bone := _skeleton.find_bone("mixamorig_" + name_suffix)
		if bone < 0:
			return
		var joint := StrideJoint.new()
		joint.index = bone
		joint.rest_rotation = _skeleton.get_bone_pose_rotation(bone)
		joint.pitch_axis = (_skeleton.get_bone_global_rest(bone).basis.inverse() * pitch).normalized()
		_stride_joints.append(joint)


func _pose_stride() -> void:
	_visual.position.y = _pace * (0.012 + 0.016 * absf(sin(_stride)))
	if _stride_joints.size() != 4:
		return
	for index in 2:
		var phase := _stride + PI * index
		var hip := _stride_joints[index * 2]
		var knee := _stride_joints[index * 2 + 1]
		_skeleton.set_bone_pose_rotation(hip.index,
			hip.rest_rotation * Quaternion(hip.pitch_axis, 0.28 * sin(phase) * _pace))
		_skeleton.set_bone_pose_rotation(knee.index,
			knee.rest_rotation * Quaternion(knee.pitch_axis, -0.40 * maxf(0.0, cos(phase)) * _pace))
