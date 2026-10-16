extends Node3D
class_name DuelSkillFX

# Effects stay independent of combat: a visible swing can still miss or be blocked.
# All geometry is cached and transparent layers are combined into a single mesh.
const MAX_EFFECTS = 24
const ULTIMATE_RADIUS = 3.8
const PALETTES = {
	"zhaoyun": [Color("49d5ee"), Color("e7fcff"), Color("2c8aa4")],
	"machao": [Color("ff9844"), Color("fff0ca"), Color("d44224")],
}

var active_effects: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _material_pool: Array[ShaderMaterial] = []
var _dust_material_pool: Array[ShaderMaterial] = []
var _shader: Shader
var _dust_shader: Shader
var _ultimate_strikes: Dictionary = {}


class MeshBuilder:
	extends RefCounted
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	var particle_centers = PackedVector2Array()
	var particle_lifts = PackedVector2Array()

	func triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color,
			particle_center = Vector3.ZERO, phase = 0.0) -> void:
		vertices.append_array(PackedVector3Array([a, b, c]))
		colors.append_array(PackedColorArray([ca, cb, cc]))
		var center = Vector2(particle_center.x, particle_center.z)
		var lift = Vector2(particle_center.y, phase)
		particle_centers.append_array(PackedVector2Array([center, center, center]))
		particle_lifts.append_array(PackedVector2Array([lift, lift, lift]))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		triangle(a, b, c, ca, cb, cc)
		triangle(a, c, d, ca, cc, cd)

	func finish() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = particle_centers
		arrays[Mesh.ARRAY_TEX_UV2] = particle_lifts
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_shader = Shader.new()
	_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;
uniform float effect_alpha : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * effect_alpha;
}
"""
	# Dust and stone use regular alpha blending so they have weight even without bloom.
	# A whole stone shower is one cached mesh; UV channels carry each stone's origin.
	_dust_shader = Shader.new()
	_dust_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
uniform float effect_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float effect_progress = 0.0;
uniform int particle_mode = 0;
void vertex() {
	if (particle_mode == 1) {
		float t = effect_progress;
		vec2 local = VERTEX.xz - UV;
		float angle = t * (UV2.y * 0.7 + 1.5);
		float c = cos(angle);
		float s = sin(angle);
		local = mat2(vec2(c, s), vec2(-s, c)) * local;
		float spread = 0.14 + 0.86 * sin(min(t / 0.8, 1.0) * 1.570796);
		VERTEX.xz = UV * spread + local;
		VERTEX.y += (t * 3.0 - t * t * 4.0) * (0.65 + UV2.x);
	} else if (particle_mode == 2) {
		VERTEX.y += 0.08 + sin(effect_progress * 7.0 + UV2.y) * 0.045 + effect_progress * 0.18;
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * effect_alpha;
}
"""


