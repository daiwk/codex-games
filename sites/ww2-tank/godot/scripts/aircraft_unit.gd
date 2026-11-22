class_name AircraftUnit
extends "res://scripts/battle_unit.gd"

const AIRFRAME := preload("res://assets/plane1.glb")
const FLIGHT_MIN := Vector3(-39.0, 4.4, -35.0)
const FLIGHT_MAX := Vector3(39.0, 11.0, 35.0)
const CRUISE_HEIGHT := 7.8
const RECOVERY_HEIGHT := 10.0
const FORWARD_SPEED := 16.0
const REVERSE_SPEED := 8.0
const STRAFE_SPEED := 10.5
const MOVE_ACCELERATION := 21.0
const AI_SPEED := 12.0
const AI_FIRE_RANGE := 36.0
const PASS_END_DISTANCE := 11.0
const BOMB_PASS_END_DISTANCE := 2.1
const BOMB_RELEASE_RADIUS := 5.6
const BOMB_ORIGIN_OFFSET := 1.12
const BOMB_GROUND_CHECK_DEPTH := 16.0

var bomb_cooldown_left := 0.0:
	set(seconds):
		if seconds > 0.0 and bomb_cooldown_left <= 0.0:
			_bomb_drop_pending = true
		bomb_cooldown_left = seconds

var _propeller: Node3D
var _target: BattleUnit
var _retarget_left := 0.0
var _exit_left := 0.0
var _exit_course := Vector3.ZERO
var _turn_side := 1.0
var _blocked_time := 0.0
var _bomb_drop_pending := false


func configure(layer: int, strength: float, title: String) -> void:
	kind = "aircraft"
	display_name = title
	max_health = maxi(1, roundi(88.0 * strength))
	health = max_health
	attack = maxi(1, roundi(13.0 * strength))
	defense = 6
	reload_time = 0.43
	reload_left = 0.4
	collision_layer = layer
	collision_mask = BATTLE_MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	safe_margin = 0.012
	position = position.clamp(FLIGHT_MIN, FLIGHT_MAX)
	_turn_side = 1.0 if layer == FRIENDLY_LAYER else -1.0

	var model := AIRFRAME.instantiate() as Node3D
	model.name = "AirframeModel"
	add_child(model)
	_propeller = model.get_node("Propeller") as Node3D
	_add_hitbox(Vector3(1.32, 1.52, 7.4), Vector3(0.0, 0.1, 0.04))
	_add_hitbox(Vector3(7.1, 0.63, 2.25), Vector3(0.0, -0.38, -1.0))


func drive_player(axes: Vector2, yaw: float, pitch: float, delta: float) -> void:
	var input := axes.limit_length()
	_turn_flight(yaw, pitch, -input.x * 0.36, 6.5, delta)
	var view_yaw := Basis(Vector3.UP, yaw)
	var view_forward := view_yaw * Vector3(0.0, sin(pitch), -cos(pitch))
	var throttle := -input.y
	var speed := REVERSE_SPEED if throttle < 0.0 else FORWARD_SPEED
	var steering := view_yaw.x * input.x * STRAFE_SPEED
	var motion := view_forward * throttle * speed + steering
	motion.y = clampf(motion.y, -5.6, 5.6)
	_advance(motion, delta)


func resume_ai() -> void:
	_target = null
	_retarget_left = 0.0
	_exit_left = 0.0
	_blocked_time = 0.0
	_bomb_drop_pending = false


