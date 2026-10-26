extends RefCounted

# Duel-only whole-body phrasing. Feet, hips, waist and hands share one clock.
# Contact and its 50ms guard retain the complete authored pose exactly.
const SharedTempo = preload("res://scripts/attack_tempo.gd")
const MAX_VARIANTS = 64
static var _variants: Dictionary = {}
static var _recent: Array[String] = []

static func source_at_action_time(time: float, profile: Dictionary) -> float:
	return SharedTempo.source_at_action_time(time, profile)

static func variant(source: Animation, duration: float, active: Vector2, heavy: bool) -> Dictionary:
	var key = "duel_body_v1_%d_%d_%d_%d_%d" % [source.get_instance_id(), roundi(duration * 100000.0), roundi(active.x * 100000.0), roundi(active.y * 100000.0), int(heavy)]
	if _variants.has(key):
		_recent.erase(key)
		_recent.append(key)
		return _variants[key]
	if duration <= 0.0 or source.length <= 0.0 or not SharedTempo._can_retime(source):
		return {"key": key, "animation": source, "profile": {}}
	var profile = SharedTempo.profile_for(source, duration, active, heavy)
	profile["scope"] = "full_body"
	var result = source.duplicate(true) as Animation
	for track in source.get_track_count():
		var rows: Array[Dictionary] = []
		for index in source.track_get_key_count(track):
			var time = source.track_get_key_time(track, index)
			rows.append({"time": SharedTempo.remap_key_time(time, profile), "value": source.track_get_key_value(track, index), "priority": 2})
		for time in [0.0, profile.left, profile.right, float(profile.right) + float(profile.hold), source.length]:
			var original = source_at_action_time(float(time) * duration / source.length, profile)
			rows.append({"time": float(time), "value": SharedTempo._pose_value(source, track, original), "priority": 1})
		for index in ceili(duration * 60.0) + 1:
			var time = minf(float(index) / 60.0, duration)
			var clip_time = time * source.length / duration
			if clip_time >= float(profile.left) and clip_time <= float(profile.right): continue
			rows.append({"time": clip_time, "value": SharedTempo._pose_value(source, track, source_at_action_time(time, profile)), "priority": 0})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
		var unique: Array[Dictionary] = []
		for row in rows:
			if not unique.is_empty() and absf(float(row.time) - float(unique[-1].time)) < 0.0000001:
				if int(row.priority) > int(unique[-1].priority): unique[-1] = row
			else: unique.append(row)
		for index in range(result.track_get_key_count(track) - 1, -1, -1): result.track_remove_key(track, index)
		for row in unique: result.track_insert_key(track, float(row.time), row.value)
	var entry = {"key": key, "animation": result, "profile": profile, "source": source}
	_variants[key] = entry
	_recent.append(key)
	while _recent.size() > MAX_VARIANTS:
		_variants.erase(_recent.pop_front())
	return entry
