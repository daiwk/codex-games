extends RefCounted

const DETAILED_EXTENT := 44
const CAMPAIGN_X_LIMIT := 50.0
const CAMPAIGN_START_Z := 42.0
const CAMPAIGN_COAST_ORIGIN_Z := -211.0
const CAMPAIGN_SHORE_Z := CAMPAIGN_COAST_ORIGIN_Z - 33.0
const CAMPAIGN_DETAIL_X := 54
const CAMPAIGN_DETAIL_NORTH := -250
const CAMPAIGN_DETAIL_SOUTH := 44
const CAMPAIGN_CELL_SIZE := 2
const COAST_PROFILE := """
float coast_distance(vec2 p) {
	return -p.y - 35.4 + 1.35 * sin(p.x * 0.12) + 0.60 * sin(p.x * 0.30);
}
"""

const TERRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform int stage_index = 0;
uniform bool campaign_map = false;
uniform float coast_origin_z = 0.0;
varying vec3 world_at;
varying vec3 world_normal;

float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(
		mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0)), blend.x), blend.y
	);
}

float track(float distance, float width, float verge) {
	return 1.0 - smoothstep(width * 0.72, width, distance + verge);
}

float campaign_road(float z) {
	return 7.5 * sin((z + 43.0) * 0.073) + 3.6 * sin((z + 43.0) * 0.031);
}

