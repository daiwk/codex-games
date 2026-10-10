extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const VFX := preload("res://scripts/combat_vfx.gd")

var player: TianquePlayer
var camera: Camera3D
var camera_shake_strength := 0.0
var camera_noise_clock := 0.0
var camera_follow_locked := false
var encounter_stage := 0
var active_enemy_count := 0
var game_over := false
var game_won := false

var health_bar: ProgressBar
var health_text: Label
var objective_label: Label
var banner_panel: PanelContainer
var banner_title: Label
var banner_subtitle: Label
var controls_panel: PanelContainer
var cooldown_labels: Dictionary = {}
var overlay: ColorRect
var overlay_title: Label
var overlay_subtitle: Label
var boss_bar: ProgressBar
var boss_label: Label

var hit_sound: AudioStreamWAV
var skill_sound: AudioStreamWAV
var death_sound: AudioStreamWAV


func _ready() -> void:
	add_to_group("game")
	seed(7319)
	_configure_input_map()
	_build_world()
	_build_ui()
	_build_audio()
	_spawn_player()
	var user_args := OS.get_cmdline_user_args()
	if "--vfx-showcase" in user_args:
		call_deferred("_run_vfx_showcase")
	elif "--vfx-test" in user_args:
		call_deferred("_run_vfx_test")
	elif "--capture-boss" in user_args:
		call_deferred("_capture_boss_preview")
	else:
		call_deferred("_begin_encounter")
	if "--capture-frame" in user_args:
		call_deferred("_capture_preview")
	if "--smoke-test" in user_args:
		call_deferred("_run_smoke_test")
	if "--turn-test" in user_args:
		call_deferred("_run_turn_test")
	if "--aim-test" in user_args:
		call_deferred("_run_aim_test")
	if "--heal-test" in user_args:
		call_deferred("_run_heal_test")


func _configure_input_map() -> void:
	var bindings := {
		"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S,
		"light_attack": KEY_J, "heavy_attack": KEY_K, "special_attack": KEY_L,
		"dash": KEY_SPACE, "heal": KEY_H
	}
	for action_name in bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var already_bound := false
		for existing in InputMap.action_get_events(action_name):
			if existing is InputEventKey and existing.physical_keycode == bindings[action_name]:
				already_bound = true
				break
		if not already_bound:
			var key := InputEventKey.new()
			key.physical_keycode = bindings[action_name]
			InputMap.action_add_event(action_name, key)


func _process(delta: float) -> void:
	_update_camera(delta)
	if (game_over or game_won) and Input.is_physical_key_pressed(KEY_R):
		get_tree().reload_current_scene()


