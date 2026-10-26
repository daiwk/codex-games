extends SceneTree

## Physical formation regression against real foot/mounted actor capsules.
## Main input/resource/cast orchestration belongs to the independent scene suite.
const Fighter = preload("res://scripts/duel_actor.gd")
const Specials = preload("res://scripts/duel_specials.gd")
const Roster = preload("res://scripts/roster.gd")
var world: Node3D
var manager: Node3D
var caster: DuelFighter
var target: DuelFighter
var contacts: Array = []
var rows: Array = []
var failures: Array = []

func _initialize() -> void: call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func check(label: String, passed: bool, detail: Variant = null) -> void:
	rows.append({"label": label, "passed": passed, "detail": detail})
	if not passed: failures.append(label)
	print("PASS " if passed else "FAIL ", label, " ", JSON.stringify(detail))

func hit(attacker: DuelFighter, defender: DuelFighter, data: Dictionary, point: Vector3) -> void:
	var before = defender.hp
	defender.receive_strike(attacker, data)
	contacts.append({"index": data.projectile_index, "formation": data.get("formation", ""), "weapon": data.get("weapon_id", ""), "damage": before - defender.hp,
		"source": data.source_position, "direction": data.impact_direction, "point": point})

func actors(role: String, mounted: bool, weapon = "") -> void:
	manager.clear()
	contacts.clear()
	for actor in [caster, target]:
		if is_instance_valid(actor): actor.queue_free()
	await frames(2)
	caster = Fighter.new()
	caster.character_id = role
	caster.weapon_id = Roster.weapon_choices(role)[0] if weapon == "" else weapon
	caster.mounted = mounted
	world.add_child(caster)
	caster.set_physics_process(false)
	caster.enabled = false
	caster.position = Vector3.ZERO
	target = Fighter.new()
	target.character_id = "machao"
	target.weapon_id = "serpent_spear"
	target.mounted = mounted
	world.add_child(target)
	target.set_physics_process(false)
	target.enabled = false
	target.position = Vector3(0, 0, 4.8)
	target.rotation.y = PI
	target.hp = 1000.0
	caster.opponent = target
	target.opponent = caster
	await frames(4)

func reset_target() -> void:
	manager.clear()
	contacts.clear()
	target.reset_fighter()
	target.set_physics_process(false)
	target.enabled = false
	target.hp = 1000.0
	target.position = Vector3(0, 0, 4.8)
	await frames(2)

func wall() -> StaticBody3D:
	var body = StaticBody3D.new()
	body.position = Vector3(0, 3.5, 2.6)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(18, 7, 0.35)
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	manager = Specials.new()
	world.add_child(manager)
	manager.hit_requested.connect(hit)
	await frames(2)
	for mounted in [false, true]:
		for role in Roster.IDS:
			await actors(role, mounted)
			var config: Dictionary = caster.skill_profile("ultimate").special.duplicate(true)
			var label = role + (" mounted" if mounted else " foot")
			var cache_size = manager._mesh_cache.size()
			var group_id = manager.spawn(caster, config, {}, "ultimate")
			check(label + " creates its configured formation", group_id >= 0 and manager.groups[group_id].entities.size() == int(config.count), manager.debug_state())
			var group: Dictionary = manager.groups[group_id]
			if role != "machao":
				var visual: MultiMesh = group.visual.multimesh
				check(label + " uses actual equipped prewarmed geometry", visual.mesh == manager._mesh_cache["weapon:" + caster.weapon_id] and manager._mesh_cache.size() == cache_size and group.weapon_id == caster.weapon_id)
				check(label + " preserves submitted actual polearm scale", is_equal_approx(float(group.entities[0].rendered_axis_scale), float(config.weapon_length)), {"submitted": group.entities[0].rendered_axis_scale, "requested": config.weapon_length})
			if role == "lubu":
				var before: Vector3 = group.entities[0].position
				await frames(20)
				check(label + " visible half-second telegraph commits no early hit", contacts.is_empty() and group.entities[0].position == before and float(group.entities[0].visual_opacity) > 0.2 and float(group.entities[0].delay) >= 0.40)
			else:
				await frames(4)
				check(label + " cannot hit at release before travel", contacts.is_empty())
			await frames(150)
			var unique: Dictionary = {}
			for contact in contacts: unique[contact.index] = true
			check(label + " actual distinct contacts stay within damage budget", contacts.size() == int(config.count) and unique.size() == contacts.size() and is_equal_approx(1000.0 - target.hp, float(config.damage) * int(config.count)), {"contacts": contacts.size(), "expected": config.count, "damage": 1000.0 - target.hp})
			await reset_target()
			manager.spawn(caster, config, {}, "ultimate")
			await frames(4)
			target.position.x = 9.0
			await frames(150)
			check(label + " fixed trajectories allow escaping the path", contacts.is_empty())
			await reset_target()
			var barrier = wall()
			await frames(2)
			manager.spawn(caster, config, {}, "ultimate")
			await frames(150)
			check(label + " solid wall blocks formation contacts", contacts.is_empty())
			barrier.queue_free()
			await frames(2)
	for weapon in ["xuchu_saber", "saber", "sword"]:
		await actors("xuchu", false, weapon)
		var config: Dictionary = caster.skill_profile("ultimate").special.duplicate(true)
		var q_id = manager.spawn(caster, {"type": "returning_blade", "speed": 13.0, "damage": 0.0})
		var u_id = manager.spawn(caster, config, {}, "ultimate")
		check(weapon + " Q and three-blade U hide one held weapon", caster.duel_weapon_is_thrown() and not caster.weapon_mesh.visible and manager.groups[u_id].weapon_id == weapon)
		var saw_partial_return = false
		var hidden_during_partial = true
		for i in 130:
			await frames(1)
			if not manager.groups.has(u_id): break
			var done = 0
			for entity in manager.groups[u_id].entities: done += int(entity.done)
			if done > 0 and done < int(config.count):
				saw_partial_return = true
				hidden_during_partial = hidden_during_partial and caster.duel_weapon_is_thrown() and not caster.weapon_mesh.visible
		check(weapon + " first return cannot reveal hand while other blades fly", saw_partial_return and hidden_during_partial)
		await frames(30)
		check(weapon + " all returns restore held weapon", not caster.duel_weapon_is_thrown() and caster.weapon_mesh.visible and manager.groups.is_empty())
		manager.spawn(caster, config, {}, "ultimate")
		manager.cancel_owner(caster.get_instance_id())
		check(weapon + " cancel clears all three and restores held mesh", manager.groups.is_empty() and not caster.duel_weapon_is_thrown() and caster.weapon_mesh.visible)
	var result = {"checks": rows.size(), "passed": failures.is_empty(), "failures": failures, "cases": rows,
		"scope": "Actual equipped formation meshes, physical foot/mounted capsules, trajectories, wall/escape, and shared Q/U return ownership; Main cast/input/resources are separate."}
	FileAccess.open("res://qa/duel-army-results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("DUEL_ARMY_QA ", JSON.stringify({"checks": rows.size(), "passed": failures.is_empty(), "failures": failures}))
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
