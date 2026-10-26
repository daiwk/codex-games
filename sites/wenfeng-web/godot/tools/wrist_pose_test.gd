extends SceneTree

# Measures the final skinned skeleton, independently from WristSolver. Palm
# proximity alone cannot detect a corkscrewed wrist or collapsed blend region.
# Run: Godot --headless --path . --script res://tools/wrist_pose_test.gd
var game: Node3D
var checks = 0
var failures: Array[String] = []
var rows: Array = []
var observing = false
var arm_frames: Array[Dictionary] = []
var skin_regions: Array[Dictionary] = []
var metrics: Dictionary = {}
var context = ""
var previous_pose: Dictionary = {}
var loop_observing = false
var loop_offset = 0.0
var loop_last_position = -1.0
var final_palms: Dictionary = {}
var action_clock: Dictionary = {}

func _initialize() -> void:
	process_frame.connect(schedule_drawn_grip)
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks += 1
	rows.append({"name": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label, " ", detail if detail != null else "")
	if not passed:
		failures.append(label)

func write_report(completed: bool) -> void:
	DirAccess.make_dir_recursive_absolute("res://qa/wrists")
	var file = FileAccess.open("res://qa/wrists/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed": completed, "passed": completed and failures.is_empty(),
		"checks": checks, "failures": failures, "results": rows}, "\t"))

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func bone(rig: Skeleton3D, suffix: String) -> int:
	for index in rig.get_bone_count():
		if rig.get_bone_name(index).ends_with(suffix):
			return index
	return -1

func skinned_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.skin != null:
		found.append(node)
	for child in node.get_children():
		found.append_array(skinned_meshes(child))
	return found

func blended_basis(values: Dictionary, joints: Array, weights: Array) -> Basis:
	var x = Vector3.ZERO
	var y = Vector3.ZERO
	var z = Vector3.ZERO
	for index in joints.size():
		var basis: Basis = values[joints[index]]
		x += basis.x * float(weights[index])
		y += basis.y * float(weights[index])
		z += basis.z * float(weights[index])
	return Basis(x, y, z)

func prepare_skin_regions(fighter: Node3D) -> void:
	skin_regions.clear()
	for mesh in skinned_meshes(fighter.model):
		var mapped: Dictionary = {}
		var rest: Dictionary = {}
		for bind in mesh.skin.get_bind_count():
			var index: int = mesh.skin.get_bind_bone(bind)
			if index < 0:
				index = fighter.skeleton.find_bone(mesh.skin.get_bind_name(bind))
			if index >= 0:
				mapped[bind] = index
				rest[bind] = fighter.skeleton.get_bone_global_rest(index).basis * mesh.skin.get_bind_pose(bind).basis
		var samples: Array = []
		for surface in mesh.mesh.get_surface_count():
			var arrays = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or joints.is_empty():
				continue
			var stride = joints.size() / vertices.size()
			for vertex in vertices.size():
				var ids: Array = []
				var amounts: Array = []
				var relevant = false
				var forearm_weights = {"Left": 0.0, "Right": 0.0}
				var hand_weights = {"Left": 0.0, "Right": 0.0}
				for offset in stride:
					var bind: int = joints[vertex * stride + offset]
					var weight: float = weights[vertex * stride + offset]
					if weight <= 0.0001 or not mapped.has(bind):
						continue
					ids.append(bind)
					amounts.append(weight)
					var name = fighter.skeleton.get_bone_name(mapped[bind])
					for side in ["Left", "Right"]:
						if name.ends_with(side + "ForeArm"):
							forearm_weights[side] += weight
						if name.ends_with(side + "Hand"):
							hand_weights[side] += weight
				for side in (["Left", "Right"] if fighter.is_two_handed() else ["Right"]):
					if forearm_weights[side] >= 0.08 and hand_weights[side] >= 0.08 and forearm_weights[side] + hand_weights[side] >= 0.65:
						relevant = true
				if relevant:
					var determinant = absf(blended_basis(rest, ids, amounts).determinant())
					if determinant > 0.0001:
						samples.append({"joints": ids, "weights": amounts, "rest_det": determinant})
		if not samples.is_empty():
			skin_regions.append({"mesh": mesh, "mapped": mapped, "samples": samples})