func play_skill(fighter: DuelFighter, skill: String, stage: String) -> void:
	if not is_instance_valid(fighter):
		return
	var owner_id = fighter.get_instance_id()
	if stage == "cancel":
		_remove_followers(owner_id)
		_ultimate_strikes.erase(owner_id)
		return
	var palette: Array = PALETTES.get(fighter.character_id, PALETTES.zhaoyun)
	var is_zhaoyun = fighter.character_id == "zhaoyun"
	# Ma Chao's ground warning stays visible between his raised blade and impact.
	if stage == "finish" or (stage == "release" and (skill != "ultimate" or is_zhaoyun)):
		_remove_followers(owner_id)
	match skill:
		"rush":
			if stage == "start":
				if is_zhaoyun:
					# A narrow wake records the takeoff point of his long forward thrust.
					_spawn(fighter, "thrust_wake", palette, 0.44, 0.08, Vector3.ONE, Vector3(1.0, 1.0, 1.3))
				else:
					_spawn(fighter, "armor_heat", palette, 0.85, 0.4, Vector3.ONE * 0.9, Vector3.ONE, true)
			elif stage in ["release", "strike"]:
				if is_zhaoyun:
					_spawn(fighter, "forward_thrust", palette, 0.31, 0.035, Vector3(0.75, 0.8, 0.92), Vector3.ONE)
				else:
					_spawn(fighter, "sweeping_cleave", palette, 0.42, 0.045, Vector3.ONE * 0.9, Vector3.ONE)
		"counter":
			if stage == "start":
				_remove_followers(owner_id)
				if is_zhaoyun:
					_spawn(fighter, "evade_echo", palette, 0.6, 0.02, Vector3.ONE, Vector3.ONE * 0.94)
					_spawn(fighter, "evade_wisps", palette, 1.35, 0.72, Vector3.ONE, Vector3.ONE, true)
				else:
					_spawn(fighter, "roar_breath", palette, 1.2, 0.4, Vector3.ONE * 0.7, Vector3.ONE, true)
			elif stage == "release":
				if is_zhaoyun:
					_spawn(fighter, "return_thrust", palette, 0.34, 0.025, Vector3(0.7, 0.8, 0.92), Vector3.ONE)
				else:
					_spawn(fighter, "roar_core", palette, 0.14, 0.015, Vector3.ONE * 0.75, Vector3.ONE)
					_spawn(fighter, "roar_wave", palette, 0.43, 0.04, Vector3(0.20, 1.0, 0.20), Vector3.ONE)
					_spawn(fighter, "roar_fractures", palette, 0.72, 0.10, Vector3.ONE, Vector3.ONE)
					_spawn(fighter, "roar_dust", palette, 0.68, 0.08, Vector3(0.26, 0.7, 0.26), Vector3.ONE)
					_spawn(fighter, "roar_sparks", palette, 0.48, 0.035, Vector3(0.2, 0.7, 0.2), Vector3.ONE)
			elif stage == "strike":
				if is_zhaoyun:
					_spawn(fighter, "return_thrust", palette, 0.34, 0.025, Vector3(0.7, 0.8, 0.92), Vector3.ONE)
		"ultimate":
			if stage == "start":
				_remove_followers(owner_id)
				_ultimate_strikes[owner_id] = 0
				if is_zhaoyun:
					_spawn(fighter, "chase_guides", palette, 1.35, 0.8, Vector3.ONE, Vector3.ONE, true)
					_spawn(fighter, "chase_charge", palette, 1.35, 0.8, Vector3.ONE * 0.8, Vector3.ONE, true)
				else:
					_spawn(fighter, "charge_rings", palette, 1.65, 1.28, Vector3.ONE * 0.78, Vector3.ONE, true)
					_spawn(fighter, "charge_wisps", palette, 1.65, 1.28, Vector3.ONE * 0.78, Vector3.ONE, true)
					_spawn(fighter, "charge_pebbles", palette, 1.65, 1.28, Vector3.ONE, Vector3.ONE, true)
					# The full 3.8 m area belongs only to the single ground impact.
					_spawn(fighter, "charge_threat", palette, 1.65, 1.28, Vector3.ONE, Vector3.ONE, true)
			elif stage == "release":
				if is_zhaoyun:
					_spawn(fighter, "thrust_wake", palette, 0.32, 0.03, Vector3.ONE, Vector3(1.0, 1.0, 1.2))
			elif stage == "strike":
				if is_zhaoyun:
					var strike = int(_ultimate_strikes.get(owner_id, 0))
					_ultimate_strikes[owner_id] = strike + 1
					var shape = "chase_cut_a" if strike % 2 == 0 else "chase_cut_b"
					_spawn(fighter, shape, palette, 0.25, 0.03, Vector3(0.85, 0.8, 0.92), Vector3.ONE)
			elif stage == "finish":
				if is_zhaoyun:
					_spawn(fighter, "chase_finish", palette, 0.46, 0.045, Vector3(0.82, 0.85, 0.94), Vector3.ONE)
				else:
					_spawn(fighter, "downward_cleave", palette, 0.32, 0.035, Vector3.ONE * 0.94, Vector3.ONE)
					_spawn(fighter, "slam_core", palette, 0.17, 0.015, Vector3.ONE * 0.85, Vector3.ONE)
					_spawn(fighter, "shockwave", palette, 0.55, 0.055, Vector3(0.13, 1.0, 0.13), Vector3.ONE)
					_spawn(fighter, "slam_fractures", palette, 1.32, 0.20, Vector3.ONE, Vector3.ONE)
					_spawn(fighter, "slam_scorch", palette, 1.50, 0.45, Vector3.ONE, Vector3.ONE)
					_spawn(fighter, "slam_dust", palette, 1.05, 0.10, Vector3(0.18, 0.65, 0.18), Vector3.ONE)
					_spawn(fighter, "slam_debris", palette, 0.95, 0.25, Vector3.ONE, Vector3.ONE)
					_spawn(fighter, "slam_sparks", palette, 0.72, 0.04, Vector3(0.16, 0.7, 0.16), Vector3.ONE)
				_ultimate_strikes.erase(owner_id)


func clear() -> void:
	for id in active_effects.keys():
		_finish_effect(id)
	_ultimate_strikes.clear()


func active_effect_count() -> int:
	return active_effects.size()


func _process(delta: float) -> void:
	for id in active_effects.keys():
		var effect: Dictionary = active_effects[id]
		if not is_instance_valid(effect.node):
			_finish_effect(id)
			continue
		effect.age += delta
		if effect.follow != null:
			var fighter = effect.follow.get_ref()
			if not is_instance_valid(fighter):
				_finish_effect(id)
				continue
			effect.node.global_position = fighter.global_position
			effect.node.global_rotation = Vector3(0.0, fighter.global_rotation.y, 0.0)
		if effect.shape == "charge_rings":
			effect.mesh.rotation.y = effect.age * 0.85
		elif effect.shape == "charge_wisps":
			effect.mesh.rotation.y = -effect.age * 1.2
			effect.mesh.position.y = sin(effect.age * 5.0) * 0.045
		elif effect.shape == "armor_heat" or effect.shape == "roar_breath":
			var pulse = 1.0 + sin(effect.age * 12.0) * 0.025
			effect.mesh.scale = Vector3.ONE * pulse
		elif effect.shape == "evade_wisps":
			effect.mesh.position = Vector3(-effect.age * 0.16, 0.0, -effect.age * 0.12)
		elif effect.shape == "chase_charge":
			effect.mesh.position.y = sin(effect.age * 10.0) * 0.035
		elif effect.shape in ["shockwave", "roar_wave"]:
			var t = clampf(effect.age / effect.lifetime, 0.0, 1.0)
			effect.mesh.scale.y = lerpf(1.0, 0.25, t)
		elif effect.shape in ["slam_dust", "roar_dust"]:
			effect.mesh.position.y = effect.age * 0.18
			effect.mesh.rotation.y = effect.age * 0.15
		elif effect.shape in ["slam_sparks", "roar_sparks"]:
			effect.mesh.position.y = effect.age * 0.25 - effect.age * effect.age * 0.8
		elif effect.shape in ["slam_debris", "charge_pebbles"]:
			effect.material.set_shader_parameter("effect_progress", clampf(effect.age / effect.lifetime, 0.0, 1.0))


