class_name TianqueEnemy
extends Combatant

var enemy_kind := "guard"
var is_boss := false
var target: TianquePlayer
var attack_cooldown := 0.8
var state_lock := false
var preferred_distance := 1.8
var phase := 1
var strafe_sign := 1.0
var spawn_position := Vector3.ZERO
var animation_player: AnimationPlayer
var imported_visual := false
var current_motion := ""


func _ready() -> void:
	if is_boss:
		max_health = 530.0
		move_speed = 3.45
	elif enemy_kind == "brute":
		max_health = 128.0
		move_speed = 3.25
	elif enemy_kind == "caster":
		max_health = 70.0
		move_speed = 4.0
		preferred_distance = 7.5
	else:
		max_health = 80.0
		move_speed = 4.5
	super._ready()
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1 | 2
	target = get_tree().get_first_node_in_group("player") as TianquePlayer
	spawn_position = global_position
	strafe_sign = -1.0 if randf() < 0.5 else 1.0
	_load_character_visual()
	if is_boss:
		var root: Node3D = visual_parts.root
		root.scale = Vector3.ONE * (1.22 if imported_visual else 1.38)
		$WorldHealth.position.y = 3.9
	elif imported_visual:
		$WorldHealth.position.y = 3.35


func _character_path() -> String:
	if is_boss:
		return "res://assets/characters/enemies/boss_cleric.glb"
	match enemy_kind:
		"brute":
			return "res://assets/characters/enemies/brute_monk.glb"
		"caster":
			return "res://assets/characters/enemies/caster_wizard.glb"
		_:
			return "res://assets/characters/enemies/guard_rogue.glb"


func _load_character_visual() -> void:
	var path := _character_path()
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var character := packed.instantiate() as Node3D
			character.name = "AuthoredCharacter"
			character.rotation.y = PI
			add_child(character)
			animation_player = _find_animation_player(character)
			visual_parts = {"root": character}
			imported_visual = animation_player != null
			if imported_visual:
				_play_animation("Idle", 0.0, true)
				return
	var palette := _palette()
	visual_parts = VisualFactory.make_humanoid(self, palette, "staff" if enemy_kind == "caster" else "blade", is_boss or enemy_kind == "brute")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _resolve_animation(requested_name: String) -> StringName:
	if animation_player == null:
		return StringName()
	for animation_name in animation_player.get_animation_list():
		if String(animation_name) == requested_name or String(animation_name).ends_with(requested_name):
			return animation_name
	return StringName()


func _play_animation(requested_name: String, blend: float = 0.12, looped: bool = false) -> void:
	var selected := _resolve_animation(requested_name)
	if selected == StringName():
		return
	if current_motion == requested_name and animation_player.is_playing():
		return
	current_motion = requested_name
	var animation := animation_player.get_animation(selected)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	animation_player.play(selected, blend)


func _palette() -> Dictionary:
	if is_boss:
		return {"body": Color(0.045, 0.035, 0.055), "armor": Color(0.17, 0.035, 0.045), "trim": Color(0.88, 0.55, 0.13), "cloth": Color(0.08, 0.01, 0.018), "skin": Color(0.42, 0.24, 0.20), "mask": Color(0.16, 0.025, 0.035), "glow": Color(1.0, 0.09, 0.025), "weapon": Color(0.55, 0.24, 0.15)}
	if enemy_kind == "caster":
		return {"body": Color(0.04, 0.07, 0.09), "armor": Color(0.055, 0.15, 0.17), "trim": Color(0.23, 0.78, 0.73), "cloth": Color(0.025, 0.12, 0.14), "skin": Color(0.37, 0.31, 0.27), "mask": Color(0.08, 0.24, 0.25), "glow": Color(0.2, 1.0, 0.88), "weapon": Color(0.3, 0.5, 0.52)}
	if enemy_kind == "brute":
		return {"body": Color(0.08, 0.055, 0.04), "armor": Color(0.22, 0.09, 0.045), "trim": Color(0.74, 0.28, 0.08), "cloth": Color(0.13, 0.025, 0.018), "skin": Color(0.43, 0.29, 0.23), "mask": Color(0.28, 0.06, 0.025), "glow": Color(1.0, 0.35, 0.04), "weapon": Color(0.42, 0.37, 0.31)}
	return {"body": Color(0.045, 0.05, 0.06), "armor": Color(0.12, 0.13, 0.14), "trim": Color(0.52, 0.42, 0.27), "cloth": Color(0.19, 0.025, 0.026), "skin": Color(0.40, 0.31, 0.26), "mask": Color(0.23, 0.23, 0.22), "glow": Color(0.92, 0.16, 0.04), "weapon": Color(0.48, 0.5, 0.49)}


