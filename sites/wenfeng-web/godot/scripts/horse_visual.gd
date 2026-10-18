extends Node3D
class_name DuelHorse

# User-supplied brown/white horses retain their original textured materials.
# Their rebuilt rigs carry the CC0 Quaternius Idle/Walk/Gallop clips in metres.
# This node owns visuals only; its parent owns movement and combat.
const COLORS = ["brown", "white"]
const HORSE_SCENES = {
	"brown": "res://assets/mounts/horse_brown.glb",
	"white": "res://assets/mounts/horse_white.glb",
}
const MANIFEST_PATH = "res://assets/mounts/manifest.json"
const SADDLE_SCENE_PATH = "res://assets/mounts/saddle.glb"
const SADDLE_MANIFEST_PATH = "res://assets/mounts/saddle_manifest.json"
const MODEL_SCALE = 1.0

var character_id = "guanyu"
var horse_color = "brown"
var belly_width = 0.68
var _saddle_surface = Vector3(0, 1.6, -0.18)
var _head_anchor = Vector3(0, 1.95, 1.075)
var _seat_offset_y = 0.05
var _model: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _saddle_frame: Node3D
var _saddle_model: Node3D
var _saddle_fit: Dictionary = {}
var _seat: Marker3D
var _bit_left: Marker3D
var _bit_right: Marker3D
var _hand_left: Marker3D
var _hand_right: Marker3D
var _reins: Array[MeshInstance3D] = []
var _leather_material: StandardMaterial3D
var _metal_material: StandardMaterial3D
var _stirrup_frames: Array[Node3D] = []
var _stirrup_straps: Array[MeshInstance3D] = []
var _rider_skeleton: Skeleton3D
var _rider_feet: Array[Dictionary] = []
var _motion_speed = 0.0
var _clips: Dictionary = {}

func _ready() -> void:
	_ensure_visual()

func setup(id: String, color: String = "brown") -> void:
	var selected = color if color in COLORS else "brown"
	var changed = horse_color != selected
	character_id = id
	horse_color = selected
	if is_inside_tree():
		if changed:
			_clear_visual()
		_ensure_visual()

func saddle_height() -> float:
	return saddle_transform().origin.y

func saddle_z() -> float:
	return saddle_transform().origin.z

func saddle_transform() -> Transform3D:
	# Local to the parent fighter, in metres; its world elevation is excluded.
	# Reading each frame
	# lets the rider follow the same back bone as the saddle during a gallop.
	if is_instance_valid(_seat):
		var parent = get_parent() as Node3D
		var pose = parent.global_transform.affine_inverse() * _seat.global_transform if parent != null else global_transform.affine_inverse() * _seat.global_transform
		pose.basis = pose.basis.orthonormalized()
		return pose
	return transform * Transform3D(Basis.IDENTITY, _saddle_surface + Vector3.UP * _seat_offset_y)

func update_motion(delta: float, speed: float, turn_rate: float, defeated = false) -> void:
	if not is_instance_valid(_animation_tree):
		return
	var turning_step = minf(absf(turn_rate) * 0.55, 1.15)
	var target = 0.0 if defeated else maxf(absf(speed), turning_step)
	_motion_speed = lerpf(_motion_speed, target, 1.0 - exp(-maxf(delta, 0.0) * 8.0))
	if _motion_speed < 0.035:
		_motion_speed = 0.0
	_animation_tree.set("parameters/Gait/blend_position", clampf(_motion_speed, 0.0, 7.2))
	var cadence = clampf(_motion_speed / 4.8, 0.78, 1.35) if _motion_speed > 3.4 else clampf(_motion_speed / 1.65, 0.78, 1.20)
	_animation_tree.set("parameters/Cadence/scale", 0.80 if _motion_speed < 0.1 else cadence)
	# Deliberately keep a standing horse under a defeated rider. The authored
	# sideways Death clip is reserved for a future proper dismount animation.

func reset_motion() -> void:
	_motion_speed = 0.0
	if not is_instance_valid(_animation_tree):
		return
	_animation_tree.active = false
	_animation_player.play(_clips.Idle, 0.0)
	_animation_player.advance(0.0)
	_animation_player.pause()
	_animation_tree.set("parameters/Gait/blend_position", 0.0)
	_animation_tree.set("parameters/Cadence/scale", 0.80)
	_animation_tree.active = true