func _spawn(fighter: DuelFighter, shape: String, palette: Array, lifetime: float, hold: float,
		start_scale: Vector3, end_scale: Vector3, follow = false) -> void:
	while active_effects.size() >= MAX_EFFECTS:
		_finish_effect(active_effects.keys()[0])
	var root = Node3D.new()
	root.name = "SkillFX_" + shape
	add_child(root)
	root.global_position = fighter.global_position
	root.global_rotation.y = fighter.global_rotation.y
	root.scale = start_scale
	var instance = MeshInstance3D.new()
	instance.mesh = _get_mesh(shape, fighter.character_id, palette)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shape in ["slam_debris", "charge_pebbles"]:
		instance.extra_cull_margin = 1.1
	var mat = _take_material(shape)
	instance.material_override = mat
	root.add_child(instance)
	var id = root.get_instance_id()
	var tween = root.create_tween().set_parallel(true)
	active_effects[id] = {"node": root, "mesh": instance, "material": mat, "tween": tween,
		"owner": fighter.get_instance_id(), "follow": weakref(fighter) if follow else null,
		"shape": shape, "age": 0.0, "lifetime": lifetime}
	tween.tween_property(root, "scale", end_scale, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_alpha.bind(id), 1.0, 0.0, maxf(0.01, lifetime - hold)).set_delay(hold).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_finish_effect.bind(id))


func _set_alpha(alpha: float, id: int) -> void:
	if active_effects.has(id):
		active_effects[id].material.set_shader_parameter("effect_alpha", alpha)


func _take_material(shape: String) -> ShaderMaterial:
	var mat: ShaderMaterial
	var is_dust = shape in ["slam_dust", "roar_dust", "slam_scorch", "slam_debris", "charge_pebbles"]
	var pool: Array[ShaderMaterial] = _dust_material_pool if is_dust else _material_pool
	if pool.is_empty():
		mat = ShaderMaterial.new()
		mat.shader = _dust_shader if is_dust else _shader
	else:
		mat = pool.pop_back()
	mat.set_shader_parameter("effect_alpha", 1.0)
	if is_dust:
		mat.set_shader_parameter("effect_progress", 0.0)
		mat.set_shader_parameter("particle_mode", 1 if shape == "slam_debris" else (2 if shape == "charge_pebbles" else 0))
	return mat


func _finish_effect(id: int) -> void:
	if not active_effects.has(id):
		return
	var effect: Dictionary = active_effects[id]
	active_effects.erase(id)
	if effect.tween != null and effect.tween.is_valid():
		effect.tween.kill()
	if is_instance_valid(effect.node):
		effect.node.visible = false
		effect.node.queue_free()
	var pool: Array[ShaderMaterial] = _dust_material_pool if effect.material.shader == _dust_shader else _material_pool
	if pool.size() < MAX_EFFECTS:
		pool.append(effect.material)


func _remove_followers(owner_id: int) -> void:
	for id in active_effects.keys():
		if active_effects[id].owner == owner_id and active_effects[id].follow != null:
			_finish_effect(id)


