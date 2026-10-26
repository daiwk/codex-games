extends SceneTree

## Temporary real-resource regression. The root owns engine execution.
## Godot --headless --path <shared godot> --script res://tools/attack_tempo_test.gd
const Fighter = preload("res://scripts/fighter.gd")
const RPGActor = preload("res://scripts/rpg_actor.gd")
const Tempo = preload("res://scripts/attack_tempo.gd")
const Roster = preload("res://scripts/roster.gd")
var rows: Array = []
var failures: Array[String] = []
var cases: Array = []
var current: Node3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa"))
	call_deferred("run")

func check(label: String, condition: bool, value: Variant = null) -> void:
	rows.append({"label": label, "passed": condition, "value": value})
	print("PASS " if condition else "FAIL ", label, " ", value if value != null else "")
	if not condition:
		failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func new_actor(id: String, mounted: bool, rpg = false, weapon = "") -> Node3D:
	var actor = RPGActor.new() if rpg else Fighter.new()
	actor.character_id = id
	actor.weapon_id = weapon if not String(weapon).is_empty() else Roster.resolve_weapon(id, "")
	actor.mounted = mounted
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	actor.set_physics_process(false)
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.enabled = true
	return actor

func pose_value(animation: Animation, track: int, time: float) -> Variant:
	match animation.track_get_type(track):
		Animation.TYPE_POSITION_3D:
			return animation.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return animation.rotation_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			return animation.scale_track_interpolate(track, time)
	return null

func quaternion_chord(a: Quaternion, b: Quaternion) -> float:
	var difference = Vector4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
	var opposite = Vector4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
	return minf(difference.length(), opposite.length())

func fingerprint(source: Animation) -> int:
	var snapshot: Array = [source.length, source.loop_mode]
	for track in source.get_track_count():
		var keys: Array = []
		for key in source.track_get_key_count(track):
			keys.append([source.track_get_key_time(track, key), source.track_get_key_value(track, key), source.track_get_key_transition(track, key)])
		snapshot.append([source.track_get_path(track), source.track_get_type(track), source.track_get_interpolation_type(track), keys])
	return JSON.stringify(snapshot).hash()

