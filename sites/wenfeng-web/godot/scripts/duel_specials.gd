extends Node3D

## Duel-only physical special effects. Every projectile/front travels before
## asking the owning combat controller to resolve its real contact outcome.
signal hit_requested(attacker: DuelFighter, defender: DuelFighter, data: Dictionary, point: Vector3)

const Roster = preload("res://scripts/roster.gd")
const CAVALRY_MESH = preload("res://assets/vfx/duel/cavalry_mesh.res")
const CAVALRY_POSES = preload("res://assets/vfx/duel/cavalry_poses.res")
const MAX_ENTITIES = 18
const MAX_GROUPS = 6
const PROJECTILE_TYPES = ["flying_blades", "returning_blade", "cavalry", "weapon_array"]
const WEAPON_LENGTHS = {"serpent_spear": 3.5, "guandao": 3.3, "halberd": 3.5, "xuchu_saber": 1.7, "saber": 1.4, "sword": 1.4}
const WEAPON_PATHS = {"flying_blades": "res://onehand_sword.glb"}
var groups: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _shader: Shader
var _cavalry_shader: Shader
var _trail_material: ShaderMaterial
var _flag_mesh: ArrayMesh
var _dust_mesh: QuadMesh
var _dust_material: StandardMaterial3D
var _nonce = 0
var _cast_keys: Dictionary = {}
var _events: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_shader = Shader.new()
	_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.35,0.8,1.0,1.0);
uniform float opacity = 1.0;
uniform float effect_time = 0.0;
varying float individual_alpha;
void vertex(){individual_alpha=INSTANCE_CUSTOM.a;}
void fragment(){
 float rim=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),1.8);
 float edge=mix(0.32,1.0,rim);
 ALBEDO=mix(tint.rgb*0.35,mix(tint.rgb,vec3(0.94,0.98,1.0),0.48),edge*0.45+0.55);
 EMISSION=tint.rgb*(0.12+rim*0.55);
 ALPHA=tint.a*opacity*individual_alpha*mix(0.58,0.95,rim);
}
"""
	_cavalry_shader = Shader.new()
	_cavalry_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D pose_texture : filter_nearest, repeat_disable;
uniform int pose_width=256;
uniform int pose_rows=58;
uniform float effect_time=0.0;
uniform float opacity=1.0;
uniform vec4 tint : source_color = vec4(1.0,0.58,0.18,0.65);
varying float individual_alpha;
varying float model_height;
vec3 pose_position(int pose,int vertex_id){return texelFetch(pose_texture,ivec2(vertex_id%pose_width,vertex_id/pose_width+pose_rows*pose),0).xyz;}
void vertex(){
 float cycle=fract(effect_time*2.7+INSTANCE_CUSTOM.r)*4.0;
 int frame=int(floor(cycle));
 float blend=fract(cycle);blend=blend*blend*(3.0-2.0*blend);
 VERTEX=mix(pose_position(frame,VERTEX_ID),pose_position((frame+1)%4,VERTEX_ID),blend);
 individual_alpha=INSTANCE_CUSTOM.a;
 model_height=VERTEX.y;
}
void fragment(){
 float rim=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),1.5);
 float height_fade=smoothstep(-0.15,0.8,model_height);
 ALBEDO=mix(tint.rgb*0.17,tint.rgb,rim*0.75+0.20);
 EMISSION=tint.rgb*rim*0.18;
 ALPHA=tint.a*opacity*individual_alpha*mix(0.50,0.90,rim)*height_fade;
}
"""
	_trail_material = ShaderMaterial.new()
	var trail_shader = Shader.new()
	trail_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
