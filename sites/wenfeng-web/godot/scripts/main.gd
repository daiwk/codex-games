extends Node3D

const Fighter = preload("res://scripts/duel_actor.gd")
const Arena = preload("res://scripts/arena.gd")
const CavalryArena = preload("res://scripts/duel_cavalry_arena.gd")
const CavalryDirector = preload("res://scripts/duel_cavalry_director.gd")
const Effects = preload("res://scripts/combat_fx.gd")
const HUD = preload("res://scripts/hud.gd")
const SkillEffects = preload("res://scripts/duel_skill_fx.gd")
const Specials = preload("res://scripts/duel_specials.gd")
const Director = preload("res://scripts/duel_director.gd")
const Roster = preload("res://scripts/roster.gd")
const ImpactFeedback = preload("res://scripts/impact_feedback.gd")
const CombatCamera = preload("res://scripts/combat_camera.gd")

var character_id = "zhaoyun"
var weapon_id = "serpent_spear"
var opponent_id = ""
var difficulty = 1
var combat_mode = "foot"
var horse_color = "white"
var enemy_horse_color = "brown"
var arena: Node3D
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
var specials
var duel_director = Director.new()
var cavalry_director = CavalryDirector.new()
var special_hit_counts: Dictionary = {}
var last_special_hit: Dictionary = {}
var resolving_special = ""
var resolving_melee_before_hp = -1.0
var last_melee_hit: Dictionary = {}
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
var hit_feedback = ImpactFeedback.new()
var camera_motion = CombatCamera.new()
var camera_axis_yaw = 0.0
var camera_axis_ready = false
var camera_look_position = Vector3.ZERO
var camera_look_ready = false
var testing = false
var elapsed = 0.0
var screenshot_pending = false
var camera_override = false
var lock_on = false
const COMBAT_INPUTS = ["light", "heavy", "dodge", "skill_rush", "skill_counter", "ultimate", "cavalry_left", "cavalry_right", "jump"]
var pending_input = ""
var pending_input_until = 0
var captured_inputs: Dictionary = {}

func _ready() -> void:
	# Only this standalone Duel entry allocates the sharper shadow atlas.
	# The shared project default remains unchanged for the RPG export.
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	if OS.has_feature("web"):
		get_viewport().scaling_3d_scale = 1.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	testing = "--test" in OS.get_cmdline_user_args() or "--skills-test" in OS.get_cmdline_user_args() or "--role-test" in OS.get_cmdline_user_args()
	rng.seed = 714 if testing else int(Time.get_unix_time_from_system())
	_configure_inputs()
	arena = Arena.new()
	add_child(arena)
	fx = Effects.new()
	# DuelSkillFX owns the contact sparks; retain this host's audio and text.
	fx.legacy_contact_sparks = false
	add_child(fx)
	skill_fx = SkillEffects.new()
	add_child(skill_fx)
	specials = Specials.new()
	add_child(specials)
	specials.hit_requested.connect(_on_special_hit)
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
		"light": [KEY_J], "heavy": [KEY_K], "guard": [KEY_L, KEY_SHIFT], "dodge": [KEY_SPACE], "jump": [KEY_V],
		"skill_rush": [KEY_Q], "skill_counter": [KEY_E], "ultimate": [KEY_U],
		"cavalry_left": [KEY_Z], "cavalry_right": [KEY_C], "cavalry_brake": [KEY_X]}
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
	player.mounted = combat_mode == "mounted"
	player.movement_radius = 28.0 if player.mounted else 7.6
	player.horse_color = horse_color
	player.is_player = true
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	enemy = Fighter.new()
	enemy.name = "Opponent"
	enemy.character_id = String(Roster.character(character_id).opponent) if opponent_id.is_empty() else opponent_id
	enemy.weapon_id = Roster.resolve_weapon(enemy.character_id, "")
	enemy.mounted = combat_mode == "mounted"
	enemy.movement_radius = 28.0 if enemy.mounted else 7.6
	enemy.horse_color = enemy_horse_color
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	player.opponent = enemy
	enemy.opponent = player
	for fighter in [player, enemy]:
		fighter.strike_requested.connect(_resolve_strike)
		fighter.impact_received.connect(_on_impact)
		fighter.action_started.connect(_on_action)
		fighter.skill_triggered.connect(_on_skill)
		if fighter.has_signal("duel_landed"):
			fighter.connect("duel_landed", _on_duel_landed.bind(fighter))
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

