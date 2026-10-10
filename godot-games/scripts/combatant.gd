class_name Combatant
extends CharacterBody3D

signal defeated(actor: Combatant)
signal health_changed(current: float, maximum: float)

var max_health: float = 100.0
var health: float = 100.0
var move_speed: float = 5.0
var dead := false
var invulnerable := false
var knockback_velocity := Vector3.ZERO
var visual_parts: Dictionary = {}
var health_fill: MeshInstance3D
var health_fill_base_x := 1.0


func _ready() -> void:
	health = max_health
	if get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := CapsuleShape3D.new()
		shape.radius = 0.48
		shape.height = 1.8
		collision.shape = shape
		collision.position.y = 0.92
		add_child(collision)
	_build_health_bar()


func _build_health_bar() -> void:
	var holder := Node3D.new()
	holder.name = "WorldHealth"
	holder.position = Vector3(0, 2.75, 0.08)
	holder.rotation.x = deg_to_rad(-38.0)
	add_child(holder)
	VisualFactory.box(holder, Vector3(1.34, 0.09, 0.035), Vector3.ZERO, Color(0.025, 0.03, 0.035, 0.92), Vector3.ZERO, "HealthBack")
	health_fill = VisualFactory.box(holder, Vector3(1.24, 0.055, 0.045), Vector3(0, 0, -0.025), Color(0.85, 0.18, 0.12), Vector3.ZERO, "HealthFill")
	health_fill_base_x = health_fill.scale.x


func take_damage(amount: float, source_position: Vector3 = Vector3.ZERO, force: float = 0.0) -> bool:
	if dead or invulnerable:
		return false
	health = max(0.0, health - amount)
	if source_position != Vector3.ZERO and force > 0.0:
		var away := global_position - source_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			knockback_velocity += away.normalized() * force
	_update_health_bar()
	health_changed.emit(health, max_health)
	get_tree().call_group("game", "spawn_impact", global_position + Vector3(0, 1.0, 0), Color(1.0, 0.33, 0.12), 0.85)
	get_tree().call_group("game", "play_sound", "hit", randf_range(0.92, 1.08))
	if visual_parts.has("root"):
		var root: Node3D = visual_parts.root
		var resting_scale := root.scale
		var tween := create_tween()
		tween.tween_property(root, "scale", resting_scale * Vector3(1.1, 0.9, 1.1), 0.045)
		tween.tween_property(root, "scale", resting_scale, 0.11)
	if health <= 0.0:
		_die()
	return true


func heal(amount: float) -> void:
	if dead:
		return
	health = min(max_health, health + amount)
	_update_health_bar()
	health_changed.emit(health, max_health)


func _update_health_bar() -> void:
	if health_fill == null:
		return
	var ratio := clampf(health / max_health, 0.0, 1.0)
	health_fill.scale.x = maxf(0.01, ratio * health_fill_base_x)
	health_fill.position.x = -0.62 * (1.0 - ratio)


func apply_character_motion(desired_velocity: Vector3, delta: float) -> void:
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity = desired_velocity + knockback_velocity
	velocity.y = 0.0
	move_and_slide()
	global_position.x = clampf(global_position.x, -18.0, 18.0)
	global_position.z = clampf(global_position.z, -14.0, 14.0)


func _die() -> void:
	if dead:
		return
	dead = true
	collision_layer = 0
	collision_mask = 0
	defeated.emit(self)
	if visual_parts.has("root"):
		var root: Node3D = visual_parts.root
		var tween := create_tween().set_parallel(true)
		tween.tween_property(root, "scale", Vector3(0.05, 0.05, 0.05), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(root, "position:y", -0.7, 0.45)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

