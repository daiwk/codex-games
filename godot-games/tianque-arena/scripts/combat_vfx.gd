class_name CombatVFX
extends Node3D
## Visual-only, bounded-lifetime effects. Never reads or changes combat state.
## One batched mesh per effect; no particles, textures, or gameplay RNG needed.

var kind := "slash"
var tint := Color(1.0, 0.38, 0.08)
var radius := 2.5
var lifetime := 0.4
var variant := 1
var actor: Node3D
var age := 0.0
var geometry := ImmediateMesh.new()
var mesh_instance := MeshInstance3D.new()
var history: Array[Vector3] = []
var sample_clock := 0.0
static var shared_material: ShaderMaterial

static func emit(parent: Node3D, effect: String, at: Vector3, color: Color, size: float, duration: float, forward: Vector3 = Vector3.FORWARD, step: int = 1, follow: Node3D = null) -> CombatVFX:
	var node := CombatVFX.new()
	node.kind = effect
	node.tint = color
	node.radius = size
	node.lifetime = duration
	node.variant = step
	node.actor = follow
	node.position = at
	node.rotation.y = atan2(-forward.x, -forward.z)
	parent.add_child(node)
	return node

func _ready() -> void:
	name = "VFX_" + kind
	add_to_group("combat_vfx")
	if shared_material == null:
		shared_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
