extends SceneTree

## Bake four real gallop/rider poses into a compact ghost-cavalry vertex atlas.
## Original horse/character/weapon meshes and textures are never written.
const Fighter = preload("res://scripts/fighter.gd")
const OUTPUT = "res://assets/vfx/duel/"
const POSES = 4
const WIDTH = 256
var snapshots: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.append(node)
	for child in node.get_children():
		meshes(child, result)

func capture(rig: Skeleton3D) -> void:
	var poses: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		poses.append(rig.get_bone_global_pose(bone))
	snapshots[rig.get_instance_id()] = poses

func surface_indices(source: ArrayMesh, surface: int, limit: int) -> PackedInt32Array:
	var arrays = source.surface_get_arrays(surface)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(arrays[Mesh.ARRAY_VERTEX].size())
		for i in indices.size(): indices[i] = i
	if indices.size() / 3 <= limit:
		return indices
	var importer = ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(60.0, 60.0, [])
	var best = indices
	var best_error = absf(log(float(best.size()) / 3.0 / float(limit)))
	for i in importer.get_surface_lod_count(0):
		var candidate = importer.get_surface_lod_indices(0, i)
		var error = absf(log(float(candidate.size()) / 3.0 / float(limit)))
		if error < best_error:
			best = candidate
			best_error = error
	return best

func skin_position(mi: MeshInstance3D, arrays: Array, index: int, fighter: Node3D) -> Vector3:
	var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
	if mi.skin == null or mi.skeleton.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
		return fighter.global_transform.affine_inverse() * (mi.global_transform * vertex)
	var rig = mi.get_node(mi.skeleton) as Skeleton3D
	var poses: Array = snapshots.get(rig.get_instance_id(), [])
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count = bones.size() / arrays[Mesh.ARRAY_VERTEX].size()
	var result = Vector3.ZERO
	for weight_index in count:
		var slot = index * count + weight_index
		if weights[slot] < 0.00001: continue
		var bind_index = bones[slot]
		var bone = mi.skin.get_bind_bone(bind_index)
		if bone < 0:
			bone = rig.find_bone(mi.skin.get_bind_name(bind_index))
		var pose: Transform3D = poses[bone] if not poses.is_empty() else rig.get_bone_global_pose(bone)
		result += pose * (mi.skin.get_bind_pose(bind_index) * vertex) * weights[slot]
	return fighter.global_transform.affine_inverse() * (rig.global_transform * result)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var fighter = Fighter.new()
	fighter.character_id = "machao"
	fighter.weapon_id = "serpent_spear"
	fighter.mounted = true
	fighter.is_player = false
	root.add_child(fighter)
	fighter.set_physics_process(false)
	fighter.enabled = true
	fighter.mount_speed = 8.2
	fighter.horse._animation_tree.active = false
	var horse_rig: Skeleton3D = fighter.horse._skeleton
	var rider_rig: Skeleton3D = fighter.skeleton
	horse_rig.skeleton_updated.connect(capture.bind(horse_rig))
	rider_rig.skeleton_updated.connect(capture.bind(rider_rig))
	var horse_anim: AnimationPlayer = fighter.horse._animation_player
	horse_anim.play(fighter.horse._clips.Gallop, 0.0)
	horse_anim.pause()
	await frames(3)
	var nodes: Array = []
	meshes(fighter.horse._model, nodes)
	meshes(fighter.model, nodes)
	meshes(fighter.weapon_mesh, nodes)
	var selected: Array = []
	var sources: Array = []
	for mi: MeshInstance3D in nodes:
		if not mi.mesh is ArrayMesh: continue
		if fighter.horse._model.is_ancestor_of(mi) and mi.skin == null: continue
		for surface in mi.mesh.get_surface_count():
			var indices = surface_indices(mi.mesh, surface, 500 if fighter.weapon_mesh.is_ancestor_of(mi) else 1000)
			var arrays = mi.mesh.surface_get_arrays(surface)
			selected.append({"mesh": mi, "surface": surface, "arrays": arrays, "indices": indices})
			sources.append({"name": str(mi.get_path()), "source_triangles": mi.mesh.surface_get_array_index_len(surface) / 3, "selected_triangles": indices.size() / 3})
	var pose_points: Array[PackedVector3Array] = []
	for phase in POSES:
		horse_anim.play(fighter.horse._clips.Gallop, 0.0)
		horse_anim.seek(horse_anim.current_animation_length * float(phase) / float(POSES), true)
		horse_anim.pause()
		await frames(2)
		var points = PackedVector3Array()
		for source in selected:
			for index in source.indices:
				points.append(skin_position(source.mesh, source.arrays, index, fighter))
		pose_points.append(points)
	var count = pose_points[0].size()
	var rows = ceili(float(count) / float(WIDTH))
	var image = Image.create(WIDTH, rows * POSES, false, Image.FORMAT_RGBAF)
	for phase in POSES:
		for i in count:
			var p = pose_points[phase][i]
			image.set_pixel(i % WIDTH, i / WIDTH + rows * phase, Color(p.x, p.y, p.z, 1.0))
	var mesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pose_points[0]
	var normals = PackedVector3Array()
	for i in range(0, count, 3):
		var normal = (pose_points[0][i + 1] - pose_points[0][i]).cross(pose_points[0][i + 2] - pose_points[0][i]).normalized()
		normals.append_array(PackedVector3Array([normal, normal, normal]))
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-1.4, -0.3, -2.2), Vector3(2.8, 4.8, 6.5))
	var texture = ImageTexture.create_from_image(image)
	assert(ResourceSaver.save(mesh, OUTPUT + "cavalry_mesh.res", ResourceSaver.FLAG_COMPRESS) == OK)
	assert(ResourceSaver.save(texture, OUTPUT + "cavalry_poses.res", ResourceSaver.FLAG_COMPRESS) == OK)
	var report = {"poses": POSES, "vertices_per_pose": count, "triangles_per_rider": count / 3, "atlas_width": WIDTH, "rows_per_pose": rows, "sources": sources, "originals_modified": false}
	var file = FileAccess.open(OUTPUT + "cavalry_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("DUEL_CAVALRY_BAKE ", JSON.stringify(report))
	fighter.queue_free()
	await frames(2)
	quit()
