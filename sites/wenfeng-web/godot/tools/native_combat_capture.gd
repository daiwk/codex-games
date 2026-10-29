extends SceneTree

# Portable QA-only offline capture: the production scene, actors and input controller
# are unchanged. A SubViewport is rendered explicitly; OS focus is irrelevant.
var role = "xuchu"
var camera_kind = "side"
var seconds = 3
var suite = "full"
var base = ""
var source_commit = ""
var tag = ""
var observers: Dictionary = {}
var source_observers: Dictionary = {}
var game: Node3D
var viewport: SubViewport
var bridge: Node
var driver: InputDriver
var overlay: FrameOverlay
var frame_index = -1
var case_frame = 0
var stage = ""
var rows: Array = []
var events: Array = []
var commands: Array = []
var held: Dictionary = {}
var side_look = Vector3.ZERO
var output = ""

class InputDriver extends Node:
	var game: Node
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(game) and game.phase == "fight" and not game.paused:
			# Same production input consumer. Main's testing flag disables only
			# duplicate polling and wall-clock hit-stop for offline simulation.
			game._player_input()

class PoseObserver extends SkeletonModifier3D:
	var rig: Skeleton3D
	var actor: Node3D
	var palms: Dictionary = {}
	var positions: Dictionary = {}
	var rotations: Dictionary = {}
	var stamp = -1
	func _process_modification_with_delta(_delta: float) -> void:
		positions.clear()
		rotations.clear()
		for suffix in ["Hips", "Spine2", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]:
			for index in rig.get_bone_count():
				if rig.get_bone_name(index).ends_with(suffix):
					positions[suffix] = rig.get_bone_global_pose(index).origin
					var q = rig.get_bone_pose_rotation(index)
					rotations[suffix] = [q.x, q.y, q.z, q.w]
		palms.clear()
		if actor != null and actor.left_hand_index >= 0 and actor.right_hand_index >= 0 and actor.grip_config.has("left_palm"):
			for side in ["left", "right"]:
				var hand = actor.left_hand_index if side == "left" else actor.right_hand_index
				var offset: Array = actor.grip_config[side + "_palm"]
				# Read the live pose here, never palm_position's cached contact pose.
				palms[side] = rig.get_bone_global_pose(hand) * Vector3(offset[0], offset[1], offset[2])
		stamp = Engine.get_physics_frames()