func _capture_preview() -> void:
	await get_tree().create_timer(2.7).timeout
	var output_dir := ProjectSettings.globalize_path("res://qa")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_dir.path_join("preview.png"))
	print("TIANQUE_CAPTURE=", output_dir.path_join("preview.png"), " error=", error)
	# A close crop validates armor, face, weapon, materials and the neutral pose.
	var old_camera_position := camera.global_position
	camera_follow_locked = true
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var hidden_for_hero_capture: Array[Node3D] = []
	for candidate in get_children():
		if candidate is Node3D and candidate != player and (candidate.is_in_group("enemies") or candidate.name.contains("Slash") or candidate.name.contains("Impact") or candidate.name.contains("Shockwave") or candidate.name.contains("Telegraph")):
			candidate.visible = false
			candidate.process_mode = Node.PROCESS_MODE_DISABLED
			hidden_for_hero_capture.append(candidate)
	camera.global_position = player.global_position + Vector3(3.15, 2.75, -4.15)
	camera.look_at(player.global_position + Vector3(0, 1.32, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var close_image := get_viewport().get_texture().get_image()
	var close_error := close_image.save_png(output_dir.path_join("hero-closeup.png"))
	player.attacking = true
	player._play_character_animation("Attack1", 0.0, false)
	await get_tree().create_timer(0.34).timeout
	var attack_image := get_viewport().get_texture().get_image()
	var attack_error := attack_image.save_png(output_dir.path_join("hero-attack.png"))
	print("TIANQUE_ATTACK_CAPTURE=", output_dir.path_join("hero-attack.png"), " error=", attack_error)
	player.attacking = false
	camera.global_position = old_camera_position
	for candidate in hidden_for_hero_capture:
		if is_instance_valid(candidate):
			candidate.visible = true
			candidate.process_mode = Node.PROCESS_MODE_INHERIT
	if hud != null:
		hud.visible = true
	camera_follow_locked = false
	print("TIANQUE_HERO_CAPTURE=", output_dir.path_join("hero-closeup.png"), " error=", close_error)
	get_tree().quit()


func _capture_boss_preview() -> void:
	await get_tree().process_frame
	camera_follow_locked = true
	player.can_control = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var boss := _spawn_enemy("boss", Vector3(0, 0.05, 0), true)
	boss.state_lock = true
	boss.health_changed.connect(_on_boss_health_changed)
	boss_bar.visible = true
	boss_label.visible = true
	_on_boss_health_changed(boss.health, boss.max_health)
	camera.global_position = boss.global_position + Vector3(4.7, 4.0, 6.2)
	camera.look_at(boss.global_position + Vector3(0, 1.45, 0), Vector3.UP)
	await get_tree().create_timer(0.75).timeout
	var output_dir := ProjectSettings.globalize_path("res://qa")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_dir.path_join("boss-cleric.png"))
	print("TIANQUE_BOSS_CAPTURE=", output_dir.path_join("boss-cleric.png"), " error=", error)
	get_tree().quit()


func _run_turn_test() -> void:
	await get_tree().create_timer(0.7).timeout
	var tests := [
		["move_right", Vector3.RIGHT], ["move_down", Vector3.BACK],
		["move_left", Vector3.LEFT], ["move_up", Vector3.FORWARD]
	]
	for test in tests:
		Input.action_press(test[0])
		await get_tree().create_timer(0.35).timeout
		Input.action_release(test[0])
		var facing := -player.global_transform.basis.z
		var score := facing.dot(test[1])
		if score < 0.94:
			push_error("Turn test failed for %s: dot=%.3f facing=%s" % [test[0], score, facing])
			get_tree().quit(5)
			return
	print("TIANQUE_TURN_TEST=PASS right=true down=true left=true up=true")
	get_tree().quit()


func _run_aim_test() -> void:
	await get_tree().create_timer(1.8).timeout
	for existing in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(existing):
			existing.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3.ZERO
	player.rotation.y = 0.0
	var front_enemy := _spawn_enemy("guard", Vector3(3.0, 0.05, -4.0), false)
	player._assist_face_target(8.0, -0.34)
	var expected_front := (front_enemy.global_position - player.global_position).normalized()
	var front_score := (-player.global_transform.basis.z).dot(expected_front)
	front_enemy.queue_free()
	await get_tree().process_frame
	player.rotation.y = 0.0
	var behind_enemy := _spawn_enemy("guard", Vector3(0, 0.05, 4.0), false)
	player._assist_face_target(8.0, -0.34)
	var behind_score := (-player.global_transform.basis.z).dot(Vector3.FORWARD)
	behind_enemy.queue_free()
	if front_score < 0.98 or behind_score < 0.98:
		push_error("Aim test failed: front=%.3f behind_stability=%.3f" % [front_score, behind_score])
		get_tree().quit(8)
		return
	print("TIANQUE_AIM_TEST=PASS front_lock=%.3f behind_ignored=%.3f" % [front_score, behind_score])
	get_tree().quit()


func _run_heal_test() -> void:
	await get_tree().process_frame
	if player.max_health != 220.0 or player.heal_charges != 5:
		push_error("Heal test: invalid initial state health=%.1f charges=%d" % [player.max_health, player.heal_charges])
		get_tree().quit(12)
		return
	if player.request_heal() or player.heal_charges != 5:
		push_error("Heal test: full-health use consumed a charge")
		get_tree().quit(13)
		return
	for expected_charges in range(4, -1, -1):
		player.take_damage(50.0)
		if not player.request_heal() or player.heal_charges != expected_charges or player.health != player.max_health:
			push_error("Heal test: failed at expected charges=%d health=%.1f" % [expected_charges, player.health])
			get_tree().quit(14)
			return
	player.take_damage(50.0)
	if player.request_heal() or player.heal_charges != 0 or player.health != 170.0:
		push_error("Heal test: sixth use was not rejected")
		get_tree().quit(15)
		return
	print("TIANQUE_HEAL_TEST=PASS full_ignored=true uses=5 sixth_rejected=true")
	get_tree().quit()


func _run_smoke_test() -> void:
	await get_tree().create_timer(2.0).timeout
	if not player.imported_hero or player.animation_player == null:
		push_error("Smoke test: authored Blender hero was not loaded")
		get_tree().quit(6)
		return
	var required_animations := ["Idle", "Run", "Attack1", "Attack2", "Attack3", "Heavy", "Dash", "Skill"]
	var available_animations := PackedStringArray()
	for animation_name in player.animation_player.get_animation_list():
		available_animations.append(String(animation_name))
	for required in required_animations:
		var found := false
		for available in available_animations:
			if available == required or available.ends_with(required):
				found = true
				break
		if not found:
			push_error("Smoke test: missing hero animation %s; available=%s" % [required, available_animations])
			get_tree().quit(7)
			return
	var first_wave := get_tree().get_nodes_in_group("enemies")
	if first_wave.size() != 6:
		push_error("Smoke test: expected 6 enemies, got %d" % first_wave.size())
		get_tree().quit(2)
		return
	for enemy in first_wave:
		if not enemy.imported_visual or enemy.animation_player == null:
			push_error("Smoke test: %s did not load authored character" % enemy.name)
			get_tree().quit(9)
			return
		for required in ["Idle", "Run", "Attack", "Hit", "Death"]:
			if enemy._resolve_animation(required) == StringName():
				push_error("Smoke test: %s missing %s" % [enemy.name, required])
				get_tree().quit(10)
				return
	player.request_dash()
	for enemy in first_wave:
		if is_instance_valid(enemy):
			enemy.take_damage(9999.0, player.global_position, 0.0)
	await get_tree().create_timer(1.8).timeout
	var boss: TianqueEnemy
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.is_boss:
			boss = enemy
			break
	if boss == null:
		push_error("Smoke test: boss did not spawn after wave one")
		get_tree().quit(3)
		return
	if not boss.imported_visual or boss._resolve_animation("Cast") == StringName():
		push_error("Smoke test: authored boss or Cast animation missing")
		get_tree().quit(11)
		return
	boss.take_damage(9999.0, player.global_position, 0.0)
	await get_tree().create_timer(0.2).timeout
	if not game_won:
		push_error("Smoke test: victory state was not reached")
		get_tree().quit(4)
		return
	print("TIANQUE_SMOKE_TEST=PASS wave=6 boss=true victory=true")
	get_tree().quit()


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "InkDuskEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.017, 0.026, 0.034)
	env.background_energy_multiplier = 0.82
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.29, 0.32)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.055, 0.085, 0.09)
	env.fog_light_energy = 0.58
	env.fog_density = 0.011
	env.fog_height = -1.4
	env.fog_height_density = 0.16
	environment.environment = env
	add_child(environment)

	var moon := DirectionalLight3D.new()
	moon.name = "MoonLight"
	moon.light_color = Color(0.55, 0.76, 0.82)
	moon.light_energy = 1.35
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 80.0
	moon.rotation_degrees = Vector3(-54, -28, 0)
	add_child(moon)
	var warm := DirectionalLight3D.new()
	warm.name = "WarmRim"
	warm.light_color = Color(1.0, 0.38, 0.12)
	warm.light_energy = 0.58
	warm.rotation_degrees = Vector3(-35, 145, 0)
	add_child(warm)

	_build_arena_geometry()
	_build_camera()


