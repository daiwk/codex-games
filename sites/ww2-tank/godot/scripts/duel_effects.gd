extends Node3D

const SAMPLE_RATE := 22050

var _flash_mesh: SphereMesh
var _smoke_mesh: SphereMesh
var _spark_mesh: BoxMesh
var _fire_mesh: SphereMesh
var _fire_sound: AudioStreamWAV
var _hit_sound: AudioStreamWAV
var _wreck_sound: AudioStreamWAV
var _small_shot_sound: AudioStreamWAV
var _small_tracer: BoxMesh
var _allied_tracer: StandardMaterial3D
var _hostile_tracer: StandardMaterial3D
var _blast_ring_mesh: TorusMesh


func _ready() -> void:
	_flash_mesh = _sphere(0.44, _surface(true, false), 10)
	_smoke_mesh = _sphere(0.49, _surface(false, true), 8)
	_fire_mesh = _sphere(0.22, _surface(true, true), 8)
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.055, 0.22, 0.055)
	_spark_mesh.material = _surface(true, true)
	_fire_sound = _make_sound(0.51, 119.0, 33.0, 8.7, 72)
	_hit_sound = _make_sound(0.26, 255.0, 71.0, 14.0, 37)
	_wreck_sound = _make_sound(0.94, 70.0, 23.0, 4.3, 156)
	_small_shot_sound = _make_sound(0.13, 340.0, 98.0, 16.0, 219)
	_small_tracer = BoxMesh.new()
	_small_tracer.size = Vector3(0.028, 0.028, 1.0)
	_allied_tracer = _surface(true, false)
	_allied_tracer.albedo_color = Color("#fff09b")
	_hostile_tracer = _surface(true, false)
	_hostile_tracer.albedo_color = Color("#ffac72")
	_blast_ring_mesh = TorusMesh.new()
	_blast_ring_mesh.inner_radius = 0.81
	_blast_ring_mesh.outer_radius = 1.0
	_blast_ring_mesh.rings = 24
	_blast_ring_mesh.ring_segments = 6


func muzzle_flash(at: Vector3, direction: Vector3) -> void:
	var axis := direction.normalized()
	if axis.is_zero_approx():
		axis = Vector3.FORWARD
	var flash := Node3D.new()
	add_child(flash)
	var up := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.99 else Vector3.UP
	flash.look_at_from_position(at, at + axis, up)
	_add_flash_lobe(flash, Color("#ff9e42"), Vector3(0.59, 0.59, 1.42), -0.28)
	_add_flash_lobe(flash, Color("#fff7c3"), Vector3(0.35, 0.35, 1.22), -0.21)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffb86b")
	light.light_energy = 2.2
	light.omni_range = 5.5
	flash.add_child(light)
	var decay := flash.create_tween().set_parallel(true)
	decay.tween_property(flash, "scale", Vector3(0.03, 0.03, 0.68), 0.105)
	decay.tween_property(light, "light_energy", 0.0, 0.105)
	decay.chain().tween_callback(flash.queue_free)

	var smoke := _burst(_smoke_mesh, axis, 4, 0.63, Vector2(0.8, 2.6), 36.0)
	smoke.gravity = Vector3.UP * 1.35
	smoke.scale_amount_min = 0.30
	smoke.scale_amount_max = 0.70
	smoke.color_ramp = _fade(Color(0.56, 0.51, 0.42, 0.48))
	_emit(smoke, at)
	_play_sound(_fire_sound, at, -5.2)