func prepare(fighter: Node3D) -> void:
	arm_frames.clear()
	for side in (["Left", "Right"] if fighter.is_two_handed() else ["Right"]):
		var upper = bone(fighter.skeleton, side + "Arm")
		var forearm = bone(fighter.skeleton, side + "ForeArm")
		var hand = bone(fighter.skeleton, side + "Hand")
		var rest: Transform3D = fighter.skeleton.get_bone_rest(hand)
		var direction = rest.origin.normalized()
		var local_forward = rest.basis.inverse() * direction
		# A neutral transverse palm axis is chosen geometrically, then compared
		# after removing the minimal forearm-to-hand swing. This does not call
		# the production solver's quaternion decomposition or its measure API.
		var local_side = Vector3.RIGHT
		if absf(local_side.dot(local_forward)) > 0.8:
			local_side = Vector3.UP
		local_side = (local_side - local_forward * local_side.dot(local_forward)).normalized()
		arm_frames.append({"side": side, "upper": upper, "forearm": forearm, "hand": hand,
			"rest": rest, "local_forward": local_forward, "local_side": local_side,
			"forearm_length": rest.origin.length()})
	prepare_skin_regions(fighter)

func reset_metrics() -> void:
	previous_pose.clear()
	action_clock.clear()
	metrics = {"Left_roll_rate": 0.0, "Right_roll_rate": 0.0, "Left_wrist_rate": 0.0, "Right_wrist_rate": 0.0,
		"Left_world_forearm_rate": 0.0, "Right_world_forearm_rate": 0.0, "Left_world_hand_rate": 0.0, "Right_world_hand_rate": 0.0,
		"worst": {}, "samples": 0, "Left_swing": 0.0, "Right_swing": 0.0,
		"Left_twist": 0.0, "Right_twist": 0.0, "length_error": 0.0,
		"grip": 0.0, "grip_samples": 0, "skin_volume": 1.0, "skin_samples": 0, "finite": true, "loop_wraps": 0}

func peak(key: String, value: float) -> void:
	if value > float(metrics[key]):
		metrics[key] = value
		metrics.worst[key] = {"action_time": game.player.action_time, "clip": game.player.current_clip,
			"physics_frame": Engine.get_physics_frames(), "animation_time": game.player.animation_player.current_animation_position, "contact_retraction": game.player.contact_retraction,
			"degrees": rad_to_deg(value)}

