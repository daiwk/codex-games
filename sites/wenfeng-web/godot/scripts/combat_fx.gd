extends Node3D
class_name DuelFX

var muted = false:
	set(value):
		muted = value
		if muted:
			for player in audio_pool:
				player.stop()
var sounds: Dictionary = {}
var audio_pool: Array[AudioStreamPlayer] = []
var trails: Dictionary = {}
var rng = RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
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
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 0.70)
	node.material_override = mat
	add_child(node)
	trails[fighter.get_instance_id()] = {"fighter": weakref(fighter), "node": node, "points": [],
		"color": Color("a4e8f5") if fighter.character_id == "zhaoyun" else Color("ffc089")}

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
		while not points.is_empty() and points[0].age > 0.14:
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
			color.a = maxf(0.0, 1.0 - float(p.age) / 0.14) * (0.62 if fighter.state == "ultimate" else 0.34)
			for vertex in [p.a, p.b, q.b, p.a, q.b, q.a]:
				mesh.surface_set_color(color)
				mesh.surface_add_vertex(vertex)
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
	var count = 20 if outcome in ["parry", "heavy_hit"] else 12
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
