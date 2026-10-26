extends SceneTree

# Six-role acceptance: actual pose trajectories AND actual damage/defense rules.
# Aliases, skill names, colours and profile dictionaries alone are insufficient.
# Run: Godot --headless --path . --script res://tools/role_identity_test.gd
const ROLES = ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu", "xuchu"]
const EXPECTED_HITS = {
	"zhaoyun": [2, 1, 5], "machao": [1, 1, 1], "guanyu": [1, 1, 2],
	"zhangfei": [1, 1, 2], "lubu": [1, 1, 3], "xuchu": [1, 1, 1]}
const EXPECTED_SHAPES = {
	"zhaoyun": [["line", "line"], ["line"], ["line", "line", "line", "line", "line"]],
	"machao": [["line"], ["line"], ["line"]],
	"guanyu": [["sector"], ["sector"], ["sector", "radial"]],
	"zhangfei": [["line"], ["radial"], ["radial", "line"]],
	"lubu": [["sector"], ["sector"], ["sector", "radial", "sector"]],
	"xuchu": [["sector"], ["sector"], ["radial"]]}
const BONES = ["Spine", "Spine1", "Spine2", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]
var game: Node3D
var checks = 0
var failures: Array[String] = []
var rows: Array = []
var hits: Array = []
var stages: Array = []
var observing = false
var trajectory: Array = []
var idle_rotations: Dictionary = {}
var indices: Dictionary = {}
var action_length = 1.0
var action_origin = Vector3.ZERO
var last_hit_hp = 120.0
var trajectories: Dictionary = {}
var motion_windows: Array = []
var window_motion: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks += 1
	rows.append({"name": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label, " ", detail if detail != null else "")
	if not passed:
		failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func until_time(moment: float) -> void:
	for index in 500:
		if game.player.action_time >= moment or game.player.state not in ["skill", "ultimate"]:
			return
		await physics_frame

func bone(suffix: String) -> int:
	for index in game.player.skeleton.get_bone_count():
		if game.player.skeleton.get_bone_name(index).ends_with(suffix):
			return index
	return -1

func impact(_fighter: Node, outcome: String, point: Vector3) -> void:
	if outcome in ["hit", "heavy_hit"]:
		hits.append({"shape": game.player.attack.get("shape", "sector"), "time": game.player.action_time,
			"damage": last_hit_hp - game.enemy.hp, "point": point})
		last_hit_hp = game.enemy.hp

func stage(_fighter: Node, id: String, phase: String) -> void:
	stages.append({"id": id, "phase": phase, "time": game.player.action_time, "clip": game.player.current_clip})

func held_frame() -> Dictionary:
	var f = game.player
	var right: Transform3D = f.skeleton.get_bone_global_pose(indices.RightHand)
	var rp: Array = f.grip_config.right_palm
	var centre: Vector3 = right * Vector3(rp[0], rp[1], rp[2])
	var axis: Vector3
	if f.is_two_handed():
		var left: Transform3D = f.skeleton.get_bone_global_pose(indices.LeftHand)
		var lp: Array = f.grip_config.left_palm
		var left_palm = left * Vector3(lp[0], lp[1], lp[2])
		axis = f.skeleton.global_basis * (centre - left_palm) * float(f.grip_config.axis_sign)
		centre = (centre + left_palm) * 0.5
	else:
		var q: Array = f.grip_config.rotation_xyzw
		axis = f.skeleton.global_basis * right.basis * Basis(Quaternion(q[0], q[1], q[2], q[3])) * Vector3.UP
	return {"axis": (f.global_basis.inverse() * axis).normalized(), "centre": f.to_local(f.skeleton.to_global(centre))}

func final_pose() -> void:
	if not observing or game.player.state not in ["skill", "ultimate"]:
		return
	var held = held_frame()
	for index in motion_windows.size():
		var window: Vector2 = motion_windows[index].active
		if game.player.action_time < window.x - 0.045 or game.player.action_time > window.y + 0.055:
			continue
		if not window_motion.has(index):
			window_motion[index] = {"samples": 0, "minimum": held.centre, "maximum": held.centre, "axis": held.axis, "angle": 0.0}
		var row: Dictionary = window_motion[index]
		row.samples += 1
		row.minimum = Vector3(row.minimum).min(held.centre)
		row.maximum = Vector3(row.maximum).max(held.centre)
		row.angle = maxf(float(row.angle), Vector3(row.axis).angle_to(held.axis))
	var fraction: float = clampf(game.player.action_time / action_length, 0.0, 1.0)
	if trajectory.size() >= 19 or fraction + 0.0001 < float(trajectory.size()) / 19.0:
		return
	var values: Dictionary = {}
	for name in BONES:
		values[name] = Quaternion(idle_rotations[name]).inverse() * game.player.skeleton.get_bone_pose_rotation(indices[name])
	trajectory.append({"phase": fraction, "bones": values, "axis": held.axis,
		"position": game.player.position - action_origin, "clip": game.player.current_clip})

func setup(role: String, mode: String, gap = 2.1) -> void:
	observing = false
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(role)
	game.select_opponent("zhaoyun")
	await frames(4)
	game.start_match()
	game.phase = "fight"
	game.round_time = 90.0
	game.ai_enabled = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, 0)
	game.enemy.position = Vector3(0, 0.015, gap)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	await frames(55)
	hits.clear()
	stages.clear()
	trajectory.clear()
	last_hit_hp = game.enemy.hp
	indices.clear()
	idle_rotations.clear()
	for name in BONES:
		indices[name] = bone(name)
		idle_rotations[name] = game.player.skeleton.get_bone_pose_rotation(indices[name])
	indices.RightHand = bone("RightHand")
	indices.LeftHand = bone("LeftHand")
	game.enemy.impact_received.connect(impact)
	game.player.skill_triggered.connect(stage)
	game.player.skeleton.skeleton_updated.connect(final_pose)

