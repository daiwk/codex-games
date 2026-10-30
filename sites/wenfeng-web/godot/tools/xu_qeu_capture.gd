extends SceneTree
const Observation=preload("res://tools/dao_k_observation.gd")

# Portable QA-only offline capture: the production scene, actors and input controller
# are unchanged. A SubViewport is rendered explicitly; OS focus is irrelevant.
var role = "xuchu"
var enemy_role = "zhaoyun"
var camera_kind = "side"
var seconds = 10.5
var entry_phase = 1
var gap = 6.0
var followup = "release"
var physical_event_count = 0
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
	var hand_transform = Transform3D.IDENTITY
	var all_global: Array=[]
	var all_local: Array=[]
	func _process_modification_with_delta(_delta: float) -> void:
		all_global.clear();all_local.clear()
		for bone in rig.get_bone_count():
			var t=rig.get_bone_global_pose(bone)
			all_global.append([t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z])
			var q=rig.get_bone_pose_rotation(bone);var v=rig.get_bone_pose_position(bone);var scale=rig.get_bone_pose_scale(bone)
			all_local.append({"p":[v.x,v.y,v.z],"q":[q.x,q.y,q.z,q.w],"s":[scale.x,scale.y,scale.z]})
		positions.clear()
		rotations.clear()
		for suffix in ["Hips", "Spine2", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot","RightShoulder","RightUpperArmTwist1","RightUpperArmTwist2","RightUpperArmTwist3"]:
			for index in rig.get_bone_count():
				if rig.get_bone_name(index).ends_with(suffix):
					positions[suffix] = rig.get_bone_global_pose(index).origin
					if suffix == "RightHand": hand_transform = rig.get_bone_global_pose(index)
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
		if arg.begins_with("--enemy="): enemy_role=arg.trim_prefix("--enemy=")
		if arg.begins_with("--camera="): camera_kind = arg.trim_prefix("--camera=")
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--suite="): suite = arg.trim_prefix("--suite=")
		if arg.begins_with("--output-root="): base = arg.trim_prefix("--output-root=")
		if arg.begins_with("--source-commit="): source_commit = arg.trim_prefix("--source-commit=")
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
		if arg.begins_with("--gap="): gap = float(arg.trim_prefix("--gap="))
		if arg.begins_with("--followup="): followup = arg.trim_prefix("--followup=")
		if arg.begins_with("--entry-phase="): entry_phase = clampi(int(arg.trim_prefix("--entry-phase=")),0,3)
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
		"result": result, "hp": actor.hp, "action_time": actor.action_time, "at":p(_at), "attacker_time":actor.opponent.action_time, "attacker_actual_blade":Observation.sample(actor.opponent.weapon_mesh.global_transform) if actor.opponent.character_id=="xuchu" else {}})

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
		actor.set_physics_process(true)
		actor.energy = 100
	game.player.position = Vector3(0, 0.015, -gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, gap * 0.5)
	game.player.rotation.y = 0
	game.enemy.rotation.y = PI
	game.lock_on = true
	game.camera_axis_ready = false
	game.camera_look_ready = false
	if camera_kind == "wrist":
		game.camera_override=true
		game.camera.position=game.player.position+Vector3(2.8,1.65,1.0)
		game.camera.fov=44
		game.camera.look_at(game.player.position+Vector3(.05,1.0,.05),Vector3.UP)
	elif camera_kind == "side":
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
	if suite in ["handoff","hit_after","hit_return","cancel","moving"]:
		if index==0:
			reset_case("handoff_"+suite,gap)
			game.enemy.hp=10000.0
			if suite=="hit_return":game.enemy.wants_block=true
		if index==12:input("skill_rush",true)
		if index==14:input("skill_rush",false)
		if suite=="handoff":
			if index==192:input("ultimate",true)
			if index==194:input("ultimate",false)
		if suite=="hit_after" and index==8:
			events.append({"frame":frame_index,"kind":"enemy_input","action":"heavy","accepted":game.enemy.request_heavy()})
		if suite=="hit_return" and index==54:
			game.enemy.wants_block=false
			events.append({"frame":frame_index,"kind":"enemy_input","action":"heavy_after_guard","accepted":game.enemy.request_heavy()})
		if suite=="cancel" and index==40:
			release_inputs();game.start_match();game.testing=true;game.ai_enabled=false;game.phase="fight"
			events.append({"frame":frame_index,"kind":"explicit_production_match_reset"})
		if suite=="moving":
			if index==70:input("move_up",true)
			if index==150:input("move_up",false)
		if camera_kind=="wrist":
			game.camera_override=true
			game.camera.position=game.player.position+Vector3(-2.15,1.65,1.0)
			game.camera.fov=42
			game.camera.look_at(game.player.position+Vector3(-0.15,1.15,0.05),Vector3.UP)
		return
	if suite=="counter":
		if index==0:reset_case("E_counter_isolated",gap)
		if index==12:input("skill_counter",true)
		if index==14:input("skill_counter",false)
		if index==18:
			var accepted=game.enemy.request_light()
			events.append({"frame":frame_index,"kind":"enemy_input","action":"light","accepted":accepted})
		if camera_kind=="wrist":
			game.camera_override=true
			game.camera.position=game.player.position+Vector3(-2.15,1.65,1.0)
			game.camera.fov=42
			game.camera.look_at(game.player.position+Vector3(-0.15,1.15,0.05),Vector3.UP)
		return
	if index==0:
		reset_case("Q_E_U_continuous",2.3)
		game.enemy.hp=10000.0
		game.player.position=Vector3(0,0.015,-1.15)
		game.enemy.position=Vector3(0,0.015,1.15)
	if index==12:input("skill_rush",true)
	if index==14:input("skill_rush",false)
	if index==192:input("skill_counter",true)
	if index==194:input("skill_counter",false)
	if index==198:
		var accepted=game.enemy.request_light()
		events.append({"frame":frame_index,"kind":"enemy_input","action":"light","accepted":accepted})
	if index==372:input("ultimate",true)
	if index==374:input("ultimate",false)
	if camera_kind=="wrist":
		game.camera_override=true
		game.camera.position=game.player.position+Vector3(-2.15,1.65,1.0)
		game.camera.fov=42
		game.camera.look_at(game.player.position+Vector3(-0.15,1.15,0.05),Vector3.UP)

