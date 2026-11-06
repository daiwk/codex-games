extends Node3D

## The charge follows the equipped spearhead. Only the wake and the contact
## discharge stay in world space as the fighter continues moving.
const ElectricShader = preload("res://assets/vfx/duel/thunder_spear.gdshader")
const GOLD = Color("eaa34f")
const PALE_GOLD = Color("ffe0a0")
const TRAIL_LIFE = 0.18
const MAX_SAMPLES = 13
const MAX_DISCHARGES = 4

class Sample:
	var tip: Vector3
	var axis: Vector3
	var movement: Vector3
	var age := 0.0
	var power: float
	var connected: bool

class Discharge:
	var origin: Vector3
	var heading: Vector3
	var age := 0.0
	var birth_clock := -1.0
	var contact: bool
	var beat: int
	var seed: int

var _fighter: WeakRef
var _mesh := ImmediateMesh.new()
var _light: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _samples: Array[Sample] = []
var _discharges: Array[Discharge] = []
var _camera_at: Vector3
var _drawing := false
var _tip: Vector3
var _axis: Vector3
var _clock := -1.0
var _beat := -1
var _charge := 0.0
var _released := false
var _serial := 0

static func eligible(fighter: DuelFighter) -> bool:
	return is_instance_valid(fighter) and not fighter.mounted and fighter.is_thrust_weapon()

static func active(fighter: DuelFighter) -> bool:
	return eligible(fighter) and fighter.attack.get("thunder_spear", false)

func attach(fighter: DuelFighter) -> void:
	_fighter = weakref(fighter)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 20
	process_physics_priority = 20
	top_level = true
	global_transform = Transform3D.IDENTITY
	var streaks := MeshInstance3D.new()
	streaks.name = "ThunderSpearElectricity"
	streaks.mesh = _mesh
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = ElectricShader
	streaks.material_override = material
	add_child(streaks)
	_light = OmniLight3D.new()
	_light.name = "ThunderSpearFlash"
	_light.light_color = PALE_GOLD
	_light.omni_attenuation = 1.7
	_light.hide()
	add_child(_light)
	RenderingServer.frame_pre_draw.connect(_sync_before_draw)

func clear() -> void:
	_mesh.clear_surfaces()
	_samples.clear()
	_discharges.clear()
	_charge = 0.0
	_beat = -1
	_clock = -1.0
	_released = false
	_light.hide()

func impact(at: Vector3, direction: Vector3, beat: int) -> void:
	# The short release spark previews the motion on a whiff. A contact on
	# this same beat replaces that preview with one burst at the actual hit.
	if not _discharges.is_empty() and _discharges[-1].beat == beat and not _discharges[-1].contact:
		_discharges.pop_back()
	_add_discharge(at, direction, true, beat)

func _add_discharge(at: Vector3, direction: Vector3, contact: bool, beat: int, birth_clock := -1.0) -> void:
	var arc := Discharge.new()
	arc.origin = at
	arc.heading = direction.normalized()
	if arc.heading.is_zero_approx():
		arc.heading = Vector3.FORWARD
	arc.contact = contact
	arc.beat = beat
	arc.birth_clock = birth_clock
	_serial += 1
	arc.seed = 3167 + _serial * 271
	_discharges.append(arc)
	if _discharges.size() > MAX_DISCHARGES:
		_discharges.pop_front()

