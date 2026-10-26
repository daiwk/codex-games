extends SceneTree

## Run after importing assets. No scene internals or animation resources are mocked.
## godot --headless --path <project> --script res://tools/motion_polish_test.gd -- --rpg-test
var game: Node3D
var rows: Array = []
var failures: Array[String] = []
var checks = 0
var rider_samples: Dictionary = {}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa"))
	if "--rpg-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --rpg-test to isolate RPG save data")
		quit(2)
		return
	call_deferred("run")

func check(label: String, condition: bool, value: Variant = null) -> void:
	checks += 1
	rows.append({"label": label, "passed": condition, "value": value})
	print("PASS " if condition else "FAIL ", label, " ", value if value != null else "")
	if not condition:
		failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func bone(rig: Skeleton3D, suffix: String) -> int:
	for index in rig.get_bone_count():
		if rig.get_bone_name(index).ends_with(suffix):
			return index
	return -1

func phase(player: AnimationPlayer) -> float:
	if player.current_animation_length <= 0.0:
		return 0.0
	return fposmod(player.current_animation_position / player.current_animation_length, 1.0)

func phase_error(a: float, b: float) -> float:
	return absf(wrapf(a - b, -0.5, 0.5))

func setup_duel(id = "zhaoyun", mode = "foot", gap = 4.8) -> void:
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(id)
	game.select_opponent("machao" if id == "zhaoyun" else "zhaoyun")
	await frames(3)
	game.phase = "fight"
	game.ai_enabled = false
	game.set_physics_process(false)
	game.set_process(false)
	game.skill_fx.clear()
	for fighter in [game.player, game.enemy]:
		fighter.reset_fighter()
		fighter.input_move = Vector3.ZERO
		fighter.enabled = false
		fighter.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, -gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, gap * 0.5)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	await frames(3)

func ground_phase_checks(id: String) -> void:
	await setup_duel(id)
	var fighter = game.player
	# Seek an actual imported loop away from its seam, then exercise the real
	# direction selector. A restart at zero cannot pass this check accidentally.
	var sequence = [
		[Vector3.FORWARD * -1.0, "Run"],
		[Vector3.RIGHT, "StrafeLeft"],
		[Vector3.FORWARD, "WalkBack"],
		[Vector3.LEFT, "StrafeRight"],
		[Vector3.FORWARD * -1.0, "Run"],
	]
	for index in sequence.size():
		var entry: Array = sequence[index]
		fighter.input_move = entry[0]
		if index == 0:
			fighter._update_locomotion(1.0 / 60.0)
			fighter.animation_player.seek(fighter.animation_player.current_animation_length * 0.57, true)
			continue
		var before = phase(fighter.animation_player)
		var prior_rate: float = fighter.animation_player.speed_scale
		fighter._update_locomotion(1.0 / 60.0)
		var after = phase(fighter.animation_player)
		check(id + " selects " + entry[1], fighter.current_clip == entry[1], fighter.current_clip)
		check(id + " direction preserves gait phase " + str(index), phase_error(before, after) < 0.08,
			{"before": before, "after": after, "error": phase_error(before, after)})
		check(id + " direction rate changes gradually " + str(index), absf(fighter.animation_player.speed_scale - prior_rate) < 0.22,
			{"before": prior_rate, "after": fighter.animation_player.speed_scale})
		fighter.animation_player.seek(fighter.animation_player.current_animation_length * 0.57, true)
	# A brief release must not freeze the loop while the body is still braking.
	fighter.input_move = Vector3.ZERO
	fighter.velocity = Vector3(0.0, 0.0, 1.5)
	fighter._update_locomotion(1.0 / 60.0)
	check(id + " braking animation rate stays finite", is_finite(fighter.animation_player.speed_scale) and fighter.animation_player.speed_scale > 0.0,
		fighter.animation_player.speed_scale)
	check(id + " installs real pre-contact secondary modifier", is_instance_valid(fighter.combat_motion) and fighter.combat_motion.get_parent() == fighter.skeleton)
	# Presentation motion must not change the committed attack pose. Real contact
	# safety is covered separately by the existing thrust_contact_test suite.
	fighter.state = "attack"
	fighter.attack = {"active": Vector2(0.20, 0.45)}
	fighter.action_time = 0.30
	check(id + " secondary motion yields during active contact", fighter.combat_motion.activity_weight() == 0.0)
	fighter.state = "ultimate"
	check(id + " secondary motion yields during ultimate", fighter.combat_motion.activity_weight() == 0.0)
	fighter.reset_fighter()
	check(id + " reset clears velocity and action", fighter.velocity.is_zero_approx() and fighter.state == "idle" and fighter.current_clip == "Idle")
	check(id + " reset clears secondary inertia", fighter.combat_motion.lean.is_zero_approx() and fighter.combat_motion.lean_velocity.is_zero_approx())

