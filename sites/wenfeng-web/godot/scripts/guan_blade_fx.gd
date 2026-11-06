extends Node3D

## Duel-only sweep reconstructed from the equipped blade. The oldest samples
## remain in the world as the fighter moves, and gaps never connect two blows.
const CutShader = preload("res://assets/vfx/duel/guan_blade.gdshader")
const MAX_SAMPLES = 19
const ROTARY_LIFE = 0.21
const TEAR_LIFE = 0.77
const TEAR_LENGTH = 5.55
const TEAR_HEIGHT = 4.55
const TEAR_ADVANCE = 2.75

signal tear_released(at: Vector3, direction: Vector3)

class BladeSample:
	var base: Vector3
	var tip: Vector3
	var lifetime: float
	var strength: float
	var style: String
	var age = 0.0
	var connected = false

var _fighter: WeakRef
var _ribbon: ImmediateMesh
var _tear: MeshInstance3D
var _tear_material: ShaderMaterial
var _tear_age = TEAR_LIFE
var _tear_origin = Vector3.ZERO
var _tear_heading = Vector3.FORWARD
var _floor: MeshInstance3D
var _floor_material: StandardMaterial3D
var _wake: MeshInstance3D
var _wake_material: ShaderMaterial
var _light: OmniLight3D
var _samples: Array[BladeSample] = []
var _previous_base = Vector3.ZERO
var _previous_tip = Vector3.ZERO
var _previous_clock = -1.0
var _previous_state = ""
var _previous_window = Vector2.ZERO
var _previous_style = ""
var _did_tear = false
var _tear_previous_tip = Vector3.ZERO
var _tear_previous_clock = -1.0

static func eligible(fighter: DuelFighter) -> bool:
	return is_instance_valid(fighter) and fighter.character_id == "guanyu" and fighter.weapon_id == "guandao" and not fighter.mounted

func attach(fighter: DuelFighter) -> void:
	_fighter = weakref(fighter)

func clear() -> void:
	_samples.clear()
	_ribbon.clear_surfaces()
	_previous_clock = -1.0
	_tear_previous_clock = -1.0
	_did_tear = false
	_hide_tear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 20
	process_physics_priority = 20
	top_level = true
	global_transform = Transform3D.IDENTITY
	_ribbon = ImmediateMesh.new()
	var material = ShaderMaterial.new()
	material.shader = CutShader
	_add_mesh("GuandaoTrackedEdge", _ribbon, material)
	_tear_material = ShaderMaterial.new()
	_tear_material.shader = CutShader
	_tear_material.set_shader_parameter("vertical_tear", true)
	_tear = _add_mesh("GuandaoVerticalTear", _tear_mesh(), _tear_material)
	_tear.hide()
	_wake_material = ShaderMaterial.new()
	_wake_material.shader = CutShader
	_wake_material.set_shader_parameter("ground_wake", true)
	_wake = _add_mesh("GuandaoGroundWake", _wake_mesh(), _wake_material)
	_wake.hide()
	_floor_material = StandardMaterial3D.new()
	_floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_floor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_floor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_floor_material.vertex_color_use_as_albedo = true
	_floor = _add_mesh("GuandaoGroundFracture", _fracture_mesh(), _floor_material)
	_floor.hide()
	_light = OmniLight3D.new()
	_light.name = "GuandaoJadeFlash"
	_light.light_color = Color("a9ffe0")
	_light.omni_range = 5.1
	_light.omni_attenuation = 1.7
	_light.hide()
	add_child(_light)