func _physics_process(delta: float) -> void:
	for sample in _samples:
		sample.age += delta
	while not _samples.is_empty() and _samples[0].age >= TRAIL_LIFE:
		_samples.pop_front()
	var fighter := _fighter.get_ref() as DuelFighter
	if not is_instance_valid(fighter) or not fighter.is_inside_tree():
		queue_free()
		return
	_charge = 0.0
	if not fighter.enabled or fighter.state not in ["attack", "skill"] or not active(fighter):
		_clock = -1.0
		_beat = -1
		return
	var clock: float = fighter.action_time
	var tip := fighter.blade_tip()
	var axis := (tip - fighter.blade_base()).normalized()
	if axis.is_zero_approx():
		axis = fighter.forward()
	var hits: Array = fighter.attack.get("hits", [fighter.attack])
	var selected := -1
	for index in hits.size():
		var window: Vector2 = hits[index].active
		if clock >= window.x - 0.25 and clock <= window.y + 0.032:
			selected = index
			break
	var new_beat := selected != _beat or clock < _clock
	if new_beat:
		_released = false
	if selected >= 0:
		var window: Vector2 = hits[selected].active
		var movement := tip - _tip
		var speed := movement.length() / delta
		if clock < window.x:
			_charge = smoothstep(window.x - 0.25, window.x - 0.04, clock)
		if not new_beat and speed > 2.3 and movement.length() < 0.95 and clock > window.x - 0.12:
			var power := lerpf(0.32, 1.0, smoothstep(2.3, 9.0, speed))
			var continuous := not _samples.is_empty() and _samples[-1].age <= delta * 1.25
			_push_sample(tip, axis, movement.normalized(), power, continuous)
		if not _released and clock >= window.x and (movement.dot(axis) > 0.05 or clock >= window.x + 0.045):
			_released = true
			if _discharges.is_empty() or not _discharges[-1].contact or _discharges[-1].beat != selected:
				_add_discharge(tip, axis, false, selected, clock)
	_clock = clock
	_beat = selected
	_tip = tip
	_axis = axis

func _push_sample(tip: Vector3, axis: Vector3, movement: Vector3, power: float, connected: bool) -> void:
	var sample := Sample.new()
	sample.tip = tip
	sample.axis = axis
	sample.movement = movement
	sample.power = power
	sample.connected = connected
	_samples.append(sample)
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()

func _process(delta: float) -> void:
	for arc in _discharges:
		arc.age += delta
	while not _discharges.is_empty() and _discharges[0].age >= 0.27:
		_discharges.pop_front()
	_sync_weapon_pose(false)
	_render()

func _sync_before_draw() -> void:
	# A final skeleton modifier can move the hands after Node._process. Pin
	# just the visible lead and the release's first frame to that final pose.
	if is_inside_tree() and not get_tree().paused and _sync_weapon_pose(true):
		_render()

func _sync_weapon_pose(presented: bool) -> bool:
	if _clock < 0.0:
		return false
	var fighter := _fighter.get_ref() as DuelFighter
	if not is_instance_valid(fighter) or fighter.action_time != _clock:
		return false
	var tip := fighter.blade_tip()
	var axis := (tip - fighter.blade_base()).normalized()
	if axis.is_zero_approx():
		axis = _axis
	var moved := not _tip.is_equal_approx(tip) or not _axis.is_equal_approx(axis)
	if not _samples.is_empty() and is_zero_approx(_samples[-1].age):
		_samples[-1].tip = tip
		_samples[-1].axis = axis
	if not _discharges.is_empty() and _discharges[-1].birth_clock == _clock:
		var arc := _discharges[-1]
		arc.origin = tip
		arc.heading = axis
		if presented:
			arc.birth_clock = -1.0
	_tip = tip
	_axis = axis
	return moved

func _render() -> void:
	_update_light()
	if _mesh.get_surface_count() > 0:
		_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera) or (_samples.size() < 2 and _discharges.is_empty() and _charge <= 0.0):
		return
	_camera_at = camera.global_position
	_drawing = false
	_draw_wake()
	_draw_charge()
	for arc in _discharges:
		_draw_discharge(arc)
	if _drawing:
		_mesh.surface_end()

func _draw_wake() -> void:
	for i in range(1, _samples.size()):
		var old := _samples[i - 1]
		var fresh := _samples[i]
		if not fresh.connected:
			continue
		var fade := pow(1.0 - fresh.age / TRAIL_LIFE, 1.8) * fresh.power
		# For a lateral stroke, the amber shoulder opens behind the white tip.
		# On a straight thrust the shoulder collapses into a thin needle.
		var lateral := 1.0 - absf(fresh.axis.dot(fresh.movement))
		if lateral > 0.10:
			var old_span := old.axis * (0.36 * lateral)
			var new_span := fresh.axis * (0.36 * lateral)
			_quad(old.tip - old_span, old.tip + old_span * 0.06,
				fresh.tip - new_span, fresh.tip + new_span * 0.06, GOLD, fade * 0.22, 0.0)
		_segment(old.tip, fresh.tip, lerpf(0.033, 0.077, lateral), PALE_GOLD, fade * 0.80, 0.80)