func shaft_error(fighter: Node3D) -> float:
	if not fighter.is_two_handed():
		return 0.0
	var start: Vector3 = fighter.weapon_mesh.to_global(Vector3.ZERO)
	var end: Vector3 = fighter.weapon_mesh.to_global(Vector3.UP)
	var result = 0.0
	for left in [false, true]:
		var palm: Vector3 = fighter.palm_position(left)
		result = maxf(result, palm.distance_to(Geometry3D.get_closest_point_to_segment(palm, start, end)))
	return result

func rider_activity_checks(fighter: Node3D, label: String) -> void:
	var rig: Skeleton3D = fighter.skeleton
	var was_processing: bool = fighter.is_processing()
	# Retain a deliberately stale nonzero render-time cache while the real
	# physics modifier sees a newly committed action. Do not call the modifier
	# manually or run fighter._process to update its cached activity first.
	fighter.set_process(false)
	for state in ["attack", "ultimate"]:
		fighter.state = state
		fighter.action_time = 0.30
		fighter.attack = {"active": Vector2(0.20, 0.45), "shape": "line", "reach": 3.0}
		fighter.rider_pose._activity_weight = 1.0
		fighter.rider_pose._lean = Vector3(0.050, 0.020, -0.030)
		fighter.rider_pose.last_secondary = Vector3.ONE
		var captured: Array = []
		var first_tick = func():
			captured.append({"secondary": fighter.rider_pose.last_secondary,
				"live_weight": fighter.rider_pose.current_activity_weight(),
				"cached_weight": fighter.rider_pose._activity_weight,
				"physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(),
				"actor_processing": fighter.is_processing()})
		rig.skeleton_updated.connect(first_tick, CONNECT_ONE_SHOT)
		for attempt in 4:
			await frames(1)
			if not captured.is_empty():
				break
		if rig.skeleton_updated.is_connected(first_tick):
			rig.skeleton_updated.disconnect(first_tick)
		check(label + " " + state + " receives first real physics modifier callback", not captured.is_empty())
		if not captured.is_empty():
			var first: Dictionary = captured[0]
			check(label + " " + state + " suppresses rider lean before render refresh",
				Vector3(first.secondary).is_zero_approx() and first.live_weight == 0.0 and
				first.cached_weight == 1.0 and not first.actor_processing, first)
	fighter.set_process(was_processing)
	fighter.reset_fighter()
	fighter.enabled = true
	await frames(3)