varying vec4 ink;
void vertex() { ink = COLOR; }
void fragment() {
 float edge = pow(max(0.0, 1.0 - abs(UV.y * 2.0 - 1.0)), 0.65);
 float grain = 0.78 + 0.22 * sin(UV.x * 137.0 + sin(UV.x * 43.0) * 4.0 + UV.y * 21.0);
 ALBEDO = ink.rgb * 2.2;
 ALPHA = ink.a * edge * grain;
}
"""
		shared_material.shader = shader
	mesh_instance.mesh = geometry
	mesh_instance.material_override = shared_material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	_draw_effect()

func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	if kind == "dash" and is_instance_valid(actor) and age < 0.20:
		sample_clock += delta
		if sample_clock >= 0.016 or history.is_empty():
			history.append(to_local(actor.global_position) + Vector3(0, 0.7, 0))
			sample_clock = 0.0
	_draw_effect()

func _vertex(point: Vector3, uv: Vector2, color: Color) -> void:
	geometry.surface_set_color(color)
	geometry.surface_set_uv(uv)
	geometry.surface_set_normal(Vector3.UP)
	geometry.surface_add_vertex(point)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, u0: float = 0.0, u1: float = 1.0) -> void:
	_vertex(a, Vector2(u0, 0), color)
	_vertex(b, Vector2(u0, 1), color)
	_vertex(c, Vector2(u1, 1), color)
	_vertex(a, Vector2(u0, 0), color)
	_vertex(c, Vector2(u1, 1), color)
	_vertex(d, Vector2(u1, 0), color)

func _ribbon(points: Array[Vector3], width: float, color: Color, vertical: bool = false) -> void:
	for i in range(points.size() - 1):
		var u := float(i) / (points.size() - 1)
		var v := float(i + 1) / (points.size() - 1)
		var side := Vector3.UP if vertical else (points[i + 1] - points[i]).cross(Vector3.UP).normalized()
		var w0 := width * pow(sin(u * PI), 0.65)
		var w1 := width * pow(sin(v * PI), 0.65)
		_quad(points[i] - side * w0, points[i] + side * w0, points[i + 1] + side * w1, points[i + 1] - side * w1, color, u, v)

func _line(a: Vector3, b: Vector3, width: float, color: Color, vertical: bool = false) -> void:
	_ribbon([a, a.lerp(b, 0.3), a.lerp(b, 0.7), b], width, color, vertical)

func _pillar(bottom: Vector3, top: Vector3, width: float, color: Color) -> void:
	# Crossed planes keep vertical star-light visible from the top-down camera.
	for side in [Vector3.RIGHT, Vector3.BACK]:
		_quad(bottom - side * width, bottom + side * width, top + side * width * 0.25, top - side * width * 0.25, color)

func _color(alpha: float, white: float = 0.0) -> Color:
	var color := tint.lerp(Color(1.0, 0.98, 0.83), white)
	color.a = alpha
	return color

func _random(index: int) -> float:
	return fposmod(sin(float(index * 127 + 31) * 12.9898) * 43758.5453, 1.0)

func _draw_effect() -> void:
	geometry.clear_surfaces()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := clampf(age / lifetime, 0.0, 1.0)
	match kind:
		"slash", "heavy": _slash(t)
		"heavy_charge": _heavy_charge(t)
		"star_charge": _star_charge(t)
		"star", "burst": _burst(t)
		"impact": _impact(t)
		"dash": _dash(t)
		"heal": _heal(t)
	# Keep empty first-frame dash meshes valid.
	_quad(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color(0, 0, 0, 0))
	geometry.surface_end()

func _slash(t: float) -> void:
	var heavy := kind == "heavy"
	var sweep := 1.0 - pow(1.0 - clampf(t * 2.4, 0.0, 1.0), 3.0)
	var fade := pow(1.0 - t, 1.25)
	var sign_value := -1.0 if variant == 2 else 1.0
	for layer in range(0 if heavy else 3):
		var points: Array[Vector3] = []
		for i in range(33):
			var u := float(i) / 32.0
			var angle := lerpf(-1.15, 1.15, u) + (sweep - 1.0) * 1.0
			angle *= sign_value
			var r := radius * (0.93 + sweep * 0.07) - layer * 0.15 + sin(u * PI) * 0.10
			var y := 0.65 + sin(u * PI) * (0.7 if variant == 3 else 0.12)
			if variant == 2: y += (u - 0.5) * 0.65
			if heavy: y += (u - 0.5) * 0.8
			points.append(Vector3(sin(angle) * r, y, -cos(angle) * r))
		_ribbon(points, (0.48 if heavy else 0.34) * (1.0 if layer == 0 else 0.14), _color(fade * (0.75 if layer == 0 else 1.0), 0.8 if layer == 1 else 0.0))
	if heavy:
		# The overhead cleave leaves a tall descending blade, distinct from J sweeps.
		var cleave: Array[Vector3] = []
		for i in range(19):
			var u := float(i) / 18.0
			cleave.append(Vector3(-1.4 + u * 2.6, 3.8 * (1.0 - u) + 0.15, -0.7 - u * 2.2))
		_ribbon(cleave, 0.65, _color(fade * 0.8))
		_ribbon(cleave, 0.11, _color(fade, 0.85))
	# Torn, asymmetric brush tails curl behind the leading blade edge.
	for tail in range(0 if heavy else 3):
		var points: Array[Vector3] = []
		for j in range(15):
			var u := float(j) / 14.0
			var angle := (-1.45 + u * (1.2 + tail * 0.24) + sweep * 0.25) * sign_value
			var r := radius * (0.68 + u * 0.3) - tail * 0.16
			points.append(Vector3(sin(angle) * r, 0.6 + tail * 0.07 + u * 0.12, -cos(angle) * r))
		_ribbon(points, 0.075, _color(fade * 0.5, 0.05))
	# Fine detached ember strokes continue tangent to the blade, not a second ring.
	for i in range(10 if heavy else 6):
		var angle := (-0.95 + float(i) * 0.32) * sign_value
		var direction := Vector3(sin(angle), 0.15 + _random(i) * 0.4, -cos(angle))
		var p := direction * (radius * 0.78 + t * (1.1 if heavy else 0.55)) + Vector3(0, 0.4, 0)
		_line(p, p - Vector3(cos(angle), 0.1, sin(angle)) * sign_value * (0.25 + _random(i + 4) * 0.35), 0.025, _color(fade, 0.65), true)

func _heavy_charge(t: float) -> void:
	var fade := sin(t * PI) * 0.65
	for i in range(8):
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -0.5 - float(i / 2) * 0.65
		var p := Vector3(side * (1.5 - t * 1.2), 0.15 + t * 0.4, z)
		_line(p, p + Vector3(-side * 0.55, 0.0, -0.4), 0.055, _color(fade, 0.2))
	_line(Vector3(0, 0.12, -0.4), Vector3(0, 0.12, -3.25), 0.12 * t, _color(fade, 0.5))

func _star_charge(t: float) -> void:
	var fade := sin(t * PI * 0.85) * 0.6
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var outer := Vector3(sin(angle), 0, cos(angle)) * radius
		# Broken inward-pointing runic strokes mark the true landing footprint.
		_line(outer + Vector3(0, 0.08, 0), outer * 0.86 + Vector3(0, 0.08, 0), 0.05, _color(fade))
		var points: Array[Vector3] = []
		for j in range(9):
			var u := float(j) / 8.0
			var a := angle + u * 0.35 + t * 0.8
			var r := (1.0 - u * 0.75) * (1.0 - t * 0.65) * radius * 0.7
			points.append(Vector3(sin(a) * r, 0.1 + u * u * 1.9, cos(a) * r))
		_ribbon(points, 0.035, _color(fade * 0.6), true)
	if t > 0.52:
		var fall := (t - 0.52) / 0.48
		var bottom := Vector3(0, lerpf(7.0, 0.2, fall), 0)
		_pillar(bottom, bottom + Vector3(0.22, 3.5, 0.1), 0.22, _color(fall * 0.85, 0.75))

func _burst(t: float) -> void:
	var extent := radius * (1.0 - pow(1.0 - t, 5.0))
	var fade := pow(1.0 - t, 1.5)
	for i in range(22):
		var angle := TAU * float(i) / 22.0
		var direction := Vector3(sin(angle), 0, cos(angle))
		var tangent := Vector3(cos(angle), 0, -sin(angle))
		var length_value := extent * (0.7 + _random(i) * 0.3)
		var points: Array[Vector3] = []
		for j in range(6):
			var u := float(j) / 5.0
			points.append(direction * length_value * u + tangent * sin(u * 14.0 + i) * 0.13 * u + Vector3(0, 0.09, 0))
		_ribbon(points, 0.055, _color(fade * 0.75, 0.2))
		var p := direction * length_value + Vector3(0, sin(t * PI) * (0.25 + _random(i + 13)), 0)
		_line(p - direction * 0.4, p, 0.035, _color(fade, 0.55), true)
	# An asymmetric vertical star pillar collapses quickly while ground sparks linger.
	if kind == "star":
		var flash := maxf(0.0, 1.0 - t * 3.5)
		_pillar(Vector3(0, 0.15, 0), Vector3(0.1, 9.2 * flash, 0), 0.42 * flash, _color(flash, 0.85))
		_pillar(Vector3(0, 0.15, 0), Vector3(0, 8.5 * flash, 0), 0.85 * flash, _color(flash * 0.16))
		_line(Vector3(-1.5 * flash, 0.25, 0), Vector3(1.5 * flash, 0.25, 0), 0.16, _color(flash, 0.65))
	# Fragmented low wisps at the shock front, never a solid torus wall.
	for i in range(9):
		var points: Array[Vector3] = []
		for j in range(8):
			var angle := float(i) * TAU / 9.0 + float(j) / 7.0 * 0.42
			points.append(Vector3(sin(angle) * extent, 0.15 + sin(t * PI) * 0.13, cos(angle) * extent))
		_ribbon(points, 0.14 * (1.0 - t), _color(fade * 0.38))

func _impact(t: float) -> void:
	var fade := pow(1.0 - t, 2.0)
	for i in range(12):
		var angle := float(i) * 2.39996
		var dir := Vector3(sin(angle), 0.2 + _random(i) * 0.8, cos(angle)).normalized()
		var p := dir * radius * (0.15 + t * 1.3)
		p.y -= t * t * 0.8
		_line(p, p - dir * (0.2 + 0.4 * (1.0 - t)) * radius, 0.035, _color(fade, 0.5), true)
	_line(Vector3(-0.5, 0, 0) * radius, Vector3(0.5, 0, 0) * radius, 0.12, _color(maxf(0, 1.0 - t * 4), 0.9))

func _dash(t: float) -> void:
	var fade := pow(1.0 - t, 1.3)
	if history.size() < 2: return
	for lane in range(5):
		var points: Array[Vector3] = []
		for i in range(history.size()):
			var u := float(i) / (history.size() - 1)
			points.append(history[i] + Vector3(sin(u * PI) * (lane - 2) * 0.18, (lane - 2) * 0.25, 0))
		_ribbon(points, 0.18 if lane == 2 else 0.085, _color(fade * 0.95, 0.7 if lane == 2 else 0.0), true)
	for i in range(8):
		var p := history[0] + Vector3((_random(i) - 0.5) * 1.3, _random(i + 8), t * 0.6)
		_line(p, p + Vector3(0, 0.05, 0.3), 0.02, _color(fade * 0.5))

func _heal(t: float) -> void:
	var fade := sin(PI * t)
	for lane in range(4):
		var points: Array[Vector3] = []
		for i in range(25):
			var u := float(i) / 24.0
			var a := lane * TAU / 4.0 + u * 2.5 + t * 2.3
			var r := (0.8 - u * 0.42) * (1.0 - t * 0.25)
			points.append(Vector3(sin(a) * r, u * 1.9 + t * 0.35, cos(a) * r))
		_ribbon(points, 0.13, _color(fade * 0.8, 0.05), true)
	for i in range(12):
		var angle := float(i) * 2.39996 + t
		var p := Vector3(sin(angle) * (0.5 + _random(i) * 0.5), fposmod(_random(i + 12) + t, 1.0) * 2.4, cos(angle) * 0.75)
		_line(p, p + Vector3(0.04, 0.18, 0), 0.045, _color(fade, 0.55))