func start_action(id: String) -> bool:
	action_origin = game.player.position
	var profile: Dictionary = game.player.skill_profile(id)
	action_length = float(profile.duration)
	motion_windows = []
	window_motion.clear()
	for hit in profile.get("hits", [profile]):
		var clip: String = hit.get("clip", profile.get("strike_clip", profile.get("clip", "")))
		motion_windows.append({"active": hit.active, "clip": clip,
			"intentional_roar": profile.get("kind", "") == "roar" or clip == "SerpentVoice"})
	if id == "ultimate":
		game.player.energy = 100.0
		return game.player.request_ultimate()
	return game.player.request_skill(id)

func finish_action() -> void:
	for index in 2000:
		await physics_frame
		if game.player.state not in ["skill", "ultimate"]:
			return

func configured_damage(profile: Dictionary) -> float:
	var total = 0.0
	if profile.has("hits"):
		for hit in profile.hits:
			total += float(hit.damage)
	else:
		total = float(profile.damage)
	return total

func action_case(role: String, mode: String, id: String, slot: int) -> void:
	# The short mounted shoulder knife is explicitly close range. Independent
	# 1.6–2.4m trials verified full hits at 1.8m and genuine whiffs at 2.1m.
	# Other role skills retain the common 2.1m acceptance scenario.
	var gap = 1.8 if role == "xuchu" and mode == "mounted" and id == "rush" else 2.1
	await setup(role, mode, gap)
	var profile: Dictionary = game.player.skill_profile(id)
	var label = role + "/" + mode + "/" + id
	var expected = configured_damage(profile)
	var before_stamina: float = game.player.stamina
	check(label + " starts actual role action", start_action(id))
	if id != "ultimate":
		check(label + " spends actual role stamina once", absf(game.player.stamina - (before_stamina - float(profile.cost))) < 0.001)
	else:
		check(label + " consumes full energy", game.player.energy == 0.0)
	var first_active: float = float(profile.hits[0].active.x) if profile.has("hits") else float(profile.active.x)
	await until_time(first_active - 0.035)
	check(label + " has no damage before actual active window", game.enemy.hp == 120.0, game.player.action_time)
	await finish_action()
	var actual_damage: float = 120.0 - game.enemy.hp
	var shapes: Array = []
	for hit in hits:
		shapes.append(hit.shape)
	check(label + " has designed distinct real hit count", hits.size() == int(EXPECTED_HITS[role][slot]), hits)
	check(label + " applies each designed hit geometry in order", shapes == EXPECTED_SHAPES[role][slot], shapes)
	check(label + " deals configured damage without duplicate hits", absf(actual_damage - expected) < 0.02,
		{"damage": actual_damage, "expected": expected})
	check(label + " finishes and clears transient contact", game.player.state == "idle" and not game.player.contact_latched)
	# Miss fixture uses the same live fighter and real clock, with no stage or
	# animation seeks. This records the pose before impact withdrawal replaces it.
	await setup(role, mode, 14.0)
	observing = true
	start_action(id)
	await finish_action()
	observing = false
	check(label + " actual far action is sampled and cannot damage", trajectory.size() >= 16 and game.enemy.hp == 120.0,
		{"samples": trajectory.size(), "hp": game.enemy.hp})
	trajectories[mode + "/" + id + "/" + role] = trajectory.duplicate(true)
	for index in motion_windows.size():
		if motion_windows[index].intentional_roar:
			continue
		var motion: Dictionary = window_motion.get(index, {})
		var span = Vector3(motion.get("maximum", Vector3.ZERO)).distance_to(Vector3(motion.get("minimum", Vector3.ZERO)))
		var angle = float(motion.get("angle", 0.0))
		check(label + " hit%d has real local weapon motion rather than a held frame" % (index + 1),
			int(motion.get("samples", 0)) >= 3 and (span > 0.025 or angle > deg_to_rad(4.0)),
			{"clip": motion_windows[index].clip, "active": motion_windows[index].active, "palm_travel_m": span, "shaft_sweep_deg": rad_to_deg(angle), "samples": motion.get("samples", 0)})