void fragment(){ALBEDO=COLOR.rgb;ALPHA=COLOR.a;}
"""
	_trail_material.shader = trail_shader
	# Immutable shared geometry is prepared outside the first cast frame.
	for type in WEAPON_PATHS:
		_mesh_cache[type] = _weapon_mesh(WEAPON_PATHS[type], 1.12)
	# Xu can equip his great saber, the one-handed saber or the sword. Warm
	# every selectable outline now so his first throw never flattens a GLB.
	for weapon_id in Roster.weapon_choices("xuchu"):
		_mesh_cache["returning_blade:" + weapon_id] = _weapon_mesh(Roster.WEAPONS[weapon_id].path, 1.40)
	# All six heroes' selectable weapons share immutable unit-length geometry.
	# Formation scale is applied per instance, preserving full polearm length.
	for role in Roster.IDS:
		for weapon_id in Roster.weapon_choices(role):
			var key = "weapon:" + weapon_id
			if not _mesh_cache.has(key): _mesh_cache[key] = _weapon_mesh(Roster.WEAPONS[weapon_id].path, 1.0)
	_flag_mesh = _standard_flag_mesh()
	_dust_mesh = QuadMesh.new()
	_dust_mesh.size = Vector2(1.1, 0.58)
	_dust_material = StandardMaterial3D.new()
	_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_dust_material.billboard_keep_scale = true
	_dust_material.vertex_color_use_as_albedo = true
	_dust_material.albedo_color = Color("5b5140")
	_dust_material.albedo_texture = load("res://assets/vfx/kenney/smoke_07.png")
	_dust_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _count_event(key: String) -> void:
	_events[key] = int(_events.get(key, 0)) + 1

func play_skill(fighter: DuelFighter, skill: String, stage: String) -> void:
	if not is_instance_valid(fighter) or not fighter.is_inside_tree(): return
	var owner = fighter.get_instance_id()
	if stage == "cancel":
		cancel_owner(owner)
		_cast_keys.erase(owner)
		return
	if stage == "start":
		_cast_keys.erase(owner)
	if stage == "complete":
		_cast_keys.erase(owner)
		return
	var profile = fighter.skill_profile(skill)
	var special: Variant = profile.get("special", {})
	if special is String: special = {"type": special}
	if not special is Dictionary or special.is_empty(): return
	var trigger: String = special.get("trigger", "release")
	if stage != trigger or _cast_keys.get(owner, "") == skill: return
	_cast_keys[owner] = skill
	spawn(fighter, special, profile, skill)

func spawn(fighter: DuelFighter, configuration: Dictionary, profile: Dictionary = {}, skill = "special") -> int:
	if not is_inside_tree() or not is_instance_valid(fighter) or fighter.hp <= 0.0: return -1
	var target: DuelFighter = fighter.opponent
	if not is_instance_valid(target) or target.hp <= 0.0: return -1
	var type: String = configuration.get("type", "")
	if type not in PROJECTILE_TYPES and type not in ["shockwave", "roar", "air_slam"]: return -1
	while groups.size() >= MAX_GROUPS: _finish_group(groups.keys()[0])
	var count = clampi(int(configuration.get("count", 7 if type == "weapon_array" else (9 if type == "flying_blades" else (6 if type == "cavalry" else 1)))), 1, 9 if type in ["weapon_array", "flying_blades"] else (6 if type == "cavalry" else 1))
	while entity_count() + count > MAX_ENTITIES and not groups.is_empty(): _finish_group(groups.keys()[0])
	_nonce += 1
	var id = _nonce
	var config = configuration.duplicate(true)
	var direction = (target.global_position - fighter.global_position).slide(Vector3.UP).normalized()
	if direction.length_squared() < 0.5: direction = fighter.forward()
	var sideways = Vector3(direction.z, 0.0, -direction.x)
	var origin = fighter.global_position
	var color = Color("65d5e9") if type == "flying_blades" else (Color("e9ad58") if type in ["cavalry", "returning_blade"] else Color("72d8ac"))
	if type == "roar": color = Color("bd9be8")
	if type == "air_slam": color = Color("ed8a8e")
	if type == "weapon_array": color = Color(Roster.character(fighter.character_id).get("color", "65d5e9"))
	var node = Node3D.new()
	node.name = "DuelSpecial_" + type
	add_child(node)
	var data = profile.duplicate(true)
	data.merge(config, true)
	data["skill"] = skill
	data["special"] = type
	data["volley_id"] = id
	data["heavy"] = bool(config.get("heavy", type in ["cavalry", "shockwave", "roar", "air_slam"]))
	data["damage"] = float(config.get("damage", 8.0 if type == "flying_blades" else (12.0 if type == "cavalry" else 24.0)))
	data["knockback"] = float(config.get("knockback", 3.5 if type in ["cavalry", "roar", "air_slam"] else 1.5))
	data["hit_stun"] = float(config.get("hit_stun", 0.18 if type == "flying_blades" else 0.32))
	data["shape"] = "projectile" if type in PROJECTILE_TYPES else "wave"
	data["wave"] = true
	var weapon_id: String = fighter.weapon_id if type in ["weapon_array", "returning_blade"] else ("sword" if type == "flying_blades" else "")
	if type == "weapon_array" and String(config.get("weapon_id", "equipped")) != "equipped": weapon_id = String(config.weapon_id)
	if type == "weapon_array" and not _mesh_cache.has("weapon:" + weapon_id):
		node.queue_free()
		return -1
	var formation: String = config.get("formation", "spear_volley") if type == "weapon_array" else ""
	data["formation"] = formation
	data["weapon_id"] = weapon_id
	var group = {"id": id, "node": node, "owner": fighter.get_instance_id(), "caster": weakref(fighter), "target": weakref(target), "type": type, "weapon_id": weapon_id, "formation": formation, "weapon_length": float(config.get("weapon_length", WEAPON_LENGTHS.get(weapon_id, 1.4))), "target_point": _target_point(target), "mounted": fighter.mounted, "skill": skill, "config": config, "data": data, "age": 0.0, "origin": origin, "direction": direction, "entities": [], "color": color, "material": null, "visual": null, "history": []}
	if type in PROJECTILE_TYPES:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var mesh_key = "weapon:" + weapon_id if type == "weapon_array" else ("returning_blade:" + weapon_id if type == "returning_blade" else type)
		if type == "returning_blade" and not _mesh_cache.has(mesh_key):
			# Generic fixture/future callers may use another equipped weapon;
			# the three playable Xu choices above never enter this slow path.
			_mesh_cache[mesh_key] = _weapon_mesh(Roster.WEAPONS[weapon_id].path, 1.40)
		mm.mesh = CAVALRY_MESH if type == "cavalry" else _mesh_cache[mesh_key]
		mm.instance_count = count
		var visual = MultiMeshInstance3D.new()
		visual.multimesh = mm
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.custom_aabb = AABB(Vector3.ONE * -24.0, Vector3.ONE * 48.0)
		var material = ShaderMaterial.new()
		material.shader = _cavalry_shader if type == "cavalry" else _shader
		material.set_shader_parameter("tint", Color(color, 0.68 if type == "cavalry" else 1.0))
		if type == "cavalry":
			material.set_shader_parameter("pose_texture", CAVALRY_POSES)
			material.set_shader_parameter("pose_width", CAVALRY_POSES.get_width())
			material.set_shader_parameter("pose_rows", CAVALRY_POSES.get_height() / 4)
		visual.material_override = material
		node.add_child(visual)
		group.visual = visual
		group.material = material
		var trail = MeshInstance3D.new()
		trail.mesh = ImmediateMesh.new()
		trail.material_override = _trail_material
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		trail.extra_cull_margin = 4.0
		node.add_child(trail)
		group["trail"] = trail
		for i in count:
			if type == "weapon_array":
				group.entities.append(_array_entity(group, fighter, target, i, count, sideways))
				continue
			var launch = origin + Vector3.UP * (2.75 if fighter.mounted else 1.90)
			var delay = float(i) * float(config.get("interval", 0.055))
			if type == "flying_blades":
				launch += sideways * (float(i % 3) - 1.0) * 1.05 + Vector3.UP * float(i / 3) * 0.55 - direction * (0.25 + float(i / 3) * 0.45)
			elif type == "returning_blade":
				launch = _throw_hand_position(fighter)
				delay = 0.0
			else:
				launch = origin - direction * (3.6 + float(i / 3) * 1.5) + sideways * (float(i % 3) - 1.0) * float(config.get("lane_spacing", 0.72))
				delay = float(i / 3) * 0.10
			var heading = (_target_point(target) - launch).normalized() if type != "cavalry" else direction
			group.entities.append({"index": i, "position": launch, "previous": launch, "heading": heading, "origin": launch, "distance": 0.0, "delay": delay, "done": false, "returning": false, "hit_set": {}, "history": []})
		if _is_returning(group): _set_weapon_thrown(fighter, true)
		if type == "cavalry": _add_cavalry_details(group)
	else:
		var visual = MeshInstance3D.new()
		visual.mesh = _wave_mesh(type, color)
		visual.material_override = _wave_material(color)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.extra_cull_margin = 3.0
		node.add_child(visual)
		group.visual = visual
		group.material = visual.material_override
		group.entities.append({"index": 0, "position": origin, "previous": origin, "done": false, "hit_set": {}})
	groups[id] = group
	_count_event(type + ":spawn")
	_update_visuals(group)
	return id

func _target_point(target: DuelFighter) -> Vector3:
	return target.thrust_body_low().lerp(target.thrust_body_high(), 0.55)

func _array_entity(group: Dictionary, caster: DuelFighter, target: DuelFighter, index: int, count: int, sideways: Vector3) -> Dictionary:
	var config: Dictionary = group.config
	var direction: Vector3 = group.direction
	var aim: Vector3 = group.target_point
	var launch: Vector3 = group.origin
	var delay = 0.12 + float(index) * float(config.get("interval", 0.07))
	var formation: String = group.formation
	if formation == "spear_volley":
		var row = 0 if index < 3 else (1 if index < 5 else 2)
		var lane = float(index - 1) if row == 0 else (float((index - 3) % 2) - 0.5) * 1.4
		var local_index = index if row == 0 else (index - 3 if row == 1 else index - 5)
		launch += direction * (1.1 - float(row) * 0.45) + sideways * lane * 0.70 + Vector3.UP * ((2.55 if caster.mounted else 1.45) + float(row) * 0.14)
		delay = 0.14 + float(row) * float(config.get("volley_interval", 0.24)) + float(local_index) * float(config.get("interval", 0.035))
	elif formation == "diagonal_cleave":
		launch += sideways * (float(index) - float(count - 1) * 0.5) * 1.4 - direction * (0.5 + float(index) * 0.35) + Vector3.UP * ((4.0 if caster.mounted else 3.2) + float(index) * 0.42)
		delay = 0.18 + float(index) * float(config.get("interval", 0.20))
	elif formation == "ground_pincer":
		var lane = float(index) - float(count - 1) * 0.5
		launch += sideways * lane * 1.25 - direction * (0.7 + absf(lane) * 0.25) + Vector3.UP * (1.75 if caster.mounted else 0.64)
		# Low ground pressure still rises into the real rider capsule in mounted
		# combat; it does not silently damage an unreachable point on the floor.
		aim = target.thrust_body_low().lerp(target.thrust_body_high(), 0.18)
		delay = 0.16 + (2.0 - absf(lane)) * 0.09
	elif formation == "halberd_encircle":
		var angle = float(index) / float(count) * TAU + atan2(direction.x, direction.z)
		launch = aim + Vector3(sin(angle), 0.0, cos(angle)) * float(config.get("formation_radius", 4.2))
		launch.y = float(group.origin.y) + (2.8 if caster.mounted else 1.55) + float(index % 2) * 0.3
		# Conjured weapons visibly wait around the release point, then commit.
		# Moving away during this half-second warning avoids the fixed centre.
		delay = maxf(0.40, float(config.get("telegraph", 0.52))) + float(index) * float(config.get("interval", 0.045))
	elif formation == "returning_fan":
		launch = _throw_hand_position(caster) + sideways * (float(index) - float(count - 1) * 0.5) * 0.16
		delay = float(index) * float(config.get("interval", 0.15))
	var heading = (aim - launch).normalized()
	if formation == "returning_fan": heading = heading.rotated(Vector3.UP, (float(index) - float(count - 1) * 0.5) * float(config.get("fan_spread", 0.10)))
	var cast_from = caster.global_position + Vector3.UP * (2.2 if caster.mounted else 1.2)
	var blocked = not _clear_environment(cast_from, aim) or not _clear_environment(cast_from, launch)
	return {"index": index, "position": launch, "previous": launch, "heading": heading, "origin": launch, "distance": 0.0, "delay": delay, "done": blocked, "returning": false, "hit_set": {}, "history": []}

func _clear_environment(from: Vector3, to: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()

func _is_returning(group: Dictionary) -> bool:
	return group.type == "returning_blade" or (group.type == "weapon_array" and group.formation == "returning_fan")

func _refresh_throw_visibility(caster: DuelFighter) -> void:
	var outstanding = false
	for active in groups.values():
		if int(active.owner) != caster.get_instance_id() or not _is_returning(active): continue
		for entity in active.entities:
			if not entity.done:
				outstanding = true
				break
	_set_weapon_thrown(caster, outstanding)

func _standard_flag_mesh() -> ArrayMesh:
	var vertices = PackedVector3Array()
	# A narrow pole and a short split pennant, small enough to preserve riders.
	for corners in [[Vector3(-0.018, 0.0, 0), Vector3(-0.018, 1.30, 0), Vector3(0.018, 1.30, 0), Vector3(0.018, 0.0, 0)],
		[Vector3(0.02, 0.76, 0), Vector3(0.02, 1.28, 0), Vector3(0.59, 1.17, 0.08), Vector3(0.43, 0.86, 0.10)]]:
		for i in [0, 1, 2, 0, 2, 3]: vertices.append(corners[i])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_cavalry_details(group: Dictionary) -> void:
	for kind in ["standards", "hoof_dust"]:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _flag_mesh if kind == "standards" else _dust_mesh
		mm.instance_count = group.entities.size() * (1 if kind == "standards" else 2)
		var visual = MultiMeshInstance3D.new()
		visual.multimesh = mm
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.custom_aabb = AABB(Vector3.ONE * -24.0, Vector3.ONE * 48.0)
		if kind == "hoof_dust": visual.material_override = _dust_material
		else:
			var material = ShaderMaterial.new()
			material.shader = _shader
			material.set_shader_parameter("tint", Color("d4b87d"))
			material.set_shader_parameter("opacity", 0.80)
			visual.material_override = material
		group.node.add_child(visual)
		group[kind] = visual

func _update_cavalry_details(group: Dictionary) -> void:
	var flags: MultiMesh = group.standards.multimesh
	var dust: MultiMesh = group.hoof_dust.multimesh
	for i in group.entities.size():
		var entity: Dictionary = group.entities[i]
		var heading: Vector3 = entity.heading
		var side = Vector3(heading.z, 0, -heading.x)
		var fade = 0.0 if entity.done else smoothstep(float(entity.delay), float(entity.delay) + 0.18, float(group.age))
		var yaw = atan2(heading.x, heading.z) + sin(float(group.age) * 7.0 + float(i)) * 0.08
		flags.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), entity.position + side * 0.25 + Vector3.UP * 1.65))
		flags.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, fade))
		for puff in 2:
			var age = fposmod(float(group.age) * 2.0 + float(i) * 0.17 + float(puff) * 0.5, 1.0)
			var point: Vector3 = entity.position - heading * (0.6 + age * 1.1) + side * (float(puff) - 0.5) * 0.7 + Vector3.UP * 0.24
			dust.set_instance_transform(i * 2 + puff, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.60 + age * 0.75)), point))
			dust.set_instance_color(i * 2 + puff, Color(1.0, 1.0, 1.0, fade * (1.0 - age) * 0.50))

func _throw_hand_position(fighter: DuelFighter) -> Vector3:
	if fighter.right_hand_index >= 0:
		return fighter.palm_position(false)
	# The one-hand attachment does not populate the shared two-hand index.
	# Resolve its actual animated palm without mutating the actor or skeleton.
	for index in fighter.skeleton.get_bone_count():
		if fighter.skeleton.get_bone_name(index).ends_with("RightHand"):
			var p: Array = fighter.grip_config.get("right_palm", [0.0, 0.0, 0.0])
			return fighter.skeleton.to_global(fighter.skeleton.get_bone_global_pose(index) * Vector3(p[0], p[1], p[2]))
	return fighter.grip.global_position if is_instance_valid(fighter.grip) else fighter.global_position + Vector3.UP

func _set_weapon_thrown(fighter: DuelFighter, value: bool) -> void:
	if fighter.has_method("set_duel_weapon_thrown"):
		fighter.call("set_duel_weapon_thrown", value)
	elif is_instance_valid(fighter.weapon_mesh):
		fighter.weapon_mesh.visible = not value

func _physics_process(delta: float) -> void:
	for id in groups.keys():
		var group: Dictionary = groups[id]
		var caster: DuelFighter = group.caster.get_ref()
		var target: DuelFighter = group.target.get_ref()
		if not is_instance_valid(caster) or caster.hp <= 0.0 or caster.state == "dead":
			_finish_group(id)
			continue
		group.age += delta
		if group.type in ["shockwave", "roar", "air_slam"]:
			_step_wave(group, caster, target, delta)
		else:
			_step_projectiles(group, caster, target, delta)
		if not groups.has(id): continue
		if group.type in PROJECTILE_TYPES:
			for entity in group.entities:
				for sample in entity.history: sample.age += delta
				while entity.history.size() > 8 or (not entity.history.is_empty() and entity.history[0].age > 0.15): entity.history.pop_front()
		_update_visuals(group)
		if _is_returning(group): _refresh_throw_visibility(caster)
		var alive = false
		for entity in group.entities: alive = alive or not entity.done
		if not alive and not group.has("finish_after"): group["finish_after"] = group.age + 0.15
		if (group.has("finish_after") and group.age >= group.finish_after) or group.age > 4.5: _finish_group(id)

func _step_projectiles(group: Dictionary, caster: DuelFighter, target: DuelFighter, delta: float) -> void:
	var config: Dictionary = group.config
	var speed = float(config.get("speed", 9.0 if group.type == "cavalry" else 13.0))
	var maximum = float(config.get("max_distance", 16.0 if group.type == "cavalry" else 14.0))
	for entity in group.entities:
		if entity.done or group.age < entity.delay: continue
		entity.previous = entity.position
		if _is_returning(group) and (entity.returning or entity.distance >= minf(maximum * 0.55, 6.0) or float(group.age) - float(entity.delay) > float(config.get("return_after", 0.60))):
			entity.returning = true
			var hand = _throw_hand_position(caster)
			entity.heading = (hand - entity.position).normalized()
			if entity.position.distance_to(hand) < speed * 1.35 * delta + 0.18:
				entity.done = true
				_refresh_throw_visibility(caster)
				_count_event("returning_blade:return")
				continue
		elif group.type == "flying_blades" and is_instance_valid(target) and target.hp > 0.0:
			var toward = (_target_point(target) - entity.position).normalized()
			# Target identity is fixed on release. Limited steering still leaves
			# a clear evasive route instead of teleporting a sword onto the body.
			var angle = entity.heading.angle_to(toward)
			if angle > 0.0001:
				entity.heading = entity.heading.slerp(toward, minf(1.0, float(config.get("homing", 0.8)) * delta / angle)).normalized()
		entity.position += entity.heading * speed * (1.35 if entity.returning else 1.0) * delta
		entity.distance += entity.position.distance_to(entity.previous)
		if not _is_returning(group) and entity.distance > maximum:
			entity.done = true
		var environment = PhysicsRayQueryParameters3D.create(entity.previous + Vector3.UP * (1.0 if group.type == "cavalry" else 0.0), entity.position + Vector3.UP * (1.0 if group.type == "cavalry" else 0.0), 1)
		var wall = get_world_3d().direct_space_state.intersect_ray(environment)
		if not wall.is_empty():
			entity.position = wall.position - Vector3.UP * (1.0 if group.type == "cavalry" else 0.0) - entity.heading * 0.04
			if _is_returning(group) and not entity.returning: entity.returning = true
			else: entity.done = true
			continue
		if is_instance_valid(target) and target.hp > 0.0 and not entity.hit_set.has(target.get_instance_id()):
			var start: Vector3 = entity.previous
			var end: Vector3 = entity.position
			if group.type == "cavalry":
				# Fixed real horse/rider chest height, never the target's height.
				# A sufficiently high jumping opponent can clear the formation.
				start.y = float(group.origin.y) + 1.55
				end.y = start.y
			var pair = Geometry3D.get_closest_points_between_segments(start, end, target.thrust_body_low(), target.thrust_body_high())
			var radius = float(config.get("radius", 0.58 if group.type == "cavalry" else (0.30 if group.type == "returning_blade" else 0.16)))
			if pair[0].distance_to(pair[1]) <= target.thrust_body_radius() + radius:
				entity.hit_set[target.get_instance_id()] = true
				var normal = (pair[0] - pair[1]).normalized()
				if normal.length_squared() < 0.5: normal = -entity.heading
				var at = pair[1] + normal * target.thrust_body_radius()
				_request_contact(group, entity, caster, target, at)
				if group.type == "flying_blades" or (group.type == "weapon_array" and not _is_returning(group)):
					entity.position = at
					entity.done = true
		entity.history.append({"point": entity.position, "age": 0.0})

func _request_contact(group: Dictionary, entity: Dictionary, caster: DuelFighter, target: DuelFighter, at: Vector3) -> void:
	var data = group.data.duplicate(true)
	data["projectile_index"] = int(entity.index)
	data["contact_point"] = at
	data["source_position"] = entity.previous
	data["impact_direction"] = entity.get("heading", group.direction)
	if group.type == "weapon_array" and group.formation == "returning_fan" and int(entity.index) == group.entities.size() - 1:
		# Only this real final blade contact earns the heavier finishing push.
		# Missing it never manufactures damage or a remote finishing event.
		data["knockback"] = float(group.config.get("finisher_knockback", data.knockback))
		data["finisher"] = true
	_count_event(group.type + ":contact")
	hit_requested.emit(caster, target, data, at)

func _step_wave(group: Dictionary, caster: DuelFighter, target: DuelFighter, _delta: float) -> void:
	var entity: Dictionary = group.entities[0]
	var config: Dictionary = group.config
	var speed = float(config.get("speed", 10.0))
	var radius = float(config.get("radius", 4.5))
	var old_front = float(entity.get("front", 0.0))
	var front = minf(group.age * speed, float(config.get("max_distance", 12.0)) if group.type == "shockwave" else radius)
	entity["front"] = front
	entity.previous = entity.position
	entity.position = group.origin + group.direction * front
	if is_instance_valid(target) and target.hp > 0.0 and not entity.hit_set.has(target.get_instance_id()):
		var flat = (target.global_position - group.origin).slide(Vector3.UP)
		var distance = flat.length()
		var crossed = distance >= old_front - 0.35 and distance <= front + target.thrust_body_radius()
		var pressure_height = 1.25 if group.type == "roar" else 0.95
		var wave_floor = float(group.origin.y) + 0.04
		var body_radius = target.thrust_body_radius()
		var body_high = target.thrust_body_high().y + body_radius
		var lower_body = target.global_position.y + (0.18 if target.mounted else 0.42)
		# Preserve the existing upper-height gate, adding only the lower bound:
		# an airborne cast cannot hit a target entirely below its release plane.
		crossed = crossed and lower_body <= float(group.origin.y) + pressure_height + 0.20 and body_high >= wave_floor - 0.15
		if group.type == "shockwave":
			var along = flat.dot(group.direction)
			crossed = crossed and along >= old_front - 0.30 and along <= front + target.thrust_body_radius() and (flat - group.direction * along).length() <= float(config.get("half_width", 1.15)) + target.thrust_body_radius()
		if crossed:
			var at = Vector3(target.global_position.x, clampf(wave_floor + pressure_height * 0.5, target.thrust_body_low().y, target.thrust_body_high().y), target.global_position.z)
			var from = group.origin + Vector3.UP * (1.8 if caster.mounted else 0.7)
			var cover = PhysicsRayQueryParameters3D.create(from, at, 1)
			if get_world_3d().direct_space_state.intersect_ray(cover).is_empty():
				entity.hit_set[target.get_instance_id()] = true
				_request_contact(group, entity, caster, target, at)
	var limit = float(config.get("max_distance", 12.0)) if group.type == "shockwave" else radius
	if group.age > limit / speed + 0.30: entity.done = true

func _update_visuals(group: Dictionary) -> void:
	if group.type in ["shockwave", "roar", "air_slam"]:
		var front = maxf(0.08, float(group.entities[0].get("front", 0.0)))
		group.visual.global_position = Vector3(group.origin.x, group.origin.y + 0.04, group.origin.z)
		group.visual.global_rotation.y = atan2(group.direction.x, group.direction.z)
		if group.type == "shockwave":
			group.visual.global_position += group.direction * front
			group.visual.scale = Vector3(float(group.config.get("half_width", 1.15)), 1.0, 0.55)
		else: group.visual.scale = Vector3(front, 1.0, front)
		group.material.set_shader_parameter("effect_time", float(group.age))
		group.material.set_shader_parameter("opacity", 1.0 - smoothstep(0.35, 1.0, group.age / (float(group.config.get("max_distance", 12.0) if group.type == "shockwave" else group.config.get("radius", 4.5)) / float(group.config.get("speed", 10.0)) + 0.30)))
		return
	var mm: MultiMesh = group.visual.multimesh
	group.material.set_shader_parameter("effect_time", float(group.age))
	for i in group.entities.size():
		var entity: Dictionary = group.entities[i]
		var heading: Vector3 = entity.heading
		var up = Vector3.UP if absf(heading.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var basis = Basis.looking_at(heading, up, true)
		var point: Vector3 = entity.position
		if group.type == "cavalry":
			basis = Basis(Vector3.UP, atan2(heading.x, heading.z)).scaled(Vector3.ONE * 0.80)
		elif group.type == "weapon_array":
			if group.formation == "diagonal_cleave":
				var swing = clampf((float(group.age) - float(entity.delay)) / 0.42, 0.0, 1.0)
				basis = basis * Basis(Vector3.RIGHT, lerpf(-0.55, 0.35, swing))
			elif _is_returning(group): basis = basis * Basis(Vector3.UP, (float(group.age) - float(entity.delay)) * 16.0)
			basis = basis.scaled(Vector3.ONE * float(group.weapon_length))
			point -= basis * Vector3(0.0, 0.0, 0.5 if _is_returning(group) else 1.0)
		else:
			point -= heading * (1.40 if group.type == "returning_blade" else 1.12)
			if group.type == "returning_blade":
				basis = basis * Basis(Vector3.UP, float(group.age) * 19.0)
				point = entity.position - basis * Vector3(0.0, 0.0, 0.70)
		mm.set_instance_transform(i, Transform3D(basis, point))
		# The headless renderer cannot read MultiMesh transforms back. Retain
		# the exact submitted scale for deterministic geometry diagnostics.
		entity["rendered_axis_scale"] = basis.z.length()
		var fade = 0.0 if entity.done else smoothstep(entity.delay, entity.delay + 0.12, float(group.age))
		if group.type == "weapon_array" and not entity.done and float(group.age) < float(entity.delay):
			fade = 0.25 + 0.38 * smoothstep(0.0, maxf(0.1, float(entity.delay)), float(group.age))
		mm.set_instance_custom_data(i, Color(float(i) * 0.173, 0.0, 0.0, fade))
		entity["visual_opacity"] = fade
	_update_trails(group)
	if group.type == "cavalry": _update_cavalry_details(group)

func _update_trails(group: Dictionary) -> void:
	var mesh: ImmediateMesh = group.trail.mesh
	mesh.clear_surfaces()
	var points = 0
	for entity in group.entities: points += maxi(0, entity.history.size() - 1)
	if points == 0: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for entity in group.entities:
		for i in range(1, entity.history.size()):
			var a: Dictionary = entity.history[i - 1]
			var b: Dictionary = entity.history[i]
			var width = Vector3.UP * (0.06 if group.type == "cavalry" else 0.025)
			var color: Color = group.color
			color.a = (1.0 - float(a.age) / 0.15) * (0.30 if group.type == "cavalry" else 0.58)
			for vertex in [a.point - width, a.point + width, b.point + width, a.point - width, b.point + width, b.point - width]:
				mesh.surface_set_color(color)
				mesh.surface_add_vertex(vertex)
	mesh.surface_end()

func cancel_owner(owner_id: int) -> void:
	for id in groups.keys():
		if int(groups[id].owner) == owner_id: _finish_group(id)

func _finish_group(id: int) -> void:
	if not groups.has(id): return
	var group: Dictionary = groups[id]
	groups.erase(id)
	if _is_returning(group):
		var caster = group.caster.get_ref()
		if is_instance_valid(caster): _refresh_throw_visibility(caster)
	if is_instance_valid(group.node):
		group.node.visible = false
		group.node.queue_free()
	_count_event(group.type + ":finish")

func clear() -> void:
	for id in groups.keys(): _finish_group(id)
	_cast_keys.clear()
	_events.clear()

func entity_count() -> int:
	var count = 0
	for group in groups.values(): count += group.entities.size()
	return count

func debug_state() -> Dictionary:
	var records: Array = []
	for group in groups.values():
		var entities: Array = []
		for entity in group.entities:
			entities.append({"index": entity.index, "position": [entity.position.x, entity.position.y, entity.position.z], "done": entity.done, "delay": entity.get("delay", 0.0), "heading": [entity.get("heading", Vector3.ZERO).x, entity.get("heading", Vector3.ZERO).y, entity.get("heading", Vector3.ZERO).z], "contacts": entity.hit_set.size()})
		records.append({"type": group.type, "formation": group.formation, "weapon_id": group.weapon_id, "weapon_length": group.weapon_length, "release_height": group.origin.y, "owner": group.owner, "volley_id": group.id, "age": group.age, "entities": entities})
	return {"groups": records, "entities": entity_count(), "events": _events.duplicate(), "max_entities": MAX_ENTITIES, "cavalry_triangles_per_rider": CAVALRY_MESH.surface_get_array_len(0) / 3}

func _exit_tree() -> void:
	clear()

func _weapon_mesh(path: String, length_m: float) -> ArrayMesh:
	var scene = load(path).instantiate()
	var points = PackedVector3Array()
	var normals = PackedVector3Array()
	_flatten(scene, Transform3D.IDENTITY, points, normals)
	scene.free()
	var bounds = AABB(points[0], Vector3.ZERO)
	for p in points: bounds = bounds.expand(p)
	var axis = bounds.size.max_axis_index()
	var scale = length_m / maxf(bounds.size[axis], 0.01)
	var centre = bounds.get_center()
	for i in points.size():
		var p = (points[i] - centre) * scale
		var n = normals[i]
		if axis == 1:
			p = Vector3(p.x, p.z, p.y)
			n = Vector3(n.x, n.z, n.y)
		elif axis == 0:
			p = Vector3(p.y, p.z, p.x)
			n = Vector3(n.y, n.z, n.x)
		p.z += length_m * 0.5
		points[i] = p
		normals[i] = n
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _flatten(node: Node, parent: Transform3D, points: PackedVector3Array, normals: PackedVector3Array) -> void:
	var transform = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				indices.resize(arrays[Mesh.ARRAY_VERTEX].size())
				for i in indices.size(): indices[i] = i
			for index in indices:
				points.append(transform * arrays[Mesh.ARRAY_VERTEX][index])
				var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][index] if arrays[Mesh.ARRAY_NORMAL] != null else Vector3.UP
				normals.append((transform.basis * n).normalized())
	for child in node.get_children(): _flatten(child, transform, points, normals)

func _wave_material(color: Color) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D dust_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D crest_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint:source_color=vec4(0.35,0.8,0.7,1.0);
uniform float opacity=1.0;
uniform float effect_time=0.0;
varying float layer_kind;
varying float patch_seed;
varying float patch_alpha;
void vertex(){
 layer_kind=COLOR.r;patch_seed=COLOR.g;patch_alpha=COLOR.a;
 if(layer_kind<0.5){
  // Each low cloud faces the view independently, so side-on wave segments
  // keep volume instead of collapsing to thin paper slices.
  vec3 centre=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
  vec3 toward=INV_VIEW_MATRIX[3].xyz-centre;toward.y=0.0;
  vec3 right=normalize(cross(vec3(0.0,1.0,0.0),toward));
  float width=UV2.x*length(MODEL_MATRIX[0].xyz);
  vec3 world=centre+right*(UV.x-0.5)*width+vec3(0.0,UV.y*UV2.y,0.0);
  VERTEX=(inverse(MODEL_MATRIX)*vec4(world,1.0)).xyz;
 }
}
void fragment(){
 float side=smoothstep(0.0,0.16,UV.x)*smoothstep(0.0,0.16,1.0-UV.x);
 float cap=smoothstep(0.0,0.10,UV.y)*smoothstep(0.0,0.18,1.0-UV.y);
 float grain=sin(UV.x*21.0+patch_seed*17.0-effect_time*9.0)*sin(UV.y*16.0+patch_seed*11.0+effect_time*5.0);
 if(layer_kind<0.5){
  vec2 drift=vec2(sin(patch_seed*9.0+effect_time*3.0)*0.045,-effect_time*0.07);
  float smoke=texture(dust_texture,UV+drift).a;
  float torn=smoothstep(0.09,0.48,smoke+grain*0.12);
  vec3 earth=mix(vec3(0.13,0.12,0.10),vec3(0.58,0.51,0.40),smoothstep(0.18,0.92,UV.y)*0.60+smoke*0.15);
  ALBEDO=mix(earth,tint.rgb*0.50,0.12);
  EMISSION=vec3(0.0);
  ALPHA=min(0.88,smoke*torn*side*cap*patch_alpha*opacity*1.10);
 }else{
  // trace_02 is a vertical tapered streak; transpose it into a short crest.
  float trace=texture(crest_texture,vec2(UV.y,UV.x)).a;
  float broken=smoothstep(-0.55,0.25,grain+0.35);
  vec3 rim=mix(vec3(1.0,0.94,0.76),tint.rgb,0.15);
  ALBEDO=rim;
  EMISSION=rim*0.28;
  ALPHA=trace*side*cap*broken*patch_alpha*opacity*(0.42+0.50*exp(-effect_time*7.0));
 }
}
"""
	material.shader = shader
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("dust_texture", load("res://assets/vfx/kenney/smoke_07.png"))
	material.set_shader_parameter("crest_texture", load("res://assets/vfx/kenney/trace_02.png"))
	return material

