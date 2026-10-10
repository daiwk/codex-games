class_name VisualFactory
extends RefCounted


static func material(color: Color, metallic: float = 0.0, roughness: float = 0.72, emission_strength: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	if color.a < 0.999:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission_strength > 0.0:
		result.emission_enabled = true
		result.emission = Color(color.r, color.g, color.b)
		result.emission_energy_multiplier = emission_strength
	return result


static func box(parent: Node, size: Vector3, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO, name_text: String = "Box") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.name = name_text
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	part.material_override = material(color, 0.05, 0.66)
	parent.add_child(part)
	return part


static func cylinder(parent: Node, radius: float, height: float, position: Vector3, color: Color, name_text: String = "Cylinder") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.04
	mesh.height = height
	mesh.radial_segments = 12
	var part := MeshInstance3D.new()
	part.name = name_text
	part.mesh = mesh
	part.position = position
	part.material_override = material(color, 0.08, 0.64)
	parent.add_child(part)
	return part


static func tapered_cylinder(parent: Node, top_radius: float, bottom_radius: float, height: float, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO, name_text: String = "TaperedCylinder") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	var part := MeshInstance3D.new()
	part.name = name_text
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	part.material_override = material(color, 0.08, 0.62)
	parent.add_child(part)
	return part


static func capsule(parent: Node, radius: float, height: float, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO, name_text: String = "Capsule") -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 4
	var part := MeshInstance3D.new()
	part.name = name_text
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	part.material_override = material(color, 0.04, 0.68)
	parent.add_child(part)
	return part


static func sphere(parent: Node, radius: float, position: Vector3, color: Color, scale_value: Vector3 = Vector3.ONE, name_text: String = "Sphere") -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var part := MeshInstance3D.new()
	part.name = name_text
	part.mesh = mesh
	part.position = position
	part.scale = scale_value
	part.material_override = material(color, 0.03, 0.7)
	parent.add_child(part)
	return part


static func blade(parent: Node, length: float, width: float, position: Vector3, color: Color, name_text: String = "Blade") -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_width := width * 0.5
	var half_thickness := width * 0.12
	var outline: Array[Vector2] = [
		Vector2(-half_width * 0.72, 0.0), Vector2(-half_width, length * 0.68),
		Vector2(-half_width * 0.32, length * 0.94), Vector2(0.0, length),
		Vector2(half_width * 0.56, length * 0.82), Vector2(half_width * 0.68, 0.0)
	]
	# Front and back faces use a fan around the silhouette center.
	var center := Vector2(0.0, length * 0.48)
	for side in [-1.0, 1.0]:
		for index in range(outline.size()):
			var next := (index + 1) % outline.size()
			var normal := Vector3(0, 0, side)
			for point in [center, outline[index], outline[next]]:
				surface.set_normal(normal)
				surface.add_vertex(Vector3(point.x, point.y, half_thickness * side))
	# Edge faces give the weapon a real silhouette under angled lighting.
	for index in range(outline.size()):
		var next := (index + 1) % outline.size()
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[next]
		var edge_normal := Vector3(b.y - a.y, -(b.x - a.x), 0).normalized()
		for point in [
			Vector3(a.x, a.y, -half_thickness), Vector3(b.x, b.y, -half_thickness), Vector3(b.x, b.y, half_thickness),
			Vector3(a.x, a.y, -half_thickness), Vector3(b.x, b.y, half_thickness), Vector3(a.x, a.y, half_thickness)
		]:
			surface.set_normal(edge_normal)
			surface.add_vertex(point)
	mesh = surface.commit()
	var part := MeshInstance3D.new()
	part.name = name_text
	part.mesh = mesh
	part.position = position
	part.material_override = material(color, 0.78, 0.25)
	parent.add_child(part)
	return part


static func make_humanoid(parent: Node3D, palette: Dictionary, weapon_kind: String = "blade", elite: bool = false) -> Dictionary:
	var visual := Node3D.new()
	visual.name = "Visual"
	parent.add_child(visual)
	var body_scale := 1.12 if elite else 1.0

	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.76 if not elite else 0.98
	shadow_mesh.bottom_radius = shadow_mesh.top_radius
	shadow_mesh.height = 0.025
	shadow_mesh.radial_segments = 32
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = shadow_mesh
	shadow.position.y = 0.035
	shadow.material_override = material(Color(0.01, 0.015, 0.02, 0.48))
	visual.add_child(shadow)

	# Articulated legs: thigh, knee guard, shin guard and a forward-facing boot.
	var leg_left := Node3D.new()
	leg_left.name = "LegLeft"
	leg_left.position = Vector3(-0.22 * body_scale, 0.91, 0.0)
	visual.add_child(leg_left)
	tapered_cylinder(leg_left, 0.17, 0.19, 0.48, Vector3(0, -0.19, 0), palette.body, Vector3.ZERO, "LeftThigh")
	sphere(leg_left, 0.19, Vector3(0, -0.48, -0.06), palette.trim, Vector3(0.88, 0.72, 0.48), "LeftKneeGuard")
	tapered_cylinder(leg_left, 0.16, 0.125, 0.48, Vector3(0, -0.69, 0.015), palette.armor, Vector3.ZERO, "LeftShin")
	box(leg_left, Vector3(0.31, 0.18, 0.49), Vector3(0, -0.97, -0.105), palette.body, Vector3.ZERO, "LeftBoot")
	var leg_right := Node3D.new()
	leg_right.name = "LegRight"
	leg_right.position = Vector3(0.22 * body_scale, 0.91, 0.0)
	visual.add_child(leg_right)
	tapered_cylinder(leg_right, 0.17, 0.19, 0.48, Vector3(0, -0.19, 0), palette.body, Vector3.ZERO, "RightThigh")
	sphere(leg_right, 0.19, Vector3(0, -0.48, -0.06), palette.trim, Vector3(0.88, 0.72, 0.48), "RightKneeGuard")
	tapered_cylinder(leg_right, 0.16, 0.125, 0.48, Vector3(0, -0.69, 0.015), palette.armor, Vector3.ZERO, "RightShin")
	box(leg_right, Vector3(0.31, 0.18, 0.49), Vector3(0, -0.97, -0.105), palette.body, Vector3.ZERO, "RightBoot")

	# A tapered torso plus overlapping lamellar plates reads much better than a single barrel.
	tapered_cylinder(visual, 0.43 * body_scale, 0.51 * body_scale, 0.86, Vector3(0, 1.45, 0), palette.body, Vector3.ZERO, "UnderRobe")
	tapered_cylinder(visual, 0.49 * body_scale, 0.43 * body_scale, 0.66, Vector3(0, 1.63, 0), palette.armor, Vector3.ZERO, "Cuirass")
	for plate_index in range(4):
		var plate_y := 1.36 + plate_index * 0.17
		var plate_width := (0.94 - plate_index * 0.045) * body_scale
		box(visual, Vector3(plate_width, 0.13, 0.10), Vector3(0, plate_y, -0.455), palette.trim if plate_index == 3 else palette.armor, Vector3(-0.08, 0, 0), "ChestPlate%d" % plate_index)
	box(visual, Vector3(0.19, 0.7, 0.08), Vector3(0, 1.55, -0.53), palette.trim, Vector3.ZERO, "ChestSpine")
	box(visual, Vector3(1.04 * body_scale, 0.16, 0.38), Vector3(0, 1.16, 0), palette.trim, Vector3.ZERO, "WarBelt")
	box(visual, Vector3(0.25, 0.24, 0.12), Vector3(0, 1.16, -0.29), palette.mask, Vector3.ZERO, "BeltEmblem")

	# Four skirt plates leave gaps for the articulated legs and add layered motion.
	box(visual, Vector3(0.38, 0.72, 0.10), Vector3(-0.23, 0.78, -0.29), palette.cloth, Vector3(-0.12, 0, -0.05), "SkirtFrontLeft")
	box(visual, Vector3(0.38, 0.72, 0.10), Vector3(0.23, 0.78, -0.29), palette.cloth, Vector3(-0.12, 0, 0.05), "SkirtFrontRight")
	box(visual, Vector3(0.18, 0.66, 0.45), Vector3(-0.47 * body_scale, 0.80, 0.0), palette.armor, Vector3(0, 0, -0.08), "SkirtSideLeft")
	box(visual, Vector3(0.18, 0.66, 0.45), Vector3(0.47 * body_scale, 0.80, 0.0), palette.armor, Vector3(0, 0, 0.08), "SkirtSideRight")
	box(visual, Vector3(0.88 * body_scale, 1.08, 0.065), Vector3(0, 1.02, 0.43), Color(palette.cloth, 0.92), Vector3(-0.12, 0, 0), "Cape")
	box(visual, Vector3(0.76 * body_scale, 0.09, 0.07), Vector3(0, 1.44, 0.48), palette.trim, Vector3.ZERO, "CapeClasp")

	# Neck, head, layered mask and helmet.
	cylinder(visual, 0.16 * body_scale, 0.23, Vector3(0, 2.02, 0), palette.skin, "Neck")
	var head_y := 2.31 if not elite else 2.36
	var head := sphere(visual, 0.33 * body_scale, Vector3(0, head_y, -0.02), palette.skin, Vector3(0.84, 1.04, 0.9), "Head")
	tapered_cylinder(visual, 0.31 * body_scale, 0.37 * body_scale, 0.23, Vector3(0, head_y + 0.23, 0), palette.armor, Vector3.ZERO, "HelmetCrown")
	cylinder(visual, 0.41 * body_scale, 0.075, Vector3(0, head_y + 0.17, 0), palette.trim, "HelmetBrim")
	box(visual, Vector3(0.49 * body_scale, 0.31, 0.075), Vector3(0, head_y - 0.01, -0.315 * body_scale), palette.mask, Vector3(-0.05, 0, 0), "FaceMask")
	box(visual, Vector3(0.18, 0.24, 0.065), Vector3(0, head_y - 0.13, -0.355 * body_scale), palette.trim, Vector3.ZERO, "MaskMouth")
	for ridge_x in [-0.17, 0.0, 0.17]:
		box(visual, Vector3(0.035, 0.27, 0.045), Vector3(ridge_x * body_scale, head_y, -0.365 * body_scale), palette.trim, Vector3.ZERO, "MaskRidge")
	box(visual, Vector3(0.09, 0.055, 0.035), Vector3(-0.13 * body_scale, head_y + 0.055, -0.39 * body_scale), palette.glow, Vector3(0, 0, -0.14), "EyeLeft")
	box(visual, Vector3(0.09, 0.055, 0.035), Vector3(0.13 * body_scale, head_y + 0.055, -0.39 * body_scale), palette.glow, Vector3(0, 0, 0.14), "EyeRight")
	box(visual, Vector3(0.10, 0.58, 0.10), Vector3(0, head_y + 0.55, 0.0), palette.trim, Vector3(0.0, 0.0, -0.06), "HelmetCrest")
	box(visual, Vector3(0.09, 0.48, 0.06), Vector3(0, head_y + 0.58, 0.07), palette.cloth, Vector3(0.45, 0.0, 0.0), "CrestPlume")

	# Layered arms with independent shoulder silhouettes, gauntlets and hands.
	var arm_left := Node3D.new()
	arm_left.name = "ArmLeft"
	arm_left.position = Vector3(-0.57 * body_scale, 1.82, 0)
	arm_left.rotation.z = deg_to_rad(-8.0)
	visual.add_child(arm_left)
	sphere(arm_left, 0.31 * body_scale, Vector3(-0.04, 0.02, 0), palette.armor, Vector3(1.0, 0.68, 0.92), "LeftPauldron")
	box(arm_left, Vector3(0.48, 0.11, 0.5), Vector3(-0.12, 0.07, 0), palette.trim, Vector3(0, 0, -0.12), "LeftShoulderPlate")
	capsule(arm_left, 0.125, 0.52, Vector3(0, -0.29, 0), palette.body, Vector3.ZERO, "LeftUpperArm")
	tapered_cylinder(arm_left, 0.15, 0.11, 0.36, Vector3(0, -0.66, 0), palette.armor, Vector3.ZERO, "LeftGauntlet")
	sphere(arm_left, 0.125, Vector3(0, -0.88, -0.02), palette.skin, Vector3(0.88, 1.0, 0.75), "LeftHand")
	var arm_right := Node3D.new()
	arm_right.name = "ArmRight"
	arm_right.position = Vector3(0.57 * body_scale, 1.82, 0)
	arm_right.rotation.z = deg_to_rad(8.0)
	visual.add_child(arm_right)
	sphere(arm_right, 0.31 * body_scale, Vector3(0.04, 0.02, 0), palette.armor, Vector3(1.0, 0.68, 0.92), "RightPauldron")
	box(arm_right, Vector3(0.48, 0.11, 0.5), Vector3(0.12, 0.07, 0), palette.trim, Vector3(0, 0, 0.12), "RightShoulderPlate")
	capsule(arm_right, 0.125, 0.52, Vector3(0, -0.29, 0), palette.body, Vector3.ZERO, "RightUpperArm")
	tapered_cylinder(arm_right, 0.15, 0.11, 0.36, Vector3(0, -0.66, 0), palette.armor, Vector3.ZERO, "RightGauntlet")
	sphere(arm_right, 0.125, Vector3(0, -0.88, -0.02), palette.skin, Vector3(0.88, 1.0, 0.75), "RightHand")

	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.68 * body_scale, 1.15, -0.04)
	weapon_pivot.rotation.z = deg_to_rad(-38.0)
	visual.add_child(weapon_pivot)
	if weapon_kind == "staff":
		cylinder(weapon_pivot, 0.055, 2.8 if not elite else 3.3, Vector3(0, 0.8, 0), palette.trim, "Staff")
		cylinder(weapon_pivot, 0.10, 0.18, Vector3(0, 2.18, 0), palette.mask, "StaffCollar")
		sphere(weapon_pivot, 0.19, Vector3(0, 2.35, 0), palette.glow, Vector3.ONE, "StaffCore")
		for spike_angle in range(0, 360, 90):
			box(weapon_pivot, Vector3(0.055, 0.42, 0.055), Vector3(0, 2.35, 0), palette.trim, Vector3(0, 0, deg_to_rad(spike_angle)), "StaffHaloSpike")
	else:
		cylinder(weapon_pivot, 0.062, 0.82, Vector3(0, 0.19, 0), palette.body, "WrappedGrip")
		for wrap_index in range(5):
			box(weapon_pivot, Vector3(0.15, 0.045, 0.15), Vector3(0, -0.02 + wrap_index * 0.14, 0), palette.trim, Vector3(0, 0, wrap_index * 0.18), "GripWrap")
		box(weapon_pivot, Vector3(0.72, 0.10, 0.16), Vector3(0, 0.63, 0), palette.glow, Vector3.ZERO, "Guard")
		blade(weapon_pivot, 1.72 if not elite else 2.15, 0.27 if not elite else 0.34, Vector3(0, 0.66, 0), palette.weapon, "SabreBlade")
		box(weapon_pivot, Vector3(0.035, 1.46 if not elite else 1.84, 0.06), Vector3(-0.095, 1.36 if not elite else 1.56, -0.04), palette.glow, Vector3(0, 0, -0.025), "BladeEdge")

	# A sheathed secondary silhouette fills the empty hip and sells the warrior design.
	var scabbard := Node3D.new()
	scabbard.name = "Scabbard"
	scabbard.position = Vector3(-0.47 * body_scale, 1.15, 0.18)
	scabbard.rotation = Vector3(deg_to_rad(13.0), 0.0, deg_to_rad(23.0))
	visual.add_child(scabbard)
	box(scabbard, Vector3(0.15, 1.48, 0.16), Vector3(0, -0.55, 0), palette.body, Vector3.ZERO, "ScabbardBody")
	box(scabbard, Vector3(0.21, 0.10, 0.21), Vector3(0, 0.19, 0), palette.trim, Vector3.ZERO, "ScabbardMouth")

	return {
		"root": visual, "weapon": weapon_pivot, "leg_left": leg_left, "leg_right": leg_right,
		"arm_left": arm_left, "arm_right": arm_right, "head": head
	}

