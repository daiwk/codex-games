extends SceneTree

const Roster = preload("res://scripts/roster.gd")
var game: Node3D
var checks: Array[String] = []
var failures: Array[String] = []
var horse_paths: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	checks.append(label)
	if not condition:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func bone(rig: Skeleton3D, suffix: String) -> int:
	for index in rig.get_bone_count():
		if rig.get_bone_name(index).ends_with(suffix) or rig.get_bone_name(index).ends_with(suffix.replace(".", "_")):
			return index
	return -1

func prepare(id: String, mode = "mounted", weapon = "", distance_m = 2.1, horse_color = "white", enemy_color = "brown") -> void:
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(id)
	game.select_opponent("machao" if id == "zhaoyun" else "zhaoyun")
	if not weapon.is_empty():
		game.select_weapon(weapon)
	game.select_horse_color(horse_color)
	game.select_horse_color(enemy_color, true)
	await frames(2)
	game.start_match()
	# Exercise the real countdown transition without waiting for the countdown
	# presentation on every isolated combat case. Physics still advances at the
	# normal 1/60-second game step (120 ticks/s, time_scale 2).
	game.phase_clock = 0.01
	Engine.time_scale = 2.0
	await frames(3)
	game.ai_enabled = false
	game.enemy.set_physics_process(false)
	reset_pair(distance_m)
	await frames(3)

func reset_pair(distance_m = 2.1) -> void:
	game.skill_fx.clear()
	for fighter in [game.player, game.enemy]:
		fighter.reset_fighter()
		fighter.set_physics_process(fighter == game.player)
	game.player.enabled = true
	game.enemy.enabled = false
	game.player.position = Vector3(0, 0.015, 0)
	game.enemy.position = Vector3(0, 0.015, distance_m)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	game.phase = "fight"
	game.ai_enabled = false

func wait_action() -> void:
	for index in 240:
		await frames(1)
		if game.player.state in ["idle", "move", "block"]:
			return
	check("action recovers within four game seconds", false)

func imported_scene_path(node: Node) -> String:
	if not node.scene_file_path.is_empty():
		return node.scene_file_path
	for child in node.get_children():
		var path = imported_scene_path(child)
		if not path.is_empty():
			return path
	return ""

func find_kind(node: Node, kind: String) -> Node:
	if node.is_class(kind):
		return node
	for child in node.get_children():
		var found = find_kind(child, kind)
		if found != null:
			return found
	return null

func find_skinned_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.skin != null:
		return node
	for child in node.get_children():
		var found = find_skinned_mesh(child)
		if found != null:
			return found
	return null

func _check_horse_skin(horse: Node3D, color: String) -> void:
	var rig = find_kind(horse, "Skeleton3D") as Skeleton3D
	var animation = find_kind(horse, "AnimationPlayer") as AnimationPlayer
	check(color + " horse has real skeleton and animation player", rig != null and animation != null)
	if rig == null or animation == null:
		return
	check(color + " horse has anatomical joints", rig.get_bone_count() >= 20)
	var clips: Array[String] = []
	for key in animation.get_animation_list():
		clips.append(String(key).get_slice("/", String(key).get_slice_count("/") - 1))
	check(color + " horse has standing walking galloping clips", "Idle" in clips and "Walk" in clips and "Gallop" in clips)
	var mesh = find_skinned_mesh(horse)
	check(color + " horse geometry is skinned", mesh != null)
	if mesh == null:
		return
	var totals: Dictionary = {}
	var weight_sum = 0.0
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var joints = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if joints == null or weights == null:
			continue
		for index in weights.size():
			var weight = float(weights[index])
			if weight > 0.0001:
				var joint = int(joints[index])
				totals[joint] = float(totals.get(joint, 0.0)) + weight
				weight_sum += weight
	var largest = 0.0
	for total in totals.values():
		largest = maxf(largest, float(total))
	check(color + " horse is not entirely bound to root", totals.size() >= 8 and weight_sum > 100.0 and largest / weight_sum < 0.90)