func select_combat_mode(id: String) -> void:
	if phase != "menu" or id not in ["foot", "mounted"] or combat_mode == id:
		return
	combat_mode = id
	remove_child(arena)
	arena.queue_free()
	arena = CavalryArena.new() if id == "mounted" else Arena.new()
	add_child(arena)
	_spawn_fighters()
	_position_preview()
	_update_camera(1.0, true)
	fx.sound("gong", -23.0, 1.2)

func select_horse_color(id: String, for_enemy = false) -> void:
	if phase != "menu" or id not in ["brown", "white"]:
		return
	if for_enemy:
		if enemy_horse_color == id:
			return
		enemy_horse_color = id
	else:
		if horse_color == id:
			return
		horse_color = id
	_spawn_fighters()
	_position_preview()
	fx.sound("step", -20.0)

func _position_preview() -> void:
	player.enabled = false
	enemy.enabled = false
	# The chosen hero owns the clear right-hand portrait area. Keep the
	# opponent behind the menu's left vignette instead of reversing emphasis.
	player.position = Vector3(2.65, 0.015, 0.6) if combat_mode == "mounted" else Vector3(2.65, 0.015, 0.7)
	enemy.position = Vector3(-0.7, 0.015, -2.6) if combat_mode == "mounted" else Vector3(-0.7, 0.015, -1.8)
	player.rotation.y = 0.12
	enemy.rotation.y = -0.35
	player.reset_fighter()
	enemy.reset_fighter()

func start_match() -> void:
	_clear_combat_input()
	lock_on = true
	_reset_hit_feedback()
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
	specials.clear()
	duel_director.reset()
	cavalry_director.reset()
	special_hit_counts.clear()
	last_special_hit.clear()
	last_melee_hit.clear()
	_clear_combat_input()
	_reset_hit_feedback()
	camera_axis_ready = false
	camera_look_ready = false
	round_number = scores[0] + scores[1] + 1
	for fighter in [player, enemy]:
		fighter.reset_fighter()
		fighter.energy = 65.0
		fighter.enabled = false
	var separation = 14.0 if combat_mode == "mounted" else 2.65
	player.position = Vector3(0, 0.015, separation)
	enemy.position = Vector3(0, 0.015, -separation)
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
	_clear_combat_input()
	specials.clear()
	duel_director.reset()
	cavalry_director.reset()
	lock_on = false
	if is_instance_valid(player):
		player.set("lock_facing", false)
	skill_fx.clear()
	_reset_hit_feedback()
	camera_axis_ready = false
	camera_look_ready = false
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
	_clear_combat_input()
	get_tree().paused = paused
	_reset_hit_feedback()

func _lock_available() -> bool:
	return phase in ["fight", "countdown"] and is_instance_valid(player) and is_instance_valid(enemy) and player.hp > 0.0 and enemy.hp > 0.0

func lock_active() -> bool:
	return lock_on and _lock_available()

func toggle_lock() -> bool:
	if paused or not _lock_available():
		return false
	lock_on = not lock_on
	_sync_lock()
	toast = ("标记对手 · W/S 调速 · A/D 转马" if combat_mode == "mounted" else "锁定对手 · W/S 进退 · A/D 绕行") if lock_on else ("策马视角" if combat_mode == "mounted" else "双人视角")
	toast_time = 1.8
	return true

func _sync_lock() -> void:
	if is_instance_valid(player):
		player.set("lock_facing", lock_active())

func _locked_movement(input: Vector2) -> Vector3:
	if not is_instance_valid(player) or not is_instance_valid(enemy):
		return Vector3.ZERO
	var toward = (enemy.global_position - player.global_position).slide(Vector3.UP)
	toward = toward.normalized() if toward.length_squared() > 0.01 else player.forward()
	return (toward.cross(Vector3.UP) * input.x - toward * input.y).limit_length()