func _build_arena_geometry() -> void:
	var arena := Node3D.new()
	arena.name = "TianqueCourtyard"
	add_child(arena)
	VisualFactory.box(arena, Vector3(39.5, 0.65, 31.5), Vector3(0, -0.4, 0), Color(0.075, 0.086, 0.085), Vector3.ZERO, "StoneCourt")
	VisualFactory.box(arena, Vector3(8.2, 0.72, 9.2), Vector3(0, -0.02, -10.2), Color(0.105, 0.11, 0.095), Vector3.ZERO, "BossDais")
	for x in range(-18, 19, 3):
		VisualFactory.box(arena, Vector3(0.045, 0.018, 30.0), Vector3(x, -0.06, 0), Color(0.18, 0.19, 0.17, 0.32), Vector3.ZERO, "StoneJointX")
	for z in range(-14, 15, 3):
		VisualFactory.box(arena, Vector3(38.0, 0.018, 0.045), Vector3(0, -0.055, z), Color(0.18, 0.19, 0.17, 0.32), Vector3.ZERO, "StoneJointZ")

	# Strong readable boundary walls and ceremonial rails.
	VisualFactory.box(arena, Vector3(40.5, 1.35, 0.8), Vector3(0, 0.25, -15.7), Color(0.12, 0.035, 0.026), Vector3.ZERO, "NorthWall")
	VisualFactory.box(arena, Vector3(40.5, 1.35, 0.8), Vector3(0, 0.25, 15.7), Color(0.12, 0.035, 0.026), Vector3.ZERO, "SouthWall")
	VisualFactory.box(arena, Vector3(0.8, 1.35, 31.0), Vector3(-19.7, 0.25, 0), Color(0.12, 0.035, 0.026), Vector3.ZERO, "WestWall")
	VisualFactory.box(arena, Vector3(0.8, 1.35, 31.0), Vector3(19.7, 0.25, 0), Color(0.12, 0.035, 0.026), Vector3.ZERO, "EastWall")
	for x in [-17.5, -12.5, 12.5, 17.5]:
		_make_lantern(arena, Vector3(x, 0, -12.8))
		_make_lantern(arena, Vector3(x, 0, 12.8))
	for z in [-8.5, -2.5, 3.5, 9.5]:
		_make_lantern(arena, Vector3(-17.6, 0, z))
		_make_lantern(arena, Vector3(17.6, 0, z))

	# Water channels and bridges give the lane a MOBA-like silhouette.
	VisualFactory.box(arena, Vector3(39.0, 0.12, 2.1), Vector3(0, -0.12, -5.5), Color(0.025, 0.22, 0.25, 0.72), Vector3.ZERO, "NorthWater")
	VisualFactory.box(arena, Vector3(39.0, 0.12, 2.1), Vector3(0, -0.12, 5.5), Color(0.025, 0.22, 0.25, 0.72), Vector3.ZERO, "SouthWater")
	for x in [-11.0, 0.0, 11.0]:
		VisualFactory.box(arena, Vector3(3.4, 0.28, 3.0), Vector3(x, 0.04, -5.5), Color(0.25, 0.17, 0.09), Vector3.ZERO, "NorthBridge")
		VisualFactory.box(arena, Vector3(3.4, 0.28, 3.0), Vector3(x, 0.04, 5.5), Color(0.25, 0.17, 0.09), Vector3.ZERO, "SouthBridge")

	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	arena.add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(39.0, 0.5, 31.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.45
	floor_body.add_child(floor_shape)
	_add_boundary_collision(arena, Vector3(40.0, 3.0, 0.6), Vector3(0, 1.0, -15.4))
	_add_boundary_collision(arena, Vector3(40.0, 3.0, 0.6), Vector3(0, 1.0, 15.4))
	_add_boundary_collision(arena, Vector3(0.6, 3.0, 31.0), Vector3(-19.4, 1.0, 0))
	_add_boundary_collision(arena, Vector3(0.6, 3.0, 31.0), Vector3(19.4, 1.0, 0))


func _make_lantern(parent: Node3D, position_value: Vector3) -> void:
	var lantern := Node3D.new()
	lantern.position = position_value
	lantern.name = "VermilionLantern"
	parent.add_child(lantern)
	VisualFactory.cylinder(lantern, 0.12, 2.5, Vector3(0, 1.25, 0), Color(0.18, 0.075, 0.03), "Post")
	VisualFactory.box(lantern, Vector3(0.72, 0.82, 0.72), Vector3(0, 2.35, 0), Color(0.85, 0.095, 0.03), Vector3.ZERO, "Lantern")
	VisualFactory.box(lantern, Vector3(0.92, 0.11, 0.92), Vector3(0, 2.81, 0), Color(0.09, 0.055, 0.025), Vector3.ZERO, "Cap")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.18, 0.045)
	light.light_energy = 1.8
	light.omni_range = 5.5
	light.position = Vector3(0, 2.35, 0)
	lantern.add_child(light)


