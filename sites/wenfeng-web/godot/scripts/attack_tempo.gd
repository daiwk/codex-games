extends RefCounted

## Project-tuned action phrasing, not timings extracted from another game.
## Source resources are read-only. Hips/legs stay on their original clock so
## their planted-foot counter-motion still matches the controller's lunge.
## Only Spine and above are rephrased. The entire physical contact interval and
## a 50 ms margin on either side keep their original pose/time correspondence.
const CONTACT_GUARD_SECONDS = 0.05
const LIGHT_HOLD_SECONDS = 0.04
const HEAVY_HOLD_SECONDS = 0.06
const SAMPLE_RATE = 60.0
const POSE_TRACKS = [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]
static var _variants: Dictionary = {}

static func profile_for(source: Animation, duration: float, active: Vector2, heavy: bool) -> Dictionary:
	var length = source.length
	var scale = length / maxf(duration, 0.001)
	var left = clampf((active.x - CONTACT_GUARD_SECONDS) * scale, 0.0, length)
	var right = clampf((active.y + CONTACT_GUARD_SECONDS) * scale, left, length)
	var hold = minf((HEAVY_HOLD_SECONDS if heavy else LIGHT_HOLD_SECONDS) * scale, (length - right) * 0.20)
	return {"length": length, "duration": duration, "active": active,
		"left": left, "right": right, "hold": hold,
		"exponent": 2.35 if heavy else 1.75, "scope": "upper_body"}

static func retimes_track(source: Animation, track: int) -> bool:
	var path = source.track_get_path(track)
	if path.get_subname_count() == 0:
		return false
	var bone = String(path.get_subname(path.get_subname_count() - 1))
	# Imported Mixamo prefixes may contain ':' or '_'; match the anatomy after
	# the NodePath separator. This includes the complete finger branches.
	for part in ["Spine", "Neck", "Head", "Shoulder", "Arm", "Hand"]:
		if bone.contains(part):
			return true
	return false

static func source_at_action_time(action_time: float, profile: Dictionary) -> float:
	var length = float(profile.length)
	var clock = clampf(action_time / maxf(float(profile.duration), 0.001), 0.0, 1.0) * length
	var left = float(profile.left)
	var right = float(profile.right)
	if clock < left and left > 0.000001:
		return left * pow(clock / left, float(profile.exponent))
	if clock <= right:
		return clock
	var hold_end = right + float(profile.hold)
	if clock <= hold_end:
		return right
	var recovery = length - hold_end
	if recovery <= 0.000001:
		return length
	var progress = clampf((clock - hold_end) / recovery, 0.0, 1.0)
	return lerpf(right, length, progress * progress * (3.0 - 2.0 * progress))

static func remap_key_time(source_time: float, profile: Dictionary) -> float:
	# Inverse of source_at_action_time in the source clip's time units. The
	# repeated right/hold-end pose below supplies the deliberate recovery hold.
	var left = float(profile.left)
	var right = float(profile.right)
	var length = float(profile.length)
	if source_time < left and left > 0.000001:
		return left * pow(maxf(0.0, source_time / left), 1.0 / float(profile.exponent))
	if source_time <= right or length - right <= 0.000001:
		return source_time
	var progress = clampf((source_time - right) / (length - right), 0.0, 1.0)
	var inverse_smoothstep = 0.5 - sin(asin(clampf(1.0 - 2.0 * progress, -1.0, 1.0)) / 3.0)
	return right + float(profile.hold) + (length - right - float(profile.hold)) * inverse_smoothstep

static func _pose_value(source: Animation, track: int, time: float) -> Variant:
	match source.track_get_type(track):
		Animation.TYPE_POSITION_3D:
			return source.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return source.rotation_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			return source.scale_track_interpolate(track, time)
	return null

static func _can_retime(source: Animation) -> bool:
	for track in source.get_track_count():
		# Arbitrary property/event/Bezier/compressed tracks need their own
		# treatment. Never silently move gameplay events or alter cubic contact.
		if source.track_get_type(track) not in POSE_TRACKS or source.track_is_compressed(track):
			return false
		if source.track_get_interpolation_type(track) != Animation.INTERPOLATION_LINEAR:
			return false
		for key in source.track_get_key_count(track):
			if not is_equal_approx(source.track_get_key_transition(track, key), 1.0):
				return false
	return true

static func variant(source: Animation, duration: float, active: Vector2, heavy: bool) -> Dictionary:
	var key = "upper_v2_%d_%d_%d_%d_%d" % [source.get_instance_id(), roundi(duration * 100000.0),
		roundi(active.x * 100000.0), roundi(active.y * 100000.0), 1 if heavy else 0]
	if _variants.has(key):
		return _variants[key]
	var profile = profile_for(source, duration, active, heavy)
	if duration <= 0.0 or source.length <= 0.0 or not _can_retime(source):
		return {"key": key, "animation": source, "profile": {}}
	var result = source.duplicate(true) as Animation
	for track in source.get_track_count():
		if not retimes_track(source, track):
			continue
		var rows: Array[Dictionary] = []
		for index in source.track_get_key_count(track):
			var time = source.track_get_key_time(track, index)
			rows.append({"time": remap_key_time(time, profile), "value": source.track_get_key_value(track, index), "priority": 2})
		for time in [0.0, profile.left, profile.right, float(profile.right) + float(profile.hold), source.length]:
			var source_time = source_at_action_time(float(time) * duration / source.length, profile)
			rows.append({"time": float(time), "value": _pose_value(source, track, source_time), "priority": 1})
		# Extra pose samples outside contact keep the acceleration/settle curve
		# smooth even when the authored source has sparse or optimized keys.
		for index in ceili(duration * SAMPLE_RATE) + 1:
			var action_time = minf(float(index) / SAMPLE_RATE, duration)
			var time = action_time * source.length / duration
			if time >= float(profile.left) and time <= float(profile.right):
				continue
			rows.append({"time": time, "value": _pose_value(source, track, source_at_action_time(action_time, profile)), "priority": 0})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
		var unique: Array[Dictionary] = []
		for row in rows:
			if not unique.is_empty() and absf(float(row.time) - float(unique[-1].time)) < 0.0000001:
				if int(row.priority) > int(unique[-1].priority):
					unique[-1] = row
			else:
				unique.append(row)
		for index in range(result.track_get_key_count(track) - 1, -1, -1):
			result.track_remove_key(track, index)
		for row in unique:
			result.track_insert_key(track, float(row.time), row.value)
	# Keep a reference to the original as well: no resource ID can be recycled
	# into a different source while this shared immutable variant is cached.
	var entry = {"key": key, "animation": result, "profile": profile, "source": source}
	_variants[key] = entry
	return entry