func _input(event: InputEvent) -> void:
	if paused or not _lock_available():
		return
	if (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE):
		toggle_lock()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	for action in COMBAT_INPUTS:
		if event.is_action_pressed(action, false):
			queue_combat_input(action)
			get_viewport().set_input_as_handled()
			return
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
			KEY_6:
				select_character("xuchu")
			KEY_B:
				select_combat_mode("mounted" if combat_mode == "foot" else "foot")

func _physics_process(delta: float) -> void:
	_sync_lock()
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
	if player.mounted:
		# Riders face +Z, so their right is forward.cross(UP), or -local X.
		# Convert player left/right reins to geometric yaw here; AI already
		# supplies world-space signed angles through set_cavalry_input().
		player.call("set_cavalry_input", -input.y, -input.x, Input.is_action_pressed("cavalry_brake"))
		player.input_move = player.forward() * -input.y
	else:
		player.input_move = _locked_movement(input) if lock_active() else right.normalized() * input.x + forward.normalized() * -input.y
	player.wants_block = Input.is_action_pressed("guard")
	for action in COMBAT_INPUTS:
		if Input.is_action_just_pressed(action) and not captured_inputs.has(action):
			queue_combat_input(action)
	captured_inputs.clear()
	_consume_combat_input()

func queue_combat_input(action: String) -> void:
	if paused or phase != "fight" or not is_instance_valid(player) or player.hp <= 0.0:
		return
	if action in ["cavalry_left", "cavalry_right"] and not player.mounted: return
	if action == "jump":
		# Jump is orthogonal to combat; V and Q/E/U in one frame must not
		# replace one another in the short combat-intent buffer.
		captured_inputs[action] = true
		player.request_jump()
		return
	pending_input = action
	pending_input_until = Time.get_ticks_msec() + 260
	captured_inputs[action] = true

func _clear_combat_input() -> void:
	pending_input = ""
	pending_input_until = 0
	captured_inputs.clear()
	for action in COMBAT_INPUTS:
		# Releasing does not clear this tick's just_pressed edge. Consume it
		# so a resume click (or paused tap) cannot enter the next input poll.
		if Input.is_action_just_pressed(action):
			captured_inputs[action] = true
		Input.action_release(action)
	Input.action_release("cavalry_brake")
	if is_instance_valid(player) and player.mounted and player.has_method("set_cavalry_input"):
		player.call("set_cavalry_input", 0.0, 0.0, false)

func _consume_combat_input() -> void:
	if pending_input == "": return
	if Time.get_ticks_msec() > pending_input_until:
		if pending_input == "ultimate": _skill_hint("ultimate")
		elif pending_input == "skill_rush": _skill_hint("rush")
		elif pending_input == "skill_counter": _skill_hint("counter")
		elif player.stamina < 17.0: _stamina_hint()
		pending_input = ""
		return
	var accepted = false
	if player.mounted and pending_input in ["light", "heavy", "cavalry_left", "cavalry_right"]:
		var side = 0
		if pending_input == "cavalry_left": side = 1
		elif pending_input == "cavalry_right": side = -1
		player.call("set_cavalry_attack_side", side)
	match pending_input:
		"light": accepted = player.request_light()
		"cavalry_left", "cavalry_right": accepted = player.request_light()
		"heavy": accepted = player.request_heavy()
		"dodge": accepted = player.request_dodge(player.input_move)
		"skill_rush": accepted = player.request_skill("rush")
		"skill_counter": accepted = player.request_skill("counter")
		"ultimate": accepted = player.request_ultimate()
	if accepted: pending_input = ""

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
	if combat_mode == "mounted":
		_update_mounted_ai(delta)
	else:
		duel_director.update(self, delta)

func _update_mounted_ai(delta: float) -> void:
	cavalry_director.update(self, delta)

