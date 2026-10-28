extends SceneTree

## Static rendering regression: keep authored unindexed roof geometry when
## combining it with indexed engine primitives. Also checks the real courtyard.
class ReviewArena extends "res://scripts/arena.gd":
	func _batch_static_meshes() -> void:
		pass
	func combine_static() -> void:
		super._batch_static_meshes()

var failed = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	print("PASS " if passed else "FAIL ", label, " ", JSON.stringify(detail))
	if not passed:
		failed += 1

func geometry(node: Node) -> Dictionary:
	var result = {"meshes": 0, "triangles": 0, "finite": true}
	for child in node.get_children():
		if child is MeshInstance3D and not child.is_queued_for_deletion():
			result.meshes += 1
			result.triangles += child.mesh.get_faces().size() / 3
			result.finite = result.finite and child.transform.is_finite() and child.mesh.get_aabb().position.is_finite()
	return result

func run() -> void:
	var fixture = ReviewArena.new()
	# The failure requires an unindexed authored surface followed by an indexed
	# primitive sharing a material. Inspect real submitted meshes after merging.
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]:
		tool.set_normal(Vector3.UP)
		tool.set_uv(Vector2.ZERO)
		tool.add_vertex(vertex)
	var mat = StandardMaterial3D.new()
	fixture.mesh_at(tool.commit(), mat, Vector3.ZERO)
	fixture.mesh_at(CylinderMesh.new(), mat, Vector3(2,0,0))
	var before = geometry(fixture)
	fixture.combine_static()
	var after = geometry(fixture)
	check("mixed indexed/unindexed fixture preserves every rendered triangle", after.triangles == before.triangles, {"before": before, "after": after})
	fixture.free()

	var court = ReviewArena.new()
	root.add_child(court)
	before = geometry(court)
	court.combine_static()
	after = geometry(court)
	check("actual courtyard batching preserves complete roof/foliage/stone geometry", after.triangles == before.triangles and before.triangles > 100000, {"before": before, "after": after})
	check("static environment remains below 80 material/layout batches", after.meshes < 80, after.meshes)
	check("all submitted environment transforms and bounds are finite", after.finite)
	check("slate color and normal textures contain real mipmaps", court.STONE_DIFF.get_image().has_mipmaps() and court.STONE_NORMAL.get_image().has_mipmaps())
	var floor_ok = false
	for node in court.get_children():
		if node is StaticBody3D:
			var collision = node.get_child(0)
			floor_ok = collision.shape.size == Vector3(40,0.5,40) and is_equal_approx(collision.position.y,-0.25)
	check("original combat floor collider remains at world Y zero", floor_ok)
	court.queue_free()
	await process_frame
	print("AUTUMN_ENVIRONMENT_RESULT ", JSON.stringify({"checks": 6, "failed": failed}))
	quit(0 if failed == 0 else 1)