func _process(_delta: float) -> void:
	_cache_rider_feet()
	_update_stirrup_straps()
	_update_reins()

func _disconnect_rider() -> void:
	if is_instance_valid(_rider_skeleton) and _rider_skeleton.skeleton_updated.is_connected(_on_rider_skeleton_updated):
		_rider_skeleton.skeleton_updated.disconnect(_on_rider_skeleton_updated)

func _exit_tree() -> void:
	_disconnect_rider()

func _clear_visual() -> void:
	_disconnect_rider()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_model = null
	_skeleton = null
	_animation_player = null
	_animation_tree = null
	_saddle_frame = null
	_saddle_model = null
	_saddle_fit.clear()
	_seat = null
	_bit_left = null
	_bit_right = null
	_hand_left = null
	_hand_right = null
	_reins.clear()
	_stirrup_frames.clear()
	_stirrup_straps.clear()
	_rider_feet.clear()
	_rider_skeleton = null
	_clips.clear()
	_motion_speed = 0.0
	_leather_material = null
	_metal_material = null

func _ensure_visual() -> void:
	if is_instance_valid(_model):
		return
	assert(FileAccess.file_exists(MANIFEST_PATH), "Prepare the user horse assets with tools/prepare_mounts.py before playing mounted mode")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(manifest.has(horse_color), "The selected horse requires its prepared mount metadata")
	var data: Dictionary = manifest[horse_color]
	belly_width = float(data.get("belly_width", 0.68))
	var saddle: Array = data.saddle_surface
	var head: Array = data.head_anchor
	_saddle_surface = Vector3(saddle[0], saddle[1], saddle[2])
	_head_anchor = Vector3(head[0], head[1], head[2])
	assert(FileAccess.file_exists(SADDLE_MANIFEST_PATH), "Prepare the supplied saddle with tools/prepare_saddle.py")
	var saddle_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SADDLE_MANIFEST_PATH))
	_saddle_fit = saddle_manifest.fits[horse_color]
	_seat_offset_y = float(_saddle_fit.rider_seat_y)
	var scene = load(HORSE_SCENES[horse_color]) as PackedScene
	assert(scene != null, "The selected user horse GLB is required")
	_model = scene.instantiate()
	_model.name = "AnimatedHorse"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_skeleton = _find(_model, "Skeleton3D") as Skeleton3D
	_animation_player = _find(_model, "AnimationPlayer") as AnimationPlayer
	assert(_skeleton != null and _animation_player != null, "Horse requires its supplied skeleton and animations")
	for key in _animation_player.get_animation_list():
		var short_name = String(key).get_slice("/", String(key).get_slice_count("/") - 1)
		if short_name in ["Idle", "Walk", "Gallop"]:
			_clips[short_name] = key
			_animation_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
	assert(_clips.has("Idle") and _clips.has("Walk") and _clips.has("Gallop"), "Horse requires authored standing, walking and galloping clips")
	_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_animation_player.play(_clips.Idle, 0.0)
	_animation_player.advance(0.0)
	_animation_player.pause()
	_skeleton.force_update_all_bone_transforms()
	_leather_material = _material(Color("34251d"), 0.0)
	_metal_material = _material(Color("aa8954"), 0.55)
	_build_tack()
	_build_gait_tree()
	reset_motion()

func _find(node: Node, kind: String) -> Node:
	if node.is_class(kind):
		return node
	for child in node.get_children():
		var found = _find(child, kind)
		if found != null:
			return found
	return null