func _resolve_strike(attacker: DuelFighter, data: Dictionary) -> void:
	if phase != "fight" or attacker.hit_landed or attacker.hp <= 0.0 or bool(data.get("external_only", false)):
		return
	if attacker.has_method("duel_weapon_is_thrown") and bool(attacker.call("duel_weapon_is_thrown")):
		return
	var defender: DuelFighter = attacker.opponent
	var offset = defender.global_position - attacker.global_position
	offset.y = 0.0
	var strike_forward: Vector3 = attacker.call("duel_strike_forward") if attacker.has_method("duel_strike_forward") else attacker.forward()
	if offset.length() > float(data.reach):
		return
	if data.get("shape", "") == "line":
		var projection = offset.dot(strike_forward)
		var sideways = (offset - strike_forward * projection).length()
		if projection < 0.0 or sideways > float(data.get("half_width", 0.5)):
			return
	if not data.get("radial", false) and offset.normalized().dot(strike_forward) < float(data.get("min_dot", 0.12)):
		return
	# A thrust must actually touch the body, including when a skill carries the
	# wave flag. Its reach/line tests are only a broad phase, not a ranged hit.
	var physical_thrust = attacker.is_physical_thrust(data)
	var low = defender.thrust_body_low()
	var high = defender.thrust_body_high()
	var blade = Geometry3D.get_closest_points_between_segments(attacker.blade_base(), attacker.blade_tip(), low, high)
	var sweep = Geometry3D.get_closest_points_between_segments(attacker.previous_tip, attacker.blade_tip(), low, high)
	var contact = minf(blade[0].distance_to(blade[1]), sweep[0].distance_to(sweep[1]))
	var physical_blade = bool(data.get("physical_blade", false))
	if physical_blade and contact > defender.thrust_body_radius() + 0.07:
		return
	if physical_thrust and contact > defender.thrust_body_radius() + 0.07:
		return
	if not physical_thrust and data.get("shape", "") != "line" and not data.get("wave", false) and contact > 0.70:
		if offset.length() > 1.48:
			return
		if not data.get("radial", false):
			# Close slashes retain their horizontal allowance, but a blade
			# wholly above/below the body cannot cause a hit, block or parry.
			var blade_min_y = minf(attacker.blade_base().y, minf(attacker.blade_tip().y, attacker.previous_tip.y))
			var blade_max_y = maxf(attacker.blade_base().y, maxf(attacker.blade_tip().y, attacker.previous_tip.y))
			var radius = defender.thrust_body_radius() + 0.07
			if blade_min_y > high.y + radius or blade_max_y < low.y - radius:
				return
	attacker.hit_landed = true
	var resolved = data.duplicate()
	if physical_thrust or physical_blade:
		var nearest = blade if blade[0].distance_to(blade[1]) <= sweep[0].distance_to(sweep[1]) else sweep
		var normal = (nearest[0] - nearest[1]).normalized()
		if normal.length_squared() < 0.01:
			normal = -attacker.forward()
		resolved["contact_point"] = nearest[1] + normal * defender.thrust_body_radius()
	if attacker.mounted and attacker.has_method("cavalry_impact_data"):
		resolved = attacker.call("cavalry_impact_data", defender, resolved)
	resolving_melee_before_hp = defender.hp
	var hp_before = defender.hp
	var outcome = defender.receive_strike(attacker, resolved)
	resolving_melee_before_hp = -1.0
	last_melee_hit = {"attacker":attacker.character_id,"damage":hp_before-defender.hp,"outcome":outcome,
		"mounted":attacker.mounted,"speed":attacker.mount_speed,"data":resolved.duplicate(true)}
	if physical_thrust and outcome not in ["evade", "dead"]:
		attacker.register_thrust_contact(resolved.contact_point)