func observe() -> void:
	if not observing:
		return
	var fighter = game.player
	metrics.samples += 1
	var sample_clock: float = fighter.action_time
	if loop_observing:
		var position: float = fighter.animation_player.current_animation_position
		var length: float = fighter.animation_player.current_animation_length
		if loop_last_position >= 0.0 and position < loop_last_position - length * 0.5:
			loop_offset += length
			metrics.loop_wraps += 1
		loop_last_position = position
		sample_clock = loop_offset + position
	else:
		# action_time returns to zero when recovery finishes, while the real
		# AnimationPlayer is still blending into Idle. Keep that boundary in
		# the continuity test instead of silently dropping its negative delta.
		# Within an action use the actor's actual clock; after reset, bridge
		# with the real physics delta. Repeated skeleton signals in one tick
		# never advance this clock or turn a render callback into fake time.
		var physics_frame: int = Engine.get_physics_frames()
		if not action_clock.is_empty():
			var advance: float = maxf(0.0, fighter.action_time - float(action_clock.action))
			if fighter.action_time < float(action_clock.action) - 0.00001 or fighter.state in ["idle", "move", "block"]:
				advance = maxf(0.0, float(physics_frame - int(action_clock.frame)) * fighter.get_physics_process_delta_time())
			sample_clock = float(action_clock.clock) + advance
		action_clock = {"action": fighter.action_time, "frame": physics_frame, "clock": sample_clock}
	for arm in arm_frames:
		var lower: Transform3D = fighter.skeleton.get_bone_global_pose(arm.forearm)
		var hand: Transform3D = fighter.skeleton.get_bone_global_pose(arm.hand)
		var axis = (hand.origin - lower.origin).normalized()
		var hand_forward = (hand.basis * Vector3(arm.local_forward)).normalized()
		var swing = acos(clampf(axis.dot(hand_forward), -1.0, 1.0))
		var align = Basis(Quaternion(axis, hand_forward))
		var neutral_side = (lower.basis * Transform3D(arm.rest).basis * Vector3(arm.local_side)).normalized()
		var current_side = (align.inverse() * hand.basis * Vector3(arm.local_side)).normalized()
		neutral_side = (neutral_side - axis * neutral_side.dot(axis)).normalized()
		current_side = (current_side - axis * current_side.dot(axis)).normalized()
		var twist = absf(neutral_side.signed_angle_to(current_side, axis))
		var side: String = arm.side
		peak(side + "_swing", swing)
		peak(side + "_twist", twist)
		var upper_basis: Basis = fighter.skeleton.get_bone_global_pose(arm.upper).basis
		var relative_forearm = upper_basis.inverse() * lower.basis
		var relative_axis = (upper_basis.inverse() * axis).normalized()
		var moment: float = sample_clock
		if previous_pose.has(side):
			var prior: Dictionary = previous_pose[side]
			var dt: float = moment - float(prior.time)
			if dt > 0.00001:
				# Actual model-space bone orientations describe visible motion.
				# Relative counter-rotation can be faster while cancelling its
				# parent's turn; keep those local rates as separate diagnostics.
				peak(side + "_world_forearm_rate", Basis(prior.world_forearm).get_rotation_quaternion().angle_to(lower.basis.get_rotation_quaternion()) / dt)
				peak(side + "_world_hand_rate", Basis(prior.world_hand).get_rotation_quaternion().angle_to(hand.basis.get_rotation_quaternion()) / dt)
				# Parallel transport removes normal arm swing. Only unexplained
				# longitudinal roll remains, exposing alternate elbow-circle flips.
				var transport = Basis(Quaternion(Vector3(prior.axis), relative_axis))
				var old_side = transport * Basis(prior.forearm).x
				var new_side = relative_forearm.x
				if absf(new_side.normalized().dot(relative_axis)) > 0.85:
					old_side = transport * Basis(prior.forearm).z
					new_side = relative_forearm.z
				old_side = (old_side - relative_axis * old_side.dot(relative_axis)).normalized()
				new_side = (new_side - relative_axis * new_side.dot(relative_axis)).normalized()
				var roll_rate = absf(old_side.signed_angle_to(new_side, relative_axis)) / dt
				var local_wrist = lower.basis.inverse() * hand.basis
				var wrist_rate = Basis(prior.wrist).get_rotation_quaternion().angle_to(local_wrist.get_rotation_quaternion()) / dt
				peak(side + "_roll_rate", roll_rate)
				peak(side + "_wrist_rate", wrist_rate)
		previous_pose[side] = {"axis": relative_axis, "forearm": relative_forearm, "wrist": lower.basis.inverse() * hand.basis,
			"world_forearm": lower.basis, "world_hand": hand.basis, "time": moment}
		metrics.length_error = maxf(float(metrics.length_error), absf(hand.origin.distance_to(lower.origin) - float(arm.forearm_length)))
		if not is_finite(swing) or not is_finite(twist):
			metrics.finite = false
		var palm_values: Array = fighter.grip_config.left_palm if side == "Left" else fighter.grip_config.right_palm
		# Capture the real final skin pose before Godot restores modifier inputs.
		# Draw-time attachments are checked after all Node._process callbacks.
		final_palms[side] = hand * Vector3(palm_values[0], palm_values[1], palm_values[2])

	# Sample the actual skin transform blend at the wrist seam. A low relative
	# determinant indicates volume collapse even when the palm centre is fixed.
	for region in skin_regions:
		var bases: Dictionary = {}
		for bind in region.mapped:
			bases[bind] = fighter.skeleton.get_bone_global_pose(region.mapped[bind]).basis * region.mesh.skin.get_bind_pose(bind).basis
		for sample in region.samples:
			var volume = absf(blended_basis(bases, sample.joints, sample.weights).determinant()) / float(sample.rest_det)
			metrics.skin_volume = minf(float(metrics.skin_volume), volume)
			metrics.skin_samples += 1