func _add_boundary_collision(parent: Node3D, size: Vector3, position_value: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	body.position = position_value
	body.add_child(collision)
	parent.add_child(body)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "ArenaCamera"
	camera.fov = 43.0
	camera.near = 0.2
	camera.far = 180.0
	camera.position = Vector3(0, 19.5, 19.5)
	add_child(camera)
	camera.look_at(Vector3(0, 0, -3.2), Vector3.UP)


func _spawn_player() -> void:
	player = TianquePlayer.new()
	player.name = "MaskedWarden"
	player.position = Vector3(0, 0.05, 10.2)
	add_child(player)
	player.health_changed.connect(_on_player_health_changed)
	player.defeated.connect(_on_player_defeated)
	_on_player_health_changed(player.health, player.max_health)


func _begin_encounter() -> void:
	show_banner("天阙试炼", "穿过守卫，击败镇殿将军")
	await get_tree().create_timer(1.4).timeout
	_spawn_wave_one()


func _spawn_wave_one() -> void:
	encounter_stage = 1
	objective_label.text = "第一阵 · 清除庭院守卫  0 / 6"
	var definitions := [
		["guard", Vector3(-10, 0.05, 2.0)], ["guard", Vector3(10, 0.05, 2.0)],
		["brute", Vector3(-5.5, 0.05, -3.0)], ["caster", Vector3(8.5, 0.05, -5.0)],
		["guard", Vector3(2.5, 0.05, -8.5)], ["caster", Vector3(-11.5, 0.05, -9.0)]
	]
	for entry in definitions:
		_spawn_enemy(entry[0], entry[1], false)


func _spawn_boss() -> void:
	encounter_stage = 2
	show_banner("殿门已开", "镇殿将军 · 赤魇")
	objective_label.text = "最终阵 · 击败镇殿将军"
	await get_tree().create_timer(1.15).timeout
	var boss := _spawn_enemy("boss", Vector3(0, 0.05, -10.0), true)
	boss.health_changed.connect(_on_boss_health_changed)
	boss_bar.visible = true
	boss_label.visible = true
	_on_boss_health_changed(boss.health, boss.max_health)
	_spawn_enemy("guard", Vector3(-7.5, 0.05, -8.0), false)
	_spawn_enemy("guard", Vector3(7.5, 0.05, -8.0), false)


func _spawn_enemy(kind: String, at: Vector3, boss: bool) -> TianqueEnemy:
	var enemy := TianqueEnemy.new()
	enemy.enemy_kind = kind
	enemy.is_boss = boss
	enemy.name = "Boss_RedNightmare" if boss else "Enemy_%s_%d" % [kind, active_enemy_count]
	enemy.position = at
	add_child(enemy)
	enemy.defeated.connect(_on_enemy_defeated)
	active_enemy_count += 1
	spawn_shockwave(at, Color(0.95, 0.12, 0.035), 1.4 if not boss else 2.8)
	return enemy


func _on_enemy_defeated(actor: Combatant) -> void:
	active_enemy_count = maxi(0, active_enemy_count - 1)
	if actor is TianqueEnemy and actor.is_boss:
		_win_game()
		return
	if encounter_stage == 1:
		objective_label.text = "第一阵 · 清除庭院守卫  %d / 6" % [6 - active_enemy_count]
		if active_enemy_count == 0:
			player.heal(70.0)
			_spawn_boss()


func _on_player_defeated(_actor: Combatant) -> void:
	game_over = true
	player.can_control = false
	overlay.visible = true
	overlay_title.text = "试炼未竟"
	overlay_subtitle.text = "按 R 再战 · 闪避拥有短暂无敌时间"
	play_sound("death", 0.84)


func _win_game() -> void:
	if game_won:
		return
	game_won = true
	player.can_control = false
	boss_bar.visible = false
	boss_label.visible = false
	overlay.visible = true
	overlay.color = Color(0.01, 0.025, 0.025, 0.72)
	overlay_title.text = "天阙已破"
	overlay_title.modulate = Color(0.92, 0.68, 0.28)
	overlay_subtitle.text = "镇殿将军已伏诛 · 按 R 重新试炼"
	spawn_shockwave(player.global_position, Color(0.9, 0.62, 0.16), 9.5)


func _update_camera(delta: float) -> void:
	if camera_follow_locked or camera == null or player == null or not is_instance_valid(player):
		return
	camera_noise_clock += delta * 38.0
	camera_shake_strength = move_toward(camera_shake_strength, 0.0, delta * 2.3)
	var shake := Vector3(sin(camera_noise_clock * 1.73), cos(camera_noise_clock * 2.31), sin(camera_noise_clock * 2.83)) * camera_shake_strength
	var target_position := player.global_position + Vector3(0, 19.5, 18.7) + shake
	camera.global_position = camera.global_position.lerp(target_position, 1.0 - exp(-delta * 5.2))
	camera.look_at(player.global_position + Vector3(0, 0.3, -5.8), Vector3.UP)


func camera_shake(strength: float) -> void:
	camera_shake_strength = maxf(camera_shake_strength, strength)


func spawn_telegraph(at: Vector3, radius: float, color: Color, duration: float) -> void:
	var disk := VisualFactory.cylinder(self, 1.0, 0.035, at + Vector3(0, 0.045, 0), color, "AttackTelegraph")
	disk.scale = Vector3(0.08, 1.0, 0.08)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(disk, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(disk, "transparency", 0.68, duration)
	tween.chain().tween_property(disk, "transparency", 1.0, 0.11)
	tween.chain().tween_callback(disk.queue_free)


func spawn_shockwave(at: Vector3, color: Color, radius: float) -> void:
	VFX.emit(self, "burst", at, color, radius, 0.65)
	play_sound("skill", randf_range(0.82, 1.08))


func spawn_star_charge(at: Vector3, radius: float, duration: float) -> void:
	VFX.emit(self, "star_charge", at, Color(0.12, 0.75, 0.82), radius, duration)


func spawn_star_impact(at: Vector3, color: Color, radius: float) -> void:
	VFX.emit(self, "star", at, color, radius, 0.8)
	play_sound("skill", randf_range(0.82, 1.08))


func spawn_heavy_charge(at: Vector3, forward: Vector3, duration: float) -> void:
	VFX.emit(self, "heavy_charge", at, Color(1.0, 0.32, 0.06), 3.35, duration, forward)


func spawn_heavy_slash(at: Vector3, forward: Vector3) -> void:
	VFX.emit(self, "heavy", at, Color(1.0, 0.24, 0.045), 3.25, 0.48, forward)


func spawn_slash(at: Vector3, forward: Vector3, radius: float, color: Color, duration: float, combo: int = 1) -> void:
	VFX.emit(self, "slash", at, color, radius, duration, forward, combo)


func spawn_impact(at: Vector3, color: Color, scale_value: float) -> void:
	VFX.emit(self, "impact", at, color, scale_value, 0.38)


func spawn_dash_echo(actor: Node3D) -> void:
	VFX.emit(self, "dash", actor.global_position, Color(0.08, 0.82, 0.84), 1.0, 0.46, -actor.global_transform.basis.z, 1, actor)
	play_sound("skill", 1.45)


func spawn_enemy_orb(from: Vector3, target_actor: TianquePlayer) -> void:
	if target_actor == null or target_actor.dead:
		return
	var orb := VisualFactory.sphere(self, 0.32, from, Color(0.08, 0.93, 0.78), Vector3.ONE, "SpiritOrb")
	orb.material_override = VisualFactory.material(Color(0.08, 0.93, 0.78), 0.0, 0.3, 4.5)
	var target_position := target_actor.global_position + Vector3(0, 0.65, 0)
	var tween := create_tween()
	tween.tween_property(orb, "position", target_position, 0.66).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if is_instance_valid(target_actor) and not target_actor.dead and orb.global_position.distance_to(target_actor.global_position + Vector3(0, 0.65, 0)) < 1.8:
			target_actor.take_damage(10.0, orb.global_position, 2.0)
		spawn_impact(orb.global_position, Color(0.08, 0.93, 0.78), 0.7)
		orb.queue_free()
	)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.color = Color(0.0, 0.0, 0.0, 0.035)
	layer.add_child(vignette)

	var title := Label.new()
	title.text = "天 阙 试 炼"
	title.position = Vector2(36, 28)
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color(0.93, 0.72, 0.36))
	layer.add_child(title)
	var rule := ColorRect.new()
	rule.position = Vector2(37, 68)
	rule.size = Vector2(238, 2)
	rule.color = Color(0.83, 0.18, 0.055, 0.88)
	layer.add_child(rule)
	objective_label = Label.new()
	objective_label.text = "试炼即将开始"
	objective_label.position = Vector2(37, 82)
	objective_label.add_theme_font_size_override("font_size", 16)
	objective_label.add_theme_color_override("font_color", Color(0.72, 0.8, 0.79))
	layer.add_child(objective_label)

	var health_panel := PanelContainer.new()
	health_panel.position = Vector2(34, 634)
	health_panel.size = Vector2(360, 58)
	health_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.028, 0.032, 0.92), Color(0.68, 0.4, 0.17, 0.65), 2))
	layer.add_child(health_panel)
	var health_margin := MarginContainer.new()
	health_margin.add_theme_constant_override("margin_left", 18)
	health_margin.add_theme_constant_override("margin_right", 18)
	health_margin.add_theme_constant_override("margin_top", 10)
	health_margin.add_theme_constant_override("margin_bottom", 9)
	health_panel.add_child(health_margin)
	var health_stack := VBoxContainer.new()
	health_margin.add_child(health_stack)
	health_text = Label.new()
	health_text.text = "无名镇守者"
	health_text.add_theme_font_size_override("font_size", 14)
	health_text.add_theme_color_override("font_color", Color(0.9, 0.76, 0.5))
	health_stack.add_child(health_text)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(320, 13)
	health_bar.show_percentage = false
	health_bar.add_theme_stylebox_override("background", _panel_style(Color(0.08, 0.09, 0.09), Color(0.12, 0.14, 0.14), 0))
	health_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.75, 0.09, 0.04), Color(0.95, 0.36, 0.08), 0))
	health_stack.add_child(health_bar)

	var skills := HBoxContainer.new()
	skills.position = Vector2(694, 626)
	skills.add_theme_constant_override("separation", 10)
	layer.add_child(skills)
	_add_skill_card(skills, "J", "三连斩", "attack")
	_add_skill_card(skills, "K", "破阵斩", "heavy")
	_add_skill_card(skills, "L", "坠星", "skill")
	_add_skill_card(skills, "SPACE", "影步", "dash")
	_add_skill_card(skills, "H", "调息", "heal")

	boss_label = Label.new()
	boss_label.text = "镇殿将军 · 赤魇"
	boss_label.position = Vector2(490, 25)
	boss_label.size = Vector2(300, 26)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 17)
	boss_label.add_theme_color_override("font_color", Color(0.95, 0.58, 0.25))
	boss_label.visible = false
	layer.add_child(boss_label)
	boss_bar = ProgressBar.new()
	boss_bar.position = Vector2(390, 53)
	boss_bar.size = Vector2(500, 12)
	boss_bar.show_percentage = false
	boss_bar.add_theme_stylebox_override("background", _panel_style(Color(0.025, 0.025, 0.03, 0.9), Color(0.35, 0.22, 0.12), 1))
	boss_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.68, 0.035, 0.025), Color(1.0, 0.25, 0.05), 1))
	boss_bar.visible = false
	layer.add_child(boss_bar)

	_build_banner(layer)
	_build_overlay(layer)


