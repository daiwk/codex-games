class_name TianquePlayer
extends Combatant

var can_control := true
var attacking := false
var dashing := false
var combo_step := 0
var combo_window := 0.0
var queued_attack := false
var skill_cooldown := 0.0
var heavy_cooldown := 0.0
var dash_cooldown := 0.0
var heal_charges := 5
const MAX_HEAL_CHARGES := 5
const HEAL_AMOUNT := 50.0
var walk_clock := 0.0
var animation_player: AnimationPlayer
var imported_hero := false
var last_move_direction := Vector3(0, 0, -1)
var facing_turn_speed := 13.0
var weapon_holder: Node3D
var weapon_skeleton: Skeleton3D
var weapon_bone_index := -1


func _ready() -> void:
	max_health = 220.0
	move_speed = 7.3
	super._ready()
	add_to_group("player")
	collision_layer = 1
	collision_mask = 2
	_load_hero_visual()


func _load_hero_visual() -> void:
	var hero_path := "res://assets/characters/tianque_hero.glb"
	if ResourceLoader.exists(hero_path):
		var packed := load(hero_path) as PackedScene
		if packed != null:
			var hero := packed.instantiate() as Node3D
			hero.name = "TianqueHeroVisual"
			hero.rotation.y = PI
			# The native Quaternius cast shares one source scale. Keeping the hero
			# at that scale preserves readable MOBA silhouettes without making the
			# player tower over regular enemies.
			hero.scale = Vector3.ONE
			add_child(hero)
			animation_player = _find_animation_player(hero)
			_attach_runtime_weapon(hero)
			visual_parts = {"root": hero}
			imported_hero = true
			var world_health := get_node_or_null("WorldHealth")
			if world_health != null:
				world_health.visible = false
			_add_hero_fill_light()
			_play_character_animation("Idle", 0.0, true)
			return
	visual_parts = VisualFactory.make_humanoid(self, {
		"body": Color(0.055, 0.07, 0.085), "armor": Color(0.07, 0.11, 0.13),
		"trim": Color(0.76, 0.48, 0.16), "cloth": Color(0.20, 0.035, 0.03),
		"skin": Color(0.50, 0.38, 0.28), "mask": Color(0.72, 0.57, 0.30),
		"glow": Color(1.0, 0.19, 0.055), "weapon": Color(0.58, 0.68, 0.70)
	}, "blade")
	var root: Node3D = visual_parts.root
	root.scale = Vector3.ONE * 1.08


func _add_hero_fill_light() -> void:
	var fill := OmniLight3D.new()
	fill.name = "HeroReadabilityLight"
	fill.position = Vector3(0, 2.5, -1.75)
	fill.light_color = Color(0.58, 0.82, 0.88)
	fill.light_energy = 0.72
	fill.omni_range = 4.8
	fill.shadow_enabled = false
	add_child(fill)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _attach_runtime_weapon(hero: Node3D) -> void:
	if _find_descendant_named(hero, "Warrior_Sword") != null:
		return
	var skeleton := _find_skeleton(hero)
	if skeleton == null or skeleton.find_bone("DEF-hand.R") < 0:
		return
	weapon_skeleton = skeleton
	weapon_bone_index = skeleton.find_bone("DEF-hand.R")
	var pivot := Node3D.new()
	pivot.name = "MoonSabre"
	add_child(pivot)
	weapon_holder = pivot
	VisualFactory.cylinder(pivot, 0.028, 0.40, Vector3(0, 0.14, 0), Color(0.18, 0.07, 0.025), "Grip")
	VisualFactory.box(pivot, Vector3(0.42, 0.055, 0.09), Vector3(0, 0.37, 0), Color(0.74, 0.45, 0.14), Vector3.ZERO, "Guard")
	# Primitive box blade is intentionally used here. The procedural fan blade
	# is fine as a world effect, but can separate into visible triangles when
	# nested under a scaled BoneAttachment3D.
	VisualFactory.box(pivot, Vector3(0.13, 1.08, 0.055), Vector3(0, 0.93, 0), Color(0.48, 0.72, 0.76), Vector3.ZERO, "Blade")
	VisualFactory.box(pivot, Vector3(0.08, 0.23, 0.045), Vector3(0, 1.54, 0), Color(0.68, 0.9, 0.91), Vector3(0, 0, deg_to_rad(-18.0)), "BladeTip")
	_update_runtime_weapon()


func _find_descendant_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_descendant_named(child, wanted)
		if found != null:
			return found
	return null


