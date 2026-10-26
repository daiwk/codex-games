extends SceneTree

## Real projectile/front physics against real fighter hurt capsules and the
## normal receive_strike path. Cast orchestration is tested by the scene suite.
const Fighter = preload("res://scripts/fighter.gd")
const Specials = preload("res://scripts/duel_specials.gd")
const Presentation = preload("res://scripts/duel_skill_fx.gd")
var world: Node3D
var caster: DuelFighter
var target: DuelFighter
var alternate: DuelFighter
var manager: Node3D
var presentation: Node3D
var rows: Array = []
var contacts: Array = []
var failures: Array = []
var checks = 0

func _initialize() -> void: call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks += 1
	rows.append({"label": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label, " ", JSON.stringify(detail))
	if not passed: failures.append(label)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func hit(attacker: DuelFighter, defender: DuelFighter, data: Dictionary, point: Vector3) -> void:
	var before = defender.hp
	var outcome = defender.receive_strike(attacker, data)
	contacts.append({"volley": data.volley_id, "index": data.projectile_index, "type": data.special,
		"target": defender.get_instance_id(), "point": [point.x, point.y, point.z], "outcome": outcome,
		"damage": before - defender.hp, "clock": Time.get_ticks_msec()})

func setup(gap = 6.0) -> void:
	manager.clear()
	presentation.clear()
	contacts.clear()
	for actor in [caster, target, alternate]:
		actor.reset_fighter()
		actor.hp = 1000.0
		actor.set_physics_process(false)
		actor.enabled = false
	caster.position = Vector3.ZERO
	caster.rotation.y = 0.0
	target.position = Vector3(0, 0, gap)
	target.rotation.y = PI
	alternate.position = Vector3(8, 0, gap)
	caster.opponent = target
	target.opponent = caster
	alternate.opponent = caster
	await frames(2)

func wall() -> StaticBody3D:
	var node = StaticBody3D.new()
	node.position = Vector3(0, 2.5, 3.0)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(12, 5, 0.25)
	collision.shape = shape
	node.add_child(collision)
	world.add_child(node)
	return node

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	for id in ["zhaoyun", "machao", "guanyu"]:
		var actor = Fighter.new()
		actor.character_id = id
		actor.weapon_id = "guandao" if id == "guanyu" else "serpent_spear"
		world.add_child(actor)
		actor.set_physics_process(false)
		if id == "zhaoyun": caster = actor
		elif id == "machao": target = actor
		else: alternate = actor
	manager = Specials.new()
	world.add_child(manager)
	manager.hit_requested.connect(hit)
	presentation = Presentation.new()
	world.add_child(presentation)
	await frames(3)
	await setup()
	manager.spawn(caster, {"type": "flying_blades", "count": 9, "damage": 8.0, "speed": 13.0})
	await frames(5)
	check("nine swords do not hit at release before visible travel", contacts.is_empty(), manager.debug_state())
	await frames(95)
	check("nine separate swept sword contacts deal actual72 damage", contacts.size() == 9 and is_equal_approx(target.hp, 928.0), contacts)
	var indices: Dictionary = {}
	for record in contacts: indices[record.index] = true
	check("volley contacts have nine unique projectile indices", indices.size() == 9)
	await setup()
	manager.spawn(caster, {"type": "flying_blades", "count": 9, "damage": 8.0, "homing": 0.0})
	caster.opponent = alternate
	await frames(100)
	check("changing lock cannot retarget released swords", target.hp < 1000.0 and alternate.hp == 1000.0)
	await setup()
	manager.spawn(caster, {"type": "flying_blades", "count": 9, "damage": 8.0, "homing": 0.8})
	await frames(6)
	target.position.x = 8.0
	await frames(100)
	check("a target moving out of the flight path can evade every sword", target.hp == 1000.0, contacts)
	await setup()
	var cavalry_id = manager.spawn(caster, {"type": "cavalry", "count": 6, "damage": 12.0, "radius": 0.58})
	check("six riders use one batched mesh with no added skeleton instances", manager.groups[cavalry_id].visual is MultiMeshInstance3D and manager.groups[cavalry_id].visual.multimesh.instance_count == 6 and manager.groups[cavalry_id].node.find_children("*", "Skeleton3D", true, false).is_empty())
	await frames(5)
	check("cavalry cannot hit ahead of its physical formation", contacts.is_empty())
	await frames(115)
	check("six real cavalry routes arrive and deal72 damage", contacts.size() == 6 and is_equal_approx(target.hp, 928.0), contacts)
	await setup(3.0)
	manager.spawn(caster, {"type": "returning_blade", "damage": 22.0, "speed": 13.0})
	check("thrown blade removes the held duplicate", not caster.weapon_mesh.visible)
	await frames(110)
	check("thrown blade hits at most once across outward and return trips", contacts.size() == 1 and target.hp == 978.0, contacts)
	check("returning blade restores the original hand weapon", caster.weapon_mesh.visible and manager.groups.is_empty())
	await setup(3.0)
	manager.spawn(caster, {"type": "returning_blade"})
	manager.cancel_owner(caster.get_instance_id())
	check("cancel restores thrown weapon and removes its geometry", caster.weapon_mesh.visible and manager.groups.is_empty())
	for type in ["shockwave", "roar", "air_slam"]:
		await setup(3.5)
		manager.spawn(caster, {"type": type, "radius": 5.0, "speed": 10.0, "damage": 20.0})
		await frames(3)
		check(type + " has no instant remote impact", contacts.is_empty())
		await frames(80)
		check(type + " moving pressure front contacts once", contacts.size() == 1 and target.hp == 980.0, contacts)
	for type in ["flying_blades", "cavalry", "shockwave"]:
		await setup()
		var barrier = wall()
		await frames(2)
		manager.spawn(caster, {"type": type, "count": 6, "radius": 0.58, "damage": 12.0})
		await frames(145)
		check(type + " is blocked by a solid wall", contacts.is_empty() and target.hp == 1000.0, contacts)
		barrier.queue_free()
		await frames(2)
	for type in ["cavalry", "shockwave", "air_slam"]:
		await setup(3.5)
		target.position.y = 3.0
		manager.spawn(caster, {"type": type, "count": 6, "radius": 5.0 if type == "air_slam" else 0.58, "damage": 12.0})
		await frames(120)
		check(type + " cannot acquire a target above its real pressure height", contacts.is_empty() and target.hp == 1000.0)
	await setup()
	manager.spawn(caster, {"type": "returning_blade"})
	caster.hp = 0.0
	await frames(2)
	check("caster death restores thrown weapon and clears active group", manager.groups.is_empty() and caster.weapon_mesh.visible)
	await setup()
	var paused_id = manager.spawn(caster, {"type": "flying_blades"})
	await frames(3)
	var before_age = float(manager.groups[paused_id].age)
	var before_point: Vector3 = manager.groups[paused_id].entities[0].position
	paused = true
	await frames(8)
	check("pause freezes projectile clock and positions", manager.groups[paused_id].age == before_age and manager.groups[paused_id].entities[0].position == before_point)
	paused = false
	await setup()
	for i in 4: manager.spawn(caster, {"type": "flying_blades", "count": 9})
	check("combined projectile budget never exceeds18", manager.entity_count() <= 18, manager.debug_state())
	manager.clear()
	check("clear removes every projectile group", manager.groups.is_empty())
	await setup(2.1)
	for i in 50: presentation.impact(Vector3(0, 1, 1), "heavy_hit", Vector3.FORWARD, 1.2)
	check("local impact layers stay inside shared24 budget", presentation.active_effect_count() <= 24)
	presentation.clear()
	check("presentation clear empties all contact layers", presentation.active_effect_count() == 0)
	var output = {"checks": checks, "passed": failures.is_empty(), "failures": failures, "cases": rows, "fixture_scope": "Actual special-manager physics and receiver damage; cast resource/timing and live AI remain scene-suite responsibilities."}
	var file = FileAccess.open("res://qa/duel-presentation-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t") + "\n")
	print("DUEL_PRESENTATION_QA ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