func _add_mesh(label: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _process(delta: float) -> void:
	# Physics stores the whole stroke, including skipped visual frames. The
	# visible front is pinned after the fighter's final skeleton update.
	if not _samples.is_empty() and is_zero_approx(_samples[-1].age):
		var fighter = _fighter.get_ref() as DuelFighter
		if is_instance_valid(fighter) and fighter.is_inside_tree() and fighter.state == _previous_state and fighter.action_time == _previous_clock:
			_samples[-1].base = fighter.blade_base()
			_samples[-1].tip = fighter.blade_tip()
	_draw_ribbon()
	_update_tear(delta)

func _physics_process(delta: float) -> void:
	var fighter = _fighter.get_ref() as DuelFighter
	if not is_instance_valid(fighter) or not fighter.is_inside_tree():
		queue_free()
		return
	for sample in _samples:
		sample.age += delta
	while not _samples.is_empty() and _samples[0].age >= _samples[0].lifetime:
		_samples.pop_front()
	var base = fighter.blade_base()
	var tip = fighter.blade_tip()
	_sample_blade(fighter, delta, base, tip)
	_sample_tear(fighter, base, tip)

func _active_beat(fighter: DuelFighter) -> Dictionary:
	if not fighter.enabled or fighter.state not in ["attack", "skill", "ultimate"] or not fighter.attack.get("guan_blade", false):
		return {}
	var beats: Array = fighter.attack.get("hits", [fighter.attack])
	for beat: Dictionary in beats:
		var window: Vector2 = beat.active
		if fighter.action_time >= window.x - 0.04 and fighter.action_time <= window.y + 0.035:
			return beat
	return {}

func _sample_blade(fighter: DuelFighter, delta: float, base: Vector3, tip: Vector3) -> void:
	var beat = _active_beat(fighter)
	var clock = fighter.action_time
	var reset = _previous_clock < 0.0 or clock < _previous_clock or fighter.state != _previous_state
	if reset:
		_previous_style = ""
	if not beat.is_empty() and not reset:
		var style = String(beat.get("guan_fx", fighter.attack.get("guan_fx", "heavy" if fighter.attack.get("heavy", false) else "light")))
		var window: Vector2 = beat.active
		var movement = tip - _previous_tip
		var speed = movement.length() / maxf(delta, 0.001)
		var clean_sample = movement.length() < 1.35 and base.distance_to(_previous_base) < 1.0
		if clean_sample and speed > 1.65:
			var strength = smoothstep(1.5, 10.0, speed)
			if _previous_style != style or _previous_window != window:
				_push_sample(_previous_base, _previous_tip, style, strength * 0.45, false)
			_push_sample(base, tip, style, strength, true)
		elif not clean_sample:
			style = ""
		_previous_window = window
		_previous_style = style
	else:
		_previous_style = ""
	_previous_state = fighter.state
	_previous_clock = clock
	_previous_base = base
	_previous_tip = tip

func _sample_tear(fighter: DuelFighter, base: Vector3, tip: Vector3) -> void:
	if not fighter.enabled or fighter.state != "ultimate":
		_did_tear = false
		_tear_previous_clock = -1.0
		return
	var clock = fighter.action_time
	if clock < _tear_previous_clock:
		_did_tear = false
	var movement = tip - _tear_previous_tip if _tear_previous_clock >= 0.0 else Vector3.ZERO
	_tear_previous_tip = tip
	_tear_previous_clock = clock
	if _did_tear or fighter.attack.get("guan_fx", "") != "dragon":
		return
	var window: Vector2 = fighter.attack.active
	# Sample the planted finish in physics even when the browser skips drawing
	# it. Older profiles without that marker still fire on a lethal contact.
	var ground_beat = float(fighter.attack.get("guan_ground_beat", (window.x + window.y) * 0.5))
	var early_finish = not fighter.attack.has("guan_ground_beat") and fighter.hit_landed \
		and is_instance_valid(fighter.opponent) and fighter.opponent.hp <= 0.0
	if clock + 0.0001 >= ground_beat or early_finish:
		_did_tear = true
		var contact = tip.lerp(base, 0.12) if tip.y <= base.y else base.lerp(tip, 0.15)
		_release_tear(contact, fighter.forward(), movement)

func _push_sample(base: Vector3, tip: Vector3, style: String, strength: float, connected: bool) -> void:
	var point = BladeSample.new()
	point.base = base
	point.tip = tip
	point.strength = strength
	point.connected = connected
	point.style = style
	point.lifetime = ROTARY_LIFE if style in ["rotary", "dragon"] else (0.145 if style in ["heavy", "counter"] else 0.11)
	_samples.append(point)
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()

func _draw_ribbon() -> void:
	_ribbon.clear_surfaces()
	if _samples.size() < 2:
		return
	var drawing = false
	for i in range(1, _samples.size()):
		var a = _samples[i - 1]
		var b = _samples[i]
		if not b.connected or a.age >= a.lifetime or b.age >= b.lifetime:
			continue
		if not drawing:
			_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drawing = true
		_ribbon_vertex(a, false)
		_ribbon_vertex(a, true)
		_ribbon_vertex(b, true)
		_ribbon_vertex(a, false)
		_ribbon_vertex(b, true)
		_ribbon_vertex(b, false)
	if drawing:
		_ribbon.surface_end()

func _ribbon_vertex(point: BladeSample, outer: bool) -> void:
	var age = point.age / point.lifetime
	var bright = point.style in ["dragon", "rotary"]
	var opacity = 0.87 if bright else (0.68 if point.style in ["heavy", "counter"] else 0.47)
	var inner = point.base.lerp(point.tip, 0.10 if bright else 0.38)
	_ribbon.surface_set_color(Color(0.91 if bright else 0.37, 0.0, 0.0, opacity * point.strength * pow(1.0 - age, 1.3)))
	_ribbon.surface_set_uv(Vector2(1.0 if outer else 0.0, age))
	_ribbon.surface_add_vertex(point.tip if outer else inner)

func _release_tear(blade_contact: Vector3, forward: Vector3, velocity: Vector3) -> void:
	_tear_age = 0.0
	_tear_origin = Vector3(blade_contact.x, 0.045, blade_contact.z)
	var motion = velocity.slide(Vector3.UP).normalized()
	_tear_heading = forward.slide(Vector3.UP).normalized()
	if motion.dot(_tear_heading) > 0.45:
		_tear_heading = _tear_heading.lerp(motion, 0.24).normalized()
	var frame = Basis(Vector3.UP.cross(_tear_heading), Vector3.UP, _tear_heading)
	_tear.global_transform = Transform3D(frame, _tear_origin)
	_floor.global_transform = _tear.global_transform
	_wake.global_transform = _tear.global_transform
	_tear.show()
	_floor.show()
	_wake.show()
	_light.show()
	_update_tear(0.0)
	tear_released.emit(_tear_origin, _tear_heading)

func _update_tear(delta: float) -> void:
	if not _tear.visible:
		return
	_tear_age += delta
	var age = _tear_age / TEAR_LIFE
	if age >= 1.0:
		_hide_tear()
		return
	_tear_material.set_shader_parameter("effect_age", age)
	_wake_material.set_shader_parameter("effect_age", age)
	# The lip travels in world space. Its body opens quickly down the same
	# heading, while dust trails back toward the original floor contact.
	var advance = TEAR_ADVANCE * (1.0 - pow(1.0 - age, 1.72))
	var opening = smoothstep(0.0, 0.23, age)
	var front = _tear_origin + _tear_heading * advance
	_tear.global_position = front
	_tear.scale = Vector3(1.0, lerpf(0.62, 1.0, opening), lerpf(0.34, 1.0, opening))
	_wake.global_position = _tear_origin + _tear_heading * advance * 0.58
	_wake.scale = Vector3(0.62 + age * 0.91, 0.94 + age * 0.90, 0.53 + opening * 0.62)
	_floor.scale.z = 0.52 + opening * 0.48
	_floor_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0 - smoothstep(0.52, 0.99, age))
	_light.global_position = front + _tear_heading * 0.55 + Vector3.UP * 0.84
	_light.light_energy = 1.50 * (1.0 - smoothstep(0.10, 0.82, age))