func schedule_drawn_grip() -> void:
	if observing and is_instance_valid(game):
		create_timer(0.0, true).timeout.connect(check_drawn_grip, CONNECT_ONE_SHOT)

func check_drawn_grip() -> void:
	if not observing or not is_instance_valid(game):
		return
	var fighter = game.player
	var shaft_start: Vector3 = fighter.weapon_mesh.to_global(Vector3.ZERO)
	var shaft_end: Vector3 = fighter.weapon_mesh.to_global(Vector3.UP)
	if not fighter.is_two_handed():
		var axis = fighter.weapon_mesh.global_basis.y.normalized()
		shaft_start -= axis * 2.0
		shaft_end = fighter.weapon_mesh.global_position + axis * 2.0
	for side in final_palms:
		var actual_palm: Vector3 = fighter.skeleton.to_global(final_palms[side])
		metrics.grip = maxf(float(metrics.grip), actual_palm.distance_to(Geometry3D.get_closest_point_to_segment(actual_palm, shaft_start, shaft_end)))
		metrics.grip_samples += 1

func setup(role: String, mode: String, gap: float) -> void:
	observing = false
	final_palms.clear()
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(role)
	game.select_opponent("zhaoyun")
	await frames(4)
	game.start_match()
	game.phase = "fight"
	game.ai_enabled = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, 0)
	game.enemy.position = Vector3(0, 0.015, gap)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	prepare(game.player)
	game.player.skeleton.skeleton_updated.connect(observe)
	await frames(4)

func exercise(role: String, mode: String, action: String, gap: float) -> void:
	await setup(role, mode, gap)
	context = "%s/%s/%s/%0.2fm" % [role, mode, action, gap]
	reset_metrics()
	loop_observing = false
	observing = true
	var accepted = false
	match action:
		"J": accepted = game.player.request_light()
		"K": accepted = game.player.request_heavy()
		"ultimate":
			game.player.energy = 100.0
			accepted = game.player.request_ultimate()
		_: accepted = game.player.request_skill(action)
	var completed = false
	var last_action_time = 0.0
	for index in 2000:
		await physics_frame
		last_action_time = maxf(last_action_time, game.player.action_time)
		if game.player.state in ["idle", "move", "block"] and index > 2:
			completed = true
			break
	if completed:
		# Include the real blend back into Idle rather than stopping at the
		# state-machine boundary while the arm is still settling.
		await frames(ceili(Engine.physics_ticks_per_second * 0.20))
	observing = false
	check(context + " full actual animation sampled", accepted and completed and metrics.samples >= 6 and metrics.finite,
		{"samples": metrics.samples, "completed": completed, "last_action_time": last_action_time})
	for side in (["Left", "Right"] if game.player.is_two_handed() else ["Right"]):
		check(context + " " + side + " wrist bend <=40deg", float(metrics[side + "_swing"]) <= deg_to_rad(40.0) + 0.002,
			rad_to_deg(float(metrics[side + "_swing"])))
		check(context + " " + side + " residual wrist roll <=35deg", float(metrics[side + "_twist"]) <= deg_to_rad(35.0) + 0.002,
			rad_to_deg(float(metrics[side + "_twist"])))
		check(context + " " + side + " actual forearm orientation changes continuously", float(metrics[side + "_world_forearm_rate"]) <= deg_to_rad(900.0),
			metrics.worst.get(side + "_world_forearm_rate", {}))
		check(context + " " + side + " actual hand orientation changes continuously", float(metrics[side + "_world_hand_rate"]) <= deg_to_rad(900.0),
			metrics.worst.get(side + "_world_hand_rate", {}))
	check(context + " forearm bone length preserved", metrics.length_error < 0.002, metrics.length_error)
	check(context + (" both actual palms" if game.player.is_two_handed() else " actual right palm") + " stay on physical handle <=3.5cm", metrics.grip_samples > 0 and metrics.grip < 0.035, {"error": metrics.grip, "draw_samples": metrics.grip_samples})
	check(context + " actual wrist skin blend retains volume", metrics.skin_samples > 0 and metrics.skin_volume >= 0.65,
		{"relative_volume": metrics.skin_volume, "vertex_frames": metrics.skin_samples})
	rows.append({"case": context, "metrics": metrics.duplicate(true)})
	write_report(false)
	game.player.skeleton.skeleton_updated.disconnect(observe)