func _on_special_hit(attacker: DuelFighter, defender: DuelFighter, data: Dictionary, at: Vector3) -> void:
	if paused or phase != "fight" or not is_instance_valid(attacker) or not is_instance_valid(defender) or attacker.hp <= 0.0 or defender.hp <= 0.0:
		return
	if attacker not in [player, enemy] or defender not in [player, enemy] or attacker == defender:
		return
	var resolved = data.duplicate(true)
	resolved["contact_point"] = at
	var before = defender.hp
	# Each swept projectile/front owns one contact. It deliberately does not
	# reuse the hand-held attack's hit_landed flag or broad-phase reach check.
	resolving_special = String(data.get("special", ""))
	var outcome = defender.receive_strike(attacker, resolved)
	resolving_special = ""
	var damage = maxf(0.0, before - defender.hp)
	var kind = String(data.get("special", ""))
	if damage > 0.0:
		fx._floating_text(at + Vector3.UP * 0.22, str(int(ceil(damage))), Color("fff1d8"))
	if outcome in ["hit", "heavy_hit", "break", "block"] and defender.hp > 0.0 and defender.has_method("apply_duel_impulse"):
		var direction: Vector3 = data.get("impact_direction", defender.position - attacker.position)
		var power = float(data.get("knockback", 1.0)) * (0.35 if outcome == "block" else 1.0)
		defender.call("apply_duel_impulse", direction, power)
	special_hit_counts[kind] = int(special_hit_counts.get(kind, 0)) + 1
	last_special_hit = {"type": kind, "damage": damage, "outcome": outcome,
		"volley_id": data.get("volley_id", 0), "projectile_index": data.get("projectile_index", 0),
		"point": [at.x, at.y, at.z]}
	if kind in ["shockwave", "roar", "air_slam"] and outcome != "evade":
		shake = maxf(shake, 0.045)
		impact_zoom = maxf(impact_zoom, 1.15)

func _on_duel_landed(_at: Vector3, fighter: DuelFighter) -> void:
	if phase != "fight" or fighter.hp <= 0.0 or fighter.skill_id != "ultimate": return
	var special: Dictionary = fighter.skill_profile("ultimate").get("special", {})
	if special.get("type", "") == "air_slam" and special.get("trigger", "") == "landing":
		specials.play_skill(fighter, "ultimate", "landing")
		skill_fx.play_skill(fighter, "ultimate", "landing")
		fx.sound("heavy", -10.0, 0.64)
		shake = maxf(shake, 0.035)

func _on_impact(fighter: DuelFighter, outcome: String, at: Vector3) -> void:
	var damage = int(fighter.opponent.attack.get("damage", 0)) if outcome in ["hit", "heavy_hit"] else 0
	if resolving_melee_before_hp >= 0.0 and outcome in ["hit", "heavy_hit"]:
		damage = int(ceil(maxf(0.0,resolving_melee_before_hp-fighter.hp)))
	# Projectile contacts report their actual resolved damage once, after guard
	# and mitigation. The wielder's current melee envelope is unrelated.
	if not resolving_special.is_empty(): damage = 0
	fx.burst(at, outcome, damage)
	if outcome != "evade":
		var heavy = outcome in ["heavy_hit", "parry", "counter", "break"]
		skill_fx.impact(at, outcome, -fighter.forward(), 1.35 if heavy else 0.8)
		# Directional recoil reads as contact; only hard contacts add a small
		# tremor, rather than vibrating through every ordinary thrust.
		shake = maxf(shake, 0.032 if heavy else 0.008)
		camera_motion.kick(-fighter.forward(), heavy)
		impact_zoom = maxf(impact_zoom, 0.9 if heavy else 0.22)
		if not testing and not paused and phase == "fight":
			var stop = 16 if resolving_special in ["flying_blades", "cavalry", "weapon_array"] else (48 if heavy else 26)
			hit_stop_until = hit_feedback.request(stop, 0.14)
	if outcome == "parry":
		toast = "招架成功 · 趁势反击" if fighter.is_player else "被招架 · 注意出招节奏"
		toast_time = 1.5
	elif outcome == "break":
		toast = "防御崩解 · 拉开距离" if fighter.is_player else "对手破防 · 进攻时机"
		toast_time = 1.5