class FrameOverlay extends Control:
	var index = 0
	var caption = ""
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 32), Color(0.01, 0.01, 0.01, 0.94))
		for bit in 16:
			var value = (index >> bit) & 1
			draw_rect(Rect2(8 + bit * 8, 8, 7, 16), Color.WHITE if value else Color.BLACK)
		draw_string(ThemeDB.fallback_font, Vector2(148, 22), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--camera="): camera_kind = arg.trim_prefix("--camera=")
		if arg.begins_with("--seconds="): seconds = int(arg.trim_prefix("--seconds="))
		if arg.begins_with("--suite="): suite = arg.trim_prefix("--suite=")
		if arg.begins_with("--output-root="): base = arg.trim_prefix("--output-root=")
		if arg.begins_with("--source-commit="): source_commit = arg.trim_prefix("--source-commit=")
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	if base.is_empty() or not base.is_absolute_path():
		printerr("Pass --output-root with an absolute writable output directory.")
		quit(2)
		return
	call_deferred("run")

func frames(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame

func p(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func input(action: String, down: bool) -> void:
	bridge._command(["input", action, down])
	held[action] = down
	commands.append({"frame": frame_index, "stage": stage, "case_frame": case_frame,
		"action": action, "pressed": down, "adapter": "production web_bridge._command"})

func release_inputs() -> void:
	for action in held.keys():
		if held[action]: input(action, false)
	held.clear()
	game._clear_combat_input()

func on_action(actor: Node, action: String) -> void:
	events.append({"frame": frame_index, "stage": stage, "kind": "action", "actor": "player" if actor == game.player else "enemy",
		"action": action, "combo": actor.combo, "state": actor.state, "action_time": actor.action_time})

func on_impact(actor: Node, result: String, _at: Vector3) -> void:
	events.append({"frame": frame_index, "stage": stage, "kind": "impact", "actor": "player" if actor == game.player else "enemy",
		"result": result, "hp": actor.hp, "action_time": actor.action_time})

func on_skill(actor: Node, skill: String, phase: String) -> void:
	events.append({"frame": frame_index, "stage": stage, "kind": "skill", "actor": "player" if actor == game.player else "enemy",
		"skill": skill, "phase": phase})

func reset_case(label: String, gap: float) -> void:
	stage = label
	case_frame = 0
	release_inputs()
	game.start_match()
	game.testing = true
	game.phase = "fight"
	game.ai_enabled = false
	for actor in [game.player, game.enemy]:
		actor.enabled = true
		actor.energy = 100
	game.player.position = Vector3(0, 0.015, -gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, gap * 0.5)
	game.player.rotation.y = 0
	game.enemy.rotation.y = PI
	game.lock_on = true
	game.camera_axis_ready = false
	game.camera_look_ready = false
	if camera_kind == "side":
		game.camera_override = true
		game.camera.position = Vector3(7.0, 2.45, 0.0)
		game.camera.fov = 48
		game.camera.look_at(Vector3(0, 1.05, 0), Vector3.UP)
	else:
		game.camera_override = false
		game._update_camera(1.0, true)
	events.append({"frame": frame_index, "kind": "fixture_reset", "stage": stage, "gap": gap,
		"note": "Visible scenario reset and resource refill; not a natural combat transition."})

func schedule(index: int) -> void:
	var boundaries: Array
	if suite == "counter":
		boundaries = [[0, "E_counter", 2.3]]
	elif suite == "contacts":
		boundaries = [[0, "J_air", 6.0], [180, "J_hit", 2.3], [360, "J_close", 1.1], [540, "K", 2.3]]
	elif role == "xuchu":
		boundaries = [[0, "J_air", 5.0], [180, "J_hit", 1.15], [360, "K", 1.4],
			[480, "move_into_J", 3.0], [660, "move_into_K", 3.0],
			[840, "J_exit_move", 1.3], [1020, "K_exit_move", 1.4]]
	else:
		boundaries = [[0, "J_air", 6.0], [180, "J_hit", 2.3], [360, "K", 2.3],
			[480, "move_into_J", 4.0], [600, "move_into_K", 4.0],
			[720, "block", 1.5], [840, "parry", 1.5], [960, "E_counter", 2.3],
			[1080, "dodge", 2.3], [1200, "jump_air_J", 2.3],
			[1380, "Q_rush", 3.0], [1500, "U", 4.2], [1680, "receive_hit", 1.5]]
	for boundary in boundaries:
		if index == int(boundary[0]): reset_case(boundary[1], boundary[2])
	var tick = case_frame
	if stage in ["J_air", "J_hit", "J_close"]:
		if tick in [6, 24, 48]: input("light", true)
		if tick in [8, 26, 50]: input("light", false)
	elif stage == "K":
		if tick == 6: input("heavy", true)
		if tick == 8: input("heavy", false)
	elif stage in ["move_into_J", "move_into_K"]:
		if tick == 6: input("move_up", true)
		if tick == 32: input("light" if stage.ends_with("J") else "heavy", true)
		if tick == 34: input("light" if stage.ends_with("J") else "heavy", false)
		if tick == 42: input("move_up", false)
	elif stage in ["J_exit_move", "K_exit_move"]:
		if tick == 6: input("light" if stage.begins_with("J") else "heavy", true)
		if tick == 8: input("light" if stage.begins_with("J") else "heavy", false)
		if tick == (58 if stage.begins_with("J") else 96): input("move_down", true)
		if tick == 158: input("move_down", false)
	elif stage == "block":
		if tick == 0: input("guard", true)
		if tick == 26: game.enemy.request_light()
		if tick == 82: input("guard", false)
	elif stage == "parry":
		if tick == 6: game.enemy.request_light()
		if tick == 12: input("guard", true)
		if tick == 40: input("guard", false)
	elif stage == "E_counter":
		if tick == 6: input("skill_counter", true)
		if tick == 8: input("skill_counter", false)
		if tick == (0 if suite == "counter" else 12): game.enemy.request_light()
	elif stage == "dodge":
		if tick == 6: input("dodge", true)
		if tick == 8: input("dodge", false)
	elif stage == "jump_air_J":
		if tick == 6: input("jump", true)
		if tick == 8: input("jump", false)
		if tick == 22: input("light", true)
		if tick == 24: input("light", false)
	elif stage == "Q_rush":
		if tick == 6: input("skill_rush", true)
		if tick == 8: input("skill_rush", false)
	elif stage == "U":
		if tick == 6: input("ultimate", true)
		if tick == 8: input("ultimate", false)
	elif stage == "receive_hit":
		if tick == 6: game.enemy.request_heavy()

func grasp_row(actor: Node3D, observer: PoseObserver) -> Dictionary:
	if observer.palms.is_empty(): return {}
	var left = actor.skeleton.to_global(observer.palms.left)
	var right = actor.skeleton.to_global(observer.palms.right)
	return {"left_palm": p(left), "right_palm": p(right), "distance": left.distance_to(right),
		"shaft_axis": p((right - left).normalized() * float(actor.grip_config.get("axis_sign", -1.0))),
		"physics_frame": observer.stamp}

func actor_row(actor: Node3D) -> Dictionary:
	var observer: PoseObserver = observers[actor.get_instance_id()]
	var bones: Dictionary = {}
	var source_bones: Dictionary = {}
	var source_observer: PoseObserver = source_observers[actor.get_instance_id()]
	for name in source_observer.positions:
		source_bones[name] = p(actor.skeleton.to_global(source_observer.positions[name]))
	for name in observer.positions:
		bones[name] = p(actor.skeleton.to_global(observer.positions[name]))
	var screen: Dictionary = {}
	for name in bones:
		var q: Array = bones[name]
		var at = game.camera.unproject_position(Vector3(q[0], q[1], q[2]))
		screen[name] = [at.x, at.y]
	return {"state": actor.state, "clip": actor.current_clip, "combo": actor.combo, "action_time": actor.action_time,
		"animation": String(actor.animation_player.current_animation), "animation_time": actor.animation_player.current_animation_position,
		"position": p(actor.position), "velocity": p(actor.velocity), "yaw": actor.rotation.y,
		"hp": actor.hp, "stamina": actor.stamina, "skill": actor.skill_id, "skill_stage": actor.skill_stage,
		"jump": actor.jump_status(), "source_bones": source_bones, "bones": bones, "screen_bones": screen,
		"source_grasp": grasp_row(actor, source_observers[actor.get_instance_id()]),
		"final_grasp": grasp_row(actor, observer), "final_local_rotations": observer.rotations.duplicate(true), "bone_sample_physics_frame": observer.stamp,
		"blade_base": p(actor.blade_base()), "blade_tip": p(actor.blade_tip()),
		"contact_active": actor.contact_active, "contact_latched": actor.contact_latched}

func run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1
	root.size = Vector2i(640, 400)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	root.add_child(viewport)
	driver = InputDriver.new()
	viewport.add_child(driver)
	game = load("res://main.tscn").instantiate()
	viewport.add_child(game)
	driver.game = game
	game.fx.muted = true
	game.testing = true
	game.ai_enabled = false
	game.select_character(role)
	game.select_opponent("zhaoyun" if role != "zhaoyun" else "machao")
	bridge = load("res://tools/native_capture_bridge.gd").new()
	bridge.game = game
	viewport.add_child(bridge)
	var layer = CanvasLayer.new()
	layer.layer = 100
	viewport.add_child(layer)
	overlay = FrameOverlay.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	for actor in [game.player, game.enemy]:
		var source_observer = PoseObserver.new()
		source_observer.rig = actor.skeleton
		source_observer.actor = actor
		actor.skeleton.add_child(source_observer)
		if is_instance_valid(actor.thrust_contact):
			actor.skeleton.move_child(source_observer, actor.thrust_contact.get_index())
		source_observers[actor.get_instance_id()] = source_observer
		var observer = PoseObserver.new()
		observer.rig = actor.skeleton
		observer.actor = actor
		actor.skeleton.add_child(observer)
		observers[actor.get_instance_id()] = observer
		actor.action_started.connect(on_action)
		actor.impact_received.connect(on_impact)
		actor.skill_triggered.connect(on_skill)
	output = base.path_join(role + "-" + camera_kind + ("-" + suite if suite != "full" else "") + ("-" + tag if tag != "" else "") + "-" + str(seconds) + "s")
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	await frames(20)
	for index in seconds * 60:
		frame_index = index
		schedule(index)
		overlay.index = index
		overlay.caption = "F%04d %.3fs %s/%s %s%s  OFFLINE DIAGNOSTIC - NOT REALTIME FPS" % [index, index / 60.0, role, camera_kind, stage, " [FIXTURE RESET]" if case_frame < 4 else ""]
		overlay.queue_redraw()
		await physics_frame
		await process_frame
		# SceneTree timers run after all nodes' process callbacks, so animation,
		# visual modifiers and camera have reached this frame's final state.
		await create_timer(0.0, true, false).timeout
		RenderingServer.force_draw(false, 1.0 / 60.0)
		var image = viewport.get_texture().get_image()
		var error = image.save_jpg(output.path_join("frames/%05d.jpg" % index), 0.95)
		if error != OK:
			push_error("Capture failed at frame %d: %s" % [index, error])
			quit(2)
			return
		rows.append({"index": index, "seconds": index / 60.0, "stage": stage, "case_frame": case_frame,
			"physics_frame": Engine.get_physics_frames(), "phase": game.phase, "held": held.duplicate(),
			"player": actor_row(game.player), "enemy": actor_row(game.enemy),
			"camera": {"position": p(game.camera.position), "fov": game.camera.fov}})
		case_frame += 1
		if index % 60 == 59: print("CAPTURE ", output, " ", index + 1, "/", seconds * 60)
	release_inputs()
	var metadata = {"source_commit": source_commit, "role": role,
		"weapon": game.player.weapon_id, "camera": camera_kind, "fps": 60, "seconds": seconds,
		"resolution": [1280,800], "testing": true, "ai": false, "audio": "muted diagnostic",
		"capture": "SubViewport UPDATE_ALWAYS; native --disable-render-loop; force_draw(false,1/60); per-frame JPG, renderer-drawn 16-bit index barcode",
		"input": "production web_bridge dispatch and original main._player_input via QA input driver; no movement/combat functions replaced",
		"fixture_resets": "Each labeled scenario resets positions/resources visibly; within-stage sequences are uncut. Not a proof of natural transitions between resets.",
		"zhaoyun_glb_sha256": FileAccess.get_sha256("res://assets/characters/zhaoyun.glb"),
		"role_glb_sha256": FileAccess.get_sha256("res://assets/characters/%s.glb" % role),
		"main_sha256": FileAccess.get_sha256("res://scripts/main.gd"), "actor_sha256": FileAccess.get_sha256("res://scripts/duel_actor.gd"),
		"motion_polish_sha256": FileAccess.get_sha256("res://scripts/duel_motion_polish.gd"), "suite": suite, "variant": tag,
		"bone_sample_point": "Read-only observer at tail of SkeletonModifier3D chain, before Godot restores base animation pose",
		"grip_config": game.player.grip_config,
		"grasp_sample_point": "Source observer directly before contact modifier; final observer at modifier tail. Palms use live hand bone transform times actual rig grip offset, never contact pose cache.",
		"frames": rows, "events": events, "commands": commands}
	FileAccess.open(output.path_join("trace.json"), FileAccess.WRITE).store_string(JSON.stringify(metadata))
	print("CAPTURE_DONE ", output)
	viewport.queue_free()
	await frames(2)
	quit()
