extends Node3D

const Actor = preload("res://scripts/rpg_actor.gd")
const Progress = preload("res://scripts/rpg_progress.gd")
const World = preload("res://scripts/rpg_world.gd")
const HUD = preload("res://scripts/rpg_hud.gd")
const Effects = preload("res://scripts/combat_fx.gd")
const SkillEffects = preload("res://scripts/skill_fx.gd")
const SAVE_KEY = "changban-rpg-save-v1"
const SAVE_FILE = "user://changban-rpg-v1.json"
const INTRO = [
	["序章 · 龙骑出关", "这是以三国人物为背景的架空外传。兵荒马乱，赵云奉命护送一封密函，踏上穿越五处关隘的长路。"],
	["驿卒", "前路有流寇，五位守关武将也各有考验。先在南郊清剿三名游骑，升至二级，再到西面的试马坡寻马超。"],
	["赵云", "长路虽远，一骑可行。WASD 策马，Space 冲刺，J / K 出招；靠近人物或驿站按 F。I 查看装备，M 打开舆图。"],
]
const STORIES = [
	"西凉战骑来去如风。马超愿以一场试锋，验你护送密函的本领。",
	"古关重门，虎痴守道。许褚要见识你在乱军之中稳住阵脚的胆气。",
	"长坂风急，张飞横矛当道：先平流寇，再与我一试！",
	"青龙岭上，关羽问的既是武艺，也是持兵者守护百姓的决心。",
	"辕门前，画戟映日。吕布等候最后一场交锋，胜者方能送函出关。",
]

var progress = Progress.new()
var world: Node3D
var player: RPGActor
var camera: Camera3D
var hud: Control
var fx: DuelFX
var skill_fx: DuelSkillFX
var phase = "explore"
var paused = false
var inventory_open = false
var map_open = false
var dead = false
var active_boss = ""
var dialogue: Array = []
var dialogue_index = 0
var dialogue_after = ""
var toast = ""
var toast_clock = 0.0
var save_label = "自动存档 · 当前浏览器"
var enemies: Dictionary = {}
var camps: Array = []
var minion_spawns: Array = []
var discovered: Array = []
var respawns: Dictionary = {}
var labels: Dictionary = {}
var ai_clocks: Dictionary = {}
var reward_claimed: Dictionary = {}
var elapsed = 0.0
var spawn_clock = 0.0
var save_clock = 0.0
var publish_clock = 0.0
var camera_yaw = 0.0
var camera_distance = 12.0
var camera_drag = false
var testing = false
var _web_callback: JavaScriptObject

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	testing = "--rpg-test" in OS.get_cmdline_user_args()
	_configure_inputs()
	world = World.new()
	add_child(world)
	camps = world.get_stations()
	fx = Effects.new()
	add_child(fx)
	skill_fx = SkillEffects.new()
	add_child(skill_fx)
	camera = Camera3D.new()
	camera.near = 0.12
	camera.far = 450.0
	camera.fov = 58.0
	camera.current = true
	add_child(camera)
	var loaded = _load_game() if not testing else false
	if not loaded:
		progress.position = World.START
	_spawn_player(progress.position, true)
	_build_spawns()
	var canvas = CanvasLayer.new()
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	hud = HUD.new()
	hud.game = self
	canvas.add_child(hud)
	_update_camera(1.0, true)
	if OS.has_feature("web"):
		_web_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").wenfengCommand = _web_callback
	if not progress.quest_started:
		_show_dialogue(INTRO, "intro")
	else:
		_notify("续行旧路 · 等级、战利品与征程已恢复")
	_update_streaming()
	_publish()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.wenfengReady && window.wenfengReady()")

func _configure_inputs() -> void:
	var keys = {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "light": [KEY_J], "heavy": [KEY_K], "guard": [KEY_L, KEY_SHIFT], "dodge": [KEY_SPACE], "skill_rush": [KEY_Q], "skill_counter": [KEY_E], "ultimate": [KEY_U]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
	for pair in [["light", MOUSE_BUTTON_LEFT], ["heavy", MOUSE_BUTTON_RIGHT]]:
		var event = InputEventMouseButton.new()
		event.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], event):
			InputMap.action_add_event(pair[0], event)

