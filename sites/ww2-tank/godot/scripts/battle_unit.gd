class_name BattleUnit
extends CharacterBody3D

const WORLD_LAYER := 1
const FRIENDLY_LAYER := 2
const HOSTILE_LAYER := 4
const BATTLE_MASK := WORLD_LAYER | FRIENDLY_LAYER | HOSTILE_LAYER

var display_name: String
var kind: String
var health: int
var max_health: int
var attack: int
var defense: int
var reload_time := 1.12
var reload_left := 0.0


func drive_player(_axes: Vector2, _yaw: float, _pitch: float, _delta: float) -> void:
	pass


func update_ai(_opponents: Array[BattleUnit], _grid: AStarGrid2D, _delta: float) -> bool:
	return false


func resume_ai() -> void:
	pass


func shot_origin() -> Vector3:
	return target_point()


func shot_direction() -> Vector3:
	return -global_basis.z


func target_point() -> Vector3:
	return global_position


func reload_fraction() -> float:
	return 1.0 - reload_left / reload_time


func update_reload(delta: float) -> void:
	reload_left = maxf(0.0, reload_left - delta)


func take_hit(damage: int) -> void:
	var received_damage := roundi(damage * (100 - defense) / 100.0)
	health = maxi(0, health - received_damage)
	if health == 0:
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		hide()
