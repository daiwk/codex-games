extends RefCounted

const META = "res://assets/motion/guanyu_crescent.json"
const ALIASES = [
	"GuanCrescentJ1", "GuanCrescentJ2", "GuanCrescentJ3", "GuanCrescentJ4",
	"GuanCrescentK", "GuanCrescentQ", "GuanCrescentE", "GuanCrescentUCharge", "GuanCrescentU",
]

var fighter
var enabled = false
var clips: Dictionary = {}

func setup(owner_fighter) -> void:
	fighter = owner_fighter
	if fighter.mounted or fighter.character_id != "guanyu" or fighter.weapon_id != "guandao":
		return
	if not FileAccess.file_exists(META):
		return
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(META))
	if not metadata is Dictionary or not metadata.get("clips") is Dictionary:
		return
	var imported: Dictionary = metadata.clips
	for alias in ALIASES:
		if not fighter.animation_names.has(alias) or not imported.get(alias) is Dictionary:
			return
		var clip: Dictionary = imported[alias]
		if float(clip.get("duration", 0.0)) <= 0.0:
			return
		for key in ["edge", "root"]:
			if not clip.get(key) is Array or clip[key].is_empty():
				return
	clips = imported
	enabled = true

func owns(clip: String) -> bool:
	return enabled and clips.has(clip)

func _sample(rows: Array, seconds: float, duration: float) -> Vector3:
	var position = clampf(seconds / duration, 0.0, 1.0) * float(rows.size() - 1)
	var begin = int(position)
	var first: Array = rows[begin]
	var second: Array = rows[mini(begin + 1, rows.size() - 1)]
	return Vector3(first[0], first[1], first[2]).lerp(Vector3(second[0], second[1], second[2]), position - float(begin))

func root_delta(clip: String, previous_time: float, current_time: float) -> Vector3:
	if not owns(clip):
		return Vector3.ZERO
	var data: Dictionary = clips[clip]
	return _sample(data.root, current_time, data.duration) - _sample(data.root, previous_time, data.duration)

func apply_grip() -> bool:
	if not enabled:
		return false
	var alias: String = fighter.current_clip
	if not owns(alias) or fighter.state not in ["attack", "skill", "ultimate"]:
		return false
	# The axis remains a line through the actual two gloves even during a
	# clip blend. The baked curve rolls only around that real cylindrical shaft.
	var right: Vector3 = fighter.palm_position(false)
	var left: Vector3 = fighter.palm_position(true)
	var axis = left - right
	if axis.length_squared() < 0.001:
		return false
	axis = axis.normalized()
	var data: Dictionary = clips[alias]
	var clock: float = fighter.animation_player.current_animation_position
	var edge = fighter.global_basis * _sample(data.edge, clock, data.duration)
	edge = edge.slide(axis)
	if edge.length_squared() < 0.001:
		return false
	var side: Vector3 = -edge.normalized()
	fighter.grip.global_transform = Transform3D(Basis(side, axis, side.cross(axis)), right)
	fighter.grip_roll_ready = true
	return true