func _spawn_player(at: Vector3, heal: bool) -> void:
	var previous_hp = player.hp if is_instance_valid(player) else 120.0
	if is_instance_valid(player):
		var previous_id = player.get_instance_id()
		if fx.trails.has(previous_id):
			fx.trails[previous_id].node.queue_free()
			fx.trails.erase(previous_id)
		player.queue_free()
	player = Actor.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.character_id = "zhaoyun"
	player.is_player = true
	player.mounted = true
	player.horse_color = progress.horse_color
	player.weapon_id = progress.stats().weapon_id
	add_child(player)
	player.position = at
	player.rotation.y = PI
	var stats = progress.stats()
	player.apply_stats(stats.hp, stats.damage_scale, stats.armor, heal)
	if not heal:
		player.hp = minf(previous_hp, player.max_hp)
	_connect_actor(player)
	player.enabled = phase == "explore"
	for enemy in enemies.values():
		if is_instance_valid(enemy):
			enemy.opponent = player

func _connect_actor(actor: RPGActor) -> void:
	actor.strike_requested.connect(_resolve_strike)
	actor.impact_received.connect(_on_impact)
	actor.action_started.connect(_on_action)
	actor.skill_triggered.connect(_on_skill)
	fx.register_fighter(actor)

func _build_spawns() -> void:
	# Camps are deliberately off the road; a rider may pass, fight, or return later.
	var groups = [
		[Vector3(-13, 0, 88), 1], [Vector3(-25, 0, 81), 1], [Vector3(-18, 0, 66), 1],
		[Vector3(-65, 0, 56), 3], [Vector3(-76, 0, 35), 3], [Vector3(-100, 0, 29), 3],
		[Vector3(-79, 0, -14), 5], [Vector3(-57, 0, -29), 5], [Vector3(-35, 0, -21), 5],
		[Vector3(2, 0, -58), 7], [Vector3(28, 0, -72), 7], [Vector3(44, 0, -47), 7],
		[Vector3(80, 0, -51), 9], [Vector3(103, 0, -32), 9], [Vector3(118, 0, 21), 9],
		[Vector3(47, 0, 22), 4], [Vector3(18, 0, 48), 2], [Vector3(42, 0, 65), 2],
	]
	for i in groups.size():
		minion_spawns.append({"id": "raider_%02d" % i, "position": groups[i][0], "level": groups[i][1]})

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not paused:
		elapsed += delta
		toast_clock = maxf(0.0, toast_clock - delta)
		if toast_clock <= 0.0:
			toast = ""
		_update_camera(delta)
	if is_instance_valid(hud):
		hud.refresh(snapshot())
	publish_clock += delta
	if publish_clock >= 0.12:
		publish_clock = 0.0
		_publish()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or paused or phase != "explore":
		return
	if player.hp <= 0.0:
		_on_player_death()
		return
	var direction = Vector3(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"), 0.0, Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
	player.input_move = direction.rotated(Vector3.UP, camera_yaw).limit_length()
	player.wants_block = Input.is_action_pressed("guard")
	if Input.is_action_just_pressed("light"):
		player.request_light()
	if Input.is_action_just_pressed("heavy"):
		player.request_heavy()
	if Input.is_action_just_pressed("dodge"):
		player.request_dodge(player.input_move)
	if Input.is_action_just_pressed("skill_rush"):
		player.request_skill("rush")
	if Input.is_action_just_pressed("skill_counter"):
		player.request_skill("counter")
	if Input.is_action_just_pressed("ultimate"):
		player.request_ultimate()
	_update_target()
	_update_enemies(delta)
	spawn_clock += delta
	if spawn_clock > 0.45:
		spawn_clock = 0.0
		_update_streaming()
	save_clock += delta
	if save_clock > 8.0:
		save_clock = 0.0
		_save_game()

func _update_target() -> void:
	# A committed strike keeps one target through its contact window. Selecting
	# a closer passer-by mid-thrust would redirect the same physical spear.
	if player.state in ["attack", "skill", "ultimate"] and is_instance_valid(player.opponent) and player.opponent.hp > 0.0 and _hostile(String(player.opponent.get_meta("rpg_id", ""))):
		return
	var nearest: RPGActor = null
	var distance = 9.0
	for id in enemies:
		var actor: RPGActor = enemies[id]
		if not is_instance_valid(actor) or actor.hp <= 0.0 or not _hostile(id):
			continue
		var gap = player.position.distance_to(actor.position)
		if gap < distance:
			nearest = actor
			distance = gap
	player.opponent = nearest

func _hostile(id: String) -> bool:
	return id.begins_with("raider_") or id == active_boss

func _update_streaming() -> void:
	for boss in Progress.BOSSES:
		var id: String = boss.id
		var distance = player.position.distance_to(boss.position)
		if distance < 50.0 and id not in discovered:
			discovered.append(id)
		if id in progress.defeated:
			_despawn(id)
		elif distance < 36.0 and not enemies.has(id):
			_spawn_enemy(id, boss.position, int(boss.level), true)
		elif distance > 62.0 and id != active_boss:
			_despawn(id)
	for spawn in minion_spawns:
		var id: String = spawn.id
		var distance = player.position.distance_to(spawn.position)
		if distance < 24.0 and not enemies.has(id) and elapsed >= float(respawns.get(id, 0.0)):
			_spawn_enemy(id, spawn.position, int(spawn.level), false)
		elif distance > 43.0:
			_despawn(id)
	for station in camps:
		var id: String = station.get("id", station.get("name", "camp"))
		if player.position.distance_to(station.position) < 48.0 and id not in discovered:
			discovered.append(id)

func _spawn_enemy(id: String, at: Vector3, level: int, boss: bool) -> void:
	reward_claimed.erase(id)
	var actor = Actor.new()
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	actor.character_id = id if boss else "bandit"
	actor.weapon_id = Progress.BOSSES[_boss_index(id)].weapon if boss else "serpent_spear"
	actor.mounted = true
	actor.horse_color = "brown"
	actor.set_meta("rpg_id", id)
	actor.set_meta("level", level)
	actor.set_meta("spawn", at)
	actor.set_meta("boss", boss)
	add_child(actor)
	actor.position = at + Vector3.UP * 0.03
	actor.rotation.y = 0.3 if boss else PI * 0.7
	actor.opponent = player
	actor.apply_stats(95.0 + level * 25.0 if boss else 34.0 + level * 9.0, 0.72 + level * 0.10 if boss else 0.24 + level * 0.045, level * 1.5 if boss else 0.0, true)
	actor.enabled = phase == "explore" and (not boss or active_boss == id)
	var label = Label3D.new()
	label.font = load("res://assets/fonts/WenfengSans.otf")
	label.text = ("%s · %d 级" % [Progress.BOSSES[_boss_index(id)].name, level]) if boss else ("山贼游骑 · %d 级" % level)
	label.font_size = 38
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("e7c789") if boss else Color("e5a49a")
	label.outline_size = 10
	label.position.y = 3.75
	actor.add_child(label)
	labels[id] = label
	enemies[id] = actor
	ai_clocks[id] = 0.45
	_connect_actor(actor)

func _despawn(id: String) -> void:
	if not enemies.has(id):
		return
	var actor = enemies[id]
	if is_instance_valid(actor):
		if player.opponent == actor:
			player.opponent = null
		var key = actor.get_instance_id()
		if fx.trails.has(key):
			fx.trails[key].node.queue_free()
			fx.trails.erase(key)
		actor.queue_free()
	enemies.erase(id)
	labels.erase(id)
	ai_clocks.erase(id)

func _update_enemies(delta: float) -> void:
	var engaged = 0
	for id in enemies.keys():
		var enemy: RPGActor = enemies[id]
		if not is_instance_valid(enemy):
			continue
		if enemy.hp <= 0.0:
			if not reward_claimed.has(id):
				_claim_reward(id, enemy)
				if phase != "explore":
					return
			elif elapsed - float(reward_claimed[id]) > 3.0:
				_despawn(id)
			continue
		if not _hostile(id):
			enemy.enabled = false
			continue
		enemy.enabled = true
		var offset = player.position - enemy.position
		offset.y = 0.0
		var distance = offset.length()
		var home: Vector3 = enemy.get_meta("spawn")
		var boss = bool(enemy.get_meta("boss"))
		var following = distance < (29.0 if boss else 12.0) and enemy.position.distance_to(home) < (38.0 if boss else 20.0)
		if not following or (engaged >= 2 and not boss):
			var back = home - enemy.position
			enemy.input_move = back.normalized() * 0.45 if back.length() > 1.4 else Vector3.ZERO
			enemy.wants_block = false
			if boss and distance > 38.0:
				active_boss = ""
				enemy.reset_fighter()
				enemy.position = home + Vector3.UP * 0.03
				_notify("脱离交锋 · 守将已回到关前")
			continue
		engaged += 1
		enemy.opponent = player
		var reach = 2.05 if enemy.is_thrust_weapon() else 2.25
		var facing = offset.normalized().dot(enemy.forward())
		enemy.input_move = offset.normalized() if distance > reach else (offset.normalized() * 0.12 if facing < 0.86 else Vector3.ZERO)
		ai_clocks[id] = float(ai_clocks.get(id, 0.0)) - delta
		enemy.wants_block = boss and distance < 4.1 and player.state == "attack" and int(elapsed * 3.0) % 5 == 0
		if float(ai_clocks[id]) > 0.0 or enemy.state not in ["idle", "move", "block"]:
			continue
		if distance < (2.65 if enemy.is_thrust_weapon() else 3.0) and facing > 0.72:
			if boss and enemy.energy >= 100.0:
				enemy.request_ultimate()
			elif boss and int(elapsed * 2) % 6 == 0 and enemy.skill_ready("rush"):
				enemy.request_skill("rush")
			elif boss and int(elapsed * 2) % 3 == 0:
				enemy.request_heavy()
			else:
				enemy.request_light()
			ai_clocks[id] = (1.55 - float(enemy.get_meta("level")) * 0.055) if boss else 2.1
		else:
			ai_clocks[id] = 0.15

func _resolve_strike(attacker: DuelFighter, data: Dictionary) -> void:
	if paused or phase != "explore" or attacker.hit_landed or attacker.hp <= 0.0:
		return
	var defender: DuelFighter = attacker.opponent
	if not is_instance_valid(defender) or defender.hp <= 0.0:
		return
	if attacker == player and not _hostile(String(defender.get_meta("rpg_id", ""))):
		return
	var offset = defender.global_position - attacker.global_position
	offset.y = 0.0
	if offset.length() > float(data.get("reach", 3.0)):
		return
	if data.get("shape", "") == "line":
		var projection = offset.dot(attacker.forward())
		if projection < 0.0 or (offset - attacker.forward() * projection).length() > float(data.get("half_width", 0.6)):
			return
	if not data.get("radial", false) and offset.normalized().dot(attacker.forward()) < float(data.get("min_dot", 0.1)):
		return
	var physical = attacker.is_physical_thrust(data)
	var low = defender.thrust_body_low()
	var high = defender.thrust_body_high()
	var blade = Geometry3D.get_closest_points_between_segments(attacker.blade_base(), attacker.blade_tip(), low, high)
	var sweep = Geometry3D.get_closest_points_between_segments(attacker.previous_tip, attacker.blade_tip(), low, high)
	var contact = minf(blade[0].distance_to(blade[1]), sweep[0].distance_to(sweep[1]))
	if physical and contact > defender.thrust_body_radius() + 0.07:
		return
	if not physical and data.get("shape", "") != "line" and not data.get("wave", false) and contact > 0.85 and offset.length() > 1.6:
		return
	attacker.hit_landed = true
	var resolved = data.duplicate(true)
	var nearest = blade if blade[0].distance_to(blade[1]) <= sweep[0].distance_to(sweep[1]) else sweep
	resolved["contact_point"] = nearest[1]
	if attacker.mounted and attacker.mount_speed > 4.8 and data.get("kind", "") != "roar":
		resolved["damage"] = float(resolved.damage) * (1.0 + minf(attacker.mount_speed / 28.0, 0.30))
	var before = defender.hp
	var outcome = defender.receive_strike(attacker, resolved)
	if physical and outcome not in ["dead", "evade"]:
		attacker.register_thrust_contact(resolved.contact_point)
	if outcome in ["hit", "heavy_hit"]:
		fx._floating_text(resolved.contact_point + Vector3.UP * 0.3, str(int(ceil(before - defender.hp))), Color("fff1d8"))

func _on_impact(_fighter: DuelFighter, outcome: String, at: Vector3) -> void:
	fx.burst(at, outcome)

func _on_action(actor: DuelFighter, action: String) -> void:
	match action:
		"light", "heavy": fx.sound("thrust" if actor.is_thrust_weapon() else "swing", -16.0)
		"hoof":
			if actor == player: fx.sound("step", -25.0, 0.75)
		"charge": fx.sound("dodge", -18.0, 0.8)

func _on_skill(actor: DuelFighter, id: String, stage: String) -> void:
	skill_fx.play_skill(actor, id, stage)
	if stage == "start": fx.sound("charge", -18.0)

func _claim_reward(id: String, actor: RPGActor) -> void:
	reward_claimed[id] = elapsed
	if id.begins_with("raider_"):
		progress.kills += 1
		var amount = 16 + int(actor.get_meta("level")) * 5
		var gained = progress.grant_xp(amount)
		_notify("流寇已退 · 经验 +%d%s" % [amount, " · 升级！" if gained > 0 else ""])
		respawns[id] = elapsed + 45.0
		_apply_progress_stats(gained > 0)
	else:
		var reward = progress.defeat_boss(id)
		active_boss = ""
		if not reward.is_empty():
			_apply_progress_stats(true)
			var item: Dictionary = Progress.ITEMS[reward.item]
			var text = "交锋已定。获得 %s，经验 +%d。按 I 打开行囊装配，装备不会自动替换。" % [item.name, reward.xp]
			if progress.defeated.size() == 5:
				text += " 五关已过，密函平安送达。长坂行的故事至此告一段落，山川仍可继续游历。"
			_show_dialogue([[Progress.BOSSES[_boss_index(id)].name, text]], "reward")
	_save_game()

func _apply_progress_stats(heal: bool) -> void:
	var stats = progress.stats()
	player.apply_stats(stats.hp, stats.damage_scale, stats.armor, heal)
	if heal:
		fx.sound("parry", -18.0, 1.2)

func _on_player_death() -> void:
	dead = true
	phase = "defeat"
	active_boss = ""
	_set_enabled(false)
	_notify("此战失利 · 等级和战利品保留，返回驿站整备再来", 10.0)
	_save_game()

func _interaction() -> Dictionary:
	if phase != "explore":
		return {}
	for boss in Progress.BOSSES:
		if player.position.distance_to(boss.position) < 7.0:
			if boss.id in progress.defeated:
				return {"kind": "cleared", "id": boss.id, "text": "%s · 试炼已完成" % boss.name}
			if active_boss == boss.id:
				return {}
			var index = _boss_index(boss.id)
			var hint = "挑战 %s · 推荐 %d 级" % [boss.name, boss.level]
			if index > progress.defeated.size(): hint = "先完成前一位守将的试炼"
			elif progress.level < int(boss.level): hint = "%s · 需要 %d 级（当前 %d）" % [boss.name, boss.level, progress.level]
			return {"kind": "boss", "id": boss.id, "text": hint}
	for station in camps:
		if player.position.distance_to(station.position) < 7.0:
			return {"kind": "station", "id": station.get("id", station.name), "text": "%s · 整备、恢复生命与更换坐骑" % station.name}
	return {}

func interact() -> void:
	if paused or phase != "explore": return
	var interaction = _interaction()
	if interaction.is_empty(): return
	if interaction.kind == "station":
		rest()
	elif interaction.kind == "boss":
		var id: String = interaction.id
		if not progress.can_challenge(id):
			_notify(interaction.text + " · 沿路清剿流寇可获得经验")
			return
		_show_dialogue([[Progress.BOSSES[_boss_index(id)].name, STORIES[_boss_index(id)]], ["赵云", "请赐教。胜负既分，便以武艺为证，赠物为信。"]], "boss:" + id)
	else:
		_notify(interaction.text)

func _show_dialogue(lines: Array, after: String = "") -> void:
	phase = "dialogue"
	dialogue = lines.duplicate(true)
	dialogue_index = 0
	dialogue_after = after
	_set_enabled(false)

func _continue_dialogue() -> void:
	if phase != "dialogue" or paused: return
	dialogue_index += 1
	if dialogue_index < dialogue.size(): return
	var after = dialogue_after
	dialogue.clear()
	dialogue_after = ""
	phase = "explore"
	if after == "intro":
		progress.quest_started = true
		_notify("征程开启 · 清剿南郊游骑，升至二级后挑战马超")
	elif after.begins_with("boss:"):
		active_boss = after.trim_prefix("boss:")
		if enemies.has(active_boss):
			enemies[active_boss].reset_fighter()
			_notify("交锋开始 · " + Progress.BOSSES[_boss_index(active_boss)].name)
	_set_enabled(true)
	_save_game()

func _set_enabled(value: bool) -> void:
	if is_instance_valid(player):
		player.enabled = value
		player.input_move = Vector3.ZERO
		player.mount_speed = 0.0
		player.velocity = Vector3.ZERO
	for id in enemies:
		var actor: RPGActor = enemies[id]
		if is_instance_valid(actor):
			actor.enabled = value and _hostile(id)
			actor.input_move = Vector3.ZERO
			actor.mount_speed = 0.0
			actor.velocity = Vector3.ZERO

func rest() -> void:
	if _interaction().get("kind", "") != "station":
		_notify("请先到驿站整备，或从暂停菜单返回南郊驿营")
		return
	if active_boss != "":
		_notify("交锋中不能整备，请先拉开距离")
		return
	for id in enemies:
		if _hostile(id) and enemies[id].hp > 0.0 and player.position.distance_to(enemies[id].position) < 12.0:
			_notify("附近仍有流寇，暂时无法整备")
			return
	player.reset_fighter()
	_apply_progress_stats(true)
	_notify("驿站整备 · 生命、体力已恢复 · 按 I 更换装备或马色")
	_save_game()

func return_to_camp() -> void:
	get_tree().paused = false
	paused = false
	map_open = false
	inventory_open = false
	dead = false
	phase = "explore"
	active_boss = ""
	for id in enemies.keys(): _despawn(id)
	reward_claimed.clear()
	player.reset_fighter()
	player.position = World.START
	player.rotation.y = PI
	_apply_progress_stats(true)
	_set_enabled(true)
	_update_streaming()
	_update_camera(1.0, true)
	_save_game()
	_notify("已回南郊驿营 · 等级与战利品保留")

func equip(id: String) -> void:
	if id not in progress.inventory or not Progress.ITEMS.has(id): return
	var item: Dictionary = Progress.ITEMS[id]
	if item.slot == "weapon" and not player.equip_weapon(item.weapon_id):
		_notify("请收招后再更换兵器")
		return
	if progress.equip_item(id):
		_apply_progress_stats(false)
		_notify("已装配 · " + item.name)
		_save_game()

func _toggle_overlay(which: String) -> void:
	if phase not in ["explore", "defeat"]: return
	if which == "inventory":
		inventory_open = not inventory_open
		map_open = false
	else:
		map_open = not map_open
		inventory_open = false
	paused = inventory_open or map_open or dead
	get_tree().paused = paused
	_release_inputs()

func toggle_pause() -> void:
	if inventory_open or map_open:
		inventory_open = false
		map_open = false
		paused = dead
	elif phase == "dialogue":
		paused = not paused
	else:
		paused = not paused or dead
	get_tree().paused = paused
	_release_inputs()
	_save_game()

func command(action: String, payload: Variant = null) -> void:
	match action:
		"continue_dialogue": _continue_dialogue()
		"interact": interact()
		"toggle_inventory": _toggle_overlay("inventory")
		"toggle_map": _toggle_overlay("map")
		"equip", "equip_item": equip(str(payload))
		"toggle_pause", "pause", "resume": toggle_pause()
		"rest": rest()
		"return_to_camp", "camp", "respawn": return_to_camp()
		"return_to_menu":
			_save_game()
			if OS.has_feature("web"): JavaScriptBridge.eval("location.reload()")
		"horse_color":
			if str(payload) in ["white", "brown"] and _interaction().get("kind", "") == "station":
				progress.horse_color = str(payload)
				_spawn_player(player.position, false)
				_save_game()
			else: _notify("请在驿站附近更换马色")
		"new_game":
			progress = Progress.new()
			progress.position = World.START
			respawns.clear()
			discovered.clear()
			elapsed = 0.0
			spawn_clock = 0.0
			save_clock = 0.0
			return_to_camp()
			_spawn_player(World.START, true)
			_show_dialogue(INTRO, "intro")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F: interact()
			KEY_ENTER: _continue_dialogue()
			KEY_I: _toggle_overlay("inventory")
			KEY_M: _toggle_overlay("map")
			KEY_ESCAPE: toggle_pause()
			KEY_R:
				if dead: return_to_camp()
			KEY_N: fx.muted = not fx.muted
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE: camera_drag = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: camera_distance = maxf(7.5, camera_distance - 0.8)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera_distance = minf(19.0, camera_distance + 0.8)
	elif event is InputEventMouseMotion and camera_drag and not paused:
		camera_yaw -= event.relative.x * 0.006

func _update_camera(delta: float, instant: bool = false) -> void:
	var target = player.position + Vector3.UP * 1.65
	var offset = Vector3(0, camera_distance * 0.68, camera_distance).rotated(Vector3.UP, camera_yaw)
	var desired = target + offset
	camera.position = desired if instant else camera.position.lerp(desired, 1.0 - exp(-delta * 7.0))
	camera.look_at(target)

func _notify(text: String, duration: float = 4.5) -> void:
	toast = text
	toast_clock = duration

func _boss_index(id: String) -> int:
	for i in Progress.BOSSES.size():
		if Progress.BOSSES[i].id == id: return i
	return -1

func _quest() -> Dictionary:
	if progress.defeated.size() >= 5:
		return {"title": "终章 · 五关已定", "detail": "密函已送达。可自由游历、清剿流寇，或装配收集到的兵器。", "target_position": World.START}
	var next: Dictionary = Progress.BOSSES[progress.defeated.size()]
	var title = "第 %d 关 · %s" % [progress.defeated.size() + 1, next.title]
	var detail = "前往挑战%s，胜出获得%s。" % [next.name, Progress.ITEMS[next.equipment].name]
	if progress.level < int(next.level):
		detail = "沿路清剿游骑，升至 %d 级后挑战%s（当前 %d 级）。" % [next.level, next.name, progress.level]
	return {"title": title, "detail": detail, "target_position": next.position}

func snapshot() -> Dictionary:
	if not is_instance_valid(player): return {"ready": false, "phase": "loading", "game_mode": "rpg"}
	var stats = progress.stats()
	var bosses: Array = []
	var pois: Array = []
	for boss in Progress.BOSSES:
		var entry = boss.duplicate()
		entry["defeated"] = boss.id in progress.defeated
		entry["available"] = progress.can_challenge(boss.id)
		entry["is_next"] = _boss_index(boss.id) == progress.defeated.size()
		bosses.append(entry)
		pois.append({"id": boss.id, "name": boss.name, "kind": "boss", "position": _point(boss.position), "discovered": boss.id in discovered})
	for station in camps:
		pois.append({"id": station.get("id", station.name), "name": station.name, "kind": "camp", "position": _point(station.position), "discovered": true})
	var target: Dictionary = {}
	if is_instance_valid(player.opponent) and player.opponent.hp > 0.0:
		var actor = player.opponent
		var id: String = actor.get_meta("rpg_id")
		target = {"id": id, "name": "山贼游骑" if id.begins_with("raider_") else Progress.BOSSES[_boss_index(id)].name, "level": actor.get_meta("level"), "hp": actor.hp, "max_hp": actor.max_hp}
	var current_dialogue: Dictionary = {}
	if phase == "dialogue" and dialogue_index < dialogue.size():
		current_dialogue = {"speaker": dialogue[dialogue_index][0], "text": dialogue[dialogue_index][1], "index": dialogue_index + 1, "total": dialogue.size()}
	var visible_enemies: Array = []
	for id in enemies:
		var actor: RPGActor = enemies[id]
		if is_instance_valid(actor): visible_enemies.append({"id": id, "character": actor.character_id, "level": actor.get_meta("level"), "hp": actor.hp, "max_hp": actor.max_hp, "state": actor.state, "hostile": _hostile(id), "position": _point(actor.position)})
	var quest = _quest()
	quest.target_position = _point(quest.target_position)
	for entry in bosses: entry.position = _point(entry.position)
	return {"ready": true, "game_mode": "rpg", "phase": phase, "paused": paused, "dead": dead, "inventory_open": inventory_open, "map_open": map_open, "horse_color": progress.horse_color, "region": world.zone_at(player.position), "player": {"name": "赵云", "character": "zhaoyun", "level": progress.level, "hp": player.hp, "max_hp": player.max_hp, "stamina": player.stamina, "max_stamina": 100.0, "xp": progress.xp, "xp_to_next": progress.xp_to_next(), "attack": stats.attack, "armor": stats.armor, "energy": player.energy, "position": _point(player.position), "facing": player.rotation.y, "state": player.state, "weapon": player.weapon_id, "mount_speed": player.mount_speed, "contact_active": player.contact_active, "contact_latched": player.contact_latched}, "quest": quest, "target": target, "interaction": _interaction().get("text", ""), "dialogue": current_dialogue, "toast": toast, "bosses": bosses, "pois": pois, "inventory": progress.inventory.duplicate(), "equipped": progress.equipped.duplicate(), "save_label": save_label, "defeated": progress.defeated.duplicate(), "kills": progress.kills, "enemies": visible_enemies, "active_boss": active_boss, "seconds": elapsed, "muted": fx.muted, "fps": Engine.get_frames_per_second(), "coordinates": "metres; Y up; X east; Z south. Continuous circular world radius 155m."}

func _point(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _save_game() -> bool:
	if testing or not is_instance_valid(player): return true
	progress.position = World.START if dead else Vector3(player.position.x, 0.05, player.position.z)
	var payload = JSON.stringify(progress.to_dict())
	if OS.has_feature("web"):
		var script = "(()=>{try{localStorage.setItem(" + JSON.stringify(SAVE_KEY) + "," + JSON.stringify(payload) + ");return true}catch(e){return false}})()"
		var saved = bool(JavaScriptBridge.eval(script))
		save_label = "自动存档 · 当前浏览器" if saved else "存档不可用 · 浏览器未允许本地存储"
		return saved
	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file == null:
		save_label = "本次未能写入存档"
		return false
	file.store_string(payload)
	return true

func _load_game() -> bool:
	var raw: Variant = null
	if OS.has_feature("web"):
		raw = JavaScriptBridge.eval("(()=>{try{return localStorage.getItem(" + JSON.stringify(SAVE_KEY) + ")}catch(e){return null}})()")
	elif FileAccess.file_exists(SAVE_FILE):
		raw = FileAccess.get_file_as_string(SAVE_FILE)
	if not raw is String or raw.length() > 65536: return false
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary or not progress.load_dict(parsed): return false
	progress.position.y = 0.05
	var flat = Vector2(progress.position.x, progress.position.z)
	if flat.length() > World.MAP_RADIUS + 0.5: progress.position = World.START
	return true

func _web_command(args: Array) -> void:
	if args.is_empty(): return
	var action = str(args[0])
	if action == "input" and args.size() >= 3:
		var id = str(args[1])
		if InputMap.has_action(id):
			if bool(args[2]): Input.action_press(id)
			else: Input.action_release(id)
	elif action == "blur":
		_release_inputs()
		_save_game()
		if not paused: toggle_pause()
	elif action == "mute": fx.muted = not fx.muted
	else: command(action, args[1] if args.size() > 1 else null)
	_publish()

func _release_inputs() -> void:
	for id in ["move_left", "move_right", "move_up", "move_down", "light", "heavy", "guard", "dodge", "skill_rush", "skill_counter", "ultimate"]:
		Input.action_release(id)
	if is_instance_valid(player):
		player.input_move = Vector3.ZERO
		player.wants_block = false

func _publish() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__wenfengState=" + JSON.stringify(snapshot()) + ";window.wenfengStateChanged && window.wenfengStateChanged();")