func _get_mesh(shape: String, character_id: String, palette: Array) -> ArrayMesh:
	var key = character_id + ":" + shape
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var b = MeshBuilder.new()
	var color: Color = palette[0]
	var bright: Color = palette[1]
	var dark: Color = palette[2]
	match shape:
		"thrust_wake":
			for i in 8:
				var side = -1.0 if i % 2 == 0 else 1.0
				var lane = float(i / 2)
				var x = side * (0.18 + lane * 0.065)
				var y = 0.46 + fmod(lane * 0.37, 0.95)
				_ribbon(b, Vector3(x, y, 0.30), Vector3(x * 1.18, y + 0.02, -1.4 - lane * 0.12), 0.017, _alpha(color, 0.55))
				_ribbon(b, Vector3(x, y, 0.27), Vector3(x * 1.18, y + 0.02, -1.0 - lane * 0.12), 0.005, _alpha(bright, 0.7))
		"forward_thrust", "return_thrust":
			var length = 3.10 if shape == "forward_thrust" else 2.70
			_lance(b, length, 0.225, 1.08, color, bright)
		"sweeping_cleave":
			# This broad forward crescent follows Ma Chao's actual 2.65 m sweep.
			_slash(b, 2.65, 0.21, -9.0, Vector3(0, 1.0, 0), color, bright)
			_slash(b, 2.28, 0.055, 11.0, Vector3(0, 0.91, 0), _alpha(dark, 0.55), bright)
		"armor_heat":
			for side in [-1.0, 1.0]:
				_ribbon(b, Vector3(side * 0.17, 1.1, 0.22), Vector3(side * 0.5, 1.48, 0.12), 0.07, _alpha(color, 0.3))
				_ribbon(b, Vector3(side * 0.19, 1.13, 0.23), Vector3(side * 0.46, 1.45, 0.13), 0.012, _alpha(bright, 0.4))
				_wisp(b, side * 1.2, 0.35, 0.72, _alpha(color, 0.42), _alpha(bright, 0.3))
		"evade_echo":
			# A thin body-shaped afterimage marks where the evasive step began.
			for side in [-1.0, 1.0]:
				_ribbon(b, Vector3(side * 0.19, 0.82, 0), Vector3(side * 0.34, 1.48, 0), 0.045, _alpha(color, 0.38))
				_ribbon(b, Vector3(side * 0.12, 0.92, 0), Vector3(side * 0.23, 0.13, -0.1), 0.035, _alpha(color, 0.3))
				_ribbon(b, Vector3(side * 0.31, 1.42, 0), Vector3(side * 0.50, 0.98, 0.12), 0.035, _alpha(bright, 0.27))
			_band(b, 0.14, 0.025, -1.4, 1.4, _pose(Vector3(0, 1.68, 0), 90.0), _alpha(bright, 0.32), 20)
		"evade_wisps":
			for i in 6:
				var y = 0.28 + i * 0.22
				_ribbon(b, Vector3(-0.10, y, 0.20), Vector3(0.62, y + 0.09, 0.92), 0.022, _alpha(color, 0.42))
				_ribbon(b, Vector3(-0.08, y, 0.20), Vector3(0.54, y + 0.07, 0.83), 0.006, _alpha(bright, 0.55))
		"roar_breath":
			for i in 8:
				_wisp(b, i * TAU / 8.0, 0.55, 0.95, _alpha(color, 0.75), bright)
			for i in 7:
				var x = (float(i) - 3.0) * 0.13
				_ribbon(b, Vector3(x * 0.45, 1.23, 0.20), Vector3(x, 1.55 + absf(x) * 0.4, 0.30), 0.022, _alpha(color, 0.34))
				_ribbon(b, Vector3(x * 0.45, 1.23, 0.20), Vector3(x * 0.9, 1.52 + absf(x) * 0.4, 0.30), 0.006, _alpha(bright, 0.42))
		"roar_wave":
			_wave_front(b, 2.75, 0.44, color, bright)
		"roar_fractures":
			_ground_rupture(b, 2.75, 11, _alpha(dark, 0.45), _alpha(bright, 0.75), false)
		"roar_core":
			_impact_core(b, 0.72, 0.75, color, bright)
		"roar_dust":
			_dust_cloud(b, 2.30, 6, 0.36, 0.50)
		"roar_sparks":
			_impact_rays(b, 2.70, 14, 0.65, color, bright)
		"chase_guides":
			# Parallel floor lines announce a directional chase, never a radial blast.
			for side in [-1.0, 1.0]:
				var x = side * 0.40
				_ribbon(b, Vector3(x, 0.045, 0.30), Vector3(x, 0.045, 3.10), 0.014, _alpha(color, 0.6))
				_ribbon(b, Vector3(x * 0.92, 0.049, 0.45), Vector3(x * 0.92, 0.049, 3.00), 0.004, _alpha(bright, 0.75))
				_ribbon(b, Vector3(x, 0.05, 3.10), Vector3(x - side * 0.14, 0.05, 2.82), 0.013, _alpha(bright, 0.65))
		"chase_charge":
			for i in 5:
				var x = (float(i) - 2.0) * 0.085
				_ribbon(b, Vector3(x, 0.83, 0.32), Vector3(x * 0.5, 1.25, 1.60 + absf(x)), 0.019, _alpha(color, 0.42))
				_ribbon(b, Vector3(x, 0.86, 0.34), Vector3(x * 0.5, 1.23, 1.50), 0.005, _alpha(bright, 0.6))
		"chase_cut_a", "chase_cut_b":
			var side = -1.0 if shape == "chase_cut_a" else 1.0
			var start = Vector3(side * 0.30, 1.40, 0.40)
			var end = Vector3(-side * 0.32, 0.76, 3.02)
			_ribbon(b, start, end, 0.14, _alpha(color, 0.8))
			_ribbon(b, start, end, 0.026, _alpha(bright, 0.98))
			_ribbon(b, start + Vector3(side * 0.16, -0.08, 0), end + Vector3(side * 0.10, -0.08, -0.10), 0.018, _alpha(color, 0.4))
		"chase_finish":
			_lance(b, 3.30, 0.25, 1.06, color, bright)
			_ribbon(b, Vector3(-0.46, 1.5, 1.12), Vector3(0.45, 0.64, 2.85), 0.075, _alpha(bright, 0.75))
		"charge_rings":
			var pose = _pose(Vector3(0, 0.038, 0))
			for i in 8:
				var a = i * TAU / 8.0
				_band(b, 0.92, 0.22, a, a + 0.44, pose, _alpha(color, 0.55), 10)
				_band(b, 0.99, 0.035, a + 0.04, a + 0.39, pose, _alpha(bright, 0.75), 9)
				var outer = Vector3(sin(a + 0.1), 0.046, cos(a + 0.1)) * Vector3(1.45, 1.0, 1.45)
				var inner = Vector3(sin(a + 0.34) * 0.5, 0.09, cos(a + 0.34) * 0.5)
				_ribbon(b, outer, inner, 0.065, _alpha(color, 0.58))
		"charge_wisps":
			for i in 9:
				_wisp(b, i * TAU / 9.0, 0.62 + float(i % 3) * 0.10, 1.40 + float(i % 2) * 0.35, color, bright, 0.060)
				var a = i * TAU / 9.0 + 0.2
				_ribbon(b, Vector3(sin(a) * 0.7, 0.10, cos(a) * 0.7), Vector3(sin(a + 0.3) * 0.43, 1.6, cos(a + 0.3) * 0.43), 0.026, _alpha(bright, 0.5))
		"charge_pebbles":
			for i in 12:
				var a = i * 2.39996
				var radius = 0.75 + float(i % 3) * 0.14
				var center = Vector3(sin(a) * radius, 0.12 + float(i % 4) * 0.08, cos(a) * radius)
				_stone(b, center, Vector3(0.07, 0.10, 0.06) * (0.7 + float(i % 3) * 0.2), a)
		"charge_threat":
			var pose = _pose(Vector3(0, 0.043, 0))
			for i in 24:
				var a = i * TAU / 24.0
				# The outside edge stays exactly at the combat radius.
				_band(b, ULTIMATE_RADIUS - 0.055, 0.11, a, a + 0.19, pose, _alpha(color, 0.40), 8)
				var tip = Vector3(sin(a + 0.09), 0, cos(a + 0.09)) * (ULTIMATE_RADIUS - 0.3)
				var left = Vector3(sin(a + 0.04), 0, cos(a + 0.04)) * (ULTIMATE_RADIUS - 0.1)
				var right = Vector3(sin(a + 0.14), 0, cos(a + 0.14)) * (ULTIMATE_RADIUS - 0.1)
				b.triangle(pose * tip, pose * left, pose * right, _alpha(bright, 0.0), _alpha(color, 0.36), _alpha(color, 0.36))
		"downward_cleave":
			# One vertical blade arc ends at the ground, followed by the radial wave.
			var pose = _pose(Vector3(0, 1.05, 0.45), 0.0, 90.0)
			_band(b, 1.9, 0.23, -0.80, 0.53, pose, _alpha(color, 0.88), 56)
			_band(b, 1.94, 0.035, -0.77, 0.50, pose, _alpha(bright, 0.98), 56)
			_ribbon(b, Vector3(0, 2.55, 0.60), Vector3(0, 0.06, 2.20), 0.14, _alpha(bright, 0.9))
		"slam_fractures":
			_ground_rupture(b, ULTIMATE_RADIUS, 17, _alpha(color, 0.8), bright, false)
		"slam_scorch":
			_ground_rupture(b, ULTIMATE_RADIUS, 17, Color(0.14, 0.09, 0.065, 0.65), Color(0.24, 0.14, 0.08, 0.3), true)
		"slam_core":
			_impact_core(b, 1.05, 1.55, color, bright)
		"slam_dust":
			_dust_cloud(b, 3.18, 8, 0.48, 0.83)
		"slam_debris":
			for i in 12:
				var a = i * 2.39996
				var radius = 1.1 + fmod(float(i) * 0.47, 2.10)
				var center = Vector3(sin(a) * radius, 0.08 + float(i % 4) * 0.07, cos(a) * radius)
				var size = 0.07 + float(i % 5) * 0.024
				_stone(b, center, Vector3(size, size * (1.05 + float(i % 3) * 0.3), size * 0.75), a)
		"slam_sparks":
			_impact_rays(b, 3.65, 14, 1.25, color, bright)
		"shockwave":
			_wave_front(b, ULTIMATE_RADIUS, 0.78, color, bright)
	var mesh = b.finish()
	_mesh_cache[key] = mesh
	return mesh