func _add_skill_card(parent: HBoxContainer, key_text: String, title_text: String, id: String) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(94, 66)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.022, 0.035, 0.04, 0.94), Color(0.24, 0.48, 0.49, 0.7), 2))
	parent.add_child(panel)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(stack)
	var key := Label.new()
	key.text = key_text
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.add_theme_font_size_override("font_size", 13)
	key.add_theme_color_override("font_color", Color(0.96, 0.59, 0.24))
	stack.add_child(key)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.78, 0.86, 0.85))
	stack.add_child(title)
	var cooldown := Label.new()
	cooldown.text = "就绪"
	cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown.add_theme_font_size_override("font_size", 11)
	cooldown.add_theme_color_override("font_color", Color(0.31, 0.74, 0.7))
	stack.add_child(cooldown)
	cooldown_labels[id] = cooldown


func _build_banner(layer: CanvasLayer) -> void:
	banner_panel = PanelContainer.new()
	banner_panel.position = Vector2(390, 140)
	banner_panel.size = Vector2(500, 104)
	banner_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.022, 0.025, 0.9), Color(0.8, 0.37, 0.08, 0.72), 2))
	banner_panel.modulate.a = 0.0
	layer.add_child(banner_panel)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_panel.add_child(stack)
	banner_title = Label.new()
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_font_size_override("font_size", 27)
	banner_title.add_theme_color_override("font_color", Color(0.95, 0.65, 0.28))
	stack.add_child(banner_title)
	banner_subtitle = Label.new()
	banner_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_subtitle.add_theme_font_size_override("font_size", 15)
	banner_subtitle.add_theme_color_override("font_color", Color(0.66, 0.76, 0.75))
	stack.add_child(banner_subtitle)


