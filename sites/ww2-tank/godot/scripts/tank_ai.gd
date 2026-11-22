extends RefCounted

const Tank = preload("res://scripts/duel_tank.gd")
const AIM_HEIGHT := Tank.NEUTRAL_MUZZLE_HEIGHT
const HOLD_DISTANCE := 17.0
const FIRE_DISTANCE := 23.0
const SHELL_SPEED := 28.0
const LOCAL_LOOK_AHEAD := 5.8
const WAYPOINT_REACHED_SQUARED := 1.48
const FORMATION_STOP_DISTANCE := 2.5
const ESCORT_ENGAGEMENT_DISTANCE_SQUARED := 48.0 * 48.0

var tank: Tank

var _grid: AStarGrid2D
var _target: BattleUnit
var _route := PackedVector2Array()
var _waypoint_index := 0
var _random := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters3D.new()
var _aim_spread: float
var _aim_error := 0.0
var _target_left := 0.0
var _repath_left: float
var _probe_left: float
var _flank_side: float
var _detour_point: Vector3
var _detour_left := 0.0
var _stall_time := 0.0
var _backoff_left := 0.0
var _regroup_direction := Vector3.ZERO


func _init(unit: Tank, grid: AStarGrid2D, aim_spread: float) -> void:
	tank = unit
	_grid = grid
	_aim_spread = maxf(0.0, aim_spread)
	_random.randomize()
	_repath_left = _random.randf_range(0.035, 0.27)
	_probe_left = _random.randf_range(0.0, 0.13)
	_flank_side = -1.0 if _random.randf() < 0.5 else 1.0
	_reroll_aim()
	_ray.collision_mask = Tank.BATTLE_MASK
	_ray.exclude = [tank.get_rid()]
	_ray.hit_from_inside = true


func resume() -> void:
	_target = null
	_target_left = 0.0
	_route.clear()
	_waypoint_index = 0
	_repath_left = 0.0
	_probe_left = 0.0
	_detour_left = 0.0
	_stall_time = 0.0
	_backoff_left = 0.0
	_regroup_direction = Vector3.ZERO


## Advance the tank once per physics frame. The match owns projectile creation.
func update(delta: float, opponents: Array[BattleUnit]) -> bool:
	if not is_instance_valid(tank) or not _living(tank):
		return false
	tank.update_reload(delta)
	_select_target(delta, opponents)
	if not is_instance_valid(_target):
		_follow_formation(delta)
		return false

	var here := tank.global_position
	var there := _target.target_point()
	var toward := _target.global_position - here
	toward.y = 0.0
	var distance := _at_aim_height(here).distance_to(there)
	var sight := _cast(_at_aim_height(here), there)
	var clear: bool = sight.is_empty() or sight["collider"] == _target

	if not clear or distance > HOLD_DISTANCE:
		_drive_to_goal(delta, _target.global_position, toward, sight.get("collider") as BattleUnit if not clear else null)
	elif distance < 4.6 and toward.dot(-tank.global_basis.z) > 0.0:
		tank.drive(-0.65, 0.0, delta)
	else:
		tank.drive(0.0, 0.0, delta)

	var travel_time := minf(distance / SHELL_SPEED, 0.62)
	var aim_point := there + _target.get_real_velocity() * travel_time * 0.50
	aim_point += Vector3.UP.cross(toward.normalized()) * _aim_error
	var aligned := tank.aim_at(aim_point, delta)
	if not clear or distance >= FIRE_DISTANCE or not aligned or tank.reload_left > 0.0:
		return false
	if not _firing_lane_clear(opponents, distance):
		return false
	_reroll_aim()
	return true


func _follow_formation(delta: float) -> void:
	var goal := tank.formation_goal
	if not goal.is_finite():
		tank.drive(0.0, 0.0, delta)
		return
	var toward := goal - tank.global_position
	toward.y = 0.0
	var distance := toward.length()
	if distance <= FORMATION_STOP_DISTANCE:
		tank.drive(0.0, 0.0, delta)
		return
	var speed_scale := lerpf(0.35, 1.36, smoothstep(FORMATION_STOP_DISTANCE, 14.0, distance))
	_drive_to_goal(delta, goal, toward, null, speed_scale)