func rider_checks(fighter: Node3D, label: String) -> void:
	var rig: Skeleton3D = fighter.skeleton
	var hips = bone(rig, "Hips")
	var spine = bone(rig, "Spine")
	check(label + " real rider skeleton", hips >= 0 and spine >= 0 and is_instance_valid(fighter.rider_pose))
	if hips < 0 or spine < 0:
		return
	var samples: Array = []
	var worst_seat = 0.0
	var worst_grip = 0.0
	var rest = rig.get_bone_global_rest(hips)
	var foot_pairs: Array = []
	for side in ["Left", "Right"]:
		foot_pairs.append([bone(rig, side + "Foot"), bone(rig, side + "ToeBase")])
	var boot_cache: Dictionary = {}
	var boot_metrics = {"rider": 0.0, "horse": 0.0, "process_final": 0.0,
		"rider_samples": 0, "horse_samples": 0, "process_final_samples": 0}
	var measure_boots = func(stage: String):
		if boot_cache.size() != 2:
			return
		for side in 2:
			# Independent expected local contacts came from final modified bones
			# in our rider callback, not the production cache being verified.
			var expected: Vector3 = fighter.model.to_global(boot_cache[side])
			var actual: Vector3 = fighter.horse._stirrup_frames[side].global_position
			boot_metrics[stage] = maxf(float(boot_metrics[stage]), expected.distance_to(actual))
		boot_metrics[stage + "_samples"] = int(boot_metrics[stage + "_samples"]) + 1
	var read_pose = func():
		var hip_pose = rig.get_bone_global_pose(hips)
		var spine_pose = rig.get_bone_global_pose(spine)
		var relative = hip_pose.basis.inverse() * spine_pose.basis
		var seat_height: float = fighter.horse.saddle_height()
		var hip_world_y: float = rig.to_global(hip_pose.origin).y
		for side in 2:
			var foot: Vector3 = rig.to_global(rig.get_bone_global_pose(foot_pairs[side][0]).origin)
			var toe: Vector3 = rig.to_global(rig.get_bone_global_pose(foot_pairs[side][1]).origin)
			var contact = foot.lerp(toe, 0.62) + Vector3.UP * 0.045
			boot_cache[side] = fighter.model.to_local(contact)
		measure_boots.call("rider")
		samples.append({"hip": hip_pose, "spine": relative.get_rotation_quaternion(), "grip": shaft_error(fighter),
			"seat": absf(hip_world_y - (fighter.horse.global_position.y + seat_height)),
			"sample": samples.size(), "physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(),
			"fighter_y": fighter.global_position.y, "model_y": fighter.model.position.y,
			"rider_hip_height": fighter.rider_hip_height, "hip_world_y": hip_world_y,
			"horse_y": fighter.horse.global_position.y, "horse_saddle_height": seat_height,
			"motion_speed": fighter.horse._motion_speed, "mount_speed": fighter.mount_speed,
			"fighter_processing": fighter.is_processing(), "fighter_physics": fighter.is_physics_processing()})
	rig.skeleton_updated.connect(read_pose)
	var horse_rig: Skeleton3D = fighter.horse._skeleton
	var read_horse = func(): measure_boots.call("horse")
	horse_rig.skeleton_updated.connect(read_horse)
	# Real modifier callbacks, real horse clips, real two-hand weapon attachment.
	# The body is parked so a long sample cannot run into the arena boundary.
	fighter.enabled = true
	fighter.set_physics_process(false)
	for index in 150:
		fighter.mount_speed = 4.8
		fighter.mount_turn_rate = sin(float(index) * 0.035) * 1.4
		if index == 45 and "--seat-stress" in OS.get_cmdline_user_args():
			# An isolated 120ms main-thread stall makes the real engine run
			# multiple physics ticks before its next render/process frame.
			# No poses, horse bones or animation clocks are mocked here.
			print("RIDER_SEAT_STRESS ", label, " main_thread_stall_ms=120")
			OS.delay_msec(120)
		await frames(1)
		# SceneTree timers process after the nodes' _process methods. This checks
		# the final render-frame placement without re-reading restored bones.
		await create_timer(0.0).timeout
		measure_boots.call("process_final")
	rig.skeleton_updated.disconnect(read_pose)
	horse_rig.skeleton_updated.disconnect(read_horse)
	rider_samples[label] = samples
	var sample_file = FileAccess.open("res://qa/motion-seat-samples.json", FileAccess.WRITE)
	sample_file.store_string(JSON.stringify(rider_samples, "\t"))
	var angle_span = 0.0
	var max_hip_drift = 0.0
	if not samples.is_empty():
		var first: Quaternion = samples[0].spine
		for sample in samples:
			angle_span = maxf(angle_span, first.angle_to(sample.spine))
			max_hip_drift = maxf(max_hip_drift, Transform3D(sample.hip).origin.distance_to(rest.origin))
			worst_seat = maxf(worst_seat, sample.seat)
			worst_grip = maxf(worst_grip, sample.grip)
	var excessive: Array = []
	for sample in samples:
		if float(sample.seat) >= 0.035:
			excessive.append(sample)
	if not excessive.is_empty():
		print("RIDER_SEAT_DIAGNOSTIC ", label, " total=", samples.size(), " excessive=", excessive.size(),
			" first=", JSON.stringify(excessive.slice(0, 6)), " last=", JSON.stringify(excessive[-1]))
	check(label + " receives live modifier updates", samples.size() > 100, samples.size())
	check(label + " upper body has restrained dynamic movement", angle_span > deg_to_rad(0.4) and angle_span < deg_to_rad(22.0), rad_to_deg(angle_span))
	check(label + " pelvis stays at rig seat", max_hip_drift < 0.001, max_hip_drift)
	check(label + " pelvis follows saddle within 3.5cm", worst_seat < 0.035, worst_seat)
	check(label + " both hands stay on shaft within 3.5cm", worst_grip < 0.035, worst_grip)
	for stage in ["rider", "horse", "process_final"]:
		check(label + " " + stage + " independently samples final boot contacts", int(boot_metrics[stage + "_samples"]) > 100, boot_metrics[stage + "_samples"])
		check(label + " " + stage + " stirrups follow final boots within 3.5cm", float(boot_metrics[stage]) <= 0.035, boot_metrics[stage])
	await rider_activity_checks(fighter, label)
	# Pause freezes horse/rider skeletons and model transforms, not just timers.
	var before_hip = rig.get_bone_global_pose(hips)
	var before_spine = rig.get_bone_global_pose(spine)
	var before_model: Transform3D = fighter.model.transform
	paused = true
	await frames(8)
	check(label + " pause freezes final pose", before_hip.is_equal_approx(rig.get_bone_global_pose(hips)) and before_spine.is_equal_approx(rig.get_bone_global_pose(spine)) and before_model.is_equal_approx(fighter.model.transform))
	paused = false
	fighter.reset_fighter()
	fighter.enabled = false
	await frames(3)
	check(label + " reset stops mounted travel", fighter.mount_speed == 0.0 and fighter.velocity.is_zero_approx())