func _hide_tear() -> void:
	_tear.hide()
	_floor.hide()
	_wake.hide()
	_light.hide()

func _tear_mesh() -> ArrayMesh:
	var mesh = SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 18:
		for column in 12:
			var from = Vector2(float(column) / 12.0, float(row) / 18.0)
			var to = from + Vector2(1.0 / 12.0, 1.0 / 18.0)
			for uv: Vector2 in [from, Vector2(to.x, from.y), to, from, to, Vector2(from.x, to.y)]:
				var h = uv.y
				var d = uv.x
				var forward = h * 0.44 - sin(h * PI) * 0.19
				var depth = TEAR_LENGTH * (0.72 + sin(h * PI * 0.79) * 0.28)
				var height = h * TEAR_HEIGHT * (1.0 - 0.25 * d * d) + 0.025 * d
				var curl = h * 0.19 - sin(h * PI) * 0.13 + d * d * sin(h * 2.7 + 0.38) * 0.66
				mesh.set_uv(uv)
				mesh.add_vertex(Vector3(curl, height, forward + d * depth))
	return mesh.commit()

func _wake_mesh() -> ArrayMesh:
	var mesh = SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip in 3:
		for uv: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2.DOWN]:
			var spread = (uv.x - 0.5) * (3.7 + strip * 0.28)
			var height = 0.055 + uv.y * float(strip) * 0.16
			mesh.set_uv(uv)
			mesh.add_vertex(Vector3(spread, height, (uv.y - 0.18) * (5.05 + strip * 0.36)))
	return mesh.commit()

func _fracture_mesh() -> ArrayMesh:
	var mesh = SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng = RandomNumberGenerator.new()
	rng.seed = 62011
	for line in 9:
		var branch = float(line - 4)
		var origin = Vector3(0.0, 0.0, -0.52 + absf(branch) * 0.18)
		var target = Vector3(branch * rng.randf_range(0.25, 0.42), 0.0, rng.randf_range(2.6, 4.3) - absf(branch) * 0.42)
		var previous = origin
		for segment in range(1, 7):
			var t = float(segment) / 6.0
			var point = origin.lerp(target, t) + Vector3(rng.randf_range(-0.12, 0.12), 0, 0.0)
			var side = (point - previous).normalized().cross(Vector3.UP) * lerpf(0.070 if line == 4 else 0.030, 0.003, t)
			for vertex in [previous - side, previous + side, point + side * 0.64, previous - side, point + side * 0.64, point - side * 0.64]:
				mesh.set_color(Color(0.08, 0.11, 0.09, (1.0 - t * 0.48) * (0.86 if line == 4 else 0.65)))
				mesh.add_vertex(vertex)
			previous = point
	return mesh.commit()