func _select_target(delta: float, opponents: Array[BattleUnit]) -> void:
	_target_left -= delta
	var previous_valid := is_instance_valid(_target) and _opposes(_target) and opponents.has(_target)
	if previous_valid and _target_left > 0.0:
		return
	_target_left = _random.randf_range(0.31, 0.51)
	var here := tank.global_position
	var nearest: BattleUnit
	var nearest_squared := INF
	for opponent in opponents:
		if not is_instance_valid(opponent) or not _opposes(opponent):
			continue
		if tank.formation_goal.is_finite() and here.distance_squared_to(opponent.global_position) > ESCORT_ENGAGEMENT_DISTANCE_SQUARED:
			continue
		var distance_squared := _target_cost(here, opponent)
		if distance_squared < nearest_squared:
			nearest = opponent
			nearest_squared = distance_squared
	if previous_valid and nearest != null and nearest != _target:
		var current_squared := _target_cost(here, _target)
		if nearest_squared > current_squared * 0.72:
			return
	if _target != nearest:
		if is_instance_valid(_target):
			_repath_left = 0.0
		_route = PackedVector2Array()
		_waypoint_index = 0
		_detour_left = 0.0
		_target = nearest


func _target_cost(from: Vector3, opponent: BattleUnit) -> float:
	var distance := from.distance_squared_to(opponent.global_position)
	return distance if opponent.kind == "tank" else distance * 2.5


func _drive_to_goal(delta: float, goal: Vector3, toward: Vector3, sight_blocker: BattleUnit, speed_scale := 1.0) -> void:
	_repath_left -= delta
	_probe_left -= delta
	_detour_left = maxf(0.0, _detour_left - delta)
	if _backoff_left > 0.0:
		_backoff_left -= delta
		if _regroup_direction.is_zero_approx() or is_instance_valid(_target):
			tank.drive(-0.54, _flank_side * 0.28, delta)
		else:
			tank.drive_direction(_regroup_direction, false, delta)
		return

	if _detour_left > 0.0 and tank.global_position.distance_squared_to(_detour_point) < 2.05:
		_detour_left = 0.0
		_repath_left = 0.0
	if _repath_left <= 0.0:
		var route_end := _detour_point if _detour_left > 0.0 else goal
		_replace_route(route_end)
	var offset := _next_offset(toward)
	if _probe_left <= 0.0 and _detour_left <= 0.0:
		_probe_left = _random.randf_range(0.15, 0.23)
		var blocker := _blocking_tank(offset, sight_blocker)
		if blocker != null and _try_detour(blocker, offset):
			offset = _next_offset(toward)
	if offset.length_squared() < 0.04:
		tank.drive(0.0, 0.0, delta)
		return

	var yaw_error := angle_difference(tank.rotation.y, Tank.yaw_towards(offset))
	var steer := clampf(yaw_error * 2.6, -1.0, 1.0)
	var throttle := clampf(cos(yaw_error * 1.45), 0.0, 1.0)
	tank.drive(throttle * speed_scale, steer, delta)
	var motion := tank.get_real_velocity()
	var stopped := Vector2(motion.x, motion.z).length_squared() < 0.27
	if stopped and (throttle > 0.40 or absf(steer) > 0.8):
		_stall_time += delta
	else:
		_stall_time = 0.0
	if _stall_time > 0.72:
		_stall_time = 0.0
		_backoff_left = 0.39
		_detour_left = 0.0
		_repath_left = 0.0
		_flank_side = -_flank_side
		if not is_instance_valid(_target) and tank.formation_goal.is_finite():
			_regroup_direction = _regroup_step(offset)
			_backoff_left = 0.68
		else:
			_regroup_direction = Vector3.ZERO


func _regroup_step(offset: Vector3) -> Vector3:
	var safe := _grid.get_point_position(_nearest_open_cell(tank.global_position))
	var here := Vector2(tank.position.x, tank.position.z)
	if here.distance_squared_to(safe) > 0.80:
		return Vector3(safe.x - here.x, 0.0, safe.y - here.y).normalized()
	var forward := offset.normalized()
	var sidestep := Vector3.UP.cross(forward) * _flank_side
	return (forward * 0.52 + sidestep).normalized()


func _blocking_tank(offset: Vector3, sight_blocker: BattleUnit) -> BattleUnit:
	var from := _at_aim_height(tank.global_position)
	var direction := offset.normalized()
	if is_instance_valid(sight_blocker):
		var toward_blocker := _at_aim_height(sight_blocker.global_position) - from
		if toward_blocker.length_squared() < 64.0 and direction.dot(toward_blocker.normalized()) > 0.64:
			return sight_blocker
	var hit := _cast(from, from + direction * LOCAL_LOOK_AHEAD, Tank.GROUND_UNIT_MASK)
	var collider := hit.get("collider") as BattleUnit
	return collider if collider != _target else null