func texture_count(effects: Node) -> int:
	var total = 0
	for effect in effects.active_effects.values():
		var material: ShaderMaterial = effect.material
		if material.get_shader_parameter("sprite_texture") is Texture2D:
			total += 1
	return total

func effect_checks(effects: Node, fighter: Node3D, label: String) -> void:
	var owner = fighter.get_instance_id()
	var saw_texture = false
	var peak = 0
	for skill in ["rush", "counter", "ultimate"]:
		effects.clear()
		for stage in ["start", "release", "strike", "finish"]:
			effects.play_skill(fighter, skill, stage)
			peak = maxi(peak, effects.active_effect_count())
			saw_texture = saw_texture or texture_count(effects) > 0
			await frames(2)
		check(label + " " + skill + " emits finite live effects", effects.active_effect_count() > 0 and effects.active_effect_count() <= effects.MAX_EFFECTS, effects.active_effect_count())
		var ages: Dictionary = {}
		for id in effects.active_effects:
			ages[id] = float(effects.active_effects[id].age)
		paused = true
		await frames(8)
		var frozen = true
		for id in ages:
			frozen = frozen and effects.active_effects.has(id) and is_equal_approx(ages[id], float(effects.active_effects[id].age))
		check(label + " " + skill + " pause freezes effects", frozen)
		paused = false
		effects.play_skill(fighter, skill, "cancel")
		var owned = 0
		for effect in effects.active_effects.values():
			if int(effect.owner) == owner:
				owned += 1
		check(label + " " + skill + " interruption removes owned layers", owned == 0, owned)
		effects.play_skill(fighter, skill, "start")
		effects.play_skill(fighter, skill, "finish")
		await frames(240)
		check(label + " " + skill + " expires without clear", effects.active_effect_count() == 0, effects.active_effect_count())
	for repeat in 20:
		effects.play_skill(fighter, "ultimate", "start")
		effects.play_skill(fighter, "ultimate", "finish")
		peak = maxi(peak, effects.active_effect_count())
	check(label + " burst effect budget respected", peak <= effects.MAX_EFFECTS, peak)
	check(label + " actually binds licensed sprite textures", saw_texture)
	effects.clear()
	await frames(2)
	check(label + " clear removes all layers", effects.active_effect_count() == 0)

func rpg_checks() -> void:
	game.queue_free()
	await frames(3)
	game = load("res://rpg.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	game.set_physics_process(false)
	game.set_process(false)
	game.phase = "explore"
	game.dialogue.clear()
	game.skill_fx.clear()
	for actor in game.enemies.values():
		actor.enabled = false
		actor.set_physics_process(false)
	game.player.input_move = Vector3.ZERO
	game.player.opponent = null
	check("RPG uses shared fighter implementation", game.player is DuelFighter)
	check("RPG uses upgraded inherited skill effects", game.skill_fx is DuelSkillFX)
	await rider_checks(game.player, "RPG mounted Zhao Yun")
	await effect_checks(game.skill_fx, game.player, "RPG")
	game.player.reset_fighter()
	game.player.enabled = true
	game.player.set_physics_process(true)
	for skill in ["rush", "counter", "ultimate"]:
		game.player.reset_fighter()
		game.player.energy = 100.0
		var accepted: bool = game.player.request_ultimate() if skill == "ultimate" else game.player.request_skill(skill)
		check("RPG actual " + skill + " action accepted", accepted)
		await frames(190)
		check("RPG actual " + skill + " recovers and releases contact", game.player.state == "idle" and not game.player.contact_latched, game.player.state)
	game.skill_fx.clear()

func run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	await frames(5)
	if "--seat-probe" in OS.get_cmdline_user_args():
		await setup_duel("zhaoyun", "mounted")
		await rider_checks(game.player, "Duel mounted Zhao Yun")
		game.queue_free()
		await frames(3)
		game = load("res://rpg.tscn").instantiate()
		root.add_child(game)
		game.testing = true
		game.fx.muted = true
		game.set_physics_process(false)
		game.set_process(false)
		game.phase = "explore"
		game.dialogue.clear()
		for actor in game.enemies.values():
			actor.enabled = false
			actor.set_physics_process(false)
		game.player.input_move = Vector3.ZERO
		game.player.opponent = null
		await rider_checks(game.player, "RPG mounted Zhao Yun")
		print("SEAT_PROBE ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
		quit(0 if failures.is_empty() else 1)
		return
	for id in ["zhaoyun", "machao", "xuchu"]:
		await ground_phase_checks(id)
	await setup_duel("zhaoyun", "mounted")
	await rider_checks(game.player, "Duel mounted Zhao Yun")
	await effect_checks(game.skill_fx, game.player, "Duel")
	await rpg_checks()
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rows": rows}
	var file = FileAccess.open("res://qa/motion-polish-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("POLISH_QA ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