func _on_action(fighter: DuelFighter, action: String) -> void:
	skill_fx.action(fighter, action)
	match action:
		"swing_light", "swing_heavy":
			fx.sound("thrust" if fighter.is_thrust_weapon() else ("heavy" if action == "swing_heavy" else "swing"), -10.0, rng.randf_range(0.93, 1.08))
		"step":
			fx.sound("step", -26.0 if fighter.is_player else -30.0, rng.randf_range(0.9, 1.1))
		"dodge":
			fx.sound("dodge", -14.0)
		"hoof":
			fx.sound("step", -21.0 if fighter.is_player else -25.0, rng.randf_range(0.65, 0.80))
		"charge":
			fx.sound("dodge", -14.0, 0.7)
		"ultimate_ready":
			fx.sound("parry", -19.0, 0.75)

func _on_skill(fighter: DuelFighter, id: String, stage: String) -> void:
	skill_fx.play_skill(fighter, id, stage)
	specials.play_skill(fighter, id, stage)
	var special: Dictionary = fighter.skill_profile(id).get("special", {})
	if stage == "release" and special.get("type", "") == "air_slam" and not fighter.mounted:
		fighter.call("begin_duel_aerial", float(special.get("launch_speed", 10.5)))
	var data: Dictionary = skill_fx.presentation_profile(fighter, id)
	var profile: Dictionary = fighter.skill_profile(id)
	var kind = String(profile.get("kind", ""))
	if stage == "start":
		if id == "ultimate" or kind == "charge":
			fx.sound("charge", -15.0, 0.85)
		elif kind == "evade":
			fx.sound("dodge", -16.0)
		return
	if stage in ["guard", "parry"]:
		fx.sound("clang", -15.0)
		return
	if stage not in ["release", "strike", "finish"]:
		return
	# A sequenced skill sounds on its actual per-hit events, not twice on
	# the same release frame or simply because the role owns a spear.
	if stage == "release" and id == "ultimate" and profile.has("hits"):
		return
	var radial = String(data.get("shape", "")) == "radial"
	var voice = kind == "roar" or ("serpent" in String(data.get("fx_style", "")) and radial)
	var sound = "roar" if voice else ("thrust" if String(data.get("shape", "")) == "line" else "heavy")
	fx.sound(sound, -12.0 if stage == "finish" else -15.0, 0.85 if stage == "finish" else 1.0)
	if id == "ultimate":
		# The released weapon carries the spectacle. Strong camera feedback
		# waits for impact_received, including when an ultimate misses.
		shake = maxf(shake, 0.018 if stage == "finish" else 0.0)

func _end_round(winner: int) -> void:
	_clear_combat_input()
	specials.clear()
	_reset_hit_feedback()
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
	# The pose pauses on contact; camera recovery follows real elapsed time.
	var real_delta = delta / maxf(Engine.time_scale, 0.01)
	hit_stop_until = hit_feedback.tick()
	if paused:
		return
	elapsed += delta
	shake = move_toward(shake, 0.0, real_delta * 0.75)
	impact_zoom = move_toward(impact_zoom, 0.0, real_delta * 12.0)
	camera_motion.update(real_delta)
	_update_camera(real_delta)