func evaluate_case(actor: Node3D, title: String) -> void:
	var key = String(actor.animation_player.current_animation)
	var source: Animation = actor.animation_player.get_animation(actor.animation_names[actor.current_clip])
	var weighted: Animation = actor.animation_player.get_animation(key)
	var profile: Dictionary = actor.tempo_profile
	check(title + " uses real weighted playback", key.begins_with("AttackTempo/") and not profile.is_empty(), key)
	if profile.is_empty():
		return
	check(title + " source remains separate", weighted != source)
	check(title + " authored total length preserved", absf(weighted.length - source.length) < 0.000001, [source.length, weighted.length])
	check(title + " action duration preserved", absf(float(profile.duration) - float(actor.action_duration)) < 0.000001,
		[profile.duration, actor.action_duration])
	check(title + " physical window preserved", Vector2(profile.active).is_equal_approx(actor.attack.active))
	check(title + " same track paths and count", weighted.get_track_count() == source.get_track_count())
	var monotonic = true
	var previous = -1.0
	for index in 1001:
		var value = Tempo.source_at_action_time(float(profile.duration) * index / 1000.0, profile)
		monotonic = monotonic and value >= previous - 0.0000001 and value >= -0.0000001 and value <= source.length + 0.0000001
		previous = value
	check(title + " time map is bounded and nondecreasing", monotonic)
	check(title + " starts and ends exactly", absf(Tempo.source_at_action_time(0.0, profile)) < 0.0000001 and
		absf(Tempo.source_at_action_time(float(profile.duration), profile) - source.length) < 0.0000001)
	var left = float(profile.left)
	var right = float(profile.right)
	var duration = float(profile.duration)
	check(title + " measurable anticipation compression", left > 0.0 and Tempo.source_at_action_time(left * 0.5 * duration / source.length, profile) < left * 0.40)
	var hold_time = float(profile.hold)
	check(title + " post-contact hold outside guard", hold_time > 0.0 and absf(
		Tempo.source_at_action_time((right + hold_time * 0.5) * duration / source.length, profile) - right) < 0.0000001)
	var max_position = 0.0
	var max_rotation = 0.0
	var lower_position = 0.0
	var lower_rotation = 0.0
	var upper_count = 0
	var lower_count = 0
	var lower_keys_unchanged = true
	var strict_keys = true
	var paths_match = true
	var sample_count = 0
	# Include both active boundaries, their 50 ms neighborhoods, every authored
	# key in that protected band, and 61 evenly spaced interior samples.
	var times: Array[float] = [left, right,
		clampf(float(actor.attack.active.x) * source.length / duration, left, right),
		clampf(float(actor.attack.active.y) * source.length / duration, left, right)]
	for index in 61:
		times.append(lerpf(left, right, float(index) / 60.0))
	for track in source.get_track_count():
		var upper = Tempo.retimes_track(source, track)
		if upper:
			upper_count += 1
		else:
			lower_count += 1
			lower_keys_unchanged = lower_keys_unchanged and weighted.track_get_key_count(track) == source.track_get_key_count(track)
			for index in mini(source.track_get_key_count(track), weighted.track_get_key_count(track)):
				lower_keys_unchanged = lower_keys_unchanged and source.track_get_key_time(track, index) == weighted.track_get_key_time(track, index) and source.track_get_key_value(track, index) == weighted.track_get_key_value(track, index)
			for index in 121:
				var t = source.length * float(index) / 120.0
				var original_lower: Variant = pose_value(source, track, t)
				var actual_lower: Variant = pose_value(weighted, track, t)
				if original_lower is Quaternion:
					lower_rotation = maxf(lower_rotation, quaternion_chord(original_lower, actual_lower))
				elif original_lower is Vector3:
					lower_position = maxf(lower_position, original_lower.distance_to(actual_lower))
		paths_match = paths_match and weighted.track_get_path(track) == source.track_get_path(track) and weighted.track_get_type(track) == source.track_get_type(track)
		var last_key = -1.0
		for index in weighted.track_get_key_count(track):
			var t = weighted.track_get_key_time(track, index)
			strict_keys = strict_keys and t > last_key
			last_key = t
		var track_times = times.duplicate()
		for index in source.track_get_key_count(track):
			var t = source.track_get_key_time(track, index)
			if t >= left and t <= right:
				track_times.append(t)
		for time in track_times:
			var original: Variant = pose_value(source, track, time)
			var actual: Variant = pose_value(weighted, track, time)
			if original is Quaternion:
				max_rotation = maxf(max_rotation, quaternion_chord(original, actual))
			elif original is Vector3:
				max_position = maxf(max_position, original.distance_to(actual))
			sample_count += 1
	check(title + " every track retains path/type", paths_match)
	check(title + " phrases only upper body", upper_count > 0 and lower_count > 0 and profile.get("scope", "") == "upper_body", [upper_count, lower_count])
	check(title + " hips and legs retain exact authored keys", lower_keys_unchanged)
	check(title + " hips and legs retain whole-action pose", lower_position < 0.000001 and lower_rotation < 0.000001,
		{"position": lower_position, "quaternion_chord": lower_rotation})
	check(title + " all weighted key times strictly increase", strict_keys)
	check(title + " full contact/guard positional pose unchanged", max_position < 0.00002, max_position)
	check(title + " full contact/guard rotational pose unchanged", max_rotation < 0.00002, max_rotation)
	cases.append({"case": title, "key": key, "tracks": source.get_track_count(), "samples": sample_count,
		"maximum_position_error": max_position, "maximum_quaternion_chord_error": max_rotation,
		"lower_whole_action_position_error": lower_position, "lower_whole_action_rotation_error": lower_rotation,
		"action_duration": duration, "contact_guard_seconds": Tempo.CONTACT_GUARD_SECONDS,
		"hold_seconds": hold_time * duration / source.length})