func impact(at: Vector3, normal: Vector3, tank_hit: bool) -> void:
	var axis := (normal + Vector3.UP * 0.55).normalized()
	if axis.is_zero_approx():
		axis = Vector3.UP
	var dust := _burst(_smoke_mesh, axis, 7, 0.55, Vector2(1.0, 3.7), 60.0)
	dust.gravity = Vector3.UP * 0.55
	dust.scale_amount_min = 0.27
	dust.scale_amount_max = 0.8
	var dust_color := Color(0.45, 0.41, 0.35, 0.66) if tank_hit else Color(0.70, 0.61, 0.44, 0.67)
	dust.color_ramp = _fade(dust_color)
	_emit(dust, at + axis * 0.065)

	var sparks := _burst(_spark_mesh, axis, 12 if tank_hit else 5, 0.23, Vector2(4.0, 11.0), 73.0)
	sparks.gravity = Vector3.DOWN * 16.0
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = 0.64
	sparks.scale_amount_max = 1.28
	sparks.color_ramp = _fade(Color("#ffc86b") if tank_hit else Color("#e1d2a9"))
	_emit(sparks, at + axis * 0.045)
	_play_sound(_hit_sound, at, -7.0 if tank_hit else -12.0)


func small_shot(from: Vector3, to: Vector3, friendly: bool, aircraft: bool) -> void:
	var span := to - from
	if span.length_squared() < 0.01:
		return
	var axis := span.normalized()
	var up := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var length := minf(2.1 if aircraft else 1.4, span.length())
	var tracer := MeshInstance3D.new()
	tracer.mesh = _small_tracer
	tracer.material_override = _allied_tracer if friendly else _hostile_tracer
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)
	tracer.look_at_from_position(from + axis * length * 0.5, from + axis * length, up)
	tracer.scale = Vector3(1.35 if aircraft else 1.0, 1.0, length)
	var flight := tracer.create_tween()
	flight.tween_property(tracer, "position", to - axis * length * 0.5, 0.13 if aircraft else 0.095)
	flight.tween_callback(tracer.queue_free)
	_play_sound(_small_shot_sound, from, -17.0 if aircraft else -14.5)


func wreck(at: Vector3) -> void:
	var center := at + Vector3.UP * 1.30
	var flame := _burst(_fire_mesh, Vector3.UP, 23, 0.77, Vector2(2.8, 6.7), 88.0)
	flame.gravity = Vector3.UP * 1.5
	flame.scale_amount_min = 0.74
	flame.scale_amount_max = 1.75
	flame.color_ramp = _fade(Color("#ff8a35"))
	flame.color_ramp.set_color(0, Color(1.0, 0.95, 0.52))
	_emit(flame, center)

	var smoke := _burst(_smoke_mesh, Vector3.UP, 26, 2.3, Vector2(0.8, 2.2), 52.0)
	smoke.explosiveness = 0.52
	smoke.gravity = Vector3(0.9, 1.0, 0.37)
	smoke.scale_amount_min = 0.65
	smoke.scale_amount_max = 1.75
	smoke.color_ramp = _fade(Color(0.15, 0.135, 0.12, 0.78))
	_emit(smoke, center)
	_play_sound(_wreck_sound, center, -3.8)


func building_collapse(at: Vector3) -> void:
	var dust := _burst(_smoke_mesh, Vector3.UP, 34, 1.45, Vector2(2.3, 6.2), 86.0)
	dust.gravity = Vector3(0.30, 0.35, -0.22)
	dust.scale_amount_min = 0.72
	dust.scale_amount_max = 2.05
	dust.color_ramp = _fade(Color(0.67, 0.58, 0.46, 0.80))
	_emit(dust, at + Vector3.UP * 0.45)
	_play_sound(_wreck_sound, at, -6.0)