func _update_camera(delta: float, instant = false) -> void:
	if not is_instance_valid(player) or camera_override:
		return
	var desired: Vector3
	var target: Vector3
	var fov: float
	if phase == "menu":
		desired = Vector3(4.1 + sin(elapsed * 0.16) * 0.065, 2.15, 6.7)
		target = Vector3(1.48, 1.03, 0.20)
		fov = 35.0
		if combat_mode == "mounted":
			desired = Vector3(4.8, 3.45, 9.6)
			# Frame the rider below the mode/horse controls while keeping
			# the horse above the opponent-selection row.
			target = Vector3(1.0, 2.2, 0.0)
			fov = 48.0
	else:
		var axis = enemy.global_position - player.global_position
		axis.y = 0.0
		var separation = axis.length()
		# Retain the last readable side when bodies cross at close range.
		if separation > 0.65 and combat_mode != "mounted":
			var wanted_yaw = atan2(axis.x, axis.z)
			camera_axis_yaw = wanted_yaw if instant or not camera_axis_ready else rotate_toward(camera_axis_yaw, wanted_yaw, delta * 2.8)
			camera_axis_ready = true
		axis = Vector3(sin(camera_axis_yaw), 0, cos(camera_axis_yaw))
		var side = Vector3(-axis.z, 0, axis.x)
		var middle = (player.global_position + enemy.global_position) * 0.5
		var distance = clampf(4.85 + separation * 0.28, 5.45, 8.6)
		desired = middle - axis * distance + side * 1.7 + Vector3.UP * 2.70
		target = middle + Vector3.UP * 1.14
		fov = 49.0
		if combat_mode == "mounted":
			distance = clampf(8.1 + separation * 0.29, 9.0, 14.0)
			desired = middle - axis * distance + side * 2.4 + Vector3.UP * 4.35
			target = middle + Vector3.UP * 1.75
			fov = 58.0
		if lock_active():
			# Shoulder framing keeps the target ahead; the arena view remains
			# available without changing either fighter's committed attack aim.
			var vertical_span = absf(player.position.y - enemy.position.y)
			var wide_special = 0.0
			for group in specials.groups.values():
				if group.type in ["cavalry", "flying_blades", "weapon_array"]:
					wide_special = 0.85
			var behind = clampf(3.30 + separation * 0.22 + vertical_span * 0.45 + wide_special, 3.85, 8.2)
			var anchor = player.global_position
			anchor.y = minf(player.position.y, enemy.position.y)
			var anticipation = (player.velocity + enemy.velocity * 0.4).slide(Vector3.UP).limit_length(6.0) * 0.07
			# Armour and two-handed weapons need a clear lane past the shoulder.
			# The smaller offset hid the opponent behind the player's torso.
			var shoulder = clampf(1.85 + (2.5 - separation) * 0.12, 1.75, 2.12)
			desired = anchor - axis * behind + side * shoulder + Vector3.UP * (2.02 + vertical_span * 0.22)
			target = player.global_position.lerp(enemy.global_position, 0.51) + Vector3.UP * 1.20 + anticipation
			fov = 52.0 + wide_special * 2.5
		if phase == "fight":
			fov -= maxf(CombatCamera.anticipation(player), CombatCamera.anticipation(enemy))
	if combat_mode == "mounted" and phase != "menu":
		# The horse keeps its own heading. Marking an enemy only biases the
		# rider's view a little; a passed foe cannot spin the camera backwards.
		var speed = player.mount_speed
		var heading = player.forward()
		var wanted = player.rotation.y
		if lock_active():
			var bearing = heading.signed_angle_to((enemy.position-player.position).slide(Vector3.UP).normalized(),Vector3.UP)
			wanted += clampf(bearing,-0.28,0.28)
		camera_axis_yaw = wanted if instant or not camera_axis_ready else rotate_toward(camera_axis_yaw,wanted,delta*2.0)
		camera_axis_ready=true
		var view_heading=Vector3(sin(camera_axis_yaw),0,cos(camera_axis_yaw))
		var lateral=Vector3(view_heading.z,0,-view_heading.x)
		desired=player.position-view_heading*(7.0+minf(speed,12.0)*0.14)+lateral*2.1+Vector3.UP*3.30
		target=player.position+view_heading*(3.3+speed*.22)+Vector3.UP*1.85
		fov=61.0+minf(speed,12.0)*0.40
	# The courtyard's decorative walls have no physics shape. Keep the low
	# foot camera inside their inner faces even when fighters separate widely.
	if combat_mode == "foot" and phase != "menu":
		desired.x = clampf(desired.x, -11.6, 11.6)
		desired.z = maxf(desired.z, -11.2)
	var weight = 1.0 if instant else 1.0 - exp(-delta * 7.0)
	# Keep the smoothed pose separate so repeated shake cannot drift the framing.
	camera_base_position = desired if instant else camera_base_position.lerp(desired, weight)
	if combat_mode == "foot" and phase != "menu":
		camera_base_position.x = clampf(camera_base_position.x, -11.6, 11.6)
		camera_base_position.z = maxf(camera_base_position.z, -11.2)
	camera_base_fov = fov if instant else lerpf(camera_base_fov, fov, weight)
	camera.position = camera_base_position + camera_motion.recoil
	camera.fov = camera_base_fov + impact_zoom
	if shake > 0.0:
		var clock = Time.get_ticks_msec() * 0.001
		var tremor = Vector3(sin(clock * 61), cos(clock * 53) * 0.45, 0.0)
		camera.position += camera.basis * tremor * shake
	if instant or not camera_look_ready:
		camera_look_position = target
		camera_look_ready = true
	else:
		camera_look_position = camera_look_position.lerp(target, 1.0 - exp(-delta * 10.5))
	camera.look_at(camera_look_position, Vector3.UP)
	if shake > 0.0:
		camera.rotate_object_local(Vector3.FORWARD, sin(elapsed * 71) * shake * 0.035)