func _wave_front(b: MeshBuilder, radius: float, height: float, color: Color, bright: Color) -> void:
	# An asymmetric ridge has a broad hot face and a narrow pale crest. Its outer
	# edge matches the skill radius rather than implying a larger damage area.
	var radii = [radius - 0.65, radius - 0.48, radius - 0.25, radius - 0.16, radius - 0.07, radius]
	var heights = [0.035, 0.08, height * 0.76, height, 0.15, 0.035]
	var shades = [_alpha(color, 0.0), _alpha(color, 0.28), _alpha(color, 0.84),
		_alpha(bright, 0.98), _alpha(color, 0.65), _alpha(color, 0.0)]
	for i in 40:
		var a0 = float(i) * TAU / 40.0
		var a1 = float(i + 1) * TAU / 40.0
		var jag0 = 0.78 + 0.17 * sin(a0 * 9.0 + 0.3) + 0.08 * cos(a0 * 17.0)
		var jag1 = 0.78 + 0.17 * sin(a1 * 9.0 + 0.3) + 0.08 * cos(a1 * 17.0)
		for row in 5:
			var p0 = Vector3(sin(a0) * radii[row], heights[row] * jag0, cos(a0) * radii[row])
			var p1 = Vector3(sin(a0) * radii[row + 1], heights[row + 1] * jag0, cos(a0) * radii[row + 1])
			var p2 = Vector3(sin(a1) * radii[row + 1], heights[row + 1] * jag1, cos(a1) * radii[row + 1])
			var p3 = Vector3(sin(a1) * radii[row], heights[row] * jag1, cos(a1) * radii[row])
			b.quad(p0, p1, p2, p3, shades[row], shades[row + 1], shades[row + 1], shades[row])