func matrix(t: Transform3D) -> Array:
	return [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z]

func special_row() -> Dictionary:
	var result=game.specials.debug_state()
	var visuals: Array=[]
	for group in game.specials.groups.values():
		if group.has("blade_visuals"):
			var submitted: Array=[]
			for blade in group.blade_visuals:
				var material=blade.get_active_material(0)
				submitted.append({"matrix":matrix(blade.global_transform),"visible":blade.visible,"visible_in_tree":blade.is_visible_in_tree(),"material_class":material.get_class() if material!=null else "none","transparency":material.transparency if material is BaseMaterial3D else -1,"shading_mode":material.shading_mode if material is BaseMaterial3D else -1,"metallic":material.metallic if material is BaseMaterial3D else -1,"albedo_texture":material.albedo_texture!=null if material is BaseMaterial3D else false,"material_override":blade.material_override!=null,"name":str(blade.get_path())})
			visuals.append({"id":group.id,"type":group.type,"formation":group.formation,"legacy_mm_visible_in_tree":group.visual.is_visible_in_tree(),"physical_blades":submitted,"shape_center":p(group.shape.center),"shape_length":group.shape.length,"materials":group.shape.materials})
			continue
		if not is_instance_valid(group.visual) or not group.visual is MultiMeshInstance3D:continue
		var transforms: Array=[]
		for i in group.entities.size():
			transforms.append(matrix(group.visual.global_transform*group.visual.multimesh.get_instance_transform(i)))
		visuals.append({"id":group.id,"type":group.type,"formation":group.formation,"matrices":transforms,"global":matrix(group.visual.global_transform)})
	result["rendered_visuals"]=visuals
	result["tree_geometry"]=mesh_visibility(game.specials)
	return result

func on_strike(actor: Node, profile: Dictionary) -> void:
	events.append({"frame":frame_index,"stage":stage,"kind":"strike","actor":"player" if actor==game.player else "enemy",
		"physics_frame":Engine.get_physics_frames(),"action_time":actor.action_time,"animation_time":actor.animation_player.current_animation_position,
		"base":p(actor.blade_base()),"tip":p(actor.blade_tip()),"previous_tip":p(actor.previous_tip),"profile":profile.duplicate(true),"hit_landed":actor.hit_landed,"actual_blade":Observation.sample(actor.weapon_mesh.global_transform) if actor.character_id=="xuchu" else {}})

func grasp_row(actor: Node3D, observer: PoseObserver) -> Dictionary:
	if observer.palms.is_empty(): return {}
	var left = actor.skeleton.to_global(observer.palms.left)
	var right = actor.skeleton.to_global(observer.palms.right)
	return {"left_palm": p(left), "right_palm": p(right), "distance": left.distance_to(right),
		"shaft_axis": p((right - left).normalized() * float(actor.grip_config.get("axis_sign", -1.0))),
		"physics_frame": observer.stamp}

