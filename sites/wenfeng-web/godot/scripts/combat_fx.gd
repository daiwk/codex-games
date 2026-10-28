extends Node3D
class_name DuelFX

const TRAIL_MASK = preload("res://assets/vfx/kenney/trace_06.png")
const TRAIL_LIFETIME = 0.11

var muted = false:
	set(value):
		muted = value
		if muted:
			for player in audio_pool:
				player.stop()
var legacy_contact_sparks = true
var sounds: Dictionary = {}
var audio_pool: Array[AudioStreamPlayer] = []
var trails: Dictionary = {}
var rng = RandomNumberGenerator.new()
var trail_shader: Shader

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	trail_shader = Shader.new()
	trail_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
uniform sampler2D trail_mask : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
	// A narrow, soft cross-section replaces the opaque full blade-width quad.
	// The middle slice is continuous across motion samples, so no seams flash.
	float edge = texture(trail_mask, vec2(UV.x, 0.5)).a;
	// Ink-coloured shoulders retain contrast on pale sand. Normal alpha
	// blending prevents overlapping samples bleaching to a solid white patch.
	ALBEDO = mix(COLOR.rgb * 0.16, COLOR.rgb * 0.88, smoothstep(0.04, 0.65, edge));
	ALBEDO = mix(ALBEDO, vec3(0.91, 0.96, 0.95), pow(edge, 8.0) * 0.16);
	ALPHA = COLOR.a * edge;
}
"""
	rng.seed = 714
	for sound in ["swing", "heavy", "hit", "clang", "parry", "step", "gong", "dodge", "charge", "ultimate", "thrust", "roar"]:
		sounds[sound] = load("res://assets/audio/%s.wav" % sound)
	for i in 14:
		var player = AudioStreamPlayer.new()
		add_child(player)
		audio_pool.append(player)

func sound(key: String, volume = -9.0, pitch = 1.0) -> void:
	if muted or not sounds.has(key):
		return
	for player in audio_pool:
		if not player.playing:
			player.stream = sounds[key]
			player.volume_db = volume
			player.pitch_scale = pitch
			player.play()
			return

func register_fighter(fighter: DuelFighter) -> void:
	var node = MeshInstance3D.new()
	node.mesh = ImmediateMesh.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat = ShaderMaterial.new()
	mat.shader = trail_shader
	mat.set_shader_parameter("trail_mask", TRAIL_MASK)
	node.material_override = mat
	add_child(node)
	var palette: Array = DuelSkillFX.PALETTES.get(fighter.character_id, DuelSkillFX.PALETTES.zhaoyun)
	trails[fighter.get_instance_id()] = {"fighter": weakref(fighter), "node": node, "points": [], "color": palette[0]}

func clear_fighters() -> void:
	for trail in trails.values():
		trail.node.queue_free()
	trails.clear()

func _process(delta: float) -> void:
	for trail in trails.values():
		var fighter = trail.fighter.get_ref()
		if not is_instance_valid(fighter):
			continue
		var points: Array = trail.points
		for point in points:
			point.age += delta
		while not points.is_empty() and points[0].age > TRAIL_LIFETIME:
			points.pop_front()
		if fighter.state in ["attack", "skill", "ultimate"] and fighter.enabled and fighter.attack.has("active"):
			var window: Vector2 = fighter.attack.active
			if fighter.action_time > window.x - 0.025 and fighter.action_time < window.y + 0.06:
				points.append({"a": fighter.blade_base(), "b": fighter.blade_tip(), "age": 0.0})
		var mesh: ImmediateMesh = trail.node.mesh
		mesh.clear_surfaces()
		if points.size() < 2:
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(1, points.size()):
			var p = points[i - 1]
			var q = points[i]
			var color: Color = trail.color
			var fade = maxf(0.0, 1.0 - float(p.age) / TRAIL_LIFETIME)
			color.a = fade * fade * (0.26 if fighter.state == "ultimate" else 0.18)
			var vertices = [p.a, p.b, q.b, p.a, q.b, q.a]
			var uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
			for corner in vertices.size():
				mesh.surface_set_color(color)
				mesh.surface_set_uv(uvs[corner])
				mesh.surface_add_vertex(vertices[corner])
		mesh.surface_end()

func burst(at: Vector3, outcome: String, damage = 0) -> void:
	if outcome == "evade":
		_floating_text(at + Vector3.UP * 0.30, "闪避", Color("bbd7d0"))
		return
	var guard = outcome in ["block", "parry", "counter", "break"]
	var color = Color("c6ffed") if outcome in ["parry", "counter"] else (Color("f9d398") if guard else Color("f2b77c"))
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	var count = (20 if outcome in ["parry", "heavy_hit"] else 12) if legacy_contact_sparks else 0
	for i in count:
		var spark = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		mesh.size = Vector3(0.022, 0.022, rng.randf_range(0.07, 0.18))
		spark.mesh = mesh
		spark.material_override = material
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.position = at
		add_child(spark)
		var dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.15, 1.1), rng.randf_range(-1, 1)).normalized()
		if absf(dir.y) < 0.98:
			spark.look_at(at + dir)
		var tween = spark.create_tween().set_parallel(true)
		tween.tween_property(spark, "position", at + dir * rng.randf_range(0.45, 1.15), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "scale", Vector3.ZERO, 0.28)
		tween.chain().tween_callback(spark.queue_free)
	if outcome == "parry":
		_floating_text(at + Vector3.UP * 0.32, "招架", color)
	elif outcome == "counter":
		_floating_text(at + Vector3.UP * 0.32, "反击", color)
	elif outcome == "break":
		_floating_text(at + Vector3.UP * 0.32, "破防", color)
	elif damage > 0:
		_floating_text(at + Vector3.UP * 0.30, str(damage), Color("fff1d8"))
	sound("parry" if outcome in ["parry", "counter"] else ("clang" if guard else "hit"), -8.0)

func _floating_text(at: Vector3, text: String, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.0045
	label.outline_size = 9
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = at
	add_child(label)
	var tween = label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", at.y + 0.55, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_delay(0.12)
	tween.chain().tween_callback(label.queue_free)