func _update_runtime_weapon() -> void:
	if weapon_holder == null or weapon_skeleton == null or weapon_bone_index < 0:
		return
	var hand_global := weapon_skeleton.global_transform * weapon_skeleton.get_bone_global_pose(weapon_bone_index)
	hand_global.basis = hand_global.basis.orthonormalized()
	var grip_basis := Basis.from_euler(Vector3(deg_to_rad(8.0), deg_to_rad(2.0), deg_to_rad(-92.0)))
	weapon_holder.global_transform = hand_global * Transform3D(grip_basis, Vector3(0.02, 0.02, 0.04))


func _unhandled_input(event: InputEvent) -> void:
	if not can_control or dead:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("light_attack"):
			request_light_attack()
		elif event.is_action_pressed("heavy_attack"):
			request_heavy_attack()
		elif event.is_action_pressed("special_attack"):
			request_skill()
		elif event.is_action_pressed("dash"):
			request_dash()
		elif event.is_action_pressed("heal"):
			request_heal()


func _physics_process(delta: float) -> void:
	if dead:
		return
	skill_cooldown = maxf(0.0, skill_cooldown - delta)
	heavy_cooldown = maxf(0.0, heavy_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	combo_window = maxf(0.0, combo_window - delta)
	if combo_window <= 0.0 and not attacking:
		combo_step = 0

	var input_vector := Vector2.ZERO
	if can_control:
		input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 1.0:
		input_vector = input_vector.normalized()
	var desired := Vector3(input_vector.x, 0.0, input_vector.y) * move_speed
	if attacking:
		desired *= 0.18
	if dashing:
		desired = -global_transform.basis.z * 16.0
	elif not attacking and input_vector.length_squared() > 0.01:
		last_move_direction = Vector3(input_vector.x, 0.0, input_vector.y).normalized()
		_turn_toward(last_move_direction, delta)
	apply_character_motion(desired, delta)
	_update_runtime_weapon()
	_update_walk_animation(input_vector.length(), delta)
	get_tree().call_group("game", "update_player_cooldowns", dash_cooldown, heavy_cooldown, skill_cooldown)


func request_heal() -> bool:
	if dead or not can_control or heal_charges <= 0 or health >= max_health:
		_notify_heal_ui()
		return false
	heal_charges -= 1
	heal(HEAL_AMOUNT)
	get_tree().call_group("game", "spawn_heal_effect", global_position + Vector3(0, 0.7, 0))
	get_tree().call_group("game", "play_sound", "skill", 1.18)
	_notify_heal_ui()
	return true


func _notify_heal_ui() -> void:
	get_tree().call_group("game", "update_heal_status", heal_charges, MAX_HEAL_CHARGES, health >= max_health)


func _turn_toward(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-facing_turn_speed * delta))


func _assist_face_target(max_distance: float = 7.5, minimum_dot: float = -0.34) -> void:
	var forward := -global_transform.basis.z
	var best_target: Node3D
	var best_score := INF
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(candidate) or candidate.dead:
			continue
		var offset: Vector3 = candidate.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.05 or distance > max_distance:
			continue
		var facing_dot := forward.dot(offset / distance)
		if facing_dot < minimum_dot:
			continue
		var score := distance * (1.35 - facing_dot * 0.35)
		if score < best_score:
			best_score = score
			best_target = candidate
	if best_target != null:
		var direction := best_target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			rotation.y = atan2(-direction.x, -direction.z)
			last_move_direction = direction.normalized()


func _update_walk_animation(amount: float, delta: float) -> void:
	if imported_hero:
		if not attacking and not dashing:
			_play_character_animation("Run" if amount > 0.1 else "Idle", 0.14, true)
		return
	if not visual_parts.has("leg_left"):
		return
	walk_clock += delta * (10.0 if amount > 0.1 else 4.0)
	var swing := sin(walk_clock) * 0.42 * amount
	var leg_left: Node3D = visual_parts.leg_left
	var leg_right: Node3D = visual_parts.leg_right
	leg_left.rotation.x = lerpf(leg_left.rotation.x, swing, minf(1.0, delta * 12.0))
	leg_right.rotation.x = lerpf(leg_right.rotation.x, -swing, minf(1.0, delta * 12.0))
	var root: Node3D = visual_parts.root
	root.position.y = lerpf(root.position.y, absf(sin(walk_clock * 2.0)) * 0.045 * amount, minf(1.0, delta * 12.0))


func request_light_attack() -> void:
	if dashing:
		return
	if attacking:
		queued_attack = true
		return
	_assist_face_target()
	_start_light_attack()