func mesh_visibility(node: Node) -> Array:
	var result: Array=[]
	if node is GeometryInstance3D:
		result.append({"path":str(node.get_path()),"visible":node.visible,"visible_in_tree":node.is_visible_in_tree(),"material_override":node.material_override!=null})
	for child in node.get_children():result.append_array(mesh_visibility(child))
	return result

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
	return {"all_source_local":source_observer.all_local.duplicate(true),"all_source_global":source_observer.all_global.duplicate(true),"all_final_local":observer.all_local.duplicate(true),"all_final_global":observer.all_global.duplicate(true),"rig_world":matrix(actor.skeleton.global_transform),"grip_local":matrix(actor.grip.transform),"weapon_local":matrix(actor.weapon_mesh.transform),"socket_local":matrix(actor.grip.get_parent().transform),"held_mesh_visibility":mesh_visibility(actor.weapon_mesh),"body_mesh_visibility":mesh_visibility(actor.model),"counter_primed":actor.skill_counter_primed,"weapon_visible":actor.weapon_mesh.visible,"weapon_thrown":actor.duel_weapon_is_thrown(),"thrust_modifier":is_instance_valid(actor.thrust_contact),"combat_motion_influence":actor.combat_motion.influence,"combat_motion_applied":p(actor.combat_motion.last_applied),"state": actor.state, "clip": actor.current_clip, "combo": actor.combo, "action_time": actor.action_time,
		"animation": String(actor.animation_player.current_animation), "animation_time": actor.animation_player.current_animation_position,
		"position": p(actor.position), "velocity": p(actor.velocity), "yaw": actor.rotation.y,
		"hp": actor.hp, "stamina": actor.stamina, "skill": actor.skill_id, "skill_stage": actor.skill_stage,
		"jump": actor.jump_status(), "source_bones": source_bones, "bones": bones, "screen_bones": screen,
		"source_grasp": grasp_row(actor, source_observers[actor.get_instance_id()]),
		"final_grasp": grasp_row(actor, observer), "final_local_rotations": observer.rotations.duplicate(true), "bone_sample_physics_frame": observer.stamp,
		"blade_base": p(actor.blade_base()), "blade_tip": p(actor.blade_tip()),
		"source_k":actor.source_k_status(), "blade_family":actor.blade_family_status(),
		"grip_quaternion":[actor.grip.quaternion.x,actor.grip.quaternion.y,actor.grip.quaternion.z,actor.grip.quaternion.w],
		"mesh_quaternion":[actor.weapon_mesh.quaternion.x,actor.weapon_mesh.quaternion.y,actor.weapon_mesh.quaternion.z,actor.weapon_mesh.quaternion.w],
		"actual_blade":Observation.sample(actor.weapon_mesh.global_transform) if actor.character_id=="xuchu" else {},
		"tail_actual_blade":Observation.sample(actor.skeleton.global_transform * observer.hand_transform * actor.grip.transform * actor.weapon_mesh.transform) if actor.character_id=="xuchu" else {},
		"tail_blade_base":p(actor.skeleton.global_transform * observer.hand_transform * actor.grip.transform * actor.weapon_mesh.transform * Vector3(0,30,0)) if actor.character_id=="xuchu" else [],
		"tail_blade_tip":p(actor.skeleton.global_transform * observer.hand_transform * actor.grip.transform * actor.weapon_mesh.transform * Vector3(0,99,0)) if actor.character_id=="xuchu" else [],
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
	# QA-only deterministic bridge input: native hardware key events must not
	# enter an offline capture while other apps or tests have keyboard focus.
	# Named Input actions and the production bridge/consumer remain unchanged.
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	game._clear_combat_input()
	driver.game = game
	game.fx.muted = true
	game.testing = true
	game.ai_enabled = false
	game.select_character(role)
	game.select_opponent(enemy_role)
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	game._clear_combat_input()
	for action in InputMap.get_actions():physical_event_count+=InputMap.action_get_events(action).size()
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
		actor.skeleton.move_child(source_observer,0)
		source_observers[actor.get_instance_id()] = source_observer
		var observer = PoseObserver.new()
		observer.rig = actor.skeleton
		observer.actor = actor
		actor.skeleton.add_child(observer)
		observers[actor.get_instance_id()] = observer
		actor.action_started.connect(on_action)
		actor.strike_requested.connect(on_strike)
		actor.impact_received.connect(on_impact)
		actor.skill_triggered.connect(on_skill)
	output = base.path_join(role + "-" + camera_kind + ("-" + suite if suite != "full" else "") + ("-" + tag if tag != "" else "") + "-" + str(seconds) + "s")
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	await frames(20)
	var lead=0
	for index in int(round(seconds * 60)):
		frame_index = index
		schedule(index+lead)
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
		var error = image.save_jpg(output.path_join("frames/%05d.jpg" % index), 0.85)
		if error != OK:
			push_error("Capture failed at frame %d: %s" % [index, error])
			quit(2)
			return
		rows.append({"index": index, "seconds": index / 60.0, "stage": stage, "case_frame": case_frame,
			"physics_frame": Engine.get_physics_frames(), "phase": game.phase, "held": held.duplicate(),
			"player": actor_row(game.player), "enemy": actor_row(game.enemy),
			"camera": {"position": p(game.camera.position), "fov": game.camera.fov},"specials":special_row()})
		case_frame += 1
		if index % 60 == 59: print("CAPTURE ", output, " ", index + 1, "/", seconds * 60)
	release_inputs()
	var bone_names: Array=[]
	for bone in game.player.skeleton.get_bone_count():bone_names.append(game.player.skeleton.get_bone_name(bone))
	var metadata = {"source_commit": source_commit, "physical_input_event_count_after_setup":physical_event_count,"gap":gap,"followup":followup, "role": role,"enemy_role":enemy_role,
		"weapon": game.player.weapon_id, "camera": camera_kind, "fps": 60, "seconds": seconds,"entry_phase":entry_phase,"unrecorded_real_input_frames":lead,"rig_bone_names":bone_names,
		"resolution": [1280,800], "testing": true, "ai": false,"defender_physics":true,"fixture":"Published ddba7a5 production scene plus isolated handoff layer; suite/commands/reset events identify the real-input scenario; enemy HP fixture10000 for repeatable impacts; raw and final observers; no pose injection", "audio": "muted diagnostic",
		"capture": "SubViewport UPDATE_ALWAYS; native --disable-render-loop; force_draw(false,1/60); per-frame JPG, renderer-drawn 16-bit index barcode",
		"input": "production web_bridge dispatch and original main._player_input via QA input driver; finite Run-entry variant identified by tag, no mocked movement or hit resolver",
		"fixture_resets": "Each labeled scenario resets positions/resources visibly; within-stage sequences are uncut. Not a proof of natural transitions between resets.",
		"zhaoyun_glb_sha256": FileAccess.get_sha256("res://assets/characters/zhaoyun.glb"),
		"role_glb_sha256": FileAccess.get_sha256("res://assets/characters/%s.glb" % role),
		"main_sha256": FileAccess.get_sha256("res://scripts/main.gd"), "actor_sha256": FileAccess.get_sha256("res://scripts/duel_actor.gd"),
		"blade_family_glb_sha256":FileAccess.get_sha256("res://assets/motion/xuchu_blade_family.glb"), "blade_family_script_sha256":FileAccess.get_sha256("res://scripts/xu_blade_family.gd"), "specials_script_sha256":FileAccess.get_sha256("res://scripts/duel_specials.gd"), "source_k_glb_sha256":FileAccess.get_sha256("res://assets/motion/xuchu_ual1_k.glb"), "source_k_json_sha256":FileAccess.get_sha256("res://assets/motion/xuchu_ual1_k.json"), "run_entry_sha256":FileAccess.get_sha256("res://scripts/xu_run_entry.gd"), "motion_polish_sha256": FileAccess.get_sha256("res://scripts/duel_motion_polish.gd"), "suite": suite, "variant": tag,
		"bone_sample_point": "Read-only observer at tail of SkeletonModifier3D chain, before Godot restores base animation pose",
		"grip_config": game.player.grip_config,
		"grasp_sample_point": "Source observer directly before contact modifier; final observer at modifier tail. Palms use live hand bone transform times actual rig grip offset, never contact pose cache.",
		"rig_identity":Observation.identity(game.player),"actual_blade_samples":{"edge_vertex_local":[6.4614506,63.640232,-1.0068892],"tip_vertex_local":[-4.470485,100.0,-1.7452493],"edge_direction":"weapon local+X"},"frames": rows, "events": events, "commands": commands}
	FileAccess.open(output.path_join("trace.json"), FileAccess.WRITE).store_string(JSON.stringify(metadata))
	print("CAPTURE_DONE ", output)
	viewport.queue_free()
	await frames(2)
	quit()