func _impact_core(b: MeshBuilder, radius: float, height: float, color: Color, bright: Color) -> void:
	for i in 15:
		var a = float(i) * TAU / 15.0
		var length = radius * (0.68 + 0.3 * sin(float(i) * 2.71) * sin(float(i) * 2.71))
		var left = Vector3(sin(a - 0.10) * length, 0.07, cos(a - 0.10) * length)
		var right = Vector3(sin(a + 0.10) * length, 0.07, cos(a + 0.10) * length)
		b.triangle(Vector3(0, 0.09, 0), left, right, _alpha(bright, 0.9), _alpha(color, 0.0), _alpha(color, 0.0))
	for i in 8:
		var a = float(i) * TAU / 8.0 + 0.2
		var axis = Vector3(sin(a), 0, cos(a))
		var tangent = Vector3(cos(a), 0, -sin(a))
		var base = axis * radius * 0.26 + Vector3.UP * 0.1
		var tip = axis * radius * 0.42 + Vector3.UP * height * (0.45 + float(i % 3) * 0.21)
		var mid = base.lerp(tip, 0.28)
		b.triangle(base - tangent * 0.14, tip, base + tangent * 0.14, _alpha(color, 0.55), _alpha(color, 0), _alpha(color, 0.55))
		b.triangle(mid - tangent * 0.05, tip, mid + tangent * 0.05, _alpha(bright, 0.95), _alpha(bright, 0), _alpha(bright, 0.95))


func _ground_rupture(b: MeshBuilder, radius: float, count: int, color: Color, bright: Color, scorch: bool) -> void:
	var width = 0.055 if scorch else 0.022
	var y = 0.048 if scorch else 0.054
	for i in count:
		var a = float(i) * TAU / float(count) + 0.13
		var direction = Vector3(sin(a), 0, cos(a))
		var tangent = Vector3(cos(a), 0, -sin(a))
		var distance = radius * (0.74 + float(i % 4) * 0.075)
		var p0 = direction * 0.18 + Vector3.UP * y
		var p1 = direction * distance * 0.36 + tangent * 0.17 + Vector3.UP * y
		var p2 = direction * distance * 0.63 - tangent * 0.11 + Vector3.UP * y
		var p3 = direction * distance + tangent * 0.04 + Vector3.UP * y
		_ground_line(b, p0, p1, width * 1.8, color)
		_ground_line(b, p1, p2, width * 1.3, color)
		_ground_line(b, p2, p3, width * 0.7, _alpha(color, 0.75))
		if not scorch:
			_ground_line(b, p0, p1, 0.008, _alpha(bright, 0.65))
			_ground_line(b, p1, p2, 0.005, _alpha(bright, 0.5))
		var fork = direction * distance * 0.76 + tangent * (0.40 if i % 2 == 0 else -0.34) + Vector3.UP * y
		_ground_line(b, p1, fork, width * 0.6, _alpha(color, 0.65))
		if scorch:
			# Broken dark plates stay below the fighter's feet while embers fade.
			b.triangle(p0 + tangent * 0.08, p1 + tangent * 0.1, p1 - tangent * 0.15,
				_alpha(color, 0.25), _alpha(color, 0.55), _alpha(color, 0.3))


func _ground_line(b: MeshBuilder, start: Vector3, end: Vector3, width: float, color: Color) -> void:
	var across = (end - start).cross(Vector3.UP).normalized() * width
	# Joined strips read as a fracture rather than disconnected diamond particles.
	b.quad(start - across, end - across, end + across, start + across,
		_alpha(color, 0.7), _alpha(color, 0.7), color, color)


func _dust_cloud(b: MeshBuilder, radius: float, count: int, width: float, height: float) -> void:
	for i in count:
		var a = float(i) * TAU / float(count) + 0.11
		var distance = radius - float(i % 3) * 0.18
		var center = Vector3(sin(a) * distance, 0.04, cos(a) * distance)
		_dust_puff(b, center, width * (0.84 + float(i % 4) * 0.08), height * (0.62 + float(i % 3) * 0.16), a)
	# A few torn inner plumes connect the rim to the broken floor without a solid disc.
	for i in 7:
		var a = float(i) * 2.39996
		var center = Vector3(sin(a) * radius * 0.52, 0.04, cos(a) * radius * 0.52)
		_dust_puff(b, center, width * 0.6, height * 0.54, a)


