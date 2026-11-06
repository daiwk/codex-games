extends SceneTree

## Runs the real duel at 60 Hz. Targets stay at fixed distances so each
## blade pass can be isolated from AI, retreat and hit recoil.
class EndOfFrame extends Node:
	signal sampled

	func _process(_delta: float) -> void:
		sampled.emit()

var game: Node3D
var end_of_frame: EndOfFrame
var checks = 0
var failures: Array[String] = []
var contacts: Array = []
var tear_events: Array = []
var report: Array = []
var report_path = "/private/tmp/wenfeng-guan-crescent-latest.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	call_deferred("run")

func verify(label: String, result: bool, detail: Variant = null) -> void:
	checks += 1
	print("PASS " if result else "FAIL ", label, " ", detail if detail != null else "")
	if not result:
		failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func setup(gap: float, mode = "foot") -> void:
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character("guanyu")
	game.select_opponent("zhaoyun")
	await frames(3)
	game.start_match()
	game.phase = "fight"
	game.ai_enabled = false
	game.player.enabled = true
	game.player.position = Vector3(0, 0.015, -gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, gap * 0.5)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	game.enemy.set_physics_process(false)
	game.player.strike_requested.connect(observe_strike)
	contacts.clear()
	tear_events.clear()
	await frames(15)

func observe_strike(attacker: DuelFighter, _data: Dictionary) -> void:
	if not attacker.hit_landed or game.last_melee_hit.is_empty():
		return
	var hit: Dictionary = game.last_melee_hit
	var data: Dictionary = hit.data
	var defender: DuelFighter = attacker.opponent
	var nearest = Geometry3D.get_closest_points_between_segments(attacker.blade_base(), attacker.blade_tip(), defender.thrust_body_low(), defender.thrust_body_high())
	var sweep = Geometry3D.get_closest_points_between_segments(attacker.previous_tip, attacker.blade_tip(), defender.thrust_body_low(), defender.thrust_body_high())
	contacts.append({
		"clip": attacker.current_clip, "time": attacker.action_time, "active": data.active,
		"distance": minf(nearest[0].distance_to(nearest[1]), sweep[0].distance_to(sweep[1])),
		"radius": defender.thrust_body_radius(), "damage": hit.damage,
		"physical": data.get("physical_blade", false),
	})

func observe_tear(at: Vector3, direction: Vector3) -> void:
	var player: DuelFighter = game.player
	var base = player.blade_base().slide(Vector3.UP)
	var tip = player.blade_tip().slide(Vector3.UP)
	var distance = Geometry3D.get_closest_point_to_segment(at.slide(Vector3.UP), base, tip).distance_to(at.slide(Vector3.UP))
	tear_events.append({"clip": player.current_clip, "time": player.action_time, "edge_distance": distance,
		"aim_dot": direction.dot(player.forward()), "at": at})

func request(id: String) -> bool:
	match id:
		"light": return game.player.request_light()
		"heavy": return game.player.request_heavy()
		"ultimate":
			game.player.energy = 100.0
			return game.player.request_ultimate()
		_: return game.player.request_skill(id)

func observe_action() -> Dictionary:
	var result = {"peak_entities": 0, "held": true, "ribbon_samples": 0, "retreat": 0.0, "advance": 0.0,
		"shaft_sample_count": 0, "shaft_max_error": 0.0, "edge_sample_error": 0.0}
	var actor: DuelFighter = game.player
	var origin = actor.position
	var forward = actor.forward()
	var tracked: Node = game.fx.trails[actor.get_instance_id()].tracked
	for index in 180:
		await end_of_frame.sampled
		if actor.state not in ["attack", "skill", "ultimate"]:
			break
		result.peak_entities = maxi(result.peak_entities, game.specials.entity_count())
		result.held = result.held and actor.weapon_mesh.visible
		var displacement = (actor.position - origin).dot(forward)
		result.retreat = minf(result.retreat, displacement)
		result.advance = maxf(result.advance, displacement)
		if actor.current_clip.begins_with("GuanCrescent"):
			var axis = actor.grip.global_basis.y.normalized()
			for left in [true, false]:
				var error = (actor.palm_position(left) - actor.grip.global_position).slide(axis).length()
				result.shaft_max_error = maxf(result.shaft_max_error, error)
			result.shaft_sample_count += 1
		if is_instance_valid(tracked) and not tracked._samples.is_empty():
			var sample = tracked._samples[-1]
			if is_zero_approx(sample.age):
				result.ribbon_samples += 1
				var error = maxf(sample.base.distance_to(actor.blade_base()), sample.tip.distance_to(actor.blade_tip()))
				result.edge_sample_error = maxf(result.edge_sample_error, error)
	result["hits"] = contacts.duplicate(true)
	result["tear"] = tear_events.duplicate(true)
	result["hp_loss"] = 120.0 - game.enemy.hp
	return result