func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.55 if metallic > 0.0 else 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _build_gait_tree() -> void:
	var gait = AnimationNodeBlendSpace1D.new()
	gait.min_space = 0.0
	gait.max_space = 7.2
	gait.sync = true
	for data in [["Idle", 0.0], ["Walk", 1.8], ["Gallop", 7.2]]:
		var clip = AnimationNodeAnimation.new()
		clip.animation = _clips[data[0]]
		gait.add_blend_point(clip, float(data[1]), -1, StringName(data[0]))
	var graph = AnimationNodeBlendTree.new()
	graph.add_node("Gait", gait, Vector2(-320, 0))
	graph.add_node("Cadence", AnimationNodeTimeScale.new(), Vector2(-140, 0))
	graph.connect_node("Cadence", 0, "Gait")
	graph.connect_node("output", 0, "Cadence")
	_animation_tree = AnimationTree.new()
	_animation_tree.name = "HorseGait"
	add_child(_animation_tree)
	_animation_tree.anim_player = _animation_tree.get_path_to(_animation_player)
	_animation_tree.tree_root = graph
	_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_animation_tree.active = true

func _bone_frame(bone_name: String, point: Vector3) -> Node3D:
	var index = _skeleton.find_bone(bone_name)
	assert(index >= 0, "Horse tack attachment bone is required: " + bone_name)
	var model_from_skeleton = _model.global_transform.affine_inverse() * _skeleton.global_transform
	var bone_in_model: Transform3D = model_from_skeleton * _skeleton.get_bone_global_rest(index)
	var attachment = BoneAttachment3D.new()
	attachment.name = bone_name + "TackSocket"
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	var frame = Node3D.new()
	frame.name = bone_name + "Tack"
	attachment.add_child(frame)
	frame.transform = bone_in_model.affine_inverse() * Transform3D(Basis.IDENTITY, point)
	return frame

func _marker(parent: Node3D, label: String, position_m: Vector3) -> Marker3D:
	var marker = Marker3D.new()
	marker.name = label
	marker.position = position_m
	parent.add_child(marker)
	return marker

func _build_tack() -> void:
	_saddle_frame = _bone_frame("MountSaddle", _saddle_surface)
	_seat = _marker(_saddle_frame, "RiderSeat", Vector3(0, _seat_offset_y, 0))
	_hand_left = _marker(_saddle_frame, "LeftReinHand", Vector3(-0.16, _seat_offset_y + 0.17, 0.22))
	_hand_right = _marker(_saddle_frame, "RightReinHand", Vector3(0.16, _seat_offset_y + 0.17, 0.22))
	# The supplied textured saddle replaces both temporary thin cloth surfaces
	# and their decorative rods. It shares the same animated back socket.
	var saddle_scene = load(SADDLE_SCENE_PATH) as PackedScene
	assert(saddle_scene != null, "The supplied saddle GLB is required")
	_saddle_model = saddle_scene.instantiate()
	_saddle_model.name = "FittedSaddle"
	_saddle_frame.add_child(_saddle_model)
	var saddle_offset: Array = _saddle_fit.saddle_offset
	_saddle_model.position = Vector3(saddle_offset[0], saddle_offset[1], saddle_offset[2])
	var saddle_mesh = _find(_saddle_model, "MeshInstance3D") as MeshInstance3D
	assert(saddle_mesh != null and saddle_mesh.mesh.get_blend_shape_count() == 1, "Saddle requires its fitted white-horse panel shape")
	saddle_mesh.set_blend_shape_value(0, 1.0 if horse_color == "white" else 0.0)
	for side in [1.0, -1.0]:
		var frame = Node3D.new()
		frame.name = "LeftStirrup" if side > 0.0 else "RightStirrup"
		frame.position = Vector3(side * 0.43, _seat_offset_y - 0.57, 0.18)
		_saddle_frame.add_child(frame)
		# BoneAttachment may update after the rider modifier. Keep the sampled
		# world-space boot contact independent of subsequent horse-back motion.
		var initial_transform = frame.global_transform
		frame.top_level = true
		frame.global_transform = initial_transform
		# A forward-facing opening and flat tread hold the boot. The former
		# torus faced sideways and hung empty beside the rider's foot.
		for index in 8:
			var a = PI * float(index) / 8.0
			var b = PI * float(index + 1) / 8.0
			_tack_rod(frame, Vector3(cos(a) * 0.065, 0.02 + sin(a) * 0.065, 0), Vector3(cos(b) * 0.065, 0.02 + sin(b) * 0.065, 0), 0.008, _metal_material)
		for x in [-0.065, 0.065]:
			_tack_rod(frame, Vector3(x, 0.02, 0), Vector3(x, -0.07, 0), 0.008, _metal_material)
		var tread = MeshInstance3D.new()
		var tread_mesh = BoxMesh.new()
		tread_mesh.size = Vector3(0.145, 0.018, 0.065)
		tread.mesh = tread_mesh
		tread.material_override = _metal_material
		tread.position.y = -0.07
		frame.add_child(tread)
		_batch_tack(frame)
		_stirrup_frames.append(frame)
		var strap = MeshInstance3D.new()
		var strap_mesh = CylinderMesh.new()
		strap_mesh.top_radius = 0.011
		strap_mesh.bottom_radius = 0.011
		strap_mesh.height = 1.0
		strap_mesh.radial_segments = 6
		strap.mesh = strap_mesh
		strap.material_override = _leather_material
		strap.name = "StirrupLeather"
		_saddle_frame.add_child(strap)
		_stirrup_straps.append(strap)
	var head_frame = _bone_frame("Head", _head_anchor)
	for index in 12:
		var a = TAU * float(index) / 12.0
		var b = TAU * float(index + 1) / 12.0
		_tack_rod(head_frame, Vector3(sin(a) * 0.13, -0.22 + cos(a) * 0.065, 0.20), Vector3(sin(b) * 0.13, -0.22 + cos(b) * 0.065, 0.20), 0.010, _leather_material)
	for side in [-1.0, 1.0]:
		_tack_rod(head_frame, Vector3(side * 0.13, -0.22, 0.20), Vector3(side * 0.12, 0.10, -0.10), 0.010, _leather_material)
	_bit_left = _marker(head_frame, "LeftBit", Vector3(-0.14, -0.22, 0.20))
	_bit_right = _marker(head_frame, "RightBit", Vector3(0.14, -0.22, 0.20))
	_batch_tack(head_frame)
	for _index in 10:
		var mesh = CylinderMesh.new()
		mesh.top_radius = 0.0055
		mesh.bottom_radius = 0.0055
		mesh.height = 1.0
		mesh.radial_segments = 5
		var rein = MeshInstance3D.new()
		rein.mesh = mesh
		rein.material_override = _leather_material
		rein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rein)
		_reins.append(rein)