func exercise(id: String, mounted: bool, rpg = false, weapon = "") -> void:
	var actor = new_actor(id, mounted, rpg, weapon)
	current = actor
	await frames(3)
	var label = ("RPG " if rpg else "Duel ") + id + (" mounted " if mounted else " foot ") + String(actor.weapon_id)
	var snapshots: Dictionary = {}
	for clip in ["Attack1", "Attack2", "Attack3", "Heavy", "RPGSlash", "RPGChop", "RPGSpin"]:
		if actor.animation_names.has(clip):
			var original: Animation = actor.animation_player.get_animation(actor.animation_names[clip])
			snapshots[clip] = fingerprint(original)
	check(label + " accepts real J1", actor.request_light())
	evaluate_case(actor, label + " J1")
	for combo_index in [1, 2]:
		check(label + " buffers real combo " + str(combo_index + 1), actor.request_light())
		actor.set_physics_process(true)
		var completed = false
		for frame in 110:
			await physics_frame
			if actor.state == "attack" and actor.combo == combo_index:
				completed = true
				break
		actor.set_physics_process(false)
		check(label + " reaches actual combo " + str(combo_index + 1), completed, actor.combo)
		if completed:
			evaluate_case(actor, label + " J" + str(combo_index + 1))
	actor.reset_fighter()
	actor.enabled = true
	check(label + " accepts real K", actor.request_heavy())
	evaluate_case(actor, label + " K")
	for skill in ["rush", "counter", "ultimate"]:
		actor.reset_fighter()
		actor.enabled = true
		actor.energy = 100.0
		var accepted: bool = actor.request_ultimate() if skill == "ultimate" else actor.request_skill(skill)
		check(label + " accepts original skill " + skill, accepted)
		check(label + " skill bypasses weighted normal library " + skill,
			actor.tempo_profile.is_empty() and not String(actor.animation_player.current_animation).begins_with("AttackTempo/"))
	for clip in snapshots:
		var original: Animation = actor.animation_player.get_animation(actor.animation_names[clip])
		check(label + " source remains immutable " + clip, snapshots[clip] == fingerprint(original))
	actor.queue_free()
	current = null
	await frames(3)

func event_checks(rpg = false) -> void:
	var actor = new_actor("zhaoyun", rpg, rpg)
	current = actor
	var events: Array = []
	actor.action_started.connect(func(_fighter, action: String): events.append({"action": action, "time": actor.action_time}))
	var label = "RPG physics" if rpg else "Duel physics"
	actor.request_heavy()
	var threshold = maxf(0.0, float(actor.attack.active.x) - 0.055)
	check(label + " preserves old heavy start signal", events.size() == 1 and events[0].action == "heavy" and events[0].time == 0.0)
	check(label + " no premature swing signal", not actor.swing_announced)
	actor.set_physics_process(true)
	for frame in 160:
		await physics_frame
		if actor.state == "idle":
			break
	actor.set_physics_process(false)
	var swings: Array = events.filter(func(entry): return entry.action == "swing_heavy")
	check(label + " one real release sound event", swings.size() == 1, swings)
	if swings.size() == 1:
		check(label + " release sound aligns to actual active window", float(swings[0].time) >= threshold - 0.000001 and float(swings[0].time) <= threshold + 0.035,
			{"threshold": threshold, "actual": swings[0].time})
	actor.reset_fighter()
	actor.enabled = true
	events.clear()
	actor.request_heavy()
	actor.stagger(0.25)
	actor.set_physics_process(true)
	await frames(40)
	actor.set_physics_process(false)
	swings = events.filter(func(entry): return String(entry.action).begins_with("swing_"))
	check(label + " early interruption never whooshes", swings.is_empty(), swings)
	actor.reset_fighter()
	actor.enabled = true
	events.clear()
	actor.request_light()
	actor.set_physics_process(true)
	var before: float = actor.action_time
	paused = true
	await frames(8)
	check(label + " pause freezes attack and release event", actor.action_time == before and not actor.swing_announced and events.size() == 1)
	paused = false
	for frame in 120:
		await physics_frame
		if actor.state == "idle":
			break
	actor.set_physics_process(false)
	swings = events.filter(func(entry): return entry.action == "swing_light")
	check(label + " resume produces one light whoosh", swings.size() == 1, swings)
	actor.reset_fighter()
	check(label + " reset clears release flag", not actor.swing_announced)
	actor.queue_free()
	current = null
	await frames(3)

func run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	var floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	for mounted in [false, true]:
		for id in ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu", "xuchu"]:
			await exercise(id, mounted)
	for weapon in ["serpent_spear", "guandao", "halberd"]:
		await exercise("zhaoyun", true, true, weapon)
	await event_checks(false)
	await event_checks(true)
	var report = {"checks": rows.size(), "passed": failures.is_empty(), "failures": failures, "cases": cases, "rows": rows}
	var file = FileAccess.open("res://qa/attack-tempo-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ATTACK_TEMPO_QA ", JSON.stringify({"checks": rows.size(), "cases": cases.size(), "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
