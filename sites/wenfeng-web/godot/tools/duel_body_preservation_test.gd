extends "res://tools/duel_wrist_focused_test.gd"

## Compare AnimationPlayer's body with the final skinned output in the same
## modifier tick. A hand/shaft correction must not rewind hips or leg motion
## while CharacterBody keeps advancing along the authored attack step.
class PoseProbe extends SkeletonModifier3D:
	var callback: Callable
	func _process_modification_with_delta(_delta: float) -> void:
		callback.call()

const BODY = ["Hips", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg",
	"LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
var source_body: Dictionary = {}
var body_peak: Dictionary = {}
var body_cases: Array = []
var body_samples = 0
var penetration = 0.0

func record_source() -> void:
	if not observing: return
	source_body.clear()
	for suffix in BODY:
		var index = bone(game.player.skeleton, suffix)
		source_body[index] = {"rotation": game.player.skeleton.get_bone_pose_rotation(index),
			"position": game.player.skeleton.get_bone_pose_position(index)}

func record_final() -> void:
	if not observing or source_body.is_empty(): return
	body_samples += 1
	var rig: Skeleton3D = game.player.skeleton
	for index in source_body:
		# acos(dot(q,q)) reports a spurious ~0.001rad for identical imported
		# float quaternions. The relative quaternion retains a stable zero.
		var relative: Quaternion = source_body[index].rotation.inverse() * rig.get_bone_pose_rotation(index)
		var changed = 2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w))
		var shifted = float(source_body[index].position.distance_to(rig.get_bone_pose_position(index)))
		if changed > float(body_peak.rotation) or shifted > float(body_peak.position):
			body_peak["worst"] = {"bone": rig.get_bone_name(index), "clip": game.player.current_clip,
				"action_time": game.player.action_time, "state": game.player.state,
				"frame": Engine.get_physics_frames()}
		body_peak.rotation = maxf(float(body_peak.rotation), changed)
		body_peak.position = maxf(float(body_peak.position), shifted)
	if game.player.is_physical_thrust():
		var palms: Array[Vector3] = []
		for side in ["right", "left"]:
			var hand = game.player.right_hand_index if side == "right" else game.player.left_hand_index
			var offset: Array = game.player.grip_config[side + "_palm"]
			palms.append(rig.to_global(rig.get_bone_global_pose(hand) * Vector3(offset[0], offset[1], offset[2])))
		var axis = (palms[0] - palms[1]).normalized() * float(game.player.grip_config.axis_sign)
		var length_m = float(game.player.grip_config.weapon_length) * (0.99 - float(game.player.grip_config.grip_fraction))
		var closest = Geometry3D.get_closest_points_between_segments(palms[0], palms[0] + axis * length_m,
			game.enemy.thrust_body_low(), game.enemy.thrust_body_high())
		penetration = maxf(penetration, float(game.enemy.thrust_body_radius()) - closest[0].distance_to(closest[1]))

func body_case(role: String, gap: float, action: String) -> void:
	await setup(role, "foot", gap)
	context = "%s/%0.1fm/%s" % [role, gap, action]
	var before = PoseProbe.new()
	before.callback = record_source
	game.player.skeleton.add_child(before)
	game.player.skeleton.move_child(before, 0)
	var after = PoseProbe.new()
	after.callback = record_final
	game.player.skeleton.add_child(after)
	body_peak = {"rotation": 0.0, "position": 0.0, "worst": {}}
	body_samples = 0
	penetration = 0.0
	reset_metrics()
	observing = true
	var accepted = game.player.request_heavy() if action == "heavy" else game.player.request_light()
	var completed = false
	for frame in 360:
		await physics_frame
		if action == "combo" and game.player.state == "attack" and game.player.combo < 2 and not game.player.combo_buffered:
			game.player.request_light()
		if frame > 8 and game.player.state in ["idle", "move", "block"]:
			completed = true
			await frames(24)
			break
	observing = false
	hard(context + " complete actual attack and recovery", accepted and completed and body_samples > 12, body_samples)
	hard(context + " original pelvis and legs retained", float(body_peak.rotation) < 0.0005 and float(body_peak.position) < 0.00001, body_peak)
	for side in ["Left", "Right"]:
		hard(context + " " + side + " anatomical wrist", float(metrics[side + "_swing"]) <= deg_to_rad(40.0) + 0.002 and float(metrics[side + "_twist"]) <= deg_to_rad(35.0) + 0.002,
			{"swing_degrees": rad_to_deg(metrics[side + "_swing"]), "twist_degrees": rad_to_deg(metrics[side + "_twist"])})
	hard(context + " real bone lengths retained", metrics.length_error < 0.002, metrics.length_error)
	hard(context + " rendered palms remain on shaft", metrics.grip_samples > 0 and metrics.grip < 0.035, metrics.grip)
	hard(context + " physical shaft clears opponent", penetration < 0.02, penetration)
	if gap == 2.3: hard(context + " contact still deals damage", game.enemy.hp < 120.0, 120.0 - game.enemy.hp)
	if gap == 6.0: hard(context + " whiff remains harmless", game.enemy.hp == 120.0, game.enemy.hp)
	body_cases.append({"case": context, "body": body_peak.duplicate(true), "samples": body_samples,
		"penetration": penetration, "metrics": metrics.duplicate(true), "damage": 120.0 - game.enemy.hp})
	game.player.skeleton.skeleton_updated.disconnect(observe)

func run() -> void:
	Engine.physics_ticks_per_second = 60
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	await frames(5)
	for role in ["zhaoyun", "machao"]:
		for gap in [6.0, 2.3, 1.1]:
			for action in ["combo", "heavy"]:
				await body_case(role, gap, action)
	FileAccess.open("/private/tmp/wenfeng-duel-body-preservation.json", FileAccess.WRITE).store_string(JSON.stringify(
		{"completed": true, "checks": checks, "failures": anatomical_failures, "cases": body_cases}, "\t"))
	game._reset_hit_feedback()
	print("BODY_PRESERVATION_DONE ", checks, " checks ", anatomical_failures.size(), " failures")
	quit(0 if anatomical_failures.is_empty() else 1)
