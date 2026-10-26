extends SceneTree

## Focused payload/receiver and throw lifecycle test after finisher tuning.
## Main's actual impulse movement is independently tested by the scene suite.
const Fighter = preload("res://scripts/duel_actor.gd")
const Specials = preload("res://scripts/duel_specials.gd")
var world: Node3D
var manager: Node3D
var caster: DuelFighter
var target: DuelFighter
var contacts: Array = []
var cases: Array = []
var failures: Array = []

func _initialize() -> void: call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func hit(attacker: DuelFighter, defender: DuelFighter, data: Dictionary, _point: Vector3) -> void:
	var before = defender.hp
	defender.receive_strike(attacker, data)
	contacts.append({"index": data.projectile_index, "damage": before - defender.hp, "knockback": data.knockback,
		"finisher": data.get("finisher", false), "special": data.special, "weapon": data.weapon_id})

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	manager = Specials.new()
	world.add_child(manager)
	manager.hit_requested.connect(hit)
	for mounted in [false, true]:
		for weapon in ["xuchu_saber", "saber", "sword"]:
			manager.clear()
			for actor in [caster, target]:
				if is_instance_valid(actor): actor.queue_free()
			await frames(2)
			caster = Fighter.new()
			caster.character_id = "xuchu"
			caster.weapon_id = weapon
			caster.mounted = mounted
			world.add_child(caster)
			caster.set_physics_process(false)
			caster.enabled = false
			target = Fighter.new()
			target.character_id = "machao"
			target.weapon_id = "serpent_spear"
			target.mounted = mounted
			world.add_child(target)
			target.set_physics_process(false)
			target.enabled = false
			target.position = Vector3(0, 0, 4.8)
			target.hp = 1000.0
			caster.opponent = target
			target.opponent = caster
			await frames(4)
			contacts.clear()
			var config: Dictionary = caster.skill_profile("ultimate").special
			manager.spawn(caster, config, {}, "ultimate")
			var hidden = caster.duel_weapon_is_thrown() and not caster.weapon_mesh.visible
			await frames(130)
			var u_contacts = contacts.duplicate(true)
			var push_ok = u_contacts.size() == 3
			var indices: Dictionary = {}
			for contact in u_contacts:
				indices[contact.index] = true
				var last = int(contact.index) == 2
				push_ok = push_ok and bool(contact.finisher) == last and is_equal_approx(float(contact.knockback), 4.8 if last else 1.4)
			var returned = manager.groups.is_empty() and not caster.duel_weapon_is_thrown() and caster.weapon_mesh.visible
			var actual_damage = 1000.0 - target.hp
			contacts.clear()
			manager.spawn(caster, caster.skill_profile("rush").special, {}, "rush")
			await frames(110)
			var q_unchanged = contacts.size() == 1 and is_equal_approx(float(contacts[0].knockback), 4.6) and not contacts[0].finisher
			var passed = hidden and push_ok and indices.size() == 3 and is_equal_approx(actual_damage, 66.0) and returned and q_unchanged
			var row = {"mounted": mounted, "weapon": weapon, "passed": passed, "hidden": hidden, "u_contacts": u_contacts,
				"u_damage": actual_damage, "unique_indices": indices.size(), "first_two_push_1_4_last_real_contact_4_8": push_ok,
				"all_returned": returned, "q_single_throw_unchanged": q_unchanged}
			cases.append(row)
			if not passed: failures.append(weapon + (" mounted" if mounted else " foot"))
			print("PASS " if passed else "FAIL ", JSON.stringify(row))
	var report = {"passed": failures.is_empty(), "cases": cases, "failures": failures,
		"scope": "Actual foot/mounted receivers with fixed targets; verifies U three contacts/66 damage, finisher payload only on index2, full return, and unchanged Q. Main movement/impulse response is separate."}
	FileAccess.open("res://qa/duel-army-return-results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