func _tack_rod(parent: Node3D, start_m: Vector3, end_m: Vector3, radius_m: float, material: Material) -> void:
	var delta = end_m - start_m
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius_m
	mesh.bottom_radius = radius_m
	mesh.height = delta.length()
	mesh.radial_segments = 6
	var rod = MeshInstance3D.new()
	rod.mesh = mesh
	rod.material_override = material
	rod.position = (start_m + end_m) * 0.5
	rod.quaternion = Quaternion(Vector3.UP, delta.normalized())
	parent.add_child(rod)

func _batch_tack(frame: Node3D) -> void:
	# One draw surface per tack material, rather than dozens of tiny rods.
	var groups: Dictionary = {}
	for child in frame.get_children():
		if child is MeshInstance3D:
			var key = child.material_override.get_instance_id()
			if not groups.has(key):
				groups[key] = []
			groups[key].append(child)
	var combined = ArrayMesh.new()
	for group in groups.values():
		var surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for instance in group:
			var arrays: Array = instance.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var normal_basis: Basis = instance.transform.basis.inverse().transposed()
			for index in indices if not indices.is_empty() else range(vertices.size()):
				surface.set_normal((normal_basis * normals[index]).normalized())
				surface.add_vertex(instance.transform * vertices[index])
		surface.commit(combined)
		combined.surface_set_material(combined.get_surface_count() - 1, group[0].material_override)
	for child in frame.get_children():
		if child is MeshInstance3D:
			frame.remove_child(child)
			child.queue_free()
	var instance = MeshInstance3D.new()
	instance.mesh = combined
	frame.add_child(instance)