func _check_roster_and_attacks(color: String) -> void:
	for id in Roster.IDS:
		var weapons: Array = Roster.weapon_choices(id)
		for weapon in weapons:
			# Short one-handed weapons require the horse to close the distance;
			# mounted J/K deliberately do not inherit the ground fighter's lunge.
			var strike_distance = 1.4 if id == "xuchu" else 2.1
			var opponent_color = "brown" if color == "white" else "white"
			await prepare(id, "mounted", weapon, strike_distance, color, opponent_color)
			var label = id + "/" + String(weapon) + "/" + color
			var fighter = game.player
			check(label + " actual mounted fighters", fighter.mounted and game.enemy.mounted)
			check(label + " selected horses on both sides", fighter.horse_color == color and game.enemy.horse_color == opponent_color)
			check(label + " horse and post-animation rider", is_instance_valid(fighter.horse) and is_instance_valid(fighter.rider_pose) and fighter.rider_pose.active)
			var path = imported_scene_path(fighter.horse)
			check(label + " actual imported horse asset", not path.is_empty() and path.ends_with(".glb"))
			if not horse_paths.has(color):
				horse_paths[color] = path
				_check_horse_skin(fighter.horse, color)
			else:
				check(label + " color asset survives changing general", horse_paths[color] == path)
			if horse_paths.size() == 2:
				check(label + " brown and white use distinct source models", horse_paths.white != horse_paths.brown)
			var collider: CollisionShape3D = fighter.get_child(0)
			check(label + " horse-sized collision", collider.shape is CapsuleShape3D and collider.shape.radius > 0.55 and collider.shape.height > 2.8)
			var pose: Dictionary = {}
			var read_pose = func():
				if not fighter.is_inside_tree():
					return
				for part in ["Hips", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]:
					pose[part] = fighter.skeleton.to_global(fighter.skeleton.get_bone_global_pose(bone(fighter.skeleton, part)).origin)
			fighter.skeleton.skeleton_updated.connect(read_pose)
			await frames(4)
			check(label + " live skeleton modifier callback", pose.size() == 5)
			if pose.size() == 5:
				var saddle_y = fighter.horse.global_position.y + fighter.horse.saddle_height()
				check(label + " pelvis rests on saddle", absf(Vector3(pose.Hips).y - saddle_y) < 0.035)
				for side in ["Left", "Right"]:
					var local_foot: Vector3 = fighter.to_local(pose[side + "Foot"])
					var direction = 1.0 if side == "Left" else -1.0
					check(label + " " + side + " stirrup clears horse centre", local_foot.x * direction > 0.28 and local_foot.y > 0.65)
			check(label + " J starts", fighter.request_light())
			var attack_shape = String(fighter.attack.get("shape", "sector"))
			check(label + " appropriate line or sector", attack_shape == ("line" if fighter.is_thrust_weapon() else "sector"))
			await wait_action()
			check(label + " J really hits", game.enemy.hp < 120.0)
			reset_pair(strike_distance)
			check(label + " K starts", fighter.request_heavy())
			await wait_action()
			check(label + " K really hits", game.enemy.hp < 120.0)
			for skill in ["rush", "counter", "ultimate"]:
				var close_cleave: bool = id == "xuchu" and skill == "rush"
				if close_cleave:
					# This role's shoulder-in knife strike is deliberately a close
					# action. Preserve its actual boundary as well as proving the
					# intended contact distance; do not enlarge a hurtbox to fit
					# the former all-roles 2m fixture.
					reset_pair(2.0)
					check(label + " close Q starts at outside boundary", fighter.request_skill(skill))
					await wait_action()
					check(label + " close Q at 2.0m really whiffs", is_equal_approx(game.enemy.hp, 120.0))
				reset_pair(1.8 if close_cleave else 2.0)
				fighter.energy = 100.0
				var started: bool = fighter.request_ultimate() if skill == "ultimate" else fighter.request_skill(skill)
				check(label + " " + skill + " starts", started)
				await wait_action()
				check(label + " " + skill + " really hits", game.enemy.hp < 120.0)
				check(label + " " + skill + " leaves no ground dodge", fighter.current_clip != "Dodge" and fighter.state != "dodge")
			fighter.skeleton.skeleton_updated.disconnect(read_pose)
			print("MOUNTED attacks checked ", label)

func _check_line_filter() -> void:
	await prepare("zhaoyun")
	for offset in [Vector3(2.0, 0.015, 2.0), Vector3(0, 0.015, -2.1)]:
		reset_pair()
		game.enemy.position = offset
		game.player.input_move = Vector3(0, 0, 1)
		check("spear off-axis attack starts", game.player.request_light())
		await wait_action()
		check("mounted spear cannot hit side or rear", is_equal_approx(game.enemy.hp, 120.0))

