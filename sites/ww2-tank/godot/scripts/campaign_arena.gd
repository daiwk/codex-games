extends Node3D

signal building_destroyed(at: Vector3)

const Region = preload("res://scripts/arena.gd")
const Terrain = preload("res://scripts/stage_terrain.gd")

const X_LIMIT := Terrain.CAMPAIGN_X_LIMIT
const START_Z := Terrain.CAMPAIGN_START_Z
const SHORE_Z := Terrain.CAMPAIGN_SHORE_Z
const COAST_ORIGIN_Z := Terrain.CAMPAIGN_COAST_ORIGIN_Z
const SUPPLY_POINTS := [Vector2(0, -43), Vector2(0, -121), Vector2(0, -171)]
const DEFENSE_POINT := Vector2(0, -214)

var cover_rects: Array[Rect2] = []
var _regions: Array[Region] = []


func _ready() -> void:
	name = "CampaignBattlefield"
	add_child(Terrain.campaign_ground())
	add_child(Terrain.sea(COAST_ORIGIN_Z))
	_add_region(0, 0.0)
	_add_region(1, -75.0)
	_add_region(1, -133.0, 1)
	_add_region(2, COAST_ORIGIN_Z)
	_update_cover_rects()
	_add_boundary()
	for index in SUPPLY_POINTS.size():
		var supply: Vector2 = SUPPLY_POINTS[index]
		_add_supply_depot(supply + Vector2(6.3 if index == 1 else -6.3, 0.0))


func ground_height(at: Vector2) -> float:
	return Terrain.campaign_height(at)


func road_center(z: float) -> float:
	return Terrain.campaign_road(z)


func position_on_ground(at: Vector2, lift := 0.0) -> Vector3:
	return Vector3(at.x, ground_height(at) + lift, at.y)


func is_ground_navigable(at: Vector2) -> bool:
	return absf(at.x) <= X_LIMIT and at.y >= SHORE_Z and at.y <= START_Z


func navigation_region(clearance: float) -> Rect2i:
	var first := Vector2i(ceili(-X_LIMIT + clearance), ceili(SHORE_Z + clearance))
	var last := Vector2i(floori(X_LIMIT - clearance), floori(START_Z - clearance))
	return Rect2i(first, last - first + Vector2i.ONE)


func damage_building(collider: Object, damage: int) -> bool:
	for region in _regions:
		if region.damage_building(collider, damage):
			return true
	return false


func damage_buildings_in_area(center: Vector3, radius: float, damage: int) -> void:
	for region in _regions:
		region.damage_buildings_in_area(center, radius, damage)


func building_info(collider: Object) -> Dictionary:
	for region in _regions:
		var info := region.building_info(collider)
		if not info.is_empty():
			return info
	return {}


func building_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for region in _regions:
		snapshots.append_array(region.building_snapshots())
	return snapshots


func reset_buildings() -> void:
	for region in _regions:
		region.reset_buildings()
	_update_cover_rects()


func _add_region(zone: int, origin_z: float, variant := 0) -> void:
	var region := Region.new()
	region.configure_region(zone, origin_z, ground_height, variant)
	region.building_destroyed.connect(_on_building_destroyed)
	_regions.append(region)
	add_child(region)


func _update_cover_rects() -> void:
	cover_rects.clear()
	for region in _regions:
		var offset := Vector2(region.position.x, region.position.z)
		for cover: Rect2 in region.cover_rects:
			cover_rects.append(Rect2(cover.position + offset, cover.size))


func _on_building_destroyed(at: Vector3) -> void:
	_update_cover_rects()
	building_destroyed.emit(at)


func _add_boundary() -> void:
	var length := START_Z - SHORE_Z
	for side: float in [-1.0, 1.0]:
		_add_border("MapSide", Vector3(side * (X_LIMIT + 0.3), 9.0, (START_Z + SHORE_Z) * 0.5),
			Vector3(0.6, 60.0, length + 1.2))
	_add_border("MapRear", Vector3(0.0, 8.0, START_Z + 0.3), Vector3(X_LIMIT * 2.0, 60.0, 0.6))
	_add_border("SurfLimit", Vector3(0.0, -3.0, SHORE_Z - 2.0), Vector3(X_LIMIT * 2.0, 10.0, 4.0))


func _add_border(label: String, at: Vector3, size: Vector3) -> void:
	var border := StaticBody3D.new()
	border.name = label
	border.position = at
	border.collision_layer = BattleUnit.COVER_LAYER
	border.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	border.add_child(collider)
	add_child(border)


func _add_supply_depot(center: Vector2) -> void:
	var depot := Node3D.new()
	depot.name = "FieldSupplyDepot"
	depot.position = position_on_ground(center)
	add_child(depot)
	var timber := _depot_material(Color("#5f4b38"))
	var olive := _depot_material(Color("#657447"))
	var trim := _depot_material(Color("#a6936a"))
	var canvas := _depot_material(Color("#a39e75"))
	var cream := _depot_material(Color("#f2e8bd"))
	for x in [-1.62, 1.62]:
		for z in [-0.89, 0.89]:
			var below := ground_height(center + Vector2(x, z)) - depot.position.y
			var pole_height := 2.38 - below
			_depot_box(depot, Vector3(x, below + pole_height * 0.5, z), Vector3(0.12, pole_height, 0.12), timber)
	var roof := _depot_box(depot, Vector3(0.0, 2.37, 0.0), Vector3(3.72, 0.12, 2.26), canvas)
	roof.rotation.x = 0.10
	for stack in 3:
		var x := -1.0 + float(stack)
		var base := ground_height(center + Vector2(x, 0.0)) - depot.position.y
		_depot_box(depot, Vector3(x, base + 0.33, 0.0), Vector3(0.84, 0.66, 0.91), olive)
		for rail in [-0.27, 0.27]:
			_depot_box(depot, Vector3(x + rail, base + 0.408, 0.0), Vector3(0.13, 0.72, 0.95), trim)
	_depot_box(depot, Vector3(0.0, 0.88, 0.20), Vector3(0.66, 0.52, 0.76), timber)
	_depot_box(depot, Vector3(0.0, 2.93, 0.95), Vector3(0.86, 0.86, 0.10), olive)
	for direction: float in [-1.0, 1.0]:
		var anchor := Vector3(0.0, 2.93, 0.95 + direction * 0.06)
		_depot_box(depot, anchor, Vector3(0.52, 0.15, 0.045), cream)
		_depot_box(depot, anchor, Vector3(0.15, 0.52, 0.045), cream)


func _depot_box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _depot_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.94
	return material