func _cache_rider_feet() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_rider_skeleton):
		return
	var fighter = get_parent()
	if fighter == null:
		return
	for property in fighter.get_property_list():
		if property.name == "skeleton":
			_rider_skeleton = fighter.get("skeleton") as Skeleton3D
			break
	if not is_instance_valid(_rider_skeleton):
		return
	_rider_feet.clear()
	for side in ["Left", "Right"]:
		var foot = -1
		var toe = -1
		for index in _rider_skeleton.get_bone_count():
			var label = _rider_skeleton.get_bone_name(index)
			if label.ends_with(side + "Foot"):
				foot = index
			elif label.ends_with(side + "ToeBase"):
				toe = index
		_rider_feet.append({"foot": foot, "toe": toe})
	if not _rider_skeleton.skeleton_updated.is_connected(_on_rider_skeleton_updated):
		_rider_skeleton.skeleton_updated.connect(_on_rider_skeleton_updated)

func _on_rider_skeleton_updated() -> void:
	# SkeletonModifier3D restores its input poses after skinning. Read only this
	# signal's final output; an idle _process read sees the standing/walking legs.
	if not is_inside_tree() or not is_instance_valid(_rider_skeleton) or not _rider_skeleton.is_inside_tree():
		return
	if _stirrup_frames.size() != 2 or not is_instance_valid(_saddle_frame) or not _saddle_frame.is_inside_tree():
		return
	for index in 2:
		var frame = _stirrup_frames[index]
		if not is_instance_valid(frame) or not frame.is_inside_tree():
			continue
		if is_instance_valid(_rider_skeleton) and _rider_feet.size() == 2:
			var pair: Dictionary = _rider_feet[index]
			if int(pair.foot) >= 0 and int(pair.toe) >= 0:
				var foot: Vector3 = _rider_skeleton.to_global(_rider_skeleton.get_bone_global_pose(int(pair.foot)).origin)
				var toe: Vector3 = _rider_skeleton.to_global(_rider_skeleton.get_bone_global_pose(int(pair.toe)).origin)
				frame.global_position = foot.lerp(toe, 0.62) + Vector3.UP * 0.045
				var forward = (toe - foot).slide(Vector3.UP).normalized()
				if forward.length_squared() > 0.5:
					frame.global_basis = Basis(Vector3.UP.cross(forward).normalized(), Vector3.UP, forward)
	_update_stirrup_straps()

func _update_stirrup_straps() -> void:
	if not is_inside_tree() or _stirrup_frames.size() != 2 or not is_instance_valid(_saddle_frame) or not _saddle_frame.is_inside_tree():
		return
	for index in 2:
		var frame = _stirrup_frames[index]
		var strap = _stirrup_straps[index]
		if not is_instance_valid(frame) or not frame.is_inside_tree() or not is_instance_valid(strap) or not strap.is_inside_tree():
			continue
		var side = 1.0 if index == 0 else -1.0
		var anchor = Vector3(side * 0.255, 0.09, 0.06)
		var end = _saddle_frame.to_local(frame.to_global(Vector3(0, 0.085, 0)))
		var delta = end - anchor
		strap.position = (anchor + end) * 0.5
		strap.quaternion = Quaternion(Vector3.UP, delta.normalized())
		strap.scale.y = maxf(delta.length(), 0.001)

func _update_reins() -> void:
	if _reins.size() != 10 or not is_instance_valid(_bit_left):
		return
	for side in 2:
		var hand = _hand_left if side == 0 else _hand_right
		var bit = _bit_left if side == 0 else _bit_right
		var a = to_local(hand.global_position)
		var b = to_local(bit.global_position)
		var control = (a + b) * 0.5 + Vector3(-0.12 if side == 0 else 0.12, -0.08, 0.0)
		for index in 5:
			var t0 = float(index) / 5.0
			var t1 = float(index + 1) / 5.0
			var p0 = (1.0 - t0) * (1.0 - t0) * a + 2.0 * (1.0 - t0) * t0 * control + t0 * t0 * b
			var p1 = (1.0 - t1) * (1.0 - t1) * a + 2.0 * (1.0 - t1) * t1 * control + t1 * t1 * b
			var rod = _reins[side * 5 + index]
			rod.position = (p0 + p1) * 0.5
			rod.quaternion = Quaternion(Vector3.UP, (p1 - p0).normalized())
			rod.scale.y = maxf(p0.distance_to(p1), 0.001)