func update_ai(opponents: Array[BattleUnit], _grid: AStarGrid2D, delta: float) -> bool:
	if health <= 0:
		return false
	if _bomb_drop_pending:
		_bomb_drop_pending = false
		_begin_exit()
	_choose_target(opponents, delta)
	if _exit_left > 0.0:
		_exit_left = maxf(0.0, _exit_left - delta)
		_follow_course(_exit_course, RECOVERY_HEIGHT, 0.12, delta)
		return false
	if not is_instance_valid(_target):
		var center := Vector3(0.0, CRUISE_HEIGHT, 0.0)
		var center_offset := center - global_position
		if Vector2(center_offset.x, center_offset.z).length_squared() > 4.0:
			_follow_course(center, CRUISE_HEIGHT, 0.0, delta)
		else:
			_advance(Vector3.ZERO, delta)
		return false

	var point := _target.target_point()
	var toward := point - global_position
	var range_flat := Vector2(toward.x, toward.z).length()
	var bombing_pass := bomb_cooldown_left <= 0.0 and _is_bomb_target(_target)
	var pass_end_distance := BOMB_PASS_END_DISTANCE if bombing_pass else PASS_END_DISTANCE
	if range_flat < pass_end_distance or _blocked_time > 0.22:
		_begin_exit()
		_follow_course(_exit_course, RECOVERY_HEIGHT, 0.12, delta)
		return false

	var preferred_height := CRUISE_HEIGHT
	if _target.kind == "aircraft":
		preferred_height = clampf(point.y, FLIGHT_MIN.y, RECOVERY_HEIGHT)
	var aim_pitch := clampf(atan2(toward.y, range_flat), -0.65, 0.54)
	if bombing_pass:
		var approach := smoothstep(PASS_END_DISTANCE, PASS_END_DISTANCE * 2.0, range_flat)
		preferred_height = lerpf(RECOVERY_HEIGHT, CRUISE_HEIGHT, approach)
		aim_pitch *= smoothstep(BOMB_RELEASE_RADIUS, PASS_END_DISTANCE, range_flat)
	_follow_course(point, preferred_height, aim_pitch, delta)
	if get_slide_collision_count() > 0:
		_blocked_time += delta
	else:
		_blocked_time = 0.0
	if reload_left > 0.0:
		return false
	return _shot_has_target(point)


func bomb_origin() -> Vector3:
	return global_position - global_basis.y * BOMB_ORIGIN_OFFSET


func wants_bomb(opponents: Array[BattleUnit]) -> bool:
	if health <= 0 or bomb_cooldown_left > 0.0 or _exit_left > 0.0:
		return false
	var origin := bomb_origin()
	var radius_squared := BOMB_RELEASE_RADIUS * BOMB_RELEASE_RADIUS
	var impact: Vector3
	var found_impact := false
	for opponent in opponents:
		if not _is_bomb_target(opponent):
			continue
		var point := opponent.target_point()
		var offset := point - origin
		if offset.y >= 0.0 or Vector2(offset.x, offset.z).length_squared() >= radius_squared:
			continue
		if not found_impact:
			var ground := PhysicsRayQueryParameters3D.create(
				origin, origin + Vector3.DOWN * BOMB_GROUND_CHECK_DEPTH, WORLD_LAYER
			)
			ground.hit_from_inside = true
			var hit := get_world_3d().direct_space_state.intersect_ray(ground)
			if hit.is_empty():
				return false
			impact = hit["position"]
			found_impact = true
		if impact.distance_squared_to(point) < radius_squared:
			return true
	return false


func shot_origin() -> Vector3:
	return global_position + shot_direction() * 4.32


func shot_direction() -> Vector3:
	return -global_basis.z.normalized()


func target_point() -> Vector3:
	return global_position + global_basis.y * 0.14


func _add_hitbox(size: Vector3, offset: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var hitbox := CollisionShape3D.new()
	hitbox.shape = box
	hitbox.position = offset
	add_child(hitbox)


func _advance(desired_velocity: Vector3, delta: float) -> void:
	velocity = velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)
	var incoming_position := global_position + velocity * delta
	var bounded_position := incoming_position.clamp(FLIGHT_MIN, FLIGHT_MAX)
	if incoming_position != bounded_position:
		velocity = (bounded_position - global_position) / delta
	move_and_slide()
	bounded_position = global_position.clamp(FLIGHT_MIN, FLIGHT_MAX)
	if global_position != bounded_position:
		global_position = bounded_position
	_propeller.rotate_z(delta * 37.0)


