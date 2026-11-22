extends Node3D

const Aircraft = preload("res://scripts/aircraft_unit.gd")

const BURST_COUNT := 3
const BURST_WINDUP := 0.88
const BURST_INTERVAL := 0.31
const BURST_COOLDOWN := 7.0
const RESERVE_CALLS := 2
const RESERVE_WINDUP := 1.45
const RESERVE_COOLDOWN := 9.5
const STRIKE_WINDUP := 2.6
const STRIKE_FLYOUT := 1.45
const STRIKE_COOLDOWN := 11.0
const STRIKE_RADIUS := 8.6
const STRIKE_SPEED := 24.0
const STRIKE_HEIGHT := 11.0
const MARKER_SEGMENTS := 56

var _id := ""
var _status := "spent"
var _remaining := 0.0
var _uses := 0
var _burst_shots := 0
var _strike_center := Vector3.ZERO
var _strike_heading := Vector3(0.96, 0.0, 0.28).normalized()
var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _flyover: Node3D
var _propeller: Node3D


func begin(stage: String) -> void:
	_id = {"plains": "burst", "hills": "reinforcements", "coast": "airstrike"}.get(stage, "")
	_status = "waiting"
	_remaining = 1.4 if _id == "burst" else 1.25


func cancel() -> void:
	_status = "spent"
	_remaining = 0.0
	_clear_strike_visuals()


func allow_cannon() -> bool:
	if _id != "burst":
		return true
	if _status == "ready":
		_status = "warning"
		_remaining = BURST_WINDUP
		_burst_shots = 0
		return false
	return _status != "warning" and _status != "active"


func advance(delta: float, boss_alive: bool, target: BattleUnit, ground_point: Callable,
		fire_burst: Callable, spawn_reserves: Callable, release_bomb: Callable) -> void:
	if _id.is_empty() or _status == "spent":
		return
	if not boss_alive and not (_id == "airstrike" and _status == "active"):
		cancel()
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _id == "airstrike" and (_status == "warning" or _status == "active"):
		_update_flyover(delta)
	if _remaining > 0.0:
		return

	match _status:
		"waiting", "cooldown", "ready":
			_prepare(target, ground_point)
		"warning":
			match _id:
				"burst":
					_uses += 1
					_fire_burst_shot(fire_burst)
				"reinforcements":
					_uses += 1
					spawn_reserves.call(_uses)
					_status = "spent" if _uses >= RESERVE_CALLS else "cooldown"
					_remaining = RESERVE_COOLDOWN if _status == "cooldown" else 0.0
				"airstrike":
					_uses += 1
					_status = "active"
					_remaining = STRIKE_FLYOUT
					release_bomb.call(_flyover.global_position - Vector3.UP * 0.8)
		"active":
			if _id == "burst":
				_fire_burst_shot(fire_burst)
			else:
				_clear_strike_visuals()
				_status = "cooldown" if boss_alive else "spent"
				_remaining = STRIKE_COOLDOWN if boss_alive else 0.0


func snapshot() -> Dictionary:
	if _id.is_empty():
		return {}
	var state := {"id": _id, "status": _status, "seconds_remaining": _remaining,
		"uses": _uses, "burst_shots": _burst_shots}
	if _id == "reinforcements":
		state["extra_enemy_tanks"] = _uses
		state["extra_enemy_infantry"] = _uses
	if _id == "airstrike" and (_status == "warning" or _status == "active"):
		state["position"] = {"x": _strike_center.x, "y": _strike_center.y, "z": _strike_center.z}
		state["radius"] = STRIKE_RADIUS
	return state


func _prepare(target: BattleUnit, ground_point: Callable) -> void:
	_status = "ready"
	if _id == "reinforcements":
		_status = "warning"
		_remaining = RESERVE_WINDUP
	elif _id == "airstrike" and is_instance_valid(target):
		_status = "warning"
		_remaining = STRIKE_WINDUP
		_strike_center = ground_point.call(target.global_position)
		_strike_heading *= -1.0
		_create_strike_visuals(ground_point)
		_update_flyover(0.0)


func _fire_burst_shot(fire_burst: Callable) -> void:
	fire_burst.call()
	_burst_shots += 1
	_status = "cooldown" if _burst_shots >= BURST_COUNT else "active"
	_remaining = BURST_COOLDOWN if _status == "cooldown" else BURST_INTERVAL


func _create_strike_visuals(ground_point: Callable) -> void:
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_material.albedo_color = Color("#ff6133e0")

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := PackedVector3Array()
	var inner := PackedVector3Array()
	for index in MARKER_SEGMENTS:
		var angle := TAU * float(index) / MARKER_SEGMENTS
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		outer.append(_marker_vertex(radial * STRIKE_RADIUS, ground_point))
		inner.append(_marker_vertex(radial * (STRIKE_RADIUS - 0.36), ground_point))
	for index in MARKER_SEGMENTS:
		var next := (index + 1) % MARKER_SEGMENTS
		for vertex in [outer[index], inner[index], outer[next], outer[next], inner[index], inner[next]]:
			surface.add_vertex(vertex)
	_marker = MeshInstance3D.new()
	_marker.name = "AirstrikeWarning"
	_marker.mesh = surface.commit()
	_marker.material_override = _marker_material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)

	_flyover = Aircraft.AIRFRAME.instantiate() as Node3D
	_flyover.name = "AirstrikePlane"
	add_child(_flyover)
	_propeller = _flyover.get_node_or_null("Propeller") as Node3D


func _marker_vertex(offset: Vector3, ground_point: Callable) -> Vector3:
	var anchor: Vector3 = ground_point.call(_strike_center + offset)
	return to_local(anchor + Vector3.UP * 0.16)


func _update_flyover(delta: float) -> void:
	var approach := -_remaining if _status == "warning" else STRIKE_FLYOUT - _remaining
	_flyover.global_position = _strike_center + _strike_heading * approach * STRIKE_SPEED + Vector3.UP * STRIKE_HEIGHT
	_flyover.look_at(_flyover.global_position + _strike_heading)
	if is_instance_valid(_propeller):
		_propeller.rotate_z(delta * 62.0)
	var pulse := 0.72 + 0.25 * cos(_remaining * 12.0)
	_marker_material.albedo_color = Color(1.0, 0.30, 0.13, pulse)
	_marker.visible = _status == "warning" or _remaining > 0.27


func _clear_strike_visuals() -> void:
	if is_instance_valid(_marker):
		_marker.hide()
		_marker.queue_free()
	if is_instance_valid(_flyover):
		_flyover.hide()
		_flyover.queue_free()
	_marker = null
	_flyover = null
	_propeller = null
	_marker_material = null
