extends "res://scripts/skill_fx.gd"

# RPG-only presentation. These event-driven meshes never decide contacts, damage
# or resources. One batched mesh contains an entire shower, not one node/spark.
# Reference: DW Origins' weapon-specific Arts / readable Musou release rhythm.
const GOLD = Color("f6bd57")
const GOLD_WHITE = Color("fff1c3")
const PARTICLES_PER_BATCH = 32
const RPG_DUST = ["rpg_dust", "rpg_debris", "rpg_wake_dust"]
const RPG_PARTICLES = ["rpg_embers", "rpg_gather", "rpg_impact_sparks"]
var _event_counts: Dictionary = {}


func _ready() -> void:
	super._ready()
	# Compatibility/WebGL: vertex-colour light with a pale core and gold edge is
	# readable without HDR/bloom, textures, particles or scene-wide post effects.
	_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;
uniform float effect_alpha = 1.0;
uniform float effect_progress = 0.0;
uniform int particle_mode = 0;
void vertex() {
	if (particle_mode > 0) {
		vec3 centre = vec3(UV.x, UV2.x, UV.y);
		vec3 local = VERTEX - centre;
		float t = effect_progress;
		float a = UV2.y;
		if (particle_mode == 2) {
			float r = 1.0 - 0.76 * t;
			float turn = t * 1.3;
			vec2 p = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * centre.xz;
			VERTEX = vec3(p.x * r, mix(centre.y, 1.20, t), p.y * r) + local * (0.65 + 0.35 * sin(t * 3.14159));
		} else {
			vec3 velocity = vec3(sin(a) * (0.6 + mod(a, 0.7)), 0.45 + mod(a * 0.73, 1.0), cos(a) * (0.6 + mod(a, 0.7)));
			VERTEX += velocity * t * 1.1 - vec3(0.0, t * t * 0.8, 0.0);
		}
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * effect_alpha;
}
"""


func play_skill(fighter: DuelFighter, skill: String, stage: String) -> void:
	if not is_instance_valid(fighter) or not fighter.is_inside_tree() or not is_inside_tree():
		return
	var owner_id = fighter.get_instance_id()
	if stage == "cancel":
		# Interruptions also remove already launched skill layers, not just charge
		# followers. Independent contact sparks may finish their short lifetime.
		for id in active_effects.keys():
			if active_effects[id].owner == owner_id:
				_finish_effect(id)
		_ultimate_strikes.erase(owner_id)
		return
	if skill not in ["rush", "counter", "ultimate"]:
		super.play_skill(fighter, skill, stage)
		return
	if stage not in ["start", "release", "strike", "finish"]:
		return
	_event_counts[skill + ":" + stage] = int(_event_counts.get(skill + ":" + stage, 0)) + 1
	var palette: Array = PALETTES.get(fighter.character_id, PALETTES.zhaoyun)
	var blade = not fighter.is_thrust_weapon()
	if stage == "start":
		_remove_followers(owner_id)
	elif stage in ["release", "finish"]:
		_remove_followers(owner_id)
	match skill:
		"rush":
			if stage == "start":
				var windup = clampf(float(fighter.skill_profile(skill).active.x) + 0.035, 0.16, 0.7)
				_emit(fighter, "rpg_focus", palette, windup, windup * 0.60, Vector3.ONE * 0.85, Vector3.ONE, true)
				_emit(fighter, "rpg_gather", palette, windup, windup * 0.65, Vector3.ONE * 0.7, Vector3.ONE, true)
			elif stage in ["release", "strike"]:
				_weapon_release(fighter, palette, blade, false)
				_emit(fighter, "rpg_wake_dust", palette, 0.44, 0.035, Vector3(0.7, 0.6, 0.6), Vector3(1.05, 0.8, 1.0), false, true)
		"counter":
			if stage == "start":
				_emit(fighter, "rpg_wind", palette, 0.46, 0.08, Vector3.ONE * 0.74, Vector3.ONE * 1.08, true)
				_emit(fighter, "rpg_echo", palette, 0.40, 0.035, Vector3.ONE, Vector3.ONE)
			elif stage in ["release", "strike"]:
				_emit(fighter, "rpg_wind", palette, 0.34, 0.02, Vector3.ONE * 0.85, Vector3.ONE * 1.28)
				var radial = fighter.skill_profile(skill).get("kind", "") == "roar"
				if radial:
					_emit(fighter, "rpg_parry_ring", palette, 0.34, 0.025, Vector3.ONE * 0.45, Vector3.ONE, false, true)
					_emit(fighter, "rpg_embers", palette, 0.38, 0.02, Vector3.ONE, Vector3.ONE)
				else:
					_weapon_release(fighter, palette, blade, false)
		"ultimate":
			if stage == "start":
				_ultimate_strikes[owner_id] = 0
				var windup = clampf(fighter.ultimate_windup() + 0.10, 0.28, 2.0)
				_emit(fighter, "rpg_charge", palette, windup, windup * 0.72, Vector3.ONE * 0.76, Vector3.ONE, true)
				_emit(fighter, "rpg_gather", palette, windup, windup * 0.75, Vector3.ONE, Vector3.ONE, true)
				_emit(fighter, "rpg_charge_seal", palette, windup, windup * 0.75, Vector3.ONE, Vector3.ONE * 0.86, true, true)
			elif stage == "release":
				# The release beat precedes the first actual strike, so it is a
				# small expanding gold collar rather than a premature hit flash.
				_emit(fighter, "rpg_release", palette, 0.22, 0.015, Vector3.ONE * 0.65, Vector3.ONE * 1.05)
			elif stage in ["strike", "finish"]:
				var index = int(_ultimate_strikes.get(owner_id, 0))
				_ultimate_strikes[owner_id] = index + 1
				_weapon_release(fighter, palette, blade, stage == "finish", index)
				if stage == "finish":
					# A low, decorative pressure ring at the last forward strike;
					# this never implies a new radial damage/knockback mechanic.
					_emit(fighter, "rpg_final_ring", palette, 0.52, 0.025, Vector3.ONE * 0.30, Vector3.ONE, false, true, 2.0)
					_emit(fighter, "rpg_dust", palette, 0.65, 0.055, Vector3.ONE * 0.58, Vector3.ONE, false, true, 1.7)
					_emit(fighter, "rpg_debris", palette, 0.57, 0.035, Vector3.ONE, Vector3.ONE, false, true, 1.7)
					_ultimate_strikes.erase(owner_id)


func _weapon_release(fighter: DuelFighter, palette: Array, blade: bool, finish: bool, index = 0) -> void:
	var shape = "rpg_cleave" if blade else "rpg_lance"
	var life = 0.34 if finish else 0.27
	var start = Vector3(0.78, 0.90, 0.88) if not finish else Vector3(0.92, 1.0, 0.96)
	var end = Vector3(1.02, 1.0, 1.05) if not finish else Vector3(1.15, 1.08, 1.12)
	var id = _emit(fighter, shape, palette, life, 0.035, start, end)
	if active_effects.has(id):
		# Alternating narrow helix phases give each real hit a separate beat.
		active_effects[id].mesh.rotation.z = (0.06 if index % 2 == 0 else -0.06) if not blade else 0.0
	_emit(fighter, "rpg_embers", palette, 0.42 if finish else 0.31, 0.015, Vector3.ONE, Vector3.ONE)


func _emit(fighter: DuelFighter, shape: String, palette: Array, lifetime: float, hold: float,
		start_scale: Vector3, end_scale: Vector3, follow = false, ground = false, forward_offset = 0.0) -> int:
	_spawn(fighter, shape, palette, lifetime, hold, start_scale, end_scale, follow)
	var id: int = active_effects.keys().back()
	var effect: Dictionary = active_effects[id]
	if shape in RPG_PARTICLES or shape == "rpg_debris":
		effect.mesh.extra_cull_margin = 2.0
	effect["ground"] = ground
	effect["forward_offset"] = forward_offset
	if ground:
		effect.node.global_position = Vector3(fighter.global_position.x, 0.055, fighter.global_position.z) + fighter.forward() * forward_offset
	return id


# Root calls this only for actual impact_received events. A missed visual
# release cannot generate a contact flash. At most three batched meshes/event.
func impact(at: Vector3, outcome: String, direction = Vector3.FORWARD, strength = 1.0) -> void:
	if not is_inside_tree() or outcome in ["evade", "dead"]:
		return
	var guard = outcome in ["block", "parry", "counter", "break"]
	var color = Color("b6f7ed") if outcome in ["parry", "counter"] else GOLD
	var palette: Array = [color, GOLD_WHITE, Color("80562d")]
	var size = clampf(float(strength), 0.55, 1.6)
	_world_effect(at, direction, "rpg_impact_flash", palette, 0.15, Vector3.ONE * size)
	_world_effect(at, direction, "rpg_impact_sparks", palette, 0.38 if guard else 0.31, Vector3.ONE * size)
	if outcome in ["heavy_hit", "break", "counter"]:
		_world_effect(Vector3(at.x, 0.055, at.z), direction, "rpg_dust", palette, 0.44, Vector3.ONE * size * 0.6)


func _world_effect(at: Vector3, direction: Vector3, shape: String, palette: Array, lifetime: float, size: Vector3) -> void:
	while active_effects.size() >= MAX_EFFECTS:
		_finish_effect(active_effects.keys()[0])
	var node = Node3D.new()
	node.name = "RPGContact_" + shape
	add_child(node)
	node.global_position = at
	var flat = Vector2(direction.x, direction.z)
	node.global_rotation.y = atan2(flat.x, flat.y) if flat.length_squared() > 0.001 else 0.0
	node.scale = size
	var mesh = MeshInstance3D.new()
	mesh.mesh = _get_mesh(shape, "impact", palette)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 2.0
	var material = _take_material(shape)
	mesh.material_override = material
	node.add_child(mesh)
	var tween = node.create_tween().set_parallel(true)
	var id = node.get_instance_id()
	active_effects[id] = {"node": node, "mesh": mesh, "material": material, "tween": tween,
		"owner": 0, "follow": null, "shape": shape, "age": 0.0, "lifetime": lifetime}
	tween.tween_property(node, "scale", size * 1.25, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_alpha.bind(id), 1.0, 0.0, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_finish_effect.bind(id))


func _take_material(shape: String) -> ShaderMaterial:
	var dust = shape in RPG_DUST
	var pool: Array[ShaderMaterial] = _dust_material_pool if dust else _material_pool
	var material = pool.pop_back() if not pool.is_empty() else ShaderMaterial.new()
	material.shader = _dust_shader if dust else _shader
	material.set_shader_parameter("effect_alpha", 1.0)
	material.set_shader_parameter("effect_progress", 0.0)
	material.set_shader_parameter("particle_mode", 1 if shape == "rpg_debris" else (2 if shape == "rpg_gather" else (1 if shape in RPG_PARTICLES else 0)))
	return material


func _process(delta: float) -> void:
	super._process(delta)
	for owner_id in _ultimate_strikes.keys():
		if not is_instance_id_valid(owner_id):
			_ultimate_strikes.erase(owner_id)
	for id in active_effects.keys():
		var effect: Dictionary = active_effects[id]
		var shape: String = effect.shape
		if not shape.begins_with("rpg_"):
			continue
		var progress = clampf(float(effect.age) / float(effect.lifetime), 0.0, 1.0)
		effect.material.set_shader_parameter("effect_progress", progress)
		if effect.get("ground", false) and effect.follow != null:
			var fighter = effect.follow.get_ref()
			if is_instance_valid(fighter):
				effect.node.global_position = Vector3(fighter.global_position.x, 0.055, fighter.global_position.z) + fighter.forward() * float(effect.get("forward_offset", 0.0))
		if shape in ["rpg_charge", "rpg_focus", "rpg_wind"]:
			effect.mesh.rotation.y = float(effect.age) * (-2.4 if shape == "rpg_wind" else 1.8)
		elif shape == "rpg_charge_seal":
			effect.mesh.rotation.y = -float(effect.age) * 0.8
		elif shape in ["rpg_dust", "rpg_wake_dust"]:
			effect.mesh.position.y = float(effect.age) * 0.12
			effect.mesh.rotation.y = float(effect.age) * 0.10
		elif shape == "rpg_echo":
			effect.mesh.position.z = -float(effect.age) * 0.65


func clear() -> void:
	super.clear()
	_event_counts.clear()

func debug_state() -> Dictionary:
	var groups: Array = []
	for effect in active_effects.values():
		groups.append({"shape": effect.shape, "age": effect.age, "lifetime": effect.lifetime})
	return {"active": active_effect_count(), "groups": groups, "events": _event_counts.duplicate()}


func _exit_tree() -> void:
	clear()


func _get_mesh(shape: String, character_id: String, palette: Array) -> ArrayMesh:
	if not shape.begins_with("rpg_"):
		return super._get_mesh(shape, character_id, palette)
	# Impact colour is part of the cache key: a gold hit must not recolour a
	# later green parry. Six hero palettes share the same small shape vocabulary.
	var key = "rpg:" + character_id + ":" + shape + ":" + Color(palette[0]).to_html(false)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var b = MeshBuilder.new()
	var color: Color = palette[0]
	var bright: Color = palette[1]
	match shape:
		"rpg_lance":
			_lance(b, 3.05, 0.095, 1.08, color, bright)
			_helix(b, 0.35, 2.95, 1.08, 0.0, color, 0.026)
			_helix(b, 0.50, 2.98, 1.08, PI, color, 0.020)
			_ribbon(b, Vector3(-0.12, 1.08, 0.45), Vector3(0, 1.08, 3.08), 0.010, _alpha(GOLD_WHITE, 0.95))
			for side in [-1.0, 1.0]:
				_ribbon(b, Vector3(side * 0.25, 0.96, 0.15), Vector3(side * 0.09, 1.03, 2.65), 0.008, _alpha(GOLD, 0.75))
		"rpg_cleave":
			_slash(b, 2.60, 0.20, -14.0, Vector3(0, 1.05, 0), color, bright)
			_band(b, 2.73, 0.026, -1.30, 1.30, _pose(Vector3(0, 1.05, 0), 8, -14), _alpha(GOLD_WHITE, 0.95), 42)
			_band(b, 2.35, 0.040, -1.18, 1.10, _pose(Vector3(0, 1.05, 0), 8, -14), _alpha(GOLD, 0.60), 40)
		"rpg_focus", "rpg_charge":
			var charge = shape == "rpg_charge"
			for i in (5 if charge else 3):
				_wisp(b, float(i) * TAU / (5.0 if charge else 3.0), 0.70 if charge else 0.50, 1.50 if charge else 1.10, _alpha(GOLD, 0.62), GOLD_WHITE, 0.016)
			for side in [-1.0, 1.0]:
				_band(b, 0.54 if charge else 0.32, 0.018, -1.2, 1.2, _pose(Vector3(side * 0.30, 1.10, 0.30), 80, side * 30), _alpha(GOLD_WHITE, 0.75), 30)
		"rpg_gather":
			_sparks(b, PARTICLES_PER_BATCH, true, GOLD, GOLD_WHITE)
		"rpg_embers", "rpg_impact_sparks":
			_sparks(b, 24 if shape == "rpg_embers" else PARTICLES_PER_BATCH, false, GOLD, GOLD_WHITE, Vector3(0, 1.08, 2.30) if shape == "rpg_embers" else Vector3.ZERO)
		"rpg_wind":
			for i in 3:
				var offset = float(i) * 0.19
				_band(b, 0.85 + offset, 0.055 - float(i) * 0.01, -2.50 + offset, 1.85 + offset, _pose(Vector3(0, 0.98, 0.2), 66, 12), _alpha(color, 0.62 - float(i) * 0.12), 38)
			_band(b, 1.07, 0.014, -2.2, 1.4, _pose(Vector3(0, 0.98, 0.2), 66, 12), _alpha(GOLD_WHITE, 0.75), 38)
		"rpg_echo":
			for echo in 2:
				var z = -0.30 - float(echo) * 0.48
				var opacity = 0.26 - float(echo) * 0.08
				for side in [-1.0, 1.0]:
					_ribbon(b, Vector3(side * 0.18, 0.45, z), Vector3(side * 0.30, 1.43, z), 0.035, _alpha(color, opacity))
					_ribbon(b, Vector3(side * 0.32, 1.43, z), Vector3(side * 0.56, 1.03, z + 0.15), 0.025, _alpha(bright, opacity))
				_band(b, 0.14, 0.022, -1.7, 1.7, _pose(Vector3(0, 1.65, z), 90), _alpha(bright, opacity), 20)
		"rpg_charge_seal":
			for i in 8:
				var a = float(i) * TAU / 8.0
				_band(b, 1.02, 0.025, a, a + 0.50, _pose(Vector3(0, 0.01, 0)), _alpha(GOLD, 0.6), 10)
				var a0 = Vector3(sin(a) * 1.20, 0.01, cos(a) * 1.20)
				var a1 = Vector3(sin(a + 0.16) * 0.76, 0.01, cos(a + 0.16) * 0.76)
				_ground_line(b, a0, a1, 0.009, _alpha(GOLD_WHITE, 0.65))
		"rpg_release":
			_band(b, 0.57, 0.055, 0, TAU, _pose(Vector3(0, 1.10, 0.65), 90), _alpha(GOLD_WHITE, 0.8), 40)
		"rpg_parry_ring", "rpg_final_ring":
			var radius = 2.25 if shape == "rpg_parry_ring" else 1.85
			_band(b, radius, 0.10, 0, TAU, _pose(Vector3(0, 0.025, 0)), _alpha(color if shape == "rpg_parry_ring" else GOLD, 0.65), 56)
			_band(b, radius + 0.08, 0.020, 0, TAU, _pose(Vector3(0, 0.035, 0)), _alpha(GOLD_WHITE, 0.80), 56)
			for i in 14:
				var a = float(i) * TAU / 14.0
				var start = Vector3(sin(a) * (radius - 0.22), 0.02, cos(a) * (radius - 0.22))
				_ribbon(b, start, start * Vector3(0.7, 1, 0.7), 0.012, _alpha(GOLD, 0.5))
		"rpg_dust", "rpg_wake_dust":
			for i in 5:
				var a = float(i) * 2.39996
				var center = Vector3(sin(a) * 1.10, 0.04, cos(a) * 1.10)
				if shape == "rpg_wake_dust":
					center = Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.40, 0.04, -0.25 - float(i) * 0.25)
				_dust_puff(b, center, 0.40, 0.34 + float(i % 3) * 0.09, a)
		"rpg_debris":
			for i in 8:
				var a = float(i) * 2.39996
				var radius = 0.45 + float(i % 4) * 0.24
				var center = Vector3(sin(a) * radius, 0.08, cos(a) * radius)
				_stone(b, center, Vector3(0.055, 0.07, 0.045) * (0.75 + float(i % 3) * 0.15), a)
		"rpg_impact_flash":
			for i in 6:
				var a = float(i) * PI / 3.0
				var end = Vector3(sin(a) * (0.65 if i % 2 == 0 else 0.40), cos(a) * (0.65 if i % 2 == 0 else 0.40), 0)
				_ribbon(b, -end * 0.10, end, 0.025, _alpha(GOLD, 0.85))
				_ribbon(b, Vector3.ZERO, end * 0.65, 0.009, _alpha(GOLD_WHITE, 1.0))
			for plane in 2:
				var side = Vector3.RIGHT if plane == 0 else Vector3.BACK
				b.triangle(-side * 0.09, Vector3.UP * 0.13, side * 0.09, _alpha(bright, 0), bright, _alpha(bright, 0))
	var mesh = b.finish()
	_mesh_cache[key] = mesh
	return mesh


func _helix(b: MeshBuilder, start: float, end: float, height: float, phase: float, color: Color, width: float) -> void:
	for i in 36:
		var t0 = float(i) / 36.0
		var t1 = float(i + 1) / 36.0
		var a0 = phase + t0 * TAU * 1.55
		var a1 = phase + t1 * TAU * 1.55
		var r0 = sin(PI * t0) * 0.22
		var r1 = sin(PI * t1) * 0.22
		var p0 = Vector3(sin(a0) * r0, height + cos(a0) * r0, lerpf(start, end, t0))
		var p1 = Vector3(sin(a1) * r1, height + cos(a1) * r1, lerpf(start, end, t1))
		var tangent0 = Vector3(sin(a0), cos(a0), 0) * width
		var tangent1 = Vector3(sin(a1), cos(a1), 0) * width
		var c0 = _alpha(color, sin(PI * t0) * 0.65)
		var c1 = _alpha(color, sin(PI * t1) * 0.65)
		b.quad(p0 - tangent0, p0 + tangent0, p1 + tangent1, p1 - tangent1, c0, c0, c1, c1)


func _sparks(b: MeshBuilder, count: int, gather: bool, color: Color, bright: Color, at = Vector3.ZERO) -> void:
	for i in mini(count, PARTICLES_PER_BATCH):
		var a = float(i) * 2.39996
		var radius = (0.55 + float(i % 5) * 0.16) if gather else (0.03 + float(i % 4) * 0.035)
		var center = at + Vector3(sin(a) * radius, 0.15 + fmod(float(i) * 0.217, 1.5) if gather else float(i % 4) * 0.025, cos(a) * radius)
		var length = 0.035 + float(i % 3) * 0.020
		for plane in 2:
			var axis = Vector3.RIGHT if plane == 0 else Vector3.BACK
			var tip = center + Vector3.UP * length
			var bottom = center - Vector3.UP * length * 0.55
			b.triangle(tip, center - axis * 0.009, bottom, _alpha(bright, 0), _alpha(color, 0.95), _alpha(bright, 0), center, a)
			b.triangle(tip, bottom, center + axis * 0.009, _alpha(bright, 0), _alpha(bright, 0), _alpha(color, 0.95), center, a)