func _dust_puff(b: MeshBuilder, center: Vector3, width: float, height: float, phase: float) -> void:
	var ring_radii = [0.7, 1.0, 0.7, 0.08]
	var ring_heights = [0.0, 0.25, 0.68, 1.0]
	var opacity = [0.0, 0.30, 0.22, 0.0]
	var base = Color("675541")
	var top = Color("ad916c")
	for row in 3:
		for i in 10:
			var a0 = float(i) * TAU / 10.0 + phase
			var a1 = float(i + 1) * TAU / 10.0 + phase
			var p0 = center + Vector3(sin(a0) * width * ring_radii[row], height * ring_heights[row], cos(a0) * width * ring_radii[row])
			var p1 = center + Vector3(sin(a0) * width * ring_radii[row + 1], height * ring_heights[row + 1], cos(a0) * width * ring_radii[row + 1])
			var p2 = center + Vector3(sin(a1) * width * ring_radii[row + 1], height * ring_heights[row + 1], cos(a1) * width * ring_radii[row + 1])
			var p3 = center + Vector3(sin(a1) * width * ring_radii[row], height * ring_heights[row], cos(a1) * width * ring_radii[row])
			var c0 = _alpha(base.lerp(top, float(row) / 3.0), opacity[row])
			var c1 = _alpha(base.lerp(top, float(row + 1) / 3.0), opacity[row + 1])
			b.quad(p0, p1, p2, p3, c0, c1, c1, c0)


func _stone(b: MeshBuilder, center: Vector3, size: Vector3, phase: float) -> void:
	var top = center + Vector3(size.x * 0.16, size.y * 0.74, size.z * 0.08)
	var bottom = center - Vector3(size.x * 0.1, size.y * 0.62, size.z * 0.15)
	var upper: Array[Vector3] = []
	var lower: Array[Vector3] = []
	for i in 5:
		var a = phase + float(i) * TAU / 5.0
		var rough = 0.82 + float(i % 3) * 0.08
		upper.append(center + Vector3(sin(a) * size.x * rough, size.y * (0.25 + float(i % 2) * 0.14), cos(a) * size.z * rough))
		lower.append(center + Vector3(sin(a + 0.16) * size.x, -size.y * (0.22 + float(i % 2) * 0.12), cos(a + 0.16) * size.z))
	for i in 5:
		var face_color = Color("75604b").lerp(Color("b79260"), float(i % 3) * 0.2)
		var next = (i + 1) % 5
		b.triangle(top, upper[i], upper[next], Color("ad9674"), face_color, face_color, center, phase)
		b.triangle(upper[i], lower[i], lower[next], face_color, face_color.darkened(0.25), face_color.darkened(0.25), center, phase)
		b.triangle(upper[i], lower[next], upper[next], face_color, face_color.darkened(0.25), face_color, center, phase)
		b.triangle(bottom, lower[next], lower[i], Color("322b25"), face_color.darkened(0.3), face_color.darkened(0.3), center, phase)


func _impact_rays(b: MeshBuilder, radius: float, count: int, height: float, color: Color, bright: Color) -> void:
	for i in count:
		var a = float(i) * 2.39996
		var distance = radius * (0.54 + float(i % 5) * 0.09)
		var direction = Vector3(sin(a), 0, cos(a))
		var y = height * (0.15 + float(i % 7) * 0.13)
		var end = direction * distance + Vector3.UP * y
		var start = end - direction * (0.20 + float(i % 3) * 0.11) - Vector3.UP * 0.10
		_ribbon(b, start, end, 0.038 if i % 3 == 0 else 0.018, _alpha(color, 0.8))
		_ribbon(b, start.lerp(end, 0.2), end, 0.010, _alpha(bright, 0.95))


func _alpha(color: Color, opacity: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * opacity)


func _pose(origin: Vector3, tilt_x = 0.0, tilt_z = 0.0) -> Transform3D:
	var basis = Basis(Vector3.FORWARD, deg_to_rad(tilt_z)) * Basis(Vector3.RIGHT, deg_to_rad(tilt_x))
	return Transform3D(basis, origin)


func _band(b: MeshBuilder, radius: float, width: float, start: float, end: float,
		pose: Transform3D, color: Color, segments: int) -> void:
	var is_ring = absf(end - start) > TAU - 0.01
	# Four radial rows produce a bright center and soft, fully transparent edges.
	var widths = [-0.5, -0.20, 0.20, 0.5]
	var opacity = [0.0, 1.0, 1.0, 0.0]
	for i in segments:
		var t0 = float(i) / segments
		var t1 = float(i + 1) / segments
		var a0 = lerpf(start, end, t0)
		var a1 = lerpf(start, end, t1)
		var edge0 = 1.0 if is_ring else pow(maxf(0.0, sin(PI * t0)), 0.65)
		var edge1 = 1.0 if is_ring else pow(maxf(0.0, sin(PI * t1)), 0.65)
		for row in 3:
			var r0 = radius + float(widths[row]) * width
			var r1 = radius + float(widths[row + 1]) * width
			var v0 = pose * Vector3(sin(a0) * r0, 0, cos(a0) * r0)
			var v1 = pose * Vector3(sin(a0) * r1, 0, cos(a0) * r1)
			var v2 = pose * Vector3(sin(a1) * r1, 0, cos(a1) * r1)
			var v3 = pose * Vector3(sin(a1) * r0, 0, cos(a1) * r0)
			b.quad(v0, v1, v2, v3, _alpha(color, opacity[row] * edge0),
				_alpha(color, opacity[row + 1] * edge0), _alpha(color, opacity[row + 1] * edge1),
				_alpha(color, opacity[row] * edge1))