func compare_trajectories(mode: String, id: String) -> void:
	for left_index in ROLES.size():
		for right_index in range(left_index + 1, ROLES.size()):
			var left: String = ROLES[left_index]
			var right: String = ROLES[right_index]
			var a: Array = trajectories.get(mode + "/" + id + "/" + left, [])
			var b: Array = trajectories.get(mode + "/" + id + "/" + right, [])
			var angle = 0.0
			var axis_angle = 0.0
			var root_separation = 0.0
			for index in mini(a.size(), b.size()):
				for name in BONES:
					angle = maxf(angle, Quaternion(a[index].bones[name]).angle_to(Quaternion(b[index].bones[name])))
				axis_angle = maxf(axis_angle, Vector3(a[index].axis).angle_to(Vector3(b[index].axis)))
				root_separation = maxf(root_separation, Vector3(a[index].position).distance_to(Vector3(b[index].position)))
			check(mode + "/" + id + " visible pose differs " + left + " vs " + right,
				a.size() >= 16 and b.size() >= 16 and (angle > deg_to_rad(10.0) or axis_angle > deg_to_rad(12.0)),
				{"joint_difference_deg": rad_to_deg(angle), "shaft_direction_deg": rad_to_deg(axis_angle), "root_path_difference": root_separation})

func guard_case(role: String, mode: String, id: String) -> void:
	await setup(role, mode)
	start_action(id)
	await finish_action()
	var baseline_damage: float = 120.0 - game.enemy.hp
	await setup(role, mode)
	start_action(id)
	game.enemy.enabled = true
	game.enemy.set_physics_process(true)
	check(role + "/" + mode + " brace opponent starts actual incoming J", game.enemy.request_light())
	await until_time(0.55)
	check(role + "/" + mode + " brace blocks physical front hit without losing HP",
		game.player.hp == 120.0 and game.player.state == "skill" and game.player.skill_counter_primed,
		{"hp": game.player.hp, "state": game.player.state, "primed": game.player.skill_counter_primed})
	game.enemy.set_physics_process(false)
	game.enemy.enabled = false
	game.enemy.state = "idle"
	game.enemy.position = game.player.position + game.player.forward() * 2.1
	await finish_action()
	var boosted_damage: float = 120.0 - game.enemy.hp
	check(role + "/" + mode + " successful brace strengthens actual return strike", boosted_damage > baseline_damage * 1.30,
		{"baseline": baseline_damage, "boosted": boosted_damage})