func _check_motion_and_charge() -> void:
	await prepare("zhaoyun", "mounted", "", 8.0)
	var fighter = game.player
	fighter.input_move = Vector3(0, 0, 1)
	await frames(12)
	check("mounted movement accelerates gradually", fighter.mount_speed > 0.4 and fighter.mount_speed < 2.0)
	await frames(50)
	check("mounted cruise reaches speed", fighter.mount_speed > 4.5 and fighter.mount_speed <= 4.81)
	var before: Vector3 = fighter.position
	fighter.input_move = Vector3.ZERO
	await frames(1)
	check("release has braking inertia", fighter.mount_speed > 3.5 and fighter.position.distance_to(before) > 0.02)
	await frames(45)
	check("release eventually stops", fighter.mount_speed < 0.01)
	reset_pair(8.0)
	fighter.input_move = Vector3(0, 0, 1)
	await frames(60)
	var original_forward: Vector3 = fighter.forward()
	fighter.input_move = -original_forward
	await frames(1)
	check("reverse input cannot reverse horse instantly", fighter.forward().dot(original_forward) > 0.98 and fighter.velocity.dot(original_forward) > 0.0)
	await frames(28)
	check("horse turns over time", absf(fighter.rotation.y) > 0.4 and absf(fighter.rotation.y) < 2.0)
	check("horse travels along heading without strafing", Vector3(fighter.velocity.x, 0, fighter.velocity.z).cross(fighter.forward()).length() < 0.05)
	reset_pair(8.0)
	fighter.input_move = Vector3(0, 0, 1)
	check("Space starts cavalry charge", fighter.request_dodge())
	check("charge spends stamina once", is_equal_approx(fighter.stamina, 76.0))
	check("charge is not invulnerable dodge", fighter.state != "dodge" and not fighter.is_invulnerable())
	check("charge begins cooldown", fighter.mount_charge_cooldown > 3.5)
	check("charge cooldown prevents repeated Space", not fighter.request_dodge() and is_equal_approx(fighter.stamina, 76.0))
	await frames(48)
	check("charge physically exceeds cruise speed", fighter.mount_speed > 7.8 and fighter.position.z > 2.0)
	fighter.input_move = Vector3.ZERO
	await frames(190)
	check("charge cooldown expires naturally", fighter.mount_charge_cooldown <= 0.0)
	check("Space works again after cooldown", fighter.request_dodge())
	fighter.reset_fighter()
	check("fighter reset clears all riding state", fighter.mount_speed == 0.0 and fighter.mount_charge_time == 0.0 and fighter.mount_charge_cooldown == 0.0)
	reset_pair(8.0)
	fighter.input_move = Vector3(0, 0, 1)
	fighter.wants_block = true
	await frames(3)
	check("held guard enters mounted block", fighter.state == "block")
	check("Space can charge while guard remains held", fighter.request_dodge())
	await frames(16)
	check("held guard does not cancel paid charge", fighter.mount_speed > 1.2 and fighter.state != "block" and fighter.mount_charge_time > 0.0)
	reset_pair(8.0)
	fighter.position.z = 11.2
	fighter.input_move = Vector3(0, 0, 1)
	await frames(45)
	check("mounted arena boundary clamps real movement", Vector2(fighter.position.x, fighter.position.z).length() <= 11.4001 and fighter.mount_speed <= 1.21)