func _draw_charge() -> void:
	if _charge <= 0.0:
		return
	var tick := int(_clock * 36.0)
	_rng.seed = 2291 + tick * 107 + _beat * 53
	var pulse := _rng.randf_range(0.44, 1.0) * _charge
	var from := _tip - _axis * 0.72
	var to := _tip + _axis * 0.07
	_bolt(from, to, 6, 0.095, 0.061, GOLD, pulse, 0.74)
	if pulse > 0.45:
		var side := _axis.cross(Vector3.UP).normalized()
		_bolt(_tip - _axis * 0.22, _tip + side * _rng.randf_range(-0.27, 0.27),
			4, 0.08, 0.045, PALE_GOLD, pulse * 0.64, 0.60)

func _draw_discharge(arc: Discharge) -> void:
	var life := 0.27 if arc.contact else 0.14
	var fade := pow(maxf(0.0, 1.0 - arc.age / life), 1.45)
	if fade < 0.015:
		return
	_rng.seed = arc.seed
	var size := (1.0 if arc.contact else 0.62) * lerpf(0.55, 1.0, smoothstep(0.0, 0.060, arc.age))
	var direction := arc.heading
	var side := direction.cross(Vector3.UP).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT
	var lift := side.cross(direction).normalized()
	var origin := arc.origin
	var lead := origin + direction * (1.14 * size)
	_bolt(origin - direction * (0.31 * size), lead, 8, 0.16 * size, 0.155 * size, PALE_GOLD, fade, 1.0)
	for index in (5 if arc.contact else 3):
		var base := origin.lerp(lead, _rng.randf_range(0.0, 0.38))
		var spread := side * _rng.randf_range(-0.75, 0.75) + lift * _rng.randf_range(-0.58, 0.65)
		var end := origin + (direction * _rng.randf_range(0.28, 0.91) + spread) * size
		_bolt(base, end, 5, 0.14 * size, 0.072 * size, GOLD, fade * 0.76, 0.87)
	if arc.contact:
		for index in 8:
			var scatter := direction * _rng.randf_range(0.0, 0.95) + side * _rng.randf_range(-1.0, 1.0) + lift * _rng.randf_range(-0.45, 0.80)
			var head := origin + scatter * (0.15 + arc.age * 5.5)
			head.y -= arc.age * arc.age * 3.0
			_segment(head - scatter * 0.09, head, 0.024, PALE_GOLD, fade * 0.67, 0.90)

func _bolt(from: Vector3, to: Vector3, steps: int, spread: float, width: float, tint: Color,
		alpha: float, core: float) -> void:
	var aim := (to - from).normalized()
	var side := aim.cross(Vector3.UP).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT
	var lift := side.cross(aim).normalized()
	var previous := from
	for index in range(1, steps + 1):
		var t := float(index) / steps
		var offset := side * _rng.randf_range(-1.0, 1.0) + lift * _rng.randf_range(-1.0, 1.0)
		var point := from.lerp(to, t) + offset * (spread * sin(t * PI))
		_segment(previous, point, width * lerpf(1.0, 0.32, t), tint, alpha * lerpf(1.0, 0.59, t), core)
		previous = point

func _segment(from: Vector3, to: Vector3, width: float, tint: Color, alpha: float, core: float) -> void:
	var side := (to - from).cross(_camera_at - (from + to) * 0.5).normalized() * width
	if not side.is_zero_approx():
		_quad(from - side, from + side, to - side, to + side, tint, alpha, core)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color, alpha: float, core: float) -> void:
	if not _drawing:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_drawing = true
	tint.a = alpha
	_mesh.surface_set_color(tint)
	_mesh.surface_set_uv(Vector2(0.0, core))
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_uv(Vector2(1.0, core))
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_uv(Vector2(0.0, core))
	_mesh.surface_add_vertex(c)
	_mesh.surface_set_uv(Vector2(0.0, core))
	_mesh.surface_add_vertex(c)
	_mesh.surface_set_uv(Vector2(1.0, core))
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_uv(Vector2(1.0, core))
	_mesh.surface_add_vertex(d)

func _update_light() -> void:
	_light.hide()
	for index in range(_discharges.size() - 1, -1, -1):
		var arc := _discharges[index]
		if arc.age >= 0.12 or (not arc.contact and _light.visible):
			continue
		_light.position = arc.origin
		_light.light_energy = (1.65 if arc.contact else 0.66) * pow(1.0 - arc.age / 0.12, 1.7)
		_light.omni_range = 2.65 if arc.contact else 1.5
		_light.show()
		if arc.contact:
			return