func _start_light_attack() -> void:
	attacking = true
	queued_attack = false
	combo_step = combo_step % 3 + 1
	var damage_values := [0.0, 24.0, 30.0, 42.0]
	var durations := [0.0, 0.34, 0.38, 0.52]
	_play_character_animation("Attack%d" % combo_step, 0.08, false)
	get_tree().call_group("game", "spawn_slash", global_position + Vector3(0, 0.25, 0), -global_transform.basis.z, 2.35 + combo_step * 0.12, Color(1.0, 0.38, 0.08), durations[combo_step], combo_step)
	if not imported_hero:
		var weapon: Node3D = visual_parts.weapon
		var start_angle := -72.0 if combo_step != 2 else 75.0
		var end_angle := 78.0 if combo_step != 2 else -82.0
		weapon.rotation.z = deg_to_rad(start_angle)
		var tween := create_tween()
		tween.tween_property(weapon, "rotation:z", deg_to_rad(end_angle), durations[combo_step] * 0.62).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(durations[combo_step] * 0.26).timeout
	_damage_arc(damage_values[combo_step], 2.55 + combo_step * 0.15, 0.05, 4.0 + combo_step)
	get_tree().call_group("game", "camera_shake", 0.09 + combo_step * 0.025)
	await get_tree().create_timer(durations[combo_step] * 0.48).timeout
	combo_window = 0.48
	attacking = false
	if queued_attack:
		_start_light_attack()


func request_heavy_attack() -> void:
	if attacking or dashing or heavy_cooldown > 0.0:
		return
	_assist_face_target(8.5, -0.45)
	_start_heavy_attack()


func _start_heavy_attack() -> void:
	attacking = true
	heavy_cooldown = 2.2
	_play_character_animation("Heavy", 0.1, false)
	if not imported_hero:
		var weapon: Node3D = visual_parts.weapon
		weapon.rotation.x = deg_to_rad(28.0)
		weapon.rotation.z = deg_to_rad(-125.0)
	get_tree().call_group("game", "spawn_heavy_charge", global_position, -global_transform.basis.z, 0.32)
	await get_tree().create_timer(0.32).timeout
	if not imported_hero:
		var weapon: Node3D = visual_parts.weapon
		var tween := create_tween()
		tween.tween_property(weapon, "rotation:z", deg_to_rad(105.0), 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_damage_arc(68.0, 3.35, -0.2, 8.5)
	get_tree().call_group("game", "spawn_heavy_slash", global_position, -global_transform.basis.z)
	get_tree().call_group("game", "spawn_impact", global_position + -global_transform.basis.z * 1.8 + Vector3(0, 0.2, 0), Color(1.0, 0.16, 0.03), 1.8)
	get_tree().call_group("game", "camera_shake", 0.42)
	await get_tree().create_timer(0.36).timeout
	if not imported_hero:
		visual_parts.weapon.rotation.x = 0.0
	attacking = false
	combo_step = 0


func request_dash() -> void:
	if dashing or attacking or dash_cooldown > 0.0:
		return
	dashing = true
	invulnerable = true
	dash_cooldown = 1.15
	_play_character_animation("Dash", 0.06, false)
	get_tree().call_group("game", "spawn_dash_echo", self)
	await get_tree().create_timer(0.19).timeout
	dashing = false
	invulnerable = false


func request_skill() -> void:
	if attacking or dashing or skill_cooldown > 0.0:
		return
	_start_skill()


func _start_skill() -> void:
	attacking = true
	skill_cooldown = 7.0
	invulnerable = true
	_play_character_animation("Skill", 0.1, false)
	get_tree().call_group("game", "spawn_star_charge", global_position, 5.2, 0.46)
	var root: Node3D = visual_parts.root
	var rise := create_tween()
	rise.tween_property(root, "position:y", 0.75, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.46).timeout
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.dead and global_position.distance_to(enemy.global_position) <= 5.3:
			enemy.take_damage(56.0, global_position, 12.0)
	get_tree().call_group("game", "spawn_star_impact", global_position, Color(0.15, 0.9, 0.9), 5.3)
	get_tree().call_group("game", "camera_shake", 0.68)
	var land := create_tween()
	land.tween_property(root, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.22).timeout
	invulnerable = false
	attacking = false


func _play_character_animation(requested_name: String, blend: float = 0.1, looped: bool = false) -> void:
	if animation_player == null:
		return
	var selected := StringName()
	for animation_name in animation_player.get_animation_list():
		var simple_name := String(animation_name).get_file().trim_prefix("Armature|")
		if simple_name == requested_name or String(animation_name).ends_with(requested_name):
			selected = animation_name
			break
	if selected == StringName():
		return
	if animation_player.current_animation == selected and animation_player.is_playing():
		return
	var animation := animation_player.get_animation(selected)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	animation_player.play(selected, blend)


func _damage_arc(damage: float, radius: float, minimum_dot: float, force: float) -> void:
	var forward := -global_transform.basis.z
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() <= radius and (offset.length_squared() < 0.01 or forward.dot(offset.normalized()) >= minimum_dot):
			enemy.take_damage(damage, global_position, force)

