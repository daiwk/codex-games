extends Node3D

const Fighter = preload("res://scripts/fighter.gd")
const Arena = preload("res://scripts/arena.gd")
const Effects = preload("res://scripts/combat_fx.gd")
const HUD = preload("res://scripts/hud.gd")
const SkillEffects = preload("res://scripts/skill_fx.gd")
const Roster = preload("res://scripts/roster.gd")

var character_id = "zhaoyun"
var weapon_id = "sword"
var opponent_id = ""
var difficulty = 1
var phase = "menu"
var paused = false
var scores = [0, 0]
var round_time = 90.0
var round_number = 1
var phase_clock = 0.0
var last_winner = 0
var overtime = false
var player: DuelFighter
var enemy: DuelFighter
var camera: Camera3D
var fx: DuelFX
var skill_fx: DuelSkillFX
var hud: DuelHUD
var toast = ""
var toast_time = 0.0
var rng = RandomNumberGenerator.new()
var ai_enabled = true
var ai_think = 0.0
var ai_cooldown = 0.0
var ai_guard = 0.0
var ai_strafe = 1.0
var shake = 0.0
var impact_zoom = 0.0
var camera_base_position = Vector3.ZERO
var camera_base_fov = 54.0
var hit_stop_until = 0
var testing = false
var elapsed = 0.0
var screenshot_pending = false
var camera_override = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	testing = "--test" in OS.get_cmdline_user_args() or "--skills-test" in OS.get_cmdline_user_args() or "--role-test" in OS.get_cmdline_user_args()
	rng.seed = 714 if testing else int(Time.get_unix_time_from_system())
	_configure_inputs()
	add_child(Arena.new())
	fx = Effects.new()
	add_child(fx)
	skill_fx = SkillEffects.new()
	add_child(skill_fx)
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 120
	camera.current = true
	add_child(camera)
	_spawn_fighters()
	var canvas = CanvasLayer.new()
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	hud = HUD.new()
	hud.game = self
	canvas.add_child(hud)
	_position_preview()
	_update_camera(1.0, true)
	var web_bridge = preload("res://scripts/web_bridge.gd").new()
	web_bridge.name = "WebBridge"
	web_bridge.game = self
	add_child(web_bridge)
	if "--skills-test" in OS.get_cmdline_user_args() or "--role-test" in OS.get_cmdline_user_args():
		call_deferred("_start_skill_tests")
	elif "--skills-showcase" in OS.get_cmdline_user_args():
		call_deferred("_start_skill_showcase")
	elif testing:
		call_deferred("_start_tests")
	elif "--showcase" in OS.get_cmdline_user_args():
		call_deferred("_start_showcase")
	elif "--input-test" in OS.get_cmdline_user_args():
		call_deferred("_start_input_tests")
	elif "--asset-review" in OS.get_cmdline_user_args():
		call_deferred("_start_asset_review")

func fighter_name(id: String) -> String:
	return String(Roster.character(id).name)