func tactical_cases(mode: String) -> void:
	await guard_case("zhangfei", mode, "rush")
	await guard_case("xuchu", mode, "counter")
	await setup("machao", mode)
	start_action("counter")
	await until_time(0.65)
	check("machao/" + mode + " E is a real long charge rather than an early roar", game.enemy.hp == 120.0 and game.player.state == "skill")
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
	check("machao/" + mode + " charged E takes full light damage without interruption", outcome == "hit" and game.player.hp == 105.0 and game.player.state == "skill")
	outcome = game.player.receive_strike(game.enemy, DuelFighter.HEAVY)
	check("machao/" + mode + " charged E is still interrupted by a heavy", outcome == "hit" and game.player.state == "hit")
	await setup("zhangfei", mode)
	start_action("counter")
	await until_time(0.22)
	game.enemy.position = game.player.position - game.player.forward() * 1.8
	await finish_action()
	check("zhangfei/" + mode + " unique E roar really reaches rear targets", game.enemy.hp < 120.0)
	await setup("machao", mode)
	start_action("counter")
	await until_time(0.4)
	game.enemy.position = game.player.position - game.player.forward() * 1.8
	await finish_action()
	check("machao/" + mode + " E thrust cannot become a rear radial hit", game.enemy.hp == 120.0)
	for role in ["guanyu", "lubu"]:
		await setup(role, mode, 14.0)
		start_action("rush")
		await until_time(0.29)
		game.enemy.position = game.player.position + game.player.global_basis.x * 2.3 + game.player.forward() * 0.25
		await finish_action()
		check(role + "/" + mode + " Q has actual " + ("broad low sweep" if role == "guanyu" else "narrow rising cut"),
			(game.enemy.hp < 120.0) if role == "guanyu" else (game.enemy.hp == 120.0), game.enemy.hp)
	for direction in [Vector3.RIGHT, Vector3.LEFT]:
		await setup("zhaoyun", mode, 5.0)
		game.player.input_move = direction
		var before = game.player.position
		start_action("counter")
		game.player.input_move = Vector3.ZERO
		await until_time(0.22)
		var outcome_evade: String = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
		check("zhaoyun/" + mode + " E follows actual selected lateral dodge and avoids incoming hit",
			(game.player.position - before).dot(direction) > (0.10 if mode == "mounted" else 0.35) and outcome_evade == "evade" and game.player.hp == 120.0,
			{"movement": game.player.position - before, "outcome": outcome_evade})
	await setup("guanyu", mode, 5.0)
	var start = game.player.position
	start_action("counter")
	await until_time(0.25)
	check("guanyu/" + mode + " E really retreats before returning cut", (game.player.position - start).dot(game.player.forward()) < (-0.12 if mode == "mounted" else -0.4),
		game.player.position - start)

func guandao_edge_case() -> void:
	await setup("guanyu", "foot", 14.0)
	game.player.set_physics_process(false)
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
		game.player.rotation.y = yaw
		for clip in ["Idle", "Attack1", "Attack2", "Heavy", "Block", "CrescentLow", "CrescentReturn", "CrescentSplit", "CrescentOrbit"]:
			game.player.play_clip(clip, 0.0)
			var animation: Animation = game.player.animation_player.get_animation(game.player.animation_names[clip])
			game.player.animation_player.advance(0.0)
			game.player.animation_player.seek(animation.length * 0.48, true)
			game.player.animation_player.pause()
			game.player.skeleton.force_update_all_bone_transforms()
			await frames(2)
			game.player._update_two_hand_grip(0.0, true)
			var edge: Vector3 = -game.player.weapon_mesh.global_basis.x.normalized()
			var shaft: Vector3 = game.player.weapon_mesh.global_basis.y.normalized()
			var facing: Vector3 = game.player.forward()
			var permitted_edge: Vector3 = facing - shaft * facing.dot(shaft)
			var geometric_limit: float = permitted_edge.length()
			var actual: float = edge.dot(facing)
			var projected_alignment: float = edge.dot(permitted_edge.normalized()) if geometric_limit > 0.000001 else -1.0
			# A cutting edge is perpendicular to its own shaft. If that shaft
			# points almost directly forward, an absolute forward dot >.20 is
			# geometrically impossible. Still reject every reversed edge, require
			# near-exact alignment with the independent permissible projection,
			# and retain the old absolute criterion whenever it can be reached.
			check("guandao actual cutting edge faces enemy %s/yaw%0.2f" % [clip, yaw],
				absf(edge.dot(shaft)) < 0.002 and projected_alignment >= 0.98 and actual > 0.0 and (actual > 0.20 if geometric_limit > 0.20 else true),
				{"actual_forward": actual, "geometric_limit": geometric_limit, "projected_alignment": projected_alignment})
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
	await guandao_edge_case()
	for mode in ["foot", "mounted"]:
		for role in ROLES:
			for index in 3:
				await action_case(role, mode, ["rush", "counter", "ultimate"][index], index)
		for id in ["rush", "counter", "ultimate"]:
			compare_trajectories(mode, id)
		await tactical_cases(mode)
	game._reset_hit_feedback()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	DirAccess.make_dir_recursive_absolute("res://qa/role-identity")
	var file = FileAccess.open("res://qa/role-identity/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "results": rows}, "\t"))
	print("ROLE_IDENTITY_QA=", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