""" + COAST_PROFILE + """
void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec2 p = world_at.xz;
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float broad = grain(p * 0.112);
	float fine = mix(grain(p * 4.6), 0.5, smoothstep(0.017, 0.27, footprint));
	float grit = mix(grain(p * 12.0), 0.5, smoothstep(0.015, 0.105, footprint));
	float verge = 0.58 * grain(p * 0.55) + 0.24 * broad;
	vec3 open_ground = vec3(0.0);
	vec3 hill_ground = vec3(0.0);
	vec3 coast_ground = vec3(0.0);
	float uplands = campaign_map ? 1.0 - smoothstep(-54.0, -42.0, p.y) : float(stage_index >= 1);
	float coastal = campaign_map ? 1.0 - smoothstep(-186.0, -170.0, p.y) : float(stage_index == 2);
	if (uplands < 1.0) {
		float main_track = campaign_map ? abs(p.x - campaign_road(p.y)) : abs(p.x + 0.29 * p.y - 1.2 * sin(p.y * 0.1));
		float side_track = abs(p.y + 5.0 - 0.19 * p.x - 1.2 * sin(p.x * 0.082));
		float farm_track = abs(p.x + 23.0 - 2.3 * sin(p.y * 0.086));
		float gravel = max(track(main_track, 4.0, verge), track(side_track, 3.1, verge));
		gravel = max(gravel, track(farm_track, 2.7, verge) * 0.87);
		vec3 green = mix(vec3(0.205, 0.265, 0.112), vec3(0.409, 0.416, 0.202), broad);
		float wheat_field = smoothstep(9.0, 11.0, p.x + 0.16 * p.y) * (1.0 - smoothstep(33.0, 35.0, p.x));
		wheat_field *= 1.0 - smoothstep(28.0, 33.0, abs(p.y));
		float furrows = sin((p.x * 0.86 + p.y * 0.42) * 4.6) * (1.0 - smoothstep(0.13, 0.56, footprint));
		vec3 wheat = mix(vec3(0.44, 0.355, 0.164), vec3(0.66, 0.542, 0.282), broad) * (1.0 + 0.12 * furrows);
		float ploughed = smoothstep(9.0, 11.0, p.y - 0.2 * p.x) * smoothstep(-34.0, -32.0, p.x);
		ploughed *= (1.0 - smoothstep(-23.0, -20.0, p.x)) * (1.0 - smoothstep(24.0, 26.0, p.y));
		vec3 soil = mix(vec3(0.308, 0.234, 0.127), vec3(0.44, 0.336, 0.191), broad);
		green = mix(mix(green, wheat, wheat_field), soil * (1.0 + 0.14 * furrows), ploughed);
		vec3 road = mix(vec3(0.409, 0.318, 0.226), vec3(0.60, 0.480, 0.337), broad);
		float ruts = (1.0 - smoothstep(0.19, 0.57, abs(main_track - 1.16))) * gravel;
		open_ground = mix(green, road * (1.0 - 0.16 * ruts), gravel);
	}
	if (uplands > 0.0 && coastal < 1.0) {
		float main_track = campaign_map ? abs(p.x - campaign_road(p.y)) : abs(p.x - (4.5 + 11.5 * sin(p.y * 0.075)));
		float west_track = abs(p.x + 25.0 - 2.5 * sin(p.y * 0.15));
		float east_track = abs(p.x - 28.0 - 2.3 * sin(p.y * 0.092));
		float crossing = abs(p.y + 4.0 - p.x * 0.065);
		if (campaign_map) {
			crossing = min(abs(p.y + 94.0), abs(p.y + 130.0));
		}
		float gravel = max(track(main_track, 3.7, verge), track(west_track, 3.1, verge));
		gravel = max(gravel, track(east_track, 2.8, verge));
		gravel = max(gravel, track(crossing, 2.5, verge) * 0.86);
		float slope = 1.0 - abs(normalize(world_normal).y);
		float strata = 0.5 + 0.5 * sin(world_at.y * 3.5 + p.x * 0.12 + p.y * 0.24 + broad * 1.85);
		vec3 moss = mix(vec3(0.168, 0.224, 0.125), vec3(0.334, 0.357, 0.202), broad);
		vec3 slate = mix(vec3(0.345, 0.326, 0.281), vec3(0.57, 0.528, 0.432), broad);
		slate *= 0.87 + 0.13 * strata;
		float rock = smoothstep(0.073, 0.175, slope + 0.045 * broad + 0.026 * strata);
		vec3 road = mix(vec3(0.353, 0.303, 0.229), vec3(0.54, 0.486, 0.390), broad);
		hill_ground = mix(mix(moss, slate, rock), road, gravel);
	}
	if (coastal > 0.0) {
		float through_track = abs(p.x - campaign_road(p.y));
		p.y -= coast_origin_z;
		float shore = coast_distance(p);
		float dry = 1.0 - smoothstep(-12.0, -1.0, shore + 1.5 * broad);
		float dune = smoothstep(-24.0, -17.0, shore + 1.8 * broad);
		vec3 wet_sand = mix(vec3(0.39, 0.32, 0.245), vec3(0.52, 0.47, 0.378), broad);
		vec3 dry_sand = mix(vec3(0.58, 0.493, 0.351), vec3(0.75, 0.660, 0.482), broad);
		float ripple = sin((p.y + 0.8 * broad + p.x * 0.23) * 5.7) * (1.0 - smoothstep(0.07, 0.38, footprint));
		vec3 sand = mix(wet_sand, dry_sand, dry) * (1.0 + 0.055 * ripple);
		vec3 scrub = mix(vec3(0.265, 0.315, 0.153), vec3(0.435, 0.438, 0.255), broad);
		float inland = 1.0 - smoothstep(-44.0, -27.5, shore + 2.6 * broad);
		float approach = max(track(abs(p.x + 13.0 - p.y * 0.21), 3.8, verge), track(abs(p.x - 15.0 + p.y * 0.19), 3.8, verge));
		float dune_lanes = mix(1.0, 1.0 - approach * 0.82, smoothstep(-33.0, -19.0, shore));
		coast_ground = mix(sand, scrub, max(inland * dune_lanes, (1.0 - dune) * 0.32 * smoothstep(-37.0, -22.0, shore) * broad));
		if (campaign_map) {
			float inland_road = track(through_track, 4.0, verge) * smoothstep(4.0, 19.0, p.y);
			coast_ground = mix(coast_ground, mix(vec3(0.43, 0.37, 0.255), sand, 0.42), inland_road);
		}
		float scar = min(
			length((p - vec2(-25.0, -15.0)) * vec2(0.88, 1.0)),
			length((p - vec2(-10.0, -10.0)) * vec2(1.12, 1.0))
		);
		scar = min(scar, min(length(p - vec2(8.0, -20.0)), length(p - vec2(23.0, -13.0))));
		coast_ground *= 1.0 - 0.32 * (1.0 - smoothstep(0.65, 1.67, scar + 0.13 * (fine - 0.5)));
	}
	vec3 ground = mix(mix(open_ground, hill_ground, uplands), coast_ground, coastal);
	ALBEDO = ground * (0.91 + 0.13 * fine + 0.04 * grit);
	ROUGHNESS = 1.0;
}
"""

const SEA_SHADER := """
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

varying vec2 sea_at;
uniform float coast_origin_z = 0.0;
""" + COAST_PROFILE + """
void vertex() {
	sea_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	sea_at.y -= coast_origin_z;
	float swell = sin(sea_at.x * 0.29 + sea_at.y * 0.34 + TIME * 1.44);
	VERTEX.y += 0.095 * swell + 0.048 * sin(sea_at.y * 0.48 - sea_at.x * 0.16 - TIME * 1.09);
}