func _check_charge_damage_and_vulnerability() -> void:
	await prepare("zhaoyun")
	var fighter = game.player
	check("baseline strike begins", fighter.request_light())
	await wait_action()
	var standing_damage = 120.0 - game.enemy.hp
	check("standing baseline has real damage", standing_damage > 0.0)
	reset_pair(5.0)
	fighter.input_move = Vector3(0, 0, 1)
	check("damage comparison starts actual charge", fighter.request_dodge())
	await frames(36)
	check("damage comparison has actual fast movement", fighter.mount_speed > 5.0)
	var contact_motion: Array[float] = []
	var read_motion = func(attacker, _data):
		if game.enemy.hp < 120.0:
			contact_motion.append(attacker.get_real_velocity().dot(attacker.forward()))
	fighter.strike_requested.connect(read_motion)
	check("attack during gallop starts", fighter.request_light())
	await wait_action()
	fighter.strike_requested.disconnect(read_motion)
	check("bonus hit occurs during genuine forward travel", not contact_motion.is_empty() and contact_motion.max() > 5.0)
	check("galloping strike gains actual damage", 120.0 - game.enemy.hp > standing_damage * 1.15)
	reset_pair(1.25)
	check("same-distance uncharged close strike starts", fighter.request_light())
	await wait_action()
	var close_standing_damage = 120.0 - game.enemy.hp
	reset_pair(1.25)
	var blocked_start: Vector3 = fighter.position
	fighter.input_move = Vector3(0, 0, 1)
	check("blocked horse accepts charge input", fighter.request_dodge())
	await frames(24)
	check("stationary opposing horse blocks real charge movement", fighter.position.distance_to(blocked_start) < 0.08 and fighter.mount_speed < 1.0 and fighter.get_real_velocity().length() < 1.0)
	check("blocked horse can still use ordinary strike", fighter.request_light())
	await wait_action()
	var blocked_damage = 120.0 - game.enemy.hp
	check("blocked charge grants no fake speed damage", is_equal_approx(blocked_damage, close_standing_damage))
	print("MOUNTED_BLOCKED_CONTACT=", JSON.stringify({"distance": 1.25, "stationary_damage": close_standing_damage,
		"blocked_damage": blocked_damage, "far_stationary_damage": standing_damage,
		"real_forward_speed": fighter.get_real_velocity().dot(fighter.forward()), "mount_speed": fighter.mount_speed}))
	reset_pair()
	game.enemy.enabled = true
	game.enemy.set_physics_process(true)
	check("vulnerability check starts charge", fighter.request_dodge())
	check("enemy starts real incoming strike", game.enemy.request_light())
	await frames(35)
	check("charging rider can be hit", fighter.hp < 120.0 and fighter.dodged_hits == 0)
	check("hit interrupts charge", fighter.mount_charge_time <= 0.0)

func _check_pause_and_rounds() -> void:
	await prepare("zhaoyun", "mounted", "", 8.0, "brown", "white")
	var fighter = game.player
	fighter.input_move = Vector3(0, 0, 1)
	fighter.request_dodge()
	await frames(12)
	game.toggle_pause()
	var at: Vector3 = fighter.position
	var cooldown = float(fighter.mount_charge_cooldown)
	var time_left = float(game.round_time)
	await frames(25)
	check("pause freezes horse physics and charge cooldown", fighter.position.is_equal_approx(at) and is_equal_approx(fighter.mount_charge_cooldown, cooldown))
	check("pause freezes round clock", is_equal_approx(game.round_time, time_left))
	game.toggle_pause()
	Engine.time_scale = 2.0
	await frames(6)
	check("resume continues mounted movement", fighter.position.distance_to(at) > 0.04 and fighter.mount_charge_cooldown < cooldown)
	reset_pair()
	game.enemy.hp = 10.0
	check("round ending attack starts", fighter.request_heavy())
	for index in 160:
		await frames(1)
		if game.phase == "round_end":
			break
	check("actual mounted hit ends round", game.phase == "round_end" and game.scores[0] == 1)
	check("defeated rider keeps a live standing horse", is_instance_valid(game.enemy.horse) and game.enemy.horse.is_inside_tree() and game.enemy.horse.visible)
	var saved_colors = [game.player.horse_color, game.enemy.horse_color]
	var stopped_at: Vector3 = fighter.position
	await frames(6)
	check("round end stops drifting horse", fighter.position.distance_to(stopped_at) < 0.001 and not fighter.enabled)
	for index in 500:
		await frames(1)
		if game.phase == "countdown":
			break
	check("next round starts with riding state cleared", game.phase == "countdown" and fighter.mount_speed == 0.0 and fighter.mount_charge_time == 0.0 and fighter.mount_charge_cooldown == 0.0)
	check("next round restores HP and keeps score", fighter.hp == 120.0 and game.enemy.hp == 120.0 and game.scores[0] == 1 and game.round_number == 2)
	check("next round retains both chosen horses", [game.player.horse_color, game.enemy.horse_color] == saved_colors)
	game.phase_clock = 0.01
	await frames(3)
	fighter.input_move = Vector3(0, 0, 1)
	fighter.request_dodge()
	await frames(10)
	game.start_match()
	Engine.time_scale = 2.0
	check("restart clears score and charge", game.scores == [0, 0] and game.round_number == 1 and fighter.mount_speed == 0.0 and fighter.mount_charge_time == 0.0 and fighter.mount_charge_cooldown == 0.0)
	check("restart retains both chosen horses", [game.player.horse_color, game.enemy.horse_color] == saved_colors)