func _try_detour(blocker: BattleUnit, offset: Vector3) -> bool:
	if offset.length_squared() < 0.04:
		return false
	var from := tank.global_position
	var forward := offset.normalized()
	var side := Vector3.UP.cross(forward)
	var advance := clampf(from.distance_to(blocker.global_position) * 0.42, 0.6, 2.8)
	var here := _nearest_open_cell(from)
	if _grid.is_point_solid(here):
		return false
	for sign in [_flank_side, -_flank_side]:
		var tentative := from + forward * advance + side * float(sign) * 4.85
		var cell := _nearest_open_cell(tentative)
		var flat := _grid.get_point_position(cell)
		var point := Vector3(flat.x, 0.0, flat.y)
		point.y = tank.ground_height_at(point)
		if _grid.is_point_solid(cell) or from.distance_squared_to(point) < 5.0:
			continue
		if point.distance_squared_to(blocker.global_position) < 12.25:
			continue
		if not _cast(_at_aim_height(from), _at_aim_height(point), Tank.GROUND_UNIT_MASK).is_empty():
			continue
		var candidate := _grid.get_point_path(here, cell)
		if candidate.size() < 2:
			continue
		_detour_point = point
		_detour_left = 2.2
		_repath_left = _random.randf_range(0.42, 0.6)
		_route = candidate
		_waypoint_index = 0
		return true
	return false


func _replace_route(goal: Vector3) -> void:
	_repath_left = _random.randf_range(0.40, 0.59)
	_waypoint_index = 0
	var first := _nearest_open_cell(tank.global_position)
	var last := _nearest_open_cell(goal)
	_route = _grid.get_point_path(first, last, true)


func _next_offset(fallback: Vector3) -> Vector3:
	var here := tank.global_position
	while _waypoint_index < _route.size():
		var cell := _route[_waypoint_index]
		var offset := Vector3(cell.x, here.y, cell.y) - here
		if offset.length_squared() > WAYPOINT_REACHED_SQUARED:
			return offset
		_waypoint_index += 1
	return fallback


func _nearest_open_cell(at: Vector3) -> Vector2i:
	var region := _grid.region
	var horizontal := Vector2(at.x, at.z)
	var origin := Vector2i(((horizontal - _grid.offset) / _grid.cell_size).round())
	origin = origin.clamp(region.position, region.end - Vector2i.ONE)
	if not _grid.is_point_solid(origin):
		return origin
	var best := origin
	var min_distance := INF
	for y in range(-5, 6):
		for x in range(-5, 6):
			var candidate := origin + Vector2i(x, y)
			if not region.has_point(candidate) or _grid.is_point_solid(candidate):
				continue
			var distance := horizontal.distance_squared_to(_grid.get_point_position(candidate))
			if distance < min_distance:
				min_distance = distance
				best = candidate
	return best


func _firing_lane_clear(opponents: Array[BattleUnit], distance: float) -> bool:
	var muzzle := tank.muzzle_position()
	var near_hit := _cast(tank.gun_pivot_position(), muzzle)
	if not near_hit.is_empty():
		return _is_opponent_hit(near_hit, opponents)
	var line_hit := _cast(muzzle, muzzle + tank.muzzle_direction() * (distance + 1.1))
	return line_hit.is_empty() or _is_opponent_hit(line_hit, opponents)


func _is_opponent_hit(hit: Dictionary, opponents: Array[BattleUnit]) -> bool:
	var victim := hit.get("collider") as BattleUnit
	return _opposes(victim) and opponents.has(victim)


func _cast(from: Vector3, to: Vector3, mask := Tank.BATTLE_MASK) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = mask
	return tank.get_world_3d().direct_space_state.intersect_ray(_ray)


func _reroll_aim() -> void:
	_aim_error = _random.randf_range(-_aim_spread, _aim_spread)


func _at_aim_height(at: Vector3) -> Vector3:
	return at + Vector3.UP * AIM_HEIGHT


func _living(unit: BattleUnit) -> bool:
	return is_instance_valid(unit) and unit.health > 0


func _opposes(unit: BattleUnit) -> bool:
	return _living(unit) and unit.collision_layer != tank.collision_layer