void fragment() {
	float edge = coast_distance(sea_at);
	if (edge < -5.2) {
		discard;
	}
	float footprint = max(fwidth(sea_at.x), fwidth(sea_at.y));
	float swell = sin(edge * 1.76 + sea_at.x * 0.07 - TIME * 2.1 + 0.35 * sin(sea_at.x * 0.32));
	float breaker = (1.0 - smoothstep(2.3, 13.0, edge)) * smoothstep(0.52, 1.0, swell);
	float ripple = sin(sea_at.x * 0.71 + sea_at.y * 1.93 - TIME * 1.65)
		* cos(sea_at.y * 0.53 - sea_at.x * 0.58 + TIME * 1.21);
	float water_grain = 1.0 - smoothstep(0.28, 1.03, footprint);
	float deep = smoothstep(1.0, 23.0, edge);
	vec3 water = mix(vec3(0.148, 0.400, 0.389), vec3(0.065, 0.235, 0.295), deep);
	water *= 1.0 + 0.08 * ripple * water_grain;
	float foam = max(breaker * (0.52 + 0.22 * water_grain * ripple), smoothstep(0.93, 0.99, ripple) * 0.12 * water_grain);
	ALBEDO = mix(water, vec3(0.80, 0.86, 0.79), foam);
	ROUGHNESS = 0.47 + 0.38 * foam;
	SPECULAR = 0.34;
}
"""


static func ground_height(stage: int, at: Vector2) -> float:
	if absf(at.x) >= DETAILED_EXTENT or absf(at.y) >= DETAILED_EXTENT:
		return _sample_height(stage, at)
	var cell := at.floor()
	var within := at - cell
	var a := _sample_height(stage, cell)
	var d := _sample_height(stage, cell + Vector2.ONE)
	# Match the two rendered triangles on either side of the diagonal in each cell.
	if within.x >= within.y:
		var b := _sample_height(stage, cell + Vector2.RIGHT)
		return a * (1.0 - within.x) + b * (within.x - within.y) + d * within.y
	var c := _sample_height(stage, cell + Vector2.DOWN)
	return a * (1.0 - within.y) + c * (within.y - within.x) + d * within.x


static func coast_distance(at: Vector2) -> float:
	return -at.y - 35.4 + 1.35 * sin(at.x * 0.12) + 0.60 * sin(at.x * 0.30)


static func road_factor(stage: int, at: Vector2) -> float:
	match stage:
		1:
			var mountain_road := at.x - (4.5 + 11.5 * sin(at.y * 0.075))
			var west_road := at.x + 25.0 - 2.5 * sin(at.y * 0.15)
			var east_road := at.x - 28.0 - 2.3 * sin(at.y * 0.092)
			return minf(minf(absf(mountain_road) / 3.3, absf(west_road) / 2.7),
				minf(absf(east_road) / 2.4, absf(at.y + 4.0 - at.x * 0.065) / 2.1))
		2:
			return minf(absf(at.x + 13.0 - at.y * 0.21), absf(at.x - 15.0 + at.y * 0.19)) / 3.4
		_:
			var main := at.x + 0.29 * at.y - 1.2 * sin(at.y * 0.1)
			var cross := at.y + 5.0 - 0.19 * at.x - 1.2 * sin(at.x * 0.082)
			var farm := at.x + 23.0 - 2.3 * sin(at.y * 0.086)
			return minf(absf(main) / 3.6, minf(absf(cross) / 2.7, absf(farm) / 2.4))


static var _campaign_heights := PackedFloat32Array()


static func campaign_road(z: float) -> float:
	return 7.5 * sin((z + 43.0) * 0.073) + 3.6 * sin((z + 43.0) * 0.031)


static func campaign_height(at: Vector2) -> float:
	if absf(at.x) >= CAMPAIGN_DETAIL_X or at.y < CAMPAIGN_DETAIL_NORTH or at.y >= CAMPAIGN_DETAIL_SOUTH:
		return _sample_campaign_height(at)
	_build_campaign_height_cache()
	var grid := (at - Vector2(-CAMPAIGN_DETAIL_X, CAMPAIGN_DETAIL_NORTH)) / CAMPAIGN_CELL_SIZE
	var cell := Vector2i(grid.floor())
	var within := grid - Vector2(cell)
	var row_width := CAMPAIGN_DETAIL_X + 1
	var first := cell.y * row_width + cell.x
	var a := _campaign_heights[first]
	var d := _campaign_heights[first + row_width + 1]
	if within.x >= within.y:
		var b := _campaign_heights[first + 1]
		return a * (1.0 - within.x) + b * (within.x - within.y) + d * within.y
	var c := _campaign_heights[first + row_width]
	return a * (1.0 - within.y) + c * (within.y - within.x) + d * within.x


static func _build_campaign_height_cache() -> void:
	if not _campaign_heights.is_empty():
		return
	for z in range(CAMPAIGN_DETAIL_NORTH, CAMPAIGN_DETAIL_SOUTH + 1, CAMPAIGN_CELL_SIZE):
		for x in range(-CAMPAIGN_DETAIL_X, CAMPAIGN_DETAIL_X + 1, CAMPAIGN_CELL_SIZE):
			_campaign_heights.append(_sample_campaign_height(Vector2(x, z)))


static func campaign_ground() -> StaticBody3D:
	_build_campaign_height_cache()
	var x_axis := PackedFloat32Array()
	for x in range(-150, -CAMPAIGN_DETAIL_X, 6):
		x_axis.append(float(x))
	for x in range(-CAMPAIGN_DETAIL_X, CAMPAIGN_DETAIL_X + 1, CAMPAIGN_CELL_SIZE):
		x_axis.append(float(x))
	for x in range(CAMPAIGN_DETAIL_X + 6, 151, 6):
		x_axis.append(float(x))
	var z_axis := PackedFloat32Array()
	for z in range(-346, CAMPAIGN_DETAIL_NORTH, 6):
		z_axis.append(float(z))
	for z in range(CAMPAIGN_DETAIL_NORTH, CAMPAIGN_DETAIL_SOUTH + 1, CAMPAIGN_CELL_SIZE):
		z_axis.append(float(z))
	for z in range(CAMPAIGN_DETAIL_SOUTH + 6, 105, 6):
		z_axis.append(float(z))
	return _build_ground(_height_mesh(x_axis, z_axis, _sample_campaign_height), 0, true)


static func ground(stage: int) -> StaticBody3D:
	return _build_ground(_terrain_mesh(stage), stage)


static func _build_ground(mesh: ArrayMesh, stage: int, campaign := false) -> StaticBody3D:
	var terrain := StaticBody3D.new()
	terrain.name = "BattlefieldSurface"
	terrain.collision_layer = BattleUnit.TERRAIN_LAYER
	terrain.collision_mask = 0
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := _shader_material(TERRAIN_SHADER)
	material.set_shader_parameter("stage_index", stage)
	material.set_shader_parameter("campaign_map", campaign)
	if campaign:
		material.set_shader_parameter("coast_origin_z", CAMPAIGN_COAST_ORIGIN_Z)
	visual.material_override = material
	terrain.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	terrain.add_child(collision)
	return terrain


static func sea(origin_z := 0.0) -> MeshInstance3D:
	var surface := MeshInstance3D.new()
	surface.name = "BreakingWaves"
	var plane := PlaneMesh.new()
	plane.size = Vector2(336.0, 160.0)
	plane.subdivide_width = 62
	plane.subdivide_depth = 40
	surface.mesh = plane
	var material := _shader_material(SEA_SHADER)
	material.set_shader_parameter("coast_origin_z", origin_z)
	surface.material_override = material
	surface.position = Vector3(0.0, -0.94, origin_z - 111.0)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return surface


static func _sample_height(stage: int, at: Vector2) -> float:
	match stage:
		1:
			var ridge := 10.9 * _mound(at, Vector2(5, 0), Vector2(28, 18.5))
			var west_spur := 5.0 * _mound(at, Vector2(-31, 8), Vector2(16, 24))
			var northeast_spur := 6.6 * _mound(at, Vector2(32, -11), Vector2(18, 24))
			var hills := 10.5 * _mound(at, Vector2(-61, -35), Vector2(25, 28))
			hills += 11.0 * _mound(at, Vector2(64, 19), Vector2(23, 31))
			return ridge + west_spur + northeast_spur + hills + 0.27 * sin(at.x * 0.17 + at.y * 0.15)
		2:
			var shore := coast_distance(at)
			var bluff := lerpf(-3.75, 0.24, 1.0 - smoothstep(-10.0, 8.0, shore))
			var dunes := 2.40 * _mound(at, Vector2(-26, 3), Vector2(14, 11))
			dunes += 1.68 * _mound(at, Vector2(0.0, 0.8), Vector2(11.5, 8.7))
			dunes += 2.25 * _mound(at, Vector2(29, 6), Vector2(16, 12))
			var sand_roll := 0.19 * sin(0.30 * at.x - 0.22 * at.y) * (1.0 - smoothstep(-8.0, 0.0, shore))
			var scars := _mound(at, Vector2(-25, -15), Vector2(1.46, 1.29))
			scars += _mound(at, Vector2(-10, -10), Vector2(1.17, 1.34))
			scars += _mound(at, Vector2(8, -20), Vector2(1.23, 1.23))
			scars += _mound(at, Vector2(23, -13), Vector2(1.30, 1.30))
			return bluff + dunes + sand_roll - 0.29 * scars
		_:
			var margin := maxf(absf(at.x) - 37.0, absf(at.y) - 34.0)
			var distant_rise := smoothstep(0.0, 57.0, margin) * (1.7 + 2.6 * sin(at.x * 0.043 + at.y * 0.052) ** 2)
			return 0.32 * sin(0.086 * at.x + 0.037 * at.y) + 0.27 * sin(0.096 * at.y - 0.059 * at.x) + distant_rise


static func _mound(at: Vector2, center: Vector2, width: Vector2) -> float:
	var offset := (at - center) / width
	return exp(-offset.dot(offset))


static func _sample_campaign_height(at: Vector2) -> float:
	var base := 0.29 * sin(0.086 * at.x + 0.037 * at.y) + 0.22 * sin(0.068 * at.y - 0.059 * at.x)
	var uplands := smoothstep(-186.0, -174.0, at.y) * (1.0 - smoothstep(-52.0, -37.0, at.y))
	if uplands > 0.0:
		var ridge := 10.8 * _mound(at, Vector2(-7.0, -73.0), Vector2(40.0, 15.5))
		ridge += 13.9 * _mound(at, Vector2(5.0, -110.0), Vector2(42.0, 15.4))
		ridge += 15.8 * _mound(at, Vector2(-6.0, -146.0), Vector2(41.0, 16.4))
		ridge += 6.1 * _mound(at, Vector2(-33.0, -83.0), Vector2(20.0, 27.0))
		ridge += 6.7 * _mound(at, Vector2(33.0, -119.0), Vector2(22.0, 26.0))
		ridge += 5.8 * _mound(at, Vector2(-32.0, -145.0), Vector2(19.0, 27.0))
		var rise := smoothstep(39.0, 70.0, absf(at.x))
		ridge += rise * (9.2 + 4.0 * sin(at.y * 0.081 + at.x * 0.045) ** 2)
		base += ridge * uplands
	if at.y > -53.0:
		var beyond := maxf(absf(at.x) - 39.0, at.y - 36.0)
		base += smoothstep(-53.0, -37.0, at.y) * smoothstep(0.0, 45.0, beyond) * (1.6 + 3.0 * sin(at.x * 0.047 + at.y * 0.055) ** 2)
	if at.y < -169.0:
		var coastal := _sample_height(2, Vector2(at.x, at.y - CAMPAIGN_COAST_ORIGIN_Z))
		base = lerpf(base, coastal, 1.0 - smoothstep(-186.0, -169.0, at.y))
	return base


static func _terrain_mesh(stage: int) -> ArrayMesh:
	var axis := PackedFloat32Array()
	for sample in range(-144, -DETAILED_EXTENT, 5):
		axis.append(float(sample))
	for sample in range(-DETAILED_EXTENT, DETAILED_EXTENT + 1):
		axis.append(float(sample))
	for sample in range(DETAILED_EXTENT + 5, 145, 5):
		axis.append(float(sample))
	return _height_mesh(axis, axis, func(at: Vector2) -> float: return _sample_height(stage, at))


static func _height_mesh(x_axis: PackedFloat32Array, z_axis: PackedFloat32Array, sample: Callable) -> ArrayMesh:
	var row_width := x_axis.size()
	var row_count := z_axis.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(row_width * row_count)
	normals.resize(vertices.size())
	for z in row_count:
		for x in row_width:
			var at := Vector2(x_axis[x], z_axis[z])
			var h: float = sample.call(at)
			var slope_x: float = sample.call(at + Vector2.RIGHT * 0.45) - sample.call(at - Vector2.RIGHT * 0.45)
			var slope_z: float = sample.call(at + Vector2.DOWN * 0.45) - sample.call(at - Vector2.DOWN * 0.45)
			vertices[z * row_width + x] = Vector3(at.x, h, at.y)
			normals[z * row_width + x] = Vector3(-slope_x, 0.9, -slope_z).normalized()
	var indices := PackedInt32Array()
	for z in range(row_count - 1):
		for x in range(row_width - 1):
			var a := z * row_width + x
			var b := a + 1
			var c := a + row_width
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, d, a, d, c]))
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


static func _shader_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