func _check_colors_and_gaits() -> void:
	game.return_to_menu()
	game.select_combat_mode("mounted")
	game.select_horse_color("brown")
	game.select_horse_color("white", true)
	check("player and enemy colors are independent", game.horse_color == "brown" and game.enemy_horse_color == "white" and game.player.horse_color == "brown" and game.enemy.horse_color == "white")
	game.select_horse_color("white")
	check("both opponents may choose the same horse color", game.player.horse_color == "white" and game.enemy.horse_color == "white")
	game.select_horse_color("brown", true)
	check("enemy color change leaves player choice intact", game.player.horse_color == "white" and game.enemy.horse_color == "brown")
	game.select_horse_color("brown")
	game.select_horse_color("white", true)
	game.select_character("xuchu")
	game.select_weapon("sword")
	game.select_opponent("guanyu")
	check("changing generals and weapon preserves horses", game.player.horse_color == "brown" and game.enemy.horse_color == "white")
	game.start_match()
	game.phase_clock = 0.01
	Engine.time_scale = 2.0
	await frames(3)
	check("match starts with independent chosen horses", game.player.horse_color == "brown" and game.enemy.horse_color == "white")
	game.select_horse_color("white")
	check("horse selection cannot respawn a fighter mid-combat", game.player.horse_color == "brown" and game.horse_color == "brown")
	game.return_to_menu()
	game.select_combat_mode("foot")
	check("foot mode retains horse preferences", game.horse_color == "brown" and game.enemy_horse_color == "white")
	game.select_combat_mode("mounted")
	check("returning to mounted restores horse preferences", game.player.horse_color == "brown" and game.enemy.horse_color == "white")
	game.select_horse_color("invalid")
	check("invalid horse color is ignored", game.horse_color == "brown")
	for color in ["white", "brown"]:
		await prepare("zhaoyun", "mounted", "", 8.0, color, "brown" if color == "white" else "white")
		var fighter = game.player
		var horse = fighter.horse
		var rig = find_kind(horse, "Skeleton3D") as Skeleton3D
		var tree = find_kind(horse, "AnimationTree") as AnimationTree
		check(color + " live horse gait tree", rig != null and tree != null and tree.active)
		if rig == null or tree == null:
			continue
		var leg_ids: Array[int] = []
		for limb in ["FrontLowerLeg.L", "FrontLowerLeg.R", "BackLowerLeg.L", "BackLowerLeg.R"]:
			var index = bone(rig, limb)
			check(color + " actual limb " + limb, index >= 0)
			if index >= 0:
				leg_ids.append(index)
		var standing: Dictionary = {}
		for index in leg_ids:
			standing[index] = rig.get_bone_pose_rotation(index)
		fighter.input_move = Vector3(0, 0, 1)
		var walk_motion: Dictionary = {}
		for index in leg_ids:
			walk_motion[index] = 0.0
		# A moving leg can briefly cross its standing rotation. Observe a short
		# window instead of declaring that valid gait phase a frozen limb.
		for tick in 42:
			await frames(1)
			for index in leg_ids:
				walk_motion[index] = maxf(walk_motion[index], rig.get_bone_pose_rotation(index).angle_to(Quaternion(standing[index])))
		check(color + " actual travel drives walking gait", fighter.mount_speed > 2.0 and float(tree.get("parameters/Gait/blend_position")) > 1.0)
		var walking: Dictionary = {}
		for index in leg_ids:
			walking[index] = rig.get_bone_pose_rotation(index)
			check(color + " walking moves limb independently " + str(index), walk_motion[index] > 0.005)
		check(color + " gallop starts through actual Space", fighter.request_dodge())
		var gallop_motion: Dictionary = {}
		for index in leg_ids:
			gallop_motion[index] = 0.0
		for tick in 38:
			await frames(1)
			for index in leg_ids:
				gallop_motion[index] = maxf(gallop_motion[index], rig.get_bone_pose_rotation(index).angle_to(Quaternion(walking[index])))
		check(color + " actual charge drives galloping gait", fighter.mount_speed > 7.0 and float(tree.get("parameters/Gait/blend_position")) > 5.0)
		for index in leg_ids:
			check(color + " galloping moves limb independently " + str(index), gallop_motion[index] > 0.005 and rig.get_bone_global_pose(index).origin.is_finite())