func _turn_flight(yaw: float, pitch: float, bank: float, turn_speed: float, delta: float) -> void:
	var angles := global_rotation
	var step := turn_speed * delta
	var next := Vector3(
		move_toward(angles.x, pitch, step),
		rotate_toward(angles.y, yaw, step),
		move_toward(angles.z, bank, step * 0.63)
	)
	if next.is_equal_approx(angles):
		return
	var pose := Transform3D(Basis.from_euler(next), global_position)
	if not test_move(pose, Vector3.ZERO, null, safe_margin, true):
		global_rotation = next


func _choose_target(opponents: Array[BattleUnit], delta: float) -> void:
	_retarget_left -= delta
	var previous: BattleUnit = _target if is_instance_valid(_target) else null
	if _can_target(previous) and _retarget_left > 0.0 and opponents.has(previous):
		return
	_retarget_left = 0.37
	var best: BattleUnit
	var best_score := INF
	var found_ground_target := false
	for opponent in opponents:
		if not _can_target(opponent):
			continue
		var ground_target := opponent.kind != "aircraft"
		if found_ground_target and not ground_target:
			continue
		if ground_target and not found_ground_target:
			found_ground_target = true
			best_score = INF
		var weight := 1.0 if opponent.kind == "tank" else 1.35
		var score := global_position.distance_squared_to(opponent.global_position) * weight
		if opponent == previous:
			score *= 0.76
		if score < best_score:
			best_score = score
			best = opponent
	_target = best


func _can_target(unit: BattleUnit) -> bool:
	return is_instance_valid(unit) and unit.health > 0 and unit.collision_layer != collision_layer


func _is_bomb_target(unit: BattleUnit) -> bool:
	var opposing_layer := HOSTILE_LAYER if collision_layer == FRIENDLY_LAYER else FRIENDLY_LAYER
	return is_instance_valid(unit) and unit.health > 0 and unit.collision_layer == opposing_layer \
		and (unit.kind == "tank" or unit.kind == "infantry")


func _begin_exit() -> void:
	var heading := Basis(Vector3.UP, global_rotation.y)
	var forward := heading * Vector3.FORWARD
	var side := heading.x * _turn_side
	var projected := global_position + forward * 14.0 + side * 7.0
	var inner_min := FLIGHT_MIN + Vector3(3.5, 0.0, 3.5)
	var inner_max := FLIGHT_MAX - Vector3(3.5, 0.0, 3.5)
	if not projected.is_equal_approx(projected.clamp(inner_min, inner_max)):
		projected = global_position * 0.44 + side * 6.0
	_exit_course = projected.clamp(inner_min, inner_max)
	_exit_left = 1.65
	_turn_side *= -1.0
	_blocked_time = 0.0


func _follow_course(point: Vector3, height: float, pitch: float, delta: float) -> void:
	var toward := point - global_position
	var yaw := atan2(-toward.x, -toward.z)
	var yaw_error := angle_difference(global_rotation.y, yaw)
	var bank := clampf(yaw_error * 0.9, -0.48, 0.48)
	_turn_flight(yaw, pitch, bank, 2.4, delta)
	var heading := Basis(Vector3.UP, global_rotation.y) * Vector3.FORWARD
	var speed_fraction := clampf(1.0 - absf(yaw_error) * 0.29, 0.32, 1.0)
	var motion := heading * AI_SPEED * speed_fraction
	motion.y = clampf((height - global_position.y) * 2.5, -4.4, 4.4)
	_advance(motion, delta)


func _shot_has_target(point: Vector3) -> bool:
	var origin := shot_origin()
	var heading := shot_direction()
	var toward := point - origin
	if toward.length_squared() > AI_FIRE_RANGE * AI_FIRE_RANGE:
		return false
	if heading.dot(toward.normalized()) < 0.985:
		return false
	var ray := PhysicsRayQueryParameters3D.create(
		origin, origin + heading * AI_FIRE_RANGE, BATTLE_MASK, [get_rid()]
	)
	ray.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return _can_target(hit.get("collider") as BattleUnit)