func light_chain() -> void:
	await setup(2.1)
	var actor: DuelFighter = game.player
	verify("foot Guan loads authored family", actor.crescent_motion.enabled)
	verify("first J starts", request("light"))
	var clips: Array[String] = []
	var previous_hands: Array[Quaternion] = []
	var hand_indices = [actor.left_hand_index, actor.right_hand_index]
	var largest_wrist_step = 0.0
	for frame in 300:
		if actor.state != "attack":
			break
		if clips.is_empty() or actor.current_clip != clips[-1]:
			clips.append(actor.current_clip)
			if clips.size() < 4:
				verify("J%d buffers next cut" % clips.size(), request("light"))
			else:
				verify("fifth J cannot extend the chain", not request("light"))
		var hands: Array[Quaternion] = []
		for index in hand_indices:
			hands.append(actor.skeleton.get_bone_global_pose(index).basis.get_rotation_quaternion())
		for side in previous_hands.size():
			largest_wrist_step = maxf(largest_wrist_step, previous_hands[side].angle_to(hands[side]))
		previous_hands = hands
		await physics_frame
	verify("J actually plays four distinct consecutive blade clips",
		clips == ["GuanCrescentJ1", "GuanCrescentJ2", "GuanCrescentJ3", "GuanCrescentJ4"], clips)
	# An earlier cross-fade flipped the right glove ~158° on the first J4 tick.
	verify("no wrist flips across a live chained transition", largest_wrist_step < deg_to_rad(60.0),
		rad_to_deg(largest_wrist_step))
	var landed: Array[String] = []
	for hit in contacts:
		if hit.physical and hit.distance <= hit.radius + 0.071:
			landed.append(hit.clip)
	verify("all four combo cuts make a single physical contact each", landed == clips, landed)
	verify("four-cut chain recovers to idle", actor.state == "idle" and game.specials.groups.is_empty())

func late_light() -> void:
	await setup(6.0)
	var actor: DuelFighter = game.player
	verify("late-J fixture starts first cut", request("light"))
	for frame in 65:
		if actor.action_time >= actor.action_duration - 0.08:
			break
		await physics_frame
	game.queue_combat_input("light")
	game._consume_combat_input()
	verify("late J keeps the intent without joining from recovery",
		actor.action_time > float(actor.attack.combo_at) and not actor.combo_buffered and game.pending_input == "light")
	for frame in 24:
		await physics_frame
		game._consume_combat_input()
		if game.pending_input.is_empty():
			break
	verify("late J restarts from J1 after recovery",
		game.pending_input.is_empty() and actor.state == "attack" and actor.combo == 0
		and actor.current_clip == "GuanCrescentJ1" and actor.action_time < 0.10)

func action_case(id: String, gap: float, expected_hits: int, live_target = false) -> void:
	await setup(gap)
	if live_target:
		game.enemy.set_physics_process(true)
	var label = "%s at %.2f m" % [id, gap]
	verify(label + " starts through its real action gate", request(id))
	var data: Dictionary = await observe_action()
	report.append({"action": id, "gap": gap, "data": data})
	verify(label + " real blade stays held with both palms on the shaft",
		data.held and data.shaft_sample_count > 15 and data.shaft_max_error < 0.09,
		{"frames": data.shaft_sample_count, "shaft_error": data.shaft_max_error})
	verify(label + " only renders tracked edge during actual cuts",
		data.ribbon_samples >= 2 and data.edge_sample_error < 0.09,
		{"samples": data.ribbon_samples, "edge_error": data.edge_sample_error})
	verify(label + " never spawns an external damage group", data.peak_entities == 0)
	verify(label + " actual contact count", data.hits.size() == expected_hits, data.hits)
	var damage = 0.0
	for hit in data.hits:
		damage += float(hit.damage)
		var window: Vector2 = hit.active
		verify(label + " strikes inside its window and touches the body",
			hit.physical and hit.time >= window.x and hit.time <= window.y and hit.distance <= hit.radius + 0.071,
			hit)
	verify(label + " HP loss matches physical contacts", is_equal_approx(damage, data.hp_loss))
	if id == "rush" and expected_hits == 2 and data.hits.size() == 2:
		verify(label + " uses two distinct live windows", data.hits[0].active.y < data.hits[1].active.x)
	if id == "counter":
		verify(label + " withdraws and then steps back in", data.retreat < -0.10 and data.advance - data.retreat > 0.22,
			{"retreat": data.retreat, "advance": data.advance})
	if id == "ultimate":
		verify(label + " produces exactly one vertical tear on its actual blade line", data.tear.size() == 1
			and data.tear[0].clip == "GuanCrescentU" and data.tear[0].time >= 1.20 and data.tear[0].time <= 1.45
			and data.tear[0].edge_distance < 0.09 and data.tear[0].aim_dot > 0.8, data.tear)
	else:
		verify(label + " has no ultimate tear", data.tear.is_empty())

func compatibility() -> void:
	await setup(6.0, "mounted")
	verify("mounted Guan retains both projectile profiles",
		not game.player.crescent_motion.enabled and game.player.skill_profile("rush").special.type == "shockwave"
		and game.player.skill_profile("ultimate").special.formation == "diagonal_cleave")
	verify("mounted Guan has no tracked ground effect", not is_instance_valid(game.fx.trails[game.player.get_instance_id()].tracked))
	var rpg_fighter = DuelFighter.new()
	rpg_fighter.character_id = "guanyu"
	verify("shared RPG still uses its own original melee profiles",
		rpg_fighter.skill_profile("rush").clip == "CrescentLow"
		and rpg_fighter.skill_profile("ultimate").hits.size() == 2)
	rpg_fighter.free()

func run() -> void:
	Engine.physics_ticks_per_second = 60
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	game.fx.guan_tear_released.connect(observe_tear)
	end_of_frame = EndOfFrame.new()
	end_of_frame.process_priority = 100
	root.add_child(end_of_frame)
	await frames(8)
	await light_chain()
	await late_light()
	for entry in [["light", 2.1, 1], ["heavy", 2.1, 1], ["rush", 2.1, 2], ["counter", 2.1, 1], ["ultimate", 2.1, 1],
			["rush", 6.0, 0], ["ultimate", 6.0, 0]]:
		await action_case(entry[0], entry[1], entry[2])
	# Real body collision and recoil at close range exposed a blind spot in U.
	await action_case("ultimate", 1.4, 1, true)
	await compatibility()
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(
		{"checks": checks, "failures": failures, "cases": report}, "\t"))
	print("GUAN CRESCENT DONE ", checks, " checks ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