func loop_case(role: String, clip: String) -> void:
	await setup(role, "foot", 14.0)
	context = role + "/loop/" + clip
	# Isolate the real AnimationPlayer loop from locomotion choosing a different
	# gait. No animation seek, bone pose override or copied wrist result is used.
	game.player.enabled = false
	game.player.set_physics_process(false)
	reset_metrics()
	loop_observing = true
	loop_offset = 0.0
	loop_last_position = -1.0
	game.player.play_clip(clip, 0.0)
	var length: float = game.player.animation_player.get_animation(game.player.animation_names[clip]).length
	observing = true
	await frames(ceili(length * 2.35 * Engine.physics_ticks_per_second))
	observing = false
	loop_observing = false
	check(context + " actual last-to-first seam crossed twice", metrics.loop_wraps >= 2 and metrics.samples > 30 and metrics.finite,
		{"wraps": metrics.loop_wraps, "samples": metrics.samples})
	for side in (["Left", "Right"] if game.player.is_two_handed() else ["Right"]):
		check(context + " " + side + " loop wrist bend <=40deg", float(metrics[side + "_swing"]) <= deg_to_rad(40.0) + 0.002,
			rad_to_deg(float(metrics[side + "_swing"])))
		check(context + " " + side + " loop residual roll <=35deg", float(metrics[side + "_twist"]) <= deg_to_rad(35.0) + 0.002,
			rad_to_deg(float(metrics[side + "_twist"])))
		check(context + " " + side + " actual forearm orientation continuous through seam", float(metrics[side + "_world_forearm_rate"]) <= deg_to_rad(900.0),
			metrics.worst.get(side + "_world_forearm_rate", {}))
		check(context + " " + side + " actual hand orientation continuous through seam", float(metrics[side + "_world_hand_rate"]) <= deg_to_rad(900.0),
			metrics.worst.get(side + "_world_hand_rate", {}))
	check(context + " actual wrist skin retains loop-seam volume", metrics.skin_samples > 0 and metrics.skin_volume >= 0.65,
		{"relative_volume": metrics.skin_volume, "vertex_frames": metrics.skin_samples})
	rows.append({"case": context, "metrics": metrics.duplicate(true)})
	write_report(false)
	game.player.skeleton.skeleton_updated.disconnect(observe)
	game.player.set_physics_process(true)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	await frames(4)
	var selected_roles = ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu", "xuchu"]
	# Xu Chu's held right wrist uses the same seam test; his free left hand is
	# not subjected to a two-handed shaft criterion or a rigid gripping pose.
	if "--zhao-only" in OS.get_cmdline_user_args():
		selected_roles = ["zhaoyun"]
	for role in selected_roles:
		for clip in ["Idle", "Walk", "WalkBack", "StrafeLeft", "StrafeRight", "Run", "TurnLeft", "TurnRight"]:
			await loop_case(role, clip)
		for mode in ["foot", "mounted"]:
			for action in ["J", "K", "rush", "counter", "ultimate"]:
				await exercise(role, mode, action, 14.0)
			for action in ["J", "K", "rush", "ultimate"]:
				await exercise(role, mode, action, 1.24)
	write_report(true)
	game._reset_hit_feedback()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("WRIST_POSE_QA=", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