func _wave_mesh(type: String, _color: Color) -> ArrayMesh:
	var points = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var uv = PackedVector2Array()
	var uv2 = PackedVector2Array()
	var patches: Array = []
	var count = 7 if type == "shockwave" else 12
	for cluster in count:
		var centre = lerpf(-0.94, 0.94, float(cluster) / float(count - 1)) if type == "shockwave" else float(cluster) / float(count) * TAU
		var seed = fposmod(float(cluster) * 0.618, 1.0)
		# Three overlapping, individually mapped soft clouds make a low volume.
		# Height is independent of expanding radius, never a tall paper fan.
		for puff in 3:
			var angle = centre + (float(puff) - 1.0) * 0.065
			var half_width = 0.160 + sin(float(cluster * 3 + puff)) * 0.018
			var radius = 0.78 + float(puff) * 0.065
			var height = (0.80 if type == "air_slam" else (0.68 if type == "roar" else 0.60)) * (0.85 + sin(float(cluster * 7 + puff * 3)) * 0.16)
			patches.append({"a": angle - half_width, "b": angle + half_width, "r0": radius, "r1": radius + 0.085, "y0": 0.025 + float(puff) * 0.025, "y1": height,
				"layer": 0.0, "seed": fposmod(seed + float(puff) * 0.21, 1.0), "alpha": 0.94 if puff == 1 else 0.82})
		# The pale, broken crest stays near the leading ground contact. The
		# broad colored pressure-sheet is replaced with this brief thin edge.
		patches.append({"a": centre - 0.16, "b": centre + 0.16, "r0": 0.99, "r1": 1.0, "y0": 0.035, "y1": 0.24,
			"layer": 1.0, "seed": seed, "alpha": 0.90})
	for patch in patches:
		# UV spans 0..1 on EACH cloud/crest, even across its curved subdivisions.
		# Mapping over the entire circular wave used to stretch the textures.
		for segment in 4:
			var u0 = float(segment) / 4.0
			var u1 = float(segment + 1) / 4.0
			var a = lerpf(float(patch.a), float(patch.b), u0)
			var b = lerpf(float(patch.a), float(patch.b), u1)
			var a0 = Vector3(sin(a) * float(patch.r0), float(patch.y0), cos(a) * float(patch.r0))
			var a1 = Vector3(sin(a) * float(patch.r1), float(patch.y1), cos(a) * float(patch.r1))
			var b1 = Vector3(sin(b) * float(patch.r1), float(patch.y1), cos(b) * float(patch.r1))
			var b0 = Vector3(sin(b) * float(patch.r0), float(patch.y0), cos(b) * float(patch.r0))
			if type == "shockwave":
				a0.z -= 1.0
				a1.z -= 1.0
				b0.z -= 1.0
				b1.z -= 1.0
			var centre_angle = (float(patch.a) + float(patch.b)) * 0.5
			var centre_radius = (float(patch.r0) + float(patch.r1)) * 0.5
			var cloud_centre = Vector3(sin(centre_angle) * centre_radius, float(patch.y0), cos(centre_angle) * centre_radius - (1.0 if type == "shockwave" else 0.0))
			for j in [0, 1, 2, 0, 2, 3]:
				points.append(cloud_centre if float(patch.layer) < 0.5 else [a0, a1, b1, b0][j])
				normals.append(Vector3.UP)
				colors.append(Color(float(patch.layer), float(patch.seed), 0.0, float(patch.alpha)))
				uv.append([Vector2(u0, 0.0), Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0)][j])
				uv2.append(Vector2((float(patch.b) - float(patch.a)) * centre_radius, float(patch.y1) - float(patch.y0)))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