func _build_overlay(layer: CanvasLayer) -> void:
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.015, 0.015, 0.018, 0.76)
	overlay.visible = false
	layer.add_child(overlay)
	overlay_title = Label.new()
	overlay_title.position = Vector2(340, 270)
	overlay_title.size = Vector2(600, 74)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.add_theme_font_size_override("font_size", 48)
	overlay_title.add_theme_color_override("font_color", Color(0.85, 0.17, 0.07))
	overlay.add_child(overlay_title)
	overlay_subtitle = Label.new()
	overlay_subtitle.position = Vector2(290, 354)
	overlay_subtitle.size = Vector2(700, 40)
	overlay_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_subtitle.add_theme_font_size_override("font_size", 19)
	overlay_subtitle.add_theme_color_override("font_color", Color(0.72, 0.79, 0.78))
	overlay.add_child(overlay_subtitle)


func _panel_style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func show_banner(title_text: String, subtitle_text: String) -> void:
	banner_title.text = title_text
	banner_subtitle.text = subtitle_text
	var tween := create_tween()
	tween.tween_property(banner_panel, "modulate:a", 1.0, 0.22)
	tween.tween_interval(1.8)
	tween.tween_property(banner_panel, "modulate:a", 0.0, 0.35)


func _on_player_health_changed(current: float, maximum: float) -> void:
	if health_bar == null:
		return
	health_bar.max_value = maximum
	health_bar.value = current
	health_text.text = "无名镇守者   %d / %d" % [ceili(current), ceili(maximum)]
	if player != null:
		update_heal_status(player.heal_charges, player.MAX_HEAL_CHARGES, current >= maximum)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current


