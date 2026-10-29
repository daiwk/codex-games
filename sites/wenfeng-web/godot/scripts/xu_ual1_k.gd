extends RefCounted

const RunEntry = preload("res://scripts/xu_run_entry.gd")
var run_entry = RunEntry.new()

const FamilyHit = preload("res://scripts/xu_family_hit.gd")
var family_hit = FamilyHit.new()

# Temporary ground Xu K only. Source pose/root share action_time at 1x.
var fighter
var enabled = false
var active = false
var ready = false
var data: Dictionary = {}
var last_time = 0.0
var start_basis = Basis.IDENTITY
var pending_root = Vector3.ZERO
var pending_strike: Dictionary = {}

func setup(owner_fighter) -> void:
	fighter = owner_fighter
	enabled = not fighter.mounted and fighter.character_id == "xuchu" and fighter.weapon_id == "xuchu_saber"
	if enabled:
		data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/motion/xuchu_ual1_k.json"))
		# Load only new animation resources; original model/27 imported clips stay untouched.
		var source = (load("res://assets/motion/xuchu_ual1_k.glb") as PackedScene).instantiate()
		var player = fighter._find_node(source, "AnimationPlayer") as AnimationPlayer
		var library = AnimationLibrary.new()
		for alias in [data.clip, data.idle_clip]:
			var key = ""
			for candidate in player.get_animation_list():
				if String(candidate).get_slice("/", String(candidate).get_slice_count("/") - 1) == alias: key = candidate
			assert(not key.is_empty(), "Missing UAL1 source alias")
			library.add_animation(alias, player.get_animation(key).duplicate(true))
			fighter.animation_names[alias] = "XuUAL1K/" + alias
		fighter.animation_player.add_animation_library("XuUAL1K", library)
		source.free()
		family_hit.setup(fighter, data.idle_clip, data.clip)
		run_entry.setup(fighter, data.clip)

func reset() -> void:
	run_entry.reset()
	family_hit.reset()
	active = false
	ready = false
	last_time = 0.0
	pending_root = Vector3.ZERO
	pending_strike.clear()

func curve(time: float) -> Vector3:
	var f = clampf(time / float(data.duration), 0.0, 1.0) * (data.times.size() - 1)
	var i = mini(int(f), data.times.size() - 1)
	var j = mini(i + 1, data.times.size() - 1)
	var a: Array = data.root_delta_model[i]
	var b: Array = data.root_delta_model[j]
	return Vector3(a[0], 0, a[2]).lerp(Vector3(b[0], 0, b[2]), f - i)

func sync_weapon() -> void:
	fighter.skeleton.force_update_all_bone_transforms()
	var socket = fighter.grip.get_parent()
	if socket is BoneAttachment3D:
		var index = fighter.skeleton.find_bone(socket.bone_name)
		if index >= 0:
			socket.transform = fighter.skeleton.get_bone_global_pose(index)

func begin() -> void:
	active = true
	ready = false
	last_time = 0.0
	pending_root = Vector3.ZERO
	pending_strike.clear()
	start_basis = fighter.global_basis
	fighter.combat_motion.influence = 0.0
	fighter.tempo_profile = {}
	fighter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if run_entry.prepared:
		run_entry.begin()
	else:
		_begin_source(0.0)

func _begin_source(time: float) -> void:
	var key: String = fighter.animation_names[data.clip]
	fighter.animation_player.get_animation(key).loop_mode = Animation.LOOP_NONE
	fighter.animation_player.speed_scale = 1.0
	fighter.animation_player.play(key, 0.0 if run_entry.prepared else 0.075, 1.0)
	fighter.animation_player.seek(time, true)
	fighter.animation_player.advance(0.0)
	fighter.current_clip = data.clip
	last_time = time
	sync_weapon()

func entry_shift() -> float:
	return run_entry.duration - RunEntry.SOURCE_START if run_entry.prepared else 0.0

func prepare_run_request() -> void:
	if enabled: run_entry.plan()

func prepare_tick() -> void:
	if not active or fighter.state != "attack": return
	if run_entry.active:
		run_entry.advance(fighter.action_time)
		sync_weapon()
		return
	var t = clampf(fighter.action_time - entry_shift(), 0.0, float(data.duration))
	pending_root += curve(t) - curve(last_time)
	fighter.animation_player.advance(maxf(0.0, t - last_time))
	last_time = t
	sync_weapon()

func apply_motion(delta: float) -> void:
	if run_entry.active:
		run_entry.motion(delta)
		return
	var world = start_basis * pending_root * float(data.actor_scale)
	fighter.velocity.x = world.x / maxf(delta, 0.00001)
	fighter.velocity.z = world.z / maxf(delta, 0.00001)
	pending_root = Vector3.ZERO

func finish() -> void:
	run_entry.reset()
	active = false
	ready = true
	pending_strike.clear()
	fighter._idle()

func play_ready() -> void:
	family_hit.finish()
	fighter.combat_motion.influence = 0.0
	fighter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	var key: String = fighter.animation_names[data.idle_clip]
	fighter.animation_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
	fighter.animation_player.speed_scale = 1.0
	fighter.animation_player.play(key, 0.075, 1.0)
	fighter.current_clip = "Idle"

func legacy_clip() -> void:
	reset()
	fighter.combat_motion.influence = 1.0
	fighter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

func queue_strike(profile: Dictionary) -> void:
	pending_strike = profile.duplicate(true)
	pending_strike["source_sample_time"] = last_time
	pending_strike["source_sample_tick"] = Engine.get_physics_frames()

func post_move() -> void:
	if run_entry.active:
		run_entry.solve_after_move()
		sync_weapon()
		if fighter.action_time >= run_entry.duration:
			run_entry.finish()
			_begin_source(RunEntry.SOURCE_START)
	if pending_strike.is_empty(): return
	sync_weapon()
	var profile = pending_strike.duplicate(true)
	pending_strike.clear()
	if active and fighter.state == "attack" and not fighter.hit_landed:
		fighter.strike_requested.emit(fighter, profile)

func status() -> Dictionary:
	return {"enabled": enabled, "active": active, "ready": ready, "time": last_time, "pending_root": pending_root, "queued_strike": not pending_strike.is_empty(), "family_hit":family_hit.status(), "run_entry":run_entry.status()}

func play_family_hit(duration: float) -> void:
	var source_time = run_entry.reaction_source_time() if run_entry.active else last_time
	var from_active = active
	run_entry.reset()
	active = false
	ready = true
	last_time = 0.0
	pending_root = Vector3.ZERO
	pending_strike.clear()
	family_hit.play(duration, source_time, from_active)
	sync_weapon()

func can_play_family_hit() -> bool:
	# First75ms is the old-to-K AnimationPlayer blend; Ready and the released
	# cut keep legacy reactions. Source preparation ends at .30, not active.x.
	if not enabled or not active:return false
	if run_entry.active:
		var preparation_time=run_entry.reaction_source_time()
		return preparation_time>=0.10 and preparation_time<=FamilyHit.PREPARATION_END and family_hit.prefix_matches_incoming(preparation_time)
	return last_time>=0.075 and last_time<=FamilyHit.PREPARATION_END and family_hit.prefix_matches_incoming(last_time)