func _slash(b: MeshBuilder, radius: float, width: float, tilt: float,
		at: Vector3, color: Color, bright: Color) -> void:
	var pose = _pose(at, 8.0, tilt)
	_band(b, radius, width, -1.45, 1.45, pose, _alpha(color, 0.75), 48)
	_band(b, radius + width * 0.19, width * 0.18, -1.39, 1.39, pose, _alpha(bright, 0.95), 48)
	_band(b, radius - width * 0.8, width * 0.24, -1.25, 1.25, pose, _alpha(color, 0.28), 40)


func _lance(b: MeshBuilder, length: float, half_width: float, height: float, color: Color, bright: Color) -> void:
	var start = Vector3(0, height, 0.35)
	var end = Vector3(0, height, length)
	_ribbon(b, start, end, half_width, _alpha(color, 0.78))
	_ribbon(b, start, end, half_width * 0.15, _alpha(bright, 0.98))
	# A second, upright blade plane keeps the thrust readable from a low camera.
	var mid = start.lerp(end, 0.35)
	var up = Vector3.UP * half_width * 0.55
	b.triangle(start, mid + up, mid - up, _alpha(color, 0.0), _alpha(color, 0.48), _alpha(color, 0.48))
	b.triangle(mid + up, end, mid - up, _alpha(color, 0.48), _alpha(bright, 0.15), _alpha(color, 0.48))
	for side in [-1.0, 1.0]:
		_ribbon(b, Vector3(side * half_width * 0.7, height, length - 0.52), end, 0.012, _alpha(bright, 0.9))


func _fractures(b: MeshBuilder, radius: float, count: int, color: Color, bright: Color) -> void:
	for i in count:
		var a = i * TAU / count + 0.11
		var direction = Vector3(sin(a), 0, cos(a))
		var tangent = Vector3(cos(a), 0, -sin(a))
		var start = direction * 0.28 + Vector3.UP * 0.052
		var mid = direction * radius * 0.56 + tangent * (0.12 if i % 2 == 0 else -0.12) + Vector3.UP * 0.052
		var end = direction * radius + Vector3.UP * 0.052
		_ribbon(b, start, mid, 0.022, _alpha(color, 0.56))
		_ribbon(b, mid, end, 0.016, _alpha(color, 0.44))
		_ribbon(b, start, mid, 0.005, _alpha(bright, 0.85))
		_ribbon(b, mid, end, 0.004, _alpha(bright, 0.72))
		if i % 2 == 0:
			var fork = direction * radius * 0.75 + tangent * 0.29 + Vector3.UP * 0.052
			_ribbon(b, mid, fork, 0.008, _alpha(color, 0.44))


func _ribbon(b: MeshBuilder, start: Vector3, end: Vector3, width: float, color: Color) -> void:
	var axis = end - start
	var across = axis.cross(Vector3.UP).normalized() * width
	if across.length_squared() < 0.000001:
		across = Vector3.RIGHT * width
	var mid = start.lerp(end, 0.22)
	var transparent = _alpha(color, 0.0)
	b.triangle(start, mid + across, mid - across, transparent, color, color)
	b.triangle(mid + across, end, mid - across, color, transparent, color)


func _wisp(b: MeshBuilder, angle: float, radius: float, height: float, color: Color, bright: Color, width = 0.018) -> void:
	for i in 12:
		var t0 = float(i) / 12.0
		var t1 = float(i + 1) / 12.0
		var a0 = angle + t0 * 0.85
		var a1 = angle + t1 * 0.85
		var r0 = radius * (1.0 - t0 * 0.18)
		var r1 = radius * (1.0 - t1 * 0.18)
		var p0 = Vector3(sin(a0) * r0, 0.07 + t0 * height, cos(a0) * r0)
		var p1 = Vector3(sin(a1) * r1, 0.07 + t1 * height, cos(a1) * r1)
		var tangent0 = Vector3(cos(a0), 0, -sin(a0)) * width
		var tangent1 = Vector3(cos(a1), 0, -sin(a1)) * width
		var c0 = _alpha(color.lerp(bright, t0), sin(PI * t0) * 0.72)
		var c1 = _alpha(color.lerp(bright, t1), sin(PI * t1) * 0.72)
		b.quad(p0 - tangent0, p0 + tangent0, p1 + tangent1, p1 - tangent1, c0, c0, c1, c1)