func _configure_inputs() -> void:
	var keys = {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"light": [KEY_J], "heavy": [KEY_K], "guard": [KEY_L, KEY_SHIFT], "dodge": [KEY_SPACE],
		"skill_rush": [KEY_Q], "skill_counter": [KEY_E], "ultimate": [KEY_U]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for pair in [["light", MOUSE_BUTTON_LEFT], ["heavy", MOUSE_BUTTON_RIGHT]]:
		var event = InputEventMouseButton.new()
		event.button_index = pair[1]
		InputMap.action_add_event(pair[0], event)

func _spawn_fighters() -> void:
	fx.clear_fighters()
	skill_fx.clear()
	for fighter in [player, enemy]:
		if is_instance_valid(fighter):
			remove_child(fighter)
			fighter.queue_free()
	player = Fighter.new()
	player.name = "Player"
	player.character_id = character_id
	weapon_id = Roster.resolve_weapon(character_id, weapon_id)
	player.weapon_id = weapon_id
	player.is_player = true
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	enemy = Fighter.new()
	enemy.name = "Opponent"
	enemy.character_id = String(Roster.character(character_id).opponent) if opponent_id.is_empty() else opponent_id
	enemy.weapon_id = Roster.resolve_weapon(enemy.character_id, "saber" if weapon_id == "sword" else "sword")
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	player.opponent = enemy
	enemy.opponent = player
	for fighter in [player, enemy]:
		fighter.strike_requested.connect(_resolve_strike)
		fighter.impact_received.connect(_on_impact)
		fighter.action_started.connect(_on_action)
		fighter.skill_triggered.connect(_on_skill)
		fx.register_fighter(fighter)

func select_character(id: String) -> void:
	if phase != "menu" or character_id == id or id not in Roster.IDS:
		return
	character_id = id
	weapon_id = Roster.resolve_weapon(character_id, weapon_id)
	_spawn_fighters()
	_position_preview()
	fx.sound("step", -16.0)

func select_weapon(id: String) -> void:
	if phase != "menu" or weapon_id == id or id not in Roster.weapon_choices(character_id):
		return
	weapon_id = id
	_spawn_fighters()
	_position_preview()
	fx.sound("clang", -20.0, 1.3)

func select_opponent(id: String) -> void:
	if phase != "menu" or id not in Roster.IDS:
		return
	opponent_id = id
	_spawn_fighters()
	_position_preview()

func _position_preview() -> void:
	player.enabled = false
	enemy.enabled = false
	player.position = Vector3(1.45, 0.015, 0.7)
	enemy.position = Vector3(3.3, 0.015, -0.9)
	player.rotation.y = -0.20
	enemy.rotation.y = -0.35
	player.reset_fighter()
	enemy.reset_fighter()

func start_match() -> void:
	get_tree().paused = false
	paused = false
	Engine.time_scale = 1.0
	hit_stop_until = 0
	scores = [0, 0]
	for fighter in [player, enemy]:
		fighter.damage_dealt = 0.0
		fighter.parries = 0
		fighter.blocked_hits = 0
		fighter.dodged_hits = 0
	_new_round()

func _new_round() -> void:
	skill_fx.clear()
	shake = 0.0
	impact_zoom = 0.0
	round_number = scores[0] + scores[1] + 1
	for fighter in [player, enemy]:
		fighter.reset_fighter()
		fighter.enabled = false
	player.position = Vector3(0, 0.015, 2.65)
	enemy.position = Vector3(0, 0.015, -2.65)
	player.rotation.y = PI
	enemy.rotation.y = 0.0
	phase = "countdown"
	phase_clock = 2.7
	round_time = 90.0
	overtime = false
	ai_guard = 0.0
	ai_think = 0.0
	ai_cooldown = 0.65
	toast_time = 0.0
	if is_instance_valid(hud):
		hud.displayed_hp = [120.0, 120.0]
	fx.sound("gong", -17.0)

func return_to_menu() -> void:
	skill_fx.clear()
	shake = 0.0
	impact_zoom = 0.0
	get_tree().paused = false
	paused = false
	Engine.time_scale = 1.0
	hit_stop_until = 0
	phase = "menu"
	scores = [0, 0]
	_position_preview()

func toggle_pause() -> void:
	if phase == "menu" or phase == "match_end":
		return
	paused = not paused
	get_tree().paused = paused
	Engine.time_scale = 1.0
	hit_stop_until = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				toggle_pause()
			KEY_F:
				var fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_M:
				fx.muted = not fx.muted
				toast = "声音已关闭" if fx.muted else "声音已开启"
				toast_time = 1.4
			KEY_R:
				if phase != "menu":
					start_match()
			KEY_ENTER:
				if phase in ["menu", "match_end"]:
					start_match()
			KEY_1:
				select_character("zhaoyun")
			KEY_2:
				select_character("machao")
			KEY_3:
				select_character("guanyu")
			KEY_4:
				select_character("zhangfei")
			KEY_5:
				select_character("lubu")

func _physics_process(delta: float) -> void:
	if paused:
		return
	toast_time = maxf(0.0, toast_time - delta)
	match phase:
		"countdown":
			phase_clock -= delta
			if phase_clock <= 0.0:
				phase = "fight"
				player.enabled = true
				enemy.enabled = true
		"fight":
			round_time = maxf(0.0, round_time - delta)
			if player.hp <= 0.0 or enemy.hp <= 0.0:
				_end_round(0 if enemy.hp <= 0.0 else 1)
				return
			if round_time <= 0.0:
				if absf(player.hp - enemy.hp) < 0.01:
					overtime = true
					player.hp = 1.0
					enemy.hp = 1.0
					round_time = 15.0
					toast = "加时 · 一击决胜"
					toast_time = 2.8
				else:
					_end_round(0 if player.hp > enemy.hp else 1)
					return
			if not testing:
				_player_input()
			if ai_enabled:
				_update_ai(delta)
		"round_end":
			phase_clock -= delta
			if phase_clock <= 0.0:
				if scores[0] >= 2 or scores[1] >= 2:
					phase = "match_end"
					fx.sound("gong", -12.0, 0.82)
				else:
					_new_round()

func _player_input() -> void:
	var input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var right = camera.global_basis.x
	var forward = -camera.global_basis.z
	right.y = 0.0
	forward.y = 0.0
	player.input_move = right.normalized() * input.x + forward.normalized() * -input.y
	player.wants_block = Input.is_action_pressed("guard")
	if Input.is_action_just_pressed("ultimate"):
		if not player.request_ultimate():
			_skill_hint("ultimate")
	elif Input.is_action_just_pressed("skill_rush"):
		if not player.request_skill("rush"):
			_skill_hint("rush")
	elif Input.is_action_just_pressed("skill_counter"):
		if not player.request_skill("counter"):
			_skill_hint("counter")
	elif Input.is_action_just_pressed("dodge"):
		if not player.request_dodge(player.input_move) and player.stamina < 24.0:
			_stamina_hint()
	elif Input.is_action_just_pressed("heavy"):
		if not player.request_heavy() and player.stamina < 29.0:
			_stamina_hint()
	elif Input.is_action_just_pressed("light"):
		if not player.request_light() and player.stamina < 15.0:
			_stamina_hint()

func _stamina_hint() -> void:
	toast = "体力不足 · 拉开距离调息"
	toast_time = 1.5

func _skill_hint(id: String) -> void:
	if player.state not in ["idle", "move", "block"]:
		return
	if id == "ultimate":
		toast = "战意 %d / 100 · 攻防积攒战意" % player.energy
	elif player.cooldowns[id] > 0.0:
		toast = "技能冷却 · %.1f 秒" % player.cooldowns[id]
	else:
		toast = "体力不足 · 暂缓出招"
	toast_time = 1.4

func _update_ai(delta: float) -> void:
	ai_think -= delta
	ai_cooldown = maxf(0.0, ai_cooldown - delta)
	ai_guard = maxf(0.0, ai_guard - delta)
	enemy.wants_block = ai_guard > 0.0
	if ai_think > 0.0:
		return
	ai_think = [0.23, 0.16, 0.115][difficulty]
	var toward = player.position - enemy.position
	toward.y = 0.0
	var distance = toward.length()
	toward = toward.normalized()
	var side = Vector3(-toward.z, 0, toward.x) * ai_strafe
	enemy.input_move = Vector3.ZERO
	if rng.randf() < 0.08:
		ai_strafe *= -1.0
	if enemy.state in ["hit", "stagger", "dodge", "dead", "skill", "ultimate"]:
		return
	if player.state == "ultimate" and distance < maxf(3.6, player.ultimate_radius() + 0.5):
		if player.skill_stage == "windup" and distance < 1.9 and ai_cooldown <= 0.0 and rng.randf() < [0.08, 0.30, 0.48][difficulty]:
			if enemy.request_heavy():
				ai_cooldown = 1.0
				return
		var evade_at = 1.12 if player.character_id == "machao" else 0.54
		if player.action_time >= evade_at and rng.randf() < [0.30, 0.60, 0.85][difficulty]:
			if enemy.request_dodge((side - toward * 0.8).normalized()):
				return
		enemy.input_move = (-toward + side * 0.5).normalized()
		return
	if ai_cooldown <= 0.0 and distance < (4.2 if enemy.character_id == "zhaoyun" else 3.5) and enemy.skill_ready("ultimate") and rng.randf() < [0.20, 0.42, 0.64][difficulty]:
		if enemy.request_ultimate():
			ai_cooldown = 3.2
			return
	var thrust_role: bool = enemy.character_id in ["zhaoyun", "zhangfei"]
	var use_offensive_q = distance > 2.8 and distance < 5.2 if thrust_role else distance < enemy.basic_reach() + 0.6 and distance > 1.2
	if use_offensive_q and ai_cooldown <= 0.0 and rng.randf() < [0.12, 0.25, 0.36][difficulty]:
		if enemy.request_skill("rush"):
			ai_cooldown = 1.05
			return
	if enemy.character_id in ["machao", "zhangfei"] and player.state == "block" and distance < 2.7 and ai_cooldown <= 0.0:
		if rng.randf() < [0.20, 0.50, 0.78][difficulty] and enemy.request_skill("counter"):
			ai_cooldown = 1.2
			return
	if enemy.character_id == "lubu" and distance > 1.6 and distance < 4.2 and ai_cooldown <= 0.0:
		if rng.randf() < [0.12, 0.26, 0.40][difficulty] and enemy.request_skill("counter"):
			ai_cooldown = 1.2
			return
	if enemy.state == "attack":
		if enemy.action_time > 0.28 and enemy.combo < 2 and rng.randf() < [0.18, 0.47, 0.72][difficulty]:
			enemy.request_light()
		return
	if enemy.stamina < 27:
		enemy.input_move = (-toward + side * 0.30).normalized() if distance < 3.5 else side * 0.35
		return
	if player.state in ["attack", "skill"] and distance < 2.8 and player.action_time < 0.42:
		var reaction = [0.23, 0.11, 0.045][difficulty]
		if player.action_time >= reaction:
			if enemy.character_id in ["zhaoyun", "guanyu"] and rng.randf() < [0.10, 0.24, 0.40][difficulty] and enemy.request_skill("counter"):
				ai_cooldown = 0.9
				return
			if player.attack.get("heavy", false) and rng.randf() < [0.15, 0.48, 0.72][difficulty]:
				if enemy.request_dodge((side - toward * 0.3).normalized()):
					ai_cooldown = 0.38
					return
			if rng.randf() < [0.30, 0.52, 0.72][difficulty]:
				ai_guard = 0.45 + rng.randf() * 0.25
				enemy.wants_block = true
				return
	if distance > enemy.preferred_distance():
		enemy.input_move = (toward + side * 0.14).normalized()
	elif ai_cooldown > 0.0:
		enemy.input_move = side * 0.42 + (-toward * 0.25 if distance < 1.25 else Vector3.ZERO)
	if distance < enemy.basic_reach() and ai_cooldown <= 0.0 and ai_guard <= 0.0:
		var heavy_chance = 0.56 if player.state == "block" else 0.25
		if enemy.stamina > 48.0 and rng.randf() < heavy_chance:
			enemy.request_heavy()
		else:
			enemy.request_light()
		ai_cooldown = rng.randf_range(0.75, 1.20) * [1.38, 1.0, 0.73][difficulty]

func _resolve_strike(attacker: DuelFighter, data: Dictionary) -> void:
	if phase != "fight" or attacker.hit_landed or attacker.hp <= 0.0:
		return
	var defender: DuelFighter = attacker.opponent
	var offset = defender.global_position - attacker.global_position
	offset.y = 0.0
	if offset.length() > float(data.reach):
		return
	if data.get("shape", "") == "line":
		var projection = offset.dot(attacker.forward())
		var sideways = (offset - attacker.forward() * projection).length()
		if projection < 0.0 or sideways > float(data.get("half_width", 0.5)):
			return
	if not data.get("radial", false) and offset.normalized().dot(attacker.forward()) < float(data.get("min_dot", 0.12)):
		return
	# Test both the current blade and its swept tip against the body capsule.
	# A close-range allowance covers contact hidden inside armor and the frame
	# immediately before the imported skeleton advances.
	var low = defender.global_position + Vector3.UP * 0.42
	var high = defender.global_position + Vector3.UP * 1.55
	var blade = Geometry3D.get_closest_points_between_segments(attacker.blade_base(), attacker.blade_tip(), low, high)
	var sweep = Geometry3D.get_closest_points_between_segments(attacker.previous_tip, attacker.blade_tip(), low, high)
	var contact = minf(blade[0].distance_to(blade[1]), sweep[0].distance_to(sweep[1]))
	if data.get("shape", "") != "line" and not data.get("wave", false) and contact > 0.70 and offset.length() > 1.48:
		return
	attacker.hit_landed = true
	defender.receive_strike(attacker, data)

func _on_impact(fighter: DuelFighter, outcome: String, at: Vector3) -> void:
	var damage = int(fighter.opponent.attack.get("damage", 0)) if outcome in ["hit", "heavy_hit"] else 0
	fx.burst(at, outcome, damage)
	if outcome != "evade":
		shake = maxf(shake, 0.10 if outcome in ["heavy_hit", "parry", "counter", "break"] else 0.045)
		if not testing:
			Engine.time_scale = 0.12
			hit_stop_until = Time.get_ticks_msec() + (75 if outcome in ["heavy_hit", "parry"] else 48)
	if outcome == "parry":
		toast = "招架成功 · 趁势反击" if fighter.is_player else "被招架 · 注意出招节奏"
		toast_time = 1.5
	elif outcome == "break":
		toast = "防御崩解 · 拉开距离" if fighter.is_player else "对手破防 · 进攻时机"
		toast_time = 1.5

func _on_action(fighter: DuelFighter, action: String) -> void:
	match action:
		"light", "heavy":
			fx.sound("heavy" if action == "heavy" else "swing", -10.0, rng.randf_range(0.93, 1.08))
		"step":
			fx.sound("step", -26.0 if fighter.is_player else -30.0, rng.randf_range(0.9, 1.1))
		"dodge":
			fx.sound("dodge", -14.0)
		"ultimate_ready":
			fx.sound("parry", -19.0, 0.75)

func _on_skill(fighter: DuelFighter, id: String, stage: String) -> void:
	skill_fx.play_skill(fighter, id, stage)
	if fighter.is_two_handed():
		if stage == "start":
			fx.sound("charge" if id == "ultimate" else "swing", -14.0, 0.8)
		elif stage in ["release", "strike", "finish"]:
			fx.sound("thrust" if fighter.character_id == "zhangfei" and id != "counter" else "heavy", -13.0)
			if id == "ultimate":
				shake = maxf(shake, 0.13 if stage == "finish" else 0.065)
		return
	if id == "ultimate":
		if stage == "start":
			fx.sound("charge", -11.0, 1.50 if fighter.character_id == "zhaoyun" else 0.72)
		elif stage == "release":
			fx.sound("thrust" if fighter.character_id == "zhaoyun" else "heavy", -12.0)
		elif stage in ["strike", "finish"]:
			if fighter.character_id == "zhaoyun":
				fx.sound("thrust", -10.0, 1.10 if stage == "finish" else 1.35)
				shake = maxf(shake, 0.08 if stage == "finish" else 0.035)
			else:
				fx.sound("ultimate", -8.0, 0.92)
				shake = maxf(shake, 0.27)
				impact_zoom = maxf(impact_zoom, 3.8)
	elif id == "rush":
		if stage in ["start", "release"]:
			if fighter.character_id == "zhaoyun":
				fx.sound("dodge" if stage == "start" else "thrust", -12.0)
			else:
				fx.sound("heavy", -13.0 if stage == "start" else -10.0, 0.8)
	elif id == "counter":
		if stage == "start":
			fx.sound("dodge" if fighter.character_id == "zhaoyun" else "heavy", -16.0, 0.9)
		elif stage == "release":
			fx.sound("thrust" if fighter.character_id == "zhaoyun" else "roar", -10.0)
			if fighter.character_id == "machao":
				shake = maxf(shake, 0.15)
				impact_zoom = maxf(impact_zoom, 1.8)

func _end_round(winner: int) -> void:
	scores[winner] += 1
	last_winner = winner
	phase = "round_end"
	phase_clock = 3.2
	for fighter in [player, enemy]:
		fighter.enabled = false
		fighter.input_move = Vector3.ZERO
		if fighter.hp > 0.0:
			fighter._idle()
	Engine.time_scale = 1.0
	hit_stop_until = 0
	fx.sound("gong", -21.0, 1.05 if winner == 0 else 0.85)

func _process(delta: float) -> void:
	if hit_stop_until > 0 and Time.get_ticks_msec() >= hit_stop_until:
		Engine.time_scale = 1.0
		hit_stop_until = 0
	if paused:
		return
	elapsed += delta
	shake = move_toward(shake, 0.0, delta * 0.55)
	impact_zoom = move_toward(impact_zoom, 0.0, delta * 12.0)
	_update_camera(delta)

func _update_camera(delta: float, instant = false) -> void:
	if not is_instance_valid(player) or camera_override:
		return
	var desired: Vector3
	var target: Vector3
	var fov: float
	if phase == "menu":
		desired = Vector3(3.5 + sin(elapsed * 0.16) * 0.12, 2.55, 6.8)
		target = Vector3(0.6, 0.98, 0.0)
		fov = 42.0
	else:
		var axis = enemy.global_position - player.global_position
		axis.y = 0.0
		var separation = axis.length()
		axis = axis.normalized() if separation > 0.05 else Vector3.FORWARD
		var side = Vector3(-axis.z, 0, axis.x)
		var middle = (player.global_position + enemy.global_position) * 0.5
		var distance = clampf(5.4 + separation * 0.30, 6.0, 8.6)
		desired = middle - axis * distance + side * 1.7 + Vector3.UP * 3.25
		target = middle + Vector3.UP * 0.92
		fov = 54.0
		if player.state == "ultimate" or enemy.state == "ultimate":
			desired += -axis * 0.45 + Vector3.UP * 0.15
			fov = 56.0
			for fighter in [player, enemy]:
				if fighter.state == "ultimate" and fighter.character_id == "machao":
					# A restrained push-in releases into the wider impact view.
					fov = 52.0 if fighter.action_time < 1.0 else 58.0
	var weight = 1.0 if instant else 1.0 - exp(-delta * 5.2)
	# Keep the smoothed pose separate so repeated shake cannot drift the framing.
	camera_base_position = desired if instant else camera_base_position.lerp(desired, weight)
	camera_base_fov = fov if instant else lerpf(camera_base_fov, fov, weight)
	camera.position = camera_base_position
	camera.fov = camera_base_fov + impact_zoom
	if shake > 0.0:
		var tremor = Vector3(sin(elapsed * 91), cos(elapsed * 79) * 0.65, sin(elapsed * 63) * 0.3)
		camera.position += camera.basis * tremor * shake
	camera.look_at(target, Vector3.UP)
	if shake > 0.0:
		camera.rotate_object_local(Vector3.FORWARD, sin(elapsed * 71) * shake * 0.035)

func snapshot() -> Dictionary:
	return {"phase": phase, "paused": paused, "scores": scores.duplicate(), "seconds": round_time,
		"player": {"character": player.character_id, "weapon": player.weapon_id, "hp": player.hp,
			"stamina": player.stamina, "energy": player.energy, "cooldowns": player.cooldowns.duplicate(),
			"skill": player.skill_id, "skill_stage": player.skill_stage, "state": player.state, "combo": player.combo, "position": [player.position.x, player.position.y, player.position.z]},
		"enemy": {"character": enemy.character_id, "weapon": enemy.weapon_id, "hp": enemy.hp,
			"stamina": enemy.stamina, "energy": enemy.energy, "cooldowns": enemy.cooldowns.duplicate(),
			"skill": enemy.skill_id, "skill_stage": enemy.skill_stage, "state": enemy.state, "position": [enemy.position.x, enemy.position.y, enemy.position.z]}}

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _start_tests() -> void:
	var suite = load("res://tools/integration_test.gd").new()
	add_child(suite)
	suite.run(self)

func _start_showcase() -> void:
	var suite = load("res://tools/showcase.gd").new()
	add_child(suite)
	suite.run(self)

func _start_input_tests() -> void:
	var suite = load("res://tools/input_test.gd").new()
	add_child(suite)
	suite.run(self)

func _start_asset_review() -> void:
	var suite = load("res://tools/asset_review.gd").new()
	add_child(suite)
	suite.run(self)

func _start_skill_tests() -> void:
	var suite = load("res://tools/role_skills_test.gd").new()
	add_child(suite)
	suite.run(self)

func _start_skill_showcase() -> void:
	var suite = load("res://tools/skills_showcase.gd").new()
	add_child(suite)
	suite.run(self)