func _reset_hit_feedback() -> void:
	hit_feedback.reset()
	camera_motion.reset()
	hit_stop_until = 0
	shake = 0.0
	impact_zoom = 0.0

func _exit_tree() -> void:
	_reset_hit_feedback()

func snapshot() -> Dictionary:
	return {"last_melee_hit": last_melee_hit.duplicate(true), "specials": specials.debug_state() if is_instance_valid(specials) else {}, "special_hits": special_hit_counts.duplicate(), "last_special_hit": last_special_hit.duplicate(), "boss_phase": duel_director.phase, "boss_intent": cavalry_director.phase if combat_mode == "mounted" else duel_director.decision, "lock_on": {"active": lock_active(), "available": _lock_available() and not paused, "target": enemy.character_id if lock_active() else "", "position": [enemy.position.x, enemy.position.y, enemy.position.z] if lock_active() else []}, "phase": phase, "paused": paused, "combat_mode": combat_mode, "horse_color": horse_color, "enemy_horse_color": enemy_horse_color, "scores": scores.duplicate(), "seconds": round_time,
		"player": {"instance_id": player.get_instance_id(), "character": player.character_id, "weapon": player.weapon_id, "hp": player.hp,
			"jump": player.jump_status(), "cavalry": player.call("cavalry_status") if player.mounted and player.has_method("cavalry_status") else {}, "airborne": player.call("duel_is_airborne"), "weapon_thrown": player.call("duel_weapon_is_thrown"),
			"mounted": player.mounted, "mount_speed": player.mount_speed, "mount_charge_cooldown": player.mount_charge_cooldown, "heading": player.rotation.y,
			"contact_active": player.contact_active, "contact_latched": player.contact_latched, "contact_retraction": player.contact_retraction,
			"horse_color": player.horse_color,
			"stamina": player.stamina, "energy": player.energy, "cooldowns": player.cooldowns.duplicate(),
			"clip": player.current_clip, "skill_hit_index": player.skill_hit_index, "skill": player.skill_id, "skill_stage": player.skill_stage, "state": player.state, "action_time": player.action_time, "combo": player.combo, "position": [player.position.x, player.position.y, player.position.z]},
		"enemy": {"instance_id": enemy.get_instance_id(), "character": enemy.character_id, "weapon": enemy.weapon_id, "hp": enemy.hp,
			"jump": enemy.jump_status(), "cavalry": enemy.call("cavalry_status") if enemy.mounted and enemy.has_method("cavalry_status") else {}, "airborne": enemy.call("duel_is_airborne"), "weapon_thrown": enemy.call("duel_weapon_is_thrown"),
			"mounted": enemy.mounted, "mount_speed": enemy.mount_speed, "mount_charge_cooldown": enemy.mount_charge_cooldown, "heading": enemy.rotation.y,
			"contact_active": enemy.contact_active, "contact_latched": enemy.contact_latched, "contact_retraction": enemy.contact_retraction,
			"horse_color": enemy.horse_color,
			"stamina": enemy.stamina, "energy": enemy.energy, "cooldowns": enemy.cooldowns.duplicate(),
			"clip": enemy.current_clip, "skill_hit_index": enemy.skill_hit_index, "skill": enemy.skill_id, "skill_stage": enemy.skill_stage, "state": enemy.state, "action_time": enemy.action_time, "position": [enemy.position.x, enemy.position.y, enemy.position.z]}}

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