func _check_ai_and_foot_regression() -> void:
	await prepare("xuchu", "mounted", "sword", 5.0)
	game.enemy.enabled = true
	game.enemy.set_physics_process(true)
	game.ai_enabled = true
	game.difficulty = 2
	game.rng.seed = 714
	for index in 900:
		await frames(1)
		if game.player.hp < 120.0:
			break
	check("mounted AI navigates and lands actual hit", game.player.hp < 120.0 and game.enemy.damage_dealt > 0.0)
	await prepare("zhaoyun", "foot")
	var fighter = game.player
	check("return to foot removes horse and modifier", not fighter.mounted and not game.enemy.mounted and fighter.horse == null and fighter.rider_pose == null)
	check("return to foot restores arena", game.arena.scale.is_equal_approx(Vector3.ONE))
	var collider: CollisionShape3D = fighter.get_child(0)
	check("foot collision restored", is_equal_approx(collider.shape.height, 1.8) and is_equal_approx(collider.shape.radius, 0.32))
	check("foot model elevation restored", absf(fighter.model.position.y) < 0.001)
	check("foot Space still dodges", fighter.request_dodge(Vector3(0, 0, -1)))
	await frames(7)
	check("foot dodge still has its real invulnerability window", fighter.state == "dodge" and fighter.is_invulnerable() and fighter.position.z < -0.3)
	await wait_action()
	reset_pair()
	fighter.input_move = Vector3(1, 0, 0)
	await frames(20)
	check("foot movement still strafes", fighter.position.x > 0.3 and fighter.current_clip != "Idle" and fighter.mount_speed == 0.0)
	reset_pair()
	check("foot light attack starts", fighter.request_light())
	await wait_action()
	check("foot light attack still deals damage", game.enemy.hp < 120.0)
	game.return_to_menu()
	game.select_character("guanyu")
	check("foot keeps character-specific low sweep skill clip", game.player.skill_profile("rush").clip == "CrescentLow")
	game.select_combat_mode("mounted")
	await frames(2)
	var old_horse = weakref(game.player.horse)
	game.select_combat_mode("foot")
	await frames(3)
	check("repeated mode switch frees former horse", old_horse.get_ref() == null and game.player.horse == null)
	game.select_combat_mode("invalid")
	check("invalid combat mode is ignored", game.combat_mode == "foot")
	check("snapshot publishes foot mode", game.snapshot().combat_mode == "foot" and not game.snapshot().player.mounted)

func _run() -> void:
	if not ResourceLoader.exists("res://scripts/horse_visual.gd"):
		push_error("HorseVisual is not ready; run this test after the horse module is present")
		quit(2)
		return
	Engine.physics_ticks_per_second = 120
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(4)
	game.testing = true
	# Audio is outside this physics suite. Muting also lets the headless runner
	# exit without pending AudioStreamPlaybackWAV voices from the last gong.
	game.fx.muted = true
	game.ai_enabled = false
	check("default mode remains foot", game.combat_mode == "foot" and not game.player.mounted)
	game.select_combat_mode("mounted")
	await frames(3)
	check("mode selection expands arena", game.combat_mode == "mounted" and game.arena.scale.x > 1.4)
	check("snapshot publishes mounted mode", game.snapshot().combat_mode == "mounted" and game.snapshot().player.mounted)
	for color in ["white", "brown"]:
		await _check_roster_and_attacks(color)
	await _check_colors_and_gaits()
	await _check_line_filter()
	await _check_motion_and_charge()
	await _check_charge_damage_and_vulnerability()
	await _check_pause_and_rounds()
	await _check_ai_and_foot_regression()
	Engine.time_scale = 1.0
	paused = false
	var result = {"checks": checks.size(), "failures": failures, "passed": failures.is_empty()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa"))
	var output = FileAccess.open("res://qa/mounted-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	print("MOUNTED RESULTS ", JSON.stringify(result))
	game.queue_free()
	game = null
	current_scene = null
	await frames(4)
	quit(0 if failures.is_empty() else 1)