func update_player_cooldowns(dash: float, heavy: float, skill: float) -> void:
	_set_cooldown_label("attack", 0.0)
	_set_cooldown_label("dash", dash)
	_set_cooldown_label("heavy", heavy)
	_set_cooldown_label("skill", skill)


func update_heal_status(charges: int, maximum: int, full_health: bool) -> void:
	if not cooldown_labels.has("heal"):
		return
	var label: Label = cooldown_labels.heal
	if charges <= 0:
		label.text = "已用尽"
		label.modulate = Color(0.68, 0.25, 0.2)
	elif full_health:
		label.text = "生命已满 %d/%d" % [charges, maximum]
		label.modulate = Color(0.52, 0.68, 0.61)
	else:
		label.text = "剩余 %d/%d" % [charges, maximum]
		label.modulate = Color(0.31, 0.82, 0.53)


func spawn_heal_effect(at: Vector3) -> void:
	VFX.emit(self, "heal", at - Vector3(0, 0.55, 0), Color(0.03, 0.82, 0.23), 1.0, 0.95)


func _set_cooldown_label(id: String, seconds: float) -> void:
	if not cooldown_labels.has(id):
		return
	var label: Label = cooldown_labels[id]
	label.text = "就绪" if seconds <= 0.0 else "%.1fs" % seconds
	label.modulate = Color(0.31, 0.74, 0.7) if seconds <= 0.0 else Color(0.72, 0.3, 0.2)


func _build_audio() -> void:
	hit_sound = _make_tone(92.0, 0.085, true)
	skill_sound = _make_tone(182.0, 0.18, false)
	death_sound = _make_tone(58.0, 0.42, true)