func bomb_blast(at: Vector3) -> void:
	var flash := Node3D.new()
	add_child(flash)
	flash.global_position = at + Vector3.UP * 0.42
	_add_flash_lobe(flash, Color("#ff8c36"), Vector3(2.90, 1.65, 2.90), 0.0)
	_add_flash_lobe(flash, Color("#fff2a7"), Vector3(1.20, 2.20, 1.20), 0.0)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc373")
	light.light_energy = 4.0
	light.omni_range = 9.0
	flash.add_child(light)
	var decay := flash.create_tween().set_parallel(true)
	decay.tween_property(flash, "scale", Vector3.ONE * 0.12, 0.15)
	decay.tween_property(light, "light_energy", 0.0, 0.15)
	decay.chain().tween_callback(flash.queue_free)

	var dust_ring := MeshInstance3D.new()
	dust_ring.mesh = _blast_ring_mesh
	dust_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dust_material := _surface(true, false)
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.albedo_color = Color(0.68, 0.59, 0.44, 0.62)
	dust_ring.material_override = dust_material
	add_child(dust_ring)
	dust_ring.global_position = at + Vector3.UP * 0.095
	dust_ring.scale = Vector3(0.68, 0.58, 0.68)
	var spread := dust_ring.create_tween().set_parallel(true)
	spread.tween_property(dust_ring, "scale", Vector3(4.15, 0.76, 4.15), 0.44).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	spread.tween_property(dust_material, "albedo_color:a", 0.0, 0.44)
	spread.chain().tween_callback(dust_ring.queue_free)

	var dust := _burst(_smoke_mesh, Vector3.UP, 13, 0.79, Vector2(2.8, 7.0), 87.0)
	dust.gravity = Vector3.UP * 0.43
	dust.scale_amount_min = 0.65
	dust.scale_amount_max = 1.42
	dust.color_ramp = _fade(Color(0.68, 0.59, 0.43, 0.57))
	_emit(dust, at + Vector3.UP * 0.15)

	var smoke := _burst(_smoke_mesh, Vector3.UP, 17, 1.85, Vector2(0.85, 3.0), 47.0)
	smoke.explosiveness = 0.69
	smoke.gravity = Vector3(0.45, 1.25, -0.27)
	smoke.scale_amount_min = 0.85
	smoke.scale_amount_max = 1.75
	smoke.color_ramp = _fade(Color(0.24, 0.21, 0.17, 0.72))
	_emit(smoke, flash.global_position)
	_play_sound(_wreck_sound, at, -1.8)


func _add_flash_lobe(parent: Node3D, color: Color, size: Vector3, offset: float) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _flash_mesh
	var material := _surface(true, false)
	material.albedo_color = color
	mesh.material_override = material
	mesh.position.z = offset
	mesh.scale = size
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


func _burst(mesh: Mesh, axis: Vector3, count: int, life: float, speed: Vector2, spread: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = life
	particles.explosiveness = 0.88
	particles.mesh = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.direction = axis
	particles.spread = spread
	particles.initial_velocity_min = speed.x
	particles.initial_velocity_max = speed.y
	return particles


func _emit(particles: CPUParticles3D, at: Vector3) -> void:
	add_child(particles)
	particles.global_position = at
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


func _fade(color: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r * 0.67, color.g * 0.67, color.b * 0.67, 0.0))
	ramp.add_point(0.37, color)
	return ramp


func _sphere(radius: float, material: Material, segments: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = 4
	mesh.material = material
	return mesh


func _surface(unshaded: bool, particle_alpha: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if particle_alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
	return material


func _play_sound(stream: AudioStream, at: Vector3, volume: float) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume
	player.max_distance = 70.0
	player.unit_size = 16.0
	add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


func _make_sound(duration: float, start_pitch: float, end_pitch: float, decay: float, seed_value: int) -> AudioStreamWAV:
	var frames := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var phase := 0.0
	var low_noise := 0.0
	for index in frames:
		var t := float(index) / SAMPLE_RATE
		var white := random.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, white, 0.17)
		var pitch := lerpf(end_pitch, start_pitch, exp(-t * 14.0))
		phase += TAU * pitch / SAMPLE_RATE
		var bass := sin(phase) * exp(-t * decay) * 0.62
		var air := low_noise * exp(-t * decay * 0.69) * 0.61
		var transient := white * exp(-t * 40.0) * 0.43
		var envelope := minf(1.0, t * 800.0) * (1.0 - smoothstep(duration * 0.78, duration, t))
		var sample := clampf((bass + air + transient) * envelope, -0.97, 0.97)
		data.encode_s16(index * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream
