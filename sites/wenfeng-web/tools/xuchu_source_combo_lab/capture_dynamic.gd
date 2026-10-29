extends SceneTree

# Portable QA-only offline capture: the production scene, actors and input controller
# are those of the explicitly prepared isolated experiment. A SubViewport
# is rendered explicitly; OS focus is irrelevant. The source motion was rejected.
var role = "xuchu"
var camera_kind = "side"
var seconds = 27
var suite = "two_dynamic"
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
var source_events: Array=[]
var strike_attempts: Array=[]
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
		"result": result, "hp": actor.hp, "action_time": actor.action_time,"source":game.player.source_combo_status(),"player_stats":dynamic_stats(game.player),"enemy_stats":dynamic_stats(game.enemy)})

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
	dynamic_schedule(index)

func dynamic_stats(actor) -> Dictionary:
	return {"state":actor.state,"action_time":actor.action_time,"action_duration":actor.action_duration,"hp":actor.hp,"stamina":actor.stamina,"energy":actor.energy,"position":p(actor.position),"velocity":p(actor.velocity)}

func on_source(row: Dictionary) -> void:
	var r=row.duplicate(true);r["frame"]=frame_index;r["case_frame"]=case_frame;r["fixture"]=stage;r["player"]=dynamic_stats(game.player);r["enemy"]=dynamic_stats(game.enemy);r["last_melee_hit"]=game.last_melee_hit.duplicate(true);source_events.append(r)

func dynamic_attempt(actor,profile: Dictionary) -> void:
	if actor!=game.player:return
	var lo=game.enemy.thrust_body_low();var hi=game.enemy.thrust_body_high()
	var blade=Geometry3D.get_closest_points_between_segments(actor.blade_base(),actor.blade_tip(),lo,hi)
	var sweep=Geometry3D.get_closest_points_between_segments(actor.previous_tip,actor.blade_tip(),lo,hi)
	strike_attempts.append({"frame":frame_index,"stage":stage,"physics":Engine.get_physics_frames(),"profile":profile.duplicate(true),"distance":minf(blade[0].distance_to(blade[1]),sweep[0].distance_to(sweep[1])),"registered_contact":actor.hit_landed,"player":dynamic_stats(actor),"enemy":dynamic_stats(game.enemy),"blade_base":p(actor.blade_base()),"blade_tip":p(actor.blade_tip()),"previous_tip":p(actor.previous_tip),"body_low":p(lo),"body_high":p(hi),"last_melee_hit":game.last_melee_hit.duplicate(true)})

func dynamic_schedule(index: int) -> void:
	var boundaries=[[0,"J_live_mid",1.7],[120,"JJ_live_mid",1.7],[282,"JJJ_live_mid",1.7],[504,"JJJ_live_edge",2.0],[726,"JJJ_hold",1.15],[948,"JJJ_parry_lift",1.15],[1170,"JJJ_parry_down",1.15],[1392,"JJJ_far",6.0]]
	if suite=="two_dynamic_side":boundaries=[[0,"JJJ_live_mid",1.7],[222,"JJJ_live_far",2.3],[444,"JJJ_hold",1.15],[666,"JJJ_parry_down",1.15]]
	for b in boundaries:
		if index==b[0]:
			reset_case(b[1],b[2]);game.enemy.enabled=true;game.enemy.set_physics_process(true);game.player.energy=0.0;game.enemy.energy=0.0
	game.enemy.wants_block=stage=="JJJ_hold" or (stage=="JJJ_parry_lift" and case_frame>=70) or (stage=="JJJ_parry_down" and (case_frame<86 or case_frame>=94))
	var taps=[6] if stage=="J_live_mid" else ([6,18] if stage=="JJ_live_mid" else [6,18,44])
	if case_frame in taps:input("light",true)
	if case_frame-2 in taps:input("light",false)

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
		"source_combo": actor.source_combo_status(), "contact_active": actor.contact_active, "contact_latched": actor.contact_latched}

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
	bridge = load("res://tools/xuchu_source_combo_lab/native_capture_bridge.gd").new()
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
		actor.source_combo_event.connect(on_source)
		actor.strike_requested.connect(dynamic_attempt)
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
			"camera": {"position": p(game.camera.position), "fov": game.camera.fov},"last_melee_hit":game.last_melee_hit.duplicate(true)})
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
		"defender_physics":suite.begins_with("two_dynamic"), "two_beat_budget":JSON.parse_string(FileAccess.get_file_as_string("res://assets/motion/xuchu_source_combo.json")).get("two_beat_budget",{}), "late_input_policy":JSON.parse_string(FileAccess.get_file_as_string("res://assets/motion/xuchu_source_combo.json"))["late_input"], "source_combo_sha256":FileAccess.get_sha256("res://scripts/xu_source_combo.gd"), "main_sha256": FileAccess.get_sha256("res://scripts/main.gd"), "actor_sha256": FileAccess.get_sha256("res://scripts/duel_actor.gd"),
		"motion_polish_sha256": FileAccess.get_sha256("res://scripts/duel_motion_polish.gd"), "suite": suite, "variant": tag,
		"bone_sample_point": "Read-only observer at tail of SkeletonModifier3D chain, before Godot restores base animation pose",
		"grip_config": game.player.grip_config,
		"grasp_sample_point": "Source observer directly before contact modifier; final observer at modifier tail. Palms use live hand bone transform times actual rig grip offset, never contact pose cache.",
		"frames": rows, "events": events, "source_events":source_events,"strike_attempts":strike_attempts, "commands": commands}
	FileAccess.open(output.path_join("trace.json"), FileAccess.WRITE).store_string(JSON.stringify(metadata))
	print("CAPTURE_DONE ", output)
	viewport.queue_free()
	await frames(2)
	quit()