func _make_tone(frequency: float, duration: float, noisy: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in range(count):
		var time := float(index) / sample_rate
		var envelope := pow(1.0 - float(index) / count, 2.2)
		var wave := sin(TAU * frequency * time) * 0.55 + sin(TAU * frequency * 2.03 * time) * 0.24
		if noisy:
			wave += randf_range(-0.38, 0.38)
		data.encode_s16(index * 2, int(clampf(wave * envelope, -1.0, 1.0) * 32760.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func play_sound(kind: String, pitch: float = 1.0) -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = death_sound if kind == "death" else (skill_sound if kind == "skill" else hit_sound)
	audio.pitch_scale = pitch
	audio.volume_db = -7.0 if kind == "hit" else -10.0
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()



## Opt-in deterministic QA harness; normal encounters and controls are unchanged.
func _run_vfx_showcase() -> void:
	camera_follow_locked = true
	player.global_position = Vector3(0, 0, 3)
	player.rotation.y = -0.35
	camera.global_position = player.global_position + Vector3(0, 12.5, 13.0)
	camera.look_at(player.global_position + Vector3(0, 0.4, -1.0), Vector3.UP)
	banner_panel.visible = false
	objective_label.text = "技能演示 · 原有伤害、判定与冷却不变"
	var output_dir := ProjectSettings.globalize_path("res://qa/vfx")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await get_tree().create_timer(0.7).timeout
	for step in range(1, 4):
		objective_label.text = "J · 三连斩 · 第 %d 式" % step
		player.request_light_attack()
		await get_tree().create_timer(0.12).timeout
		await _save_vfx_frame(output_dir, "j-combo-%d" % step)
		await get_tree().create_timer(0.30 if step < 3 else 0.8).timeout
	objective_label.text = "K · 破阵斩 · 聚气 / 刀锋 / 迸火"
	player.request_heavy_attack()
	await get_tree().create_timer(0.20).timeout
	await _save_vfx_frame(output_dir, "k-charge")
	await get_tree().create_timer(0.23).timeout
	await _save_vfx_frame(output_dir, "k-impact")
	await get_tree().create_timer(1.0).timeout
	objective_label.text = "L · 坠星 · 引星 / 陨落 / 震地"
	player.request_skill()
	await get_tree().create_timer(0.36).timeout
	await _save_vfx_frame(output_dir, "l-descent")
	await get_tree().create_timer(0.18).timeout
	await _save_vfx_frame(output_dir, "l-impact")
	await get_tree().create_timer(0.16).timeout
	await _save_vfx_frame(output_dir, "l-afterglow")
	await get_tree().create_timer(0.8).timeout
	objective_label.text = "SPACE · 影步 · 随位移拖尾"
	player.request_dash()
	await get_tree().create_timer(0.17).timeout
	await _save_vfx_frame(output_dir, "space-dash")
	await get_tree().create_timer(0.75).timeout
	objective_label.text = "H · 调息 · 青叶回旋 / 灵气上升"
	player.health = player.max_health - 50.0
	player.request_heal()
	await get_tree().create_timer(0.4).timeout
	await _save_vfx_frame(output_dir, "h-heal")
	await get_tree().create_timer(1.1).timeout
	objective_label.text = "实战镜头 · 敌人轮廓与范围可读性"
	player.global_position = Vector3(0, 0, 3)
	camera.global_position = player.global_position + Vector3(0, 19.5, 18.7)
	camera.look_at(player.global_position + Vector3(0, 0.3, -5.8), Vector3.UP)
	for offset in [Vector3(-2.3, 0, -1.5), Vector3(2.3, 0, -1.5), Vector3(0, 0, -3.6)]:
		var guard := _spawn_enemy("guard", player.global_position + offset, false)
		guard.set_physics_process(false)
	await get_tree().create_timer(0.8).timeout
	player.skill_cooldown = 0.0
	player.request_skill()
	await get_tree().create_timer(0.58).timeout
	await _save_vfx_frame(output_dir, "combat-readability")
	await get_tree().create_timer(0.9).timeout
	print("TIANQUE_VFX_SHOWCASE=PASS ", output_dir)
	get_tree().quit()


func _save_vfx_frame(directory: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
	if error != OK:
		push_error("VFX screenshot failed: " + label)


func _run_vfx_test() -> void:
	# Exercise repeated emissions, follow-target deletion and bounded cleanup.
	for i in range(3):
		spawn_slash(Vector3.ZERO, Vector3.FORWARD, 2.5, Color.ORANGE, 0.34, i + 1)
		spawn_heavy_charge(Vector3.ZERO, Vector3.FORWARD, 0.32)
		spawn_heavy_slash(Vector3.ZERO, Vector3.FORWARD)
		spawn_star_charge(Vector3.ZERO, 5.2, 0.46)
		spawn_star_impact(Vector3.ZERO, Color.CYAN, 5.3)
		spawn_impact(Vector3.ZERO, Color.ORANGE, 1.0)
		spawn_heal_effect(Vector3.ZERO)
		spawn_dash_echo(player)
		await get_tree().create_timer(0.1).timeout
	var transient_actor := Node3D.new()
	add_child(transient_actor)
	spawn_dash_echo(transient_actor)
	transient_actor.queue_free()
	await get_tree().create_timer(1.2).timeout
	if not get_tree().get_nodes_in_group("combat_vfx").is_empty():
		push_error("VFX cleanup failed")
		get_tree().quit(1)
		return
	print("TIANQUE_VFX_TEST=PASS")
	get_tree().quit()
