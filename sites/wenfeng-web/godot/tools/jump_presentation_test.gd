extends SceneTree

## Presentation and release-height compatibility only. Actual jump input,
## animation, landing and resource orchestration belong to controller tests.
const DuelActor = preload("res://scripts/duel_actor.gd")
const JourneyActor = preload("res://scripts/rpg_actor.gd")
const DuelFX = preload("res://scripts/duel_skill_fx.gd")
const JourneyFX = preload("res://scripts/rpg_skill_fx.gd")
const Specials = preload("res://scripts/duel_specials.gd")
const Roster = preload("res://scripts/roster.gd")
var world: Node3D
var manager: Node3D
var duel_fx: Node3D
var journey_fx: Node3D
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

func actors(role: String, mounted: bool, journey = false, weapon = "") -> void:
	manager.clear()
	duel_fx.clear()
	journey_fx.clear()
	contacts.clear()
	for actor in [caster, target]:
		if is_instance_valid(actor): actor.queue_free()
	await frames(2)
	caster = JourneyActor.new() if journey else DuelActor.new()
	caster.character_id = role
	caster.weapon_id = Roster.weapon_choices(role)[0] if weapon == "" else weapon
	caster.mounted = mounted
	world.add_child(caster)
	caster.set_physics_process(false)
	caster.enabled = false
	target = DuelActor.new()
	target.character_id = "machao"
	target.weapon_id = "serpent_spear"
	target.mounted = mounted
	world.add_child(target)
	target.set_physics_process(false)
	target.enabled = false
	target.position = Vector3(0, 0, 3.5)
	target.hp = 1000.0
	caster.opponent = target
	target.opponent = caster
	await frames(4)
	caster.animation_player.pause()
	target.animation_player.pause()

func effect_positions(fx: Node3D) -> Array:
	var result: Array = []
	for effect in fx.active_effects.values(): result.append({"shape": effect.shape, "y": effect.node.global_position.y})
	return result

func skill_height(fx: Node3D, id: String, label: String) -> void:
	fx.clear()
	caster.position.y = 0.0
	fx.play_skill(caster, id, "start")
	fx.play_skill(caster, id, "release")
	if id == "ultimate":
		fx.play_skill(caster, id, "strike")
		fx.play_skill(caster, id, "finish")
	var ground = effect_positions(fx)
	fx.clear()
	caster.position.y = 3.0
	fx.play_skill(caster, id, "start")
	fx.play_skill(caster, id, "release")
	if id == "ultimate":
		fx.play_skill(caster, id, "strike")
		fx.play_skill(caster, id, "finish")
	var air = effect_positions(fx)
	var passed = ground.size() == air.size() and not air.is_empty()
	for i in mini(ground.size(), air.size()):
		passed = passed and ground[i].shape == air[i].shape and absf(float(air[i].y) - float(ground[i].y) - 3.0) < 0.08
	check(label + " " + id + " FX follows cast height", passed, {"ground": ground, "air": air})
	fx.clear()

func hit(attacker: DuelFighter, defender: DuelFighter, data: Dictionary, point: Vector3) -> void:
	contacts.append({"point_y": point.y, "index": data.projectile_index})
	defender.receive_strike(attacker, data)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	manager = Specials.new()
	world.add_child(manager)
	manager.hit_requested.connect(hit)
	duel_fx = DuelFX.new()
	world.add_child(duel_fx)
	journey_fx = JourneyFX.new()
	world.add_child(journey_fx)
	for mounted in [false, true]:
		for role in Roster.IDS:
			await actors(role, mounted)
			var label = role + (" mounted" if mounted else " foot")
			for id in ["rush", "counter", "ultimate"]: skill_height(duel_fx, id, label)
			caster.position.y = 3.0
			var profile: Dictionary = caster.skill_profile("ultimate")
			var group_id = manager.spawn(caster, profile.special, profile, "ultimate")
			var group: Dictionary = manager.groups[group_id]
			var minimum = 1000.0
			for entity in group.entities: minimum = minf(minimum, entity.position.y)
			check(label + " U entities preserve airborne source", is_equal_approx(float(group.origin.y), 3.0) and minimum >= 2.99 and group.entities.size() == int(profile.special.count), {"release_y": group.origin.y, "minimum_spawn_y": minimum, "count": group.entities.size()})
			manager.clear()
	for weapon in ["serpent_spear", "guandao", "halberd"]:
		await actors("zhaoyun", true, true, weapon)
		for id in ["rush", "counter", "ultimate"]: skill_height(journey_fx, id, "RPG " + weapon)
	# Explicit RPG custom-ground emit and its following update must agree.
	caster.position.y = 3.0
	var palette: Array = [Color("d8be6c"), Color.WHITE, Color("554329")]
	var effect_id = journey_fx._emit(caster, "rpg_dust", palette, 0.5, 0.0, Vector3.ONE, Vector3.ONE, true, true)
	await frames(2)
	check("RPG custom ground follower keeps actor elevation", absf(float(journey_fx.active_effects[effect_id].node.global_position.y) - 3.055) < 0.01)
	journey_fx.clear()
	# Ground-type pressure expands at its release altitude, with no damage
	# below that plane and no virtual follow-up strike added on landing.
	for mounted in [false, true]:
		await actors("zhangfei", mounted)
		for kind in ["shockwave", "roar", "air_slam"]:
			for target_y in [0.0, 5.0]:
				manager.clear()
				contacts.clear()
				caster.position.y = 5.0
				target.position.y = target_y
				target.hp = 1000.0
				manager.spawn(caster, {"type": kind, "damage": 17.0, "speed": 10.0, "radius": 5.0})
				await frames(70)
				var expected = 1 if target_y > 0.0 else 0
				check(kind + (" mounted" if mounted else " foot") + " respects release altitude target_y=" + str(target_y), contacts.size() == expected and is_equal_approx(target.hp, 1000.0 - 17.0 * expected), contacts.duplicate(true))
	# Action feedback stays in the existing pool and clears fully.
	for fx in [duel_fx, journey_fx]:
		for i in 40: fx.action(caster, "land")
		check("jump landing layer budget " + str(fx.get_script().resource_path), fx.active_effect_count() <= 24)
		fx.clear()
		check("jump feedback clear " + str(fx.get_script().resource_path), fx.active_effect_count() == 0)
	var result = {"checks": rows.size(), "passed": failures.is_empty(), "failures": failures, "cases": rows,
		"scope": "Controlled elevation tests for presentation, special source height and pressure altitude; actual V jump state/input/physics is tested independently."}
	FileAccess.open("res://qa/jump-presentation-results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("JUMP_PRESENTATION_QA ", JSON.stringify({"checks": rows.size(), "passed": failures.is_empty(), "failures": failures}))
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