func _physics_process(delta: float) -> void:
	if dead or target == null or target.dead:
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if is_boss and phase == 1 and health <= max_health * 0.5:
		phase = 2
		move_speed *= 1.22
		get_tree().call_group("game", "show_banner", "镇殿将军 · 狂怒", "攻击速度提升，注意朱砂预警")
		get_tree().call_group("game", "spawn_shockwave", global_position, Color(1.0, 0.08, 0.02), 6.0)

	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > 0.08:
		look_at(target.global_position * Vector3(1, 0, 1) + Vector3(0, global_position.y, 0), Vector3.UP)
	var desired := Vector3.ZERO
	if not state_lock:
		if enemy_kind == "caster":
			if distance > preferred_distance + 1.0:
				desired = offset.normalized() * move_speed
			elif distance < preferred_distance - 1.7:
				desired = -offset.normalized() * move_speed
			else:
				desired = Vector3(-offset.z, 0, offset.x).normalized() * move_speed * 0.55 * strafe_sign
			if attack_cooldown <= 0.0 and distance <= 10.5:
				_cast_orb()
		else:
			if distance > preferred_distance:
				desired = offset.normalized() * move_speed
			elif attack_cooldown <= 0.0:
				_melee_attack()
	apply_character_motion(desired, delta)
	_animate_walk(desired.length(), delta)


func _animate_walk(speed: float, delta: float) -> void:
	if imported_visual:
		if not state_lock:
			_play_animation("Run" if speed > 0.1 else "Idle", 0.16, true)
		return
	if not visual_parts.has("leg_left"):
		return
	var amount := clampf(speed / maxf(move_speed, 0.1), 0.0, 1.0)
	var clock := Time.get_ticks_msec() * 0.009 + get_instance_id() * 0.1
	var swing := sin(clock) * 0.36 * amount
	visual_parts.leg_left.rotation.x = lerpf(visual_parts.leg_left.rotation.x, swing, delta * 10.0)
	visual_parts.leg_right.rotation.x = lerpf(visual_parts.leg_right.rotation.x, -swing, delta * 10.0)


func _melee_attack() -> void:
	state_lock = true
	_play_animation("Attack2" if is_boss and phase == 2 else "Attack", 0.08, false)
	var windup := 0.72 if enemy_kind == "brute" else 0.46
	if is_boss:
		windup = 0.55 if phase == 1 else 0.38
	var radius := 2.9 if is_boss else (2.35 if enemy_kind == "brute" else 1.85)
	get_tree().call_group("game", "spawn_telegraph", global_position + -global_transform.basis.z * 0.9, radius, Color(0.98, 0.08, 0.025, 0.28), windup)
	if not imported_visual:
		var weapon: Node3D = visual_parts.weapon
		weapon.rotation.z = deg_to_rad(-115.0)
	await get_tree().create_timer(windup).timeout
	if dead or target == null:
		state_lock = false
		return
	if not imported_visual:
		var weapon: Node3D = visual_parts.weapon
		var sweep := create_tween()
		sweep.tween_property(weapon, "rotation:z", deg_to_rad(105.0), 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if global_position.distance_to(target.global_position) <= radius + 0.65:
		var damage := 26.0 if is_boss else (18.0 if enemy_kind == "brute" else 11.0)
		target.take_damage(damage, global_position, 8.0 if is_boss else 4.0)
	get_tree().call_group("game", "camera_shake", 0.24 if is_boss else 0.1)
	await get_tree().create_timer(0.32).timeout
	state_lock = false
	attack_cooldown = (1.05 if phase == 2 else 1.55) + randf_range(0.0, 0.35)


func _cast_orb() -> void:
	state_lock = true
	_play_animation("Cast2" if is_boss and phase == 2 else "Cast", 0.08, false)
	get_tree().call_group("game", "spawn_telegraph", target.global_position, 1.45, Color(0.08, 0.8, 0.75, 0.25), 0.72)
	await get_tree().create_timer(0.72).timeout
	if not dead and target != null:
		get_tree().call_group("game", "spawn_enemy_orb", global_position + Vector3(0, 1.5, 0), target)
	state_lock = false
	attack_cooldown = randf_range(2.6, 3.2)


func take_damage(amount: float, source_position: Vector3 = Vector3.ZERO, force: float = 0.0) -> bool:
	var applied := super.take_damage(amount, source_position, force)
	if applied and not dead:
		_play_animation("Hit", 0.04, false)
	return applied


func _die() -> void:
	if dead:
		return
	dead = true
	collision_layer = 0
	collision_mask = 0
	defeated.emit(self)
	if imported_visual:
		_play_animation("Death", 0.05, false)
		await get_tree().create_timer(0.92).timeout
	if visual_parts.has("root") and is_instance_valid(visual_parts.root):
		var root: Node3D = visual_parts.root
		var tween := create_tween().set_parallel(true)
		tween.tween_property(root, "scale", Vector3(0.05, 0.05, 0.05), 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(root, "position:y", -0.7, 0.38)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

