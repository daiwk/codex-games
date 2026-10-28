extends Node3D
class_name DuelArena

var materials: Dictionary = {}
var surface_materials: Dictionary = {}
var rng = RandomNumberGenerator.new()
const MOUNTAIN_SKY_SHADER = preload("res://assets/environment/autumn_court/mountain_sky.gdshader")
const MOUNTAIN_PANORAMA = preload("res://assets/environment/autumn_court/mountain_panorama.png")
const STONE_DIFF = preload("res://assets/environment/autumn_court/stone_diff.jpg")
const STONE_NORMAL = preload("res://assets/environment/autumn_court/stone_normal.jpg")
const STONE_ROUGH = preload("res://assets/environment/autumn_court/stone_rough.jpg")
const WOOD_DIFF = preload("res://assets/environment/autumn_court/wood_diff.jpg")
const WOOD_NORMAL = preload("res://assets/environment/autumn_court/wood_normal.jpg")

func _ready() -> void:
	rng.seed = 10282026
	_build_lighting()
	_build_court()
	_build_gate()
	_build_surroundings()
	_batch_static_meshes()

func _batch_static_meshes() -> void:
	# Merge static surfaces by material after applying their transforms. AABB is
	# deliberately not used as a mesh identity: authored foliage/stone can share
	# bounds while containing different geometry.
	var groups: Dictionary = {}
	for child in get_children():
		if child is MeshInstance3D and child.mesh != null and child.material_override != null:
			# Indexed and unindexed surfaces must never be appended into one
			# SurfaceTool: a later index buffer would silently omit earlier
			# unindexed vertices (notably the authored curved tile geometry).
			var layout=""
			for attribute in child.mesh.surface_get_arrays(0):
				layout += "1" if attribute != null and attribute.size() > 0 else "0"
			var key = str(child.material_override.get_instance_id()) + ":" + layout
			if not groups.has(key): groups[key] = []
			groups[key].append(child)
	for group in groups.values():
		if group.size() < 2: continue
		var merged = SurfaceTool.new()
		merged.begin(Mesh.PRIMITIVE_TRIANGLES)
		for node in group:
			for surface_index in node.mesh.get_surface_count():
				merged.append_from(node.mesh, surface_index, node.transform)
		var instance = MeshInstance3D.new()
		instance.mesh = merged.commit()
		instance.material_override = group[0].material_override
		add_child(instance)
		for node in group: node.queue_free()

func material(color: Color, metallic = 0.0) -> StandardMaterial3D:
	var key = str(color) + str(metallic)
	if materials.has(key):
		return materials[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color if get_script().resource_path.ends_with("duel_cavalry_arena.gd") else color.srgb_to_linear()
	mat.roughness = 0.86 if metallic == 0.0 else 0.42
	mat.metallic = metallic
	materials[key] = mat
	return mat

func mesh_at(mesh: Mesh, mat: Material, at: Vector3, parent: Node = null) -> MeshInstance3D:
	if parent == null:
		parent = self
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance

func box(at: Vector3, size: Vector3, color: Color, parent: Node = null) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	return mesh_at(mesh, material(color), at, parent)

func cylinder(at: Vector3, radius: float, height: float, color: Color, sides = 24) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh_at(mesh, material(color), at)

func ring(radius: float, tube: float, at: Vector3, color: Color) -> void:
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - tube
	mesh.outer_radius = radius + tube
	mesh.rings = 48
	mesh.ring_segments = 6
	mesh_at(mesh, material(color, 0.18), at)


## Photographed CC0 slate and wood; shared materials and world-space mapping.
func surface(kind: String, tint = Color.WHITE) -> Material:
	var key = kind + str(tint)
	if surface_materials.has(key): return surface_materials[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = tint.srgb_to_linear()
	mat.roughness = 0.88
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 5.0
	mat.uv1_scale = Vector3.ONE * (0.48 if kind == "stone" else 0.60)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_texture = STONE_DIFF if kind == "stone" else WOOD_DIFF
	mat.normal_enabled = true
	mat.normal_texture = STONE_NORMAL if kind == "stone" else WOOD_NORMAL
	mat.normal_scale = 0.65 if kind == "stone" else 0.40
	if kind == "stone":
		mat.roughness_texture = STONE_ROUGH
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	surface_materials[key] = mat
	return mat

func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for index in [0,1,2,0,2,3]:
		st.set_uv([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)][index])
		st.add_vertex([a,b,c,d][index])

func block(at: Vector3, size: Vector3, mat: Material, bevel = 0.035) -> MeshInstance3D:
	# Actual bevels catch the low sun along the edges of masonry and wood.
	var extent = size * 0.5
	var b = minf(bevel, minf(extent.x,minf(extent.y,extent.z)) * 0.42)
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in 6:
		var axis = int(face / 2)
		var sign_value=1.0 if face%2==0 else -1.0
		var a=(axis+1)%3
		var c=(axis+2)%3
		var points: Array[Vector3]=[]
		for uv in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var pt=Vector3.ZERO
			pt[axis]=extent[axis]*sign_value
			pt[a]=(extent[a]-b)*uv.x
			pt[c]=(extent[c]-b)*uv.y
			points.append(pt)
		if sign_value<0: points.reverse()
		quad(st,points[0],points[1],points[2],points[3])
		for i in 4:
			var p=points[i]
			var q=points[(i+1)%4]
			var outer_p=p
			var outer_q=q
			outer_p[axis]-=b*sign_value
			outer_q[axis]-=b*sign_value
			for other_axis in [a,c]:
				outer_p[other_axis]+=signf(p[other_axis])*b
				outer_q[other_axis]+=signf(q[other_axis])*b
			quad(st,p,outer_p,outer_q,q)
	st.generate_normals()
	st.generate_tangents()
	return mesh_at(st.commit(),mat,at)

func beam(a: Vector3, b: Vector3, radius: float, mat: Material, taper = 1.0) -> MeshInstance3D:
	var mesh=CylinderMesh.new()
	mesh.height=a.distance_to(b)
	mesh.top_radius=radius*taper
	mesh.bottom_radius=radius
	mesh.radial_segments=10
	mesh.rings=1
	var node=mesh_at(mesh,mat,(a+b)*0.5)
	var axis=(b-a).normalized()
	var side=axis.cross(Vector3.FORWARD).normalized()
	if side.length_squared()<0.1: side=Vector3.RIGHT
	node.basis=Basis(side,axis,side.cross(axis))
	return node

func _build_lighting() -> void:
	if get_script().resource_path.ends_with("duel_cavalry_arena.gd"):
		_build_cavalry_lighting()
		return
	var world=WorldEnvironment.new()
	var env=Environment.new()
	var sky=Sky.new()
	var sky_mat=ShaderMaterial.new()
	sky_mat.shader=MOUNTAIN_SKY_SHADER
	sky_mat.set_shader_parameter("mountain_panorama",MOUNTAIN_PANORAMA)
	sky_mat.set_shader_parameter("panorama_energy",0.82)
	sky_mat.set_shader_parameter("horizon_v",0.58)
	sky_mat.set_shader_parameter("overlap",0.10)
	sky.radiance_size=Sky.RADIANCE_SIZE_128
	sky.sky_material=sky_mat
	env.background_mode=Environment.BG_SKY
	env.sky=sky
	env.sky_rotation=Vector3.ZERO
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy=0.46
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure=0.95
	env.fog_enabled=true
	env.fog_light_color=Color("b2b7af")
	env.fog_light_energy=0.75
	env.fog_density=0.0040
	env.fog_sky_affect=0.30
	world.environment=env
	add_child(world)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-29,-43,0)
	sun.light_color=Color("ffdfb3")
	sun.light_energy=1.05
	sun.shadow_enabled=true
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance=38
	sun.shadow_bias=0.028
	sun.shadow_normal_bias=1.2
	add_child(sun)
	var fill=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-47,132,0)
	fill.light_color=Color("9fbdd3")
	fill.light_energy=0.25
	add_child(fill)

func _build_court() -> void:
	var stone=surface("stone",Color("a3a59b"))
	var dark_stone=surface("stone",Color("666d65"))
	block(Vector3(0,-0.58,0),Vector3(70,0.35,70),surface("stone",Color("707765")),0.03)
	var floor_mesh=BoxMesh.new()
	floor_mesh.size=Vector3(19,0.22,19)
	mesh_at(floor_mesh,_court_material(),Vector3(0,-0.11,0))
	block(Vector3(0,-0.28,0),Vector3(19.8,0.35,19.8),dark_stone,0.07)
	for side in [-1,1]:
		for i in 20:
			block(Vector3(side*9.32,-0.015,-9.025+i*0.95),Vector3(0.34,0.09,0.92),dark_stone,0.02)
			block(Vector3(-9.025+i*0.95,-0.015,side*9.32),Vector3(0.92,0.09,0.34),dark_stone,0.02)
	var body=StaticBody3D.new()
	body.collision_layer=1
	var collision=CollisionShape3D.new()
	var shape=BoxShape3D.new()
	shape.size=Vector3(40,0.5,40)
	collision.shape=shape
	collision.position.y=-0.25
	body.add_child(collision)
	add_child(body)
	ring(8.16,0.013,Vector3(0,0.008,0),Color("877f5c"))
	for i in 8:
		var a=TAU*i/8.0
		var mark=block(Vector3(sin(a)*8,0.006,cos(a)*8),Vector3(0.055,0.016,0.32),material(Color("9a8e68"),0.3),0.006)
		mark.rotation.y=a
	_moss_edges()
	for step in 4:
		block(Vector3(0,-0.10-step*0.13,9.8+step*0.34),Vector3(6.8,0.22,0.50),stone,0.045)

func roof_y(t: float, x: float, width: float) -> float:
	return 1.60-2.15*t+0.72*t*t+0.30*pow(t,12.0)+0.32*pow(absf(x)/width,9.0)*pow(t,3.0)

func roof(center: Vector3, width: float, depth: float, tint: Color) -> void:
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		for ix in 40:
			for iz in 12:
				var x0=lerpf(-width,width,ix/40.0)
				var x1=lerpf(-width,width,(ix+1)/40.0)
				var t0=iz/12.0
				var t1=(iz+1)/12.0
				var p0=Vector3(x0,roof_y(t0,x0,width),side*depth*t0)
				var p1=Vector3(x1,roof_y(t0,x1,width),side*depth*t0)
				var p2=Vector3(x1,roof_y(t1,x1,width),side*depth*t1)
				var p3=Vector3(x0,roof_y(t1,x0,width),side*depth*t1)
				if side>0: quad(st,p0,p3,p2,p1)
				else: quad(st,p0,p1,p2,p3)
	st.generate_normals()
	var mat=surface("stone",tint).duplicate()
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale=Vector3.ONE*1.4
	mesh_at(st.commit(),mat,center)
	# Semi-cylindrical tile courses and upturned ridge ends are real geometry.
	var tile_mat=surface("stone",tint.lightened(0.12)).duplicate()
	tile_mat.uv1_scale=Vector3.ONE*2.0
	tile_mat.normal_scale=0.30
	tile_mat.vertex_color_use_as_albedo=true
	tile_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var tiles=SurfaceTool.new()
	tiles.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		for ix in int(width*2/0.26)+1:
			var x=-width+ix*0.26
			for segment in 12:
				var t0=segment/12.0
				var t1=(segment+1)/12.0
				var shade=0.68+fmod(float(ix*17+segment*7),19.0)/19.0*0.32
				tiles.set_color(Color(shade,shade,shade,1.0))
				for arc in 6:
					var a0=arc*PI/6.0
					var a1=(arc+1)*PI/6.0
					var p0=Vector3(x+cos(a0)*0.13,roof_y(t0,x,width)+sin(a0)*0.10+0.075,side*depth*t0)
					var p1=Vector3(x+cos(a1)*0.13,roof_y(t0,x,width)+sin(a1)*0.10+0.075,side*depth*t0)
					var p2=Vector3(x+cos(a1)*0.13,roof_y(t1,x,width)+sin(a1)*0.10+0.035,side*depth*t1)
					var p3=Vector3(x+cos(a0)*0.13,roof_y(t1,x,width)+sin(a0)*0.10+0.035,side*depth*t1)
					quad(tiles,p0,p1,p2,p3)
	tiles.generate_normals()
	mesh_at(tiles.commit(),tile_mat,center)
	beam(center+Vector3(-width,1.66,0),center+Vector3(width,1.66,0),0.12,tile_mat)
	for side in [-1,1]:
		var tip=center+Vector3(side*width,1.66,0)
		beam(tip,tip+Vector3(side*0.42,0.40,0),0.10,tile_mat,0.3)

func _build_gate() -> void:
	var first_gate_child=get_child_count()
	var wood=surface("wood",Color("a44937"))
	var darkwood=surface("wood",Color("392e29"))
	var stone=surface("stone",Color("9c9d8a"))
	var gold=material(Color("b29a64"),0.22)
	for step in 4:
		block(Vector3(0,-0.20+step*0.13,-12-step*0.32),Vector3(17-step*0.3,0.22,0.62),stone,0.05)
	for x in [-7.2,-3.5,3.5,7.2]:
		block(Vector3(x,0.22,-13),Vector3(0.92,0.75,0.92),stone,0.11)
		var column=cylinder(Vector3(x,2.45,-13),0.22,4.10,Color("7c3e31"),20)
		column.material_override=wood
		for h in [0.65,3.83]:
			var collar=cylinder(Vector3(x,h,-13),0.27,0.15,Color("766b45"),20)
			collar.material_override=gold
		for layer in 3:
			block(Vector3(x,3.9+layer*0.18,-13),Vector3(0.66+layer*0.34,0.16,0.44),darkwood,0.025)
			block(Vector3(x,4+layer*0.18,-13),Vector3(0.36,0.14,0.80+layer*0.36),wood,0.02)
		beam(Vector3(x,3.25,-13),Vector3(x-0.7,3.95,-13),0.095,wood)
		beam(Vector3(x,3.25,-13),Vector3(x+0.7,3.95,-13),0.095,wood)
	block(Vector3(0,4.30,-13),Vector3(15.4,0.40,0.48),wood,0.04)
	block(Vector3(0,4.56,-13),Vector3(16.5,0.14,1.3),darkwood,0.02)
	roof(Vector3(0,4.56,-13),9.20,2.35,Color("414e49"))
	block(Vector3(0,6.03,-13),Vector3(5.9,0.52,1.05),wood,0.04)
	roof(Vector3(0,6.15,-13),4.20,1.40,Color("495951"))
	for x in [-5.4,5.4]:
		block(Vector3(x,2.20,-13.15),Vector3(3.1,3,0.16),darkwood,0.025)
		for i in 9: block(Vector3(x-1.35+i*0.34,2.2,-12.99),Vector3(0.045,2.8,0.055),wood,0.008)
		for h in [1.0,2.2,3.4]: block(Vector3(x,h,-12.94),Vector3(3.1,0.075,0.08),gold,0.008)
	block(Vector3(0,3.72,-12.56),Vector3(3.8,0.94,0.20),darkwood,0.045)
	for h in [3.29,4.15]: block(Vector3(0,h,-12.42),Vector3(3.65,0.035,0.035),gold,0.008)
	var plaque=Label3D.new()
	plaque.text="问  锋"
	plaque.font=load("res://assets/fonts/WenfengSerif.otf")
	plaque.font_size=112
	plaque.pixel_size=0.007
	plaque.modulate=Color("d9bd7d")
	plaque.position=Vector3(0,3.69,-12.39)
	add_child(plaque)
	for x in [-3.55,3.55]: _lantern(Vector3(x,3.31,-12.52))
	for side in [-1,1]:
		block(Vector3(side*12.30,1,-1),Vector3(0.56,2.55,23),surface("stone",Color("bebca5")),0.06)
		block(Vector3(side*12.30,2.3,-1),Vector3(0.92,0.17,23.3),darkwood,0.035)
		for z in [-10,-5,0,5,10]:
			block(Vector3(side*12.30,1.35,z),Vector3(0.76,3,0.76),stone,0.05)
			block(Vector3(side*12.30,2.90,z),Vector3(1.05,0.18,1.05),darkwood,0.035)
		for i in 58:
			var tile=cylinder(Vector3(side*12.30,2.45,-12.35+i*0.40),0.12,0.80,Color("46534a"),8)
			tile.rotation.z=PI*0.5
		for i in 7:
			var x=side*(4.3+i*0.85)
			block(Vector3(x,0.38,10),Vector3(0.22,0.90,0.22),stone,0.035)
			var cap=SphereMesh.new()
			cap.radius=0.16;cap.height=0.28;cap.radial_segments=10;cap.rings=5
			mesh_at(cap,stone,Vector3(x,0.93,10))
		block(Vector3(side*6.85,0.75,10),Vector3(5.4,0.16,0.19),stone,0.035)
		block(Vector3(side*6.85,0.16,10),Vector3(5.4,0.18,0.24),stone,0.035)


	# Keep the full curved silhouette in the gameplay shoulder composition.
	var compress=Transform3D(Basis.from_scale(Vector3(1,0.75,1)),Vector3.ZERO)
	for i in range(first_gate_child,get_child_count()):
		if get_child(i) is Node3D:
			get_child(i).transform=compress*get_child(i).transform
	_gate_depth()

func _court_material() -> ShaderMaterial:
	var shader=Shader.new()
	shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform sampler2D slate_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slate_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world.xz; float row=floor(p.y/1.18); vec2 tile=vec2(p.x/1.62+mod(row,2.0)*0.5,p.y/1.18);
 tile+=vec2(sin(p.y*6.1)*0.003,sin(p.x*5.7)*0.004);
 vec2 f=fract(tile); vec2 fw=fwidth(tile)*1.1;
 vec2 edge=min(f,1.0-f); float block=hash(floor(tile));
 float seam=0.0035+block*0.0025;
 float joint=1.0-smoothstep(seam,seam+max(fw.x,fw.y),min(edge.x,edge.y));
 vec3 tex=texture(slate_color,p*0.40+vec2(block*0.035)).rgb;
 float detail=dot(tex,vec3(0.299,0.587,0.114));
 vec3 stone=mix(vec3(0.118,0.146,0.151),vec3(0.222,0.250,0.245),block*0.62);
 stone*=mix(0.66,1.26,clamp(detail*2.8,0.0,1.0));
 float wear=(1.0-smoothstep(0.015,0.075,min(edge.x,edge.y)))*clamp(detail*3.0,0.0,1.0);
 stone+=vec3(0.028,0.030,0.027)*wear;
 float scratch=texture(slate_color,p*1.1+vec2(0.37,0.19)).r;
 stone*=0.90+scratch*0.45;
 float damp=smoothstep(6.4,9.4,max(abs(p.x),abs(p.y)));
 float patch=sin(p.x*1.7+sin(p.y*0.9))*sin(p.y*1.3+cos(p.x*0.6));
 stone*=1.0-damp*smoothstep(-0.2,0.8,patch)*0.25;
 stone=mix(stone,vec3(0.103,0.133,0.101),damp*smoothstep(0.15,0.72,patch)*0.30);
 ALBEDO=stone*(1.0-joint*0.36);
 NORMAL_MAP=mix(vec3(0.5,0.5,1.0),texture(slate_normal,p*0.40).rgb,0.22);
 ROUGHNESS=0.94;
 AO=1.0-joint*0.30;
}"""
	var mat=ShaderMaterial.new()
	mat.shader=shader
	mat.set_shader_parameter("slate_color",STONE_DIFF)
	mat.set_shader_parameter("slate_normal",STONE_NORMAL)
	return mat

func _gate_depth() -> void:
	var stone=surface("stone",Color("656e63"))
	var wood=surface("wood",Color("5e493a"))
	# A receding stair/path and smaller inner gate give the main opening depth.
	block(Vector3(0,-0.10,-22),Vector3(4.4,0.20,17),stone,0.04)
	for i in 7:
		block(Vector3(0,0.04+i*0.09,-17.0-i*0.95),Vector3(4.6,0.20,0.85),stone,0.035)
	for x in [-2.4,2.4]:
		beam(Vector3(x,0.4,-28),Vector3(x,3.0,-28),0.16,wood)
	block(Vector3(0,2.8,-28),Vector3(5.5,0.26,0.40),wood,0.03)
	roof(Vector3(0,2.9,-28),4.1,1.35,Color("4b6057"))
	for side in [-1,1]:
		for i in 7:
			bamboo(Vector3(side*rng.randf_range(3.2,6.0),0,-16.5-i*1.6),rng.randf_range(4.6,6.2))
		_pine(Vector3(side*7.7,0,-23),8.2)
		_pine(Vector3(side*4.8,0,-31),6.5)

func _pine(at: Vector3, height: float) -> void:
	var bark=surface("wood",Color("62695c"))
	beam(at,at+Vector3(0.3,height,0),0.20,bark,0.30)
	# Broad asymmetric needles form several separated dark crowns.
	for layer in 5:
		var y=height*(0.40+layer*0.12)
		var radius=(height-y)*0.47+0.35
		for branch in 5:
			var a=TAU*branch/5.0+layer*0.8
			var tip=at+Vector3(sin(a)*radius,y+0.12,cos(a)*radius)
			beam(at+Vector3(0,y-0.25,0),tip,0.045,bark,0.20)
			var crown=SphereMesh.new()
			crown.radius=1.0;crown.height=2.0;crown.radial_segments=10;crown.rings=5
			var node=mesh_at(crown,material(Color("3d5749").lightened(layer*0.016)),tip)
			node.scale=Vector3(radius*0.62,0.25,radius*0.47)

func _lantern(at: Vector3) -> void:
	beam(at+Vector3.UP*0.42,at+Vector3.UP*0.88,0.018,material(Color("40372d")))
	var mesh=SphereMesh.new()
	mesh.radius=0.28;mesh.height=0.64;mesh.radial_segments=16;mesh.rings=10
	var mat=material(Color("bc623c")).duplicate()
	mat.emission_enabled=true;mat.emission=Color("e5a657");mat.emission_energy_multiplier=0.65
	mesh_at(mesh,mat,at)
	for h in [-0.32,0.32]: cylinder(at+Vector3.UP*h,0.19,0.05,Color("4b362b"),16)
	for i in 10:
		var a=TAU*i/10.0
		beam(at+Vector3(sin(a)*0.255,-0.22,cos(a)*0.255),at+Vector3(sin(a)*0.255,0.22,cos(a)*0.255),0.008,material(Color("8e4430")))
	beam(at-Vector3.UP*0.35,at-Vector3.UP*0.67,0.018,material(Color("a95e37")))
	var light=OmniLight3D.new()
	light.position=at;light.light_color=Color("ffb86a");light.light_energy=0.45;light.omni_range=2.5
	add_child(light)

func _moss_edges() -> void:
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 300:
		var side=1 if i%2 else -1
		var p=Vector3(side*rng.randf_range(8.70,9.30),0.009,rng.randf_range(-9.2,9.2))
		if i%3==0: p=Vector3(p.z,0.009,p.x)
		var r=rng.randf_range(0.025,0.17)
		st.set_color(Color("4c5941").lerp(Color("778064"),rng.randf()))
		for a in [0.0,2.1,4.2]: st.add_vertex(p+Vector3(cos(a)*r,0,sin(a)*r))
	st.generate_normals()
	var mat=material(Color.WHITE).duplicate()
	mat.vertex_color_use_as_albedo=true;mat.vertex_color_is_srgb=true;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh_at(st.commit(),mat,Vector3.ZERO)

func leaf_spray(at: Vector3, direction: Vector3, color: Color) -> void:
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var p=at+direction*i*0.075
		var turn=direction.rotated(Vector3.UP,(0.60 if i%2 else -0.60)+rng.randf_range(-0.25,0.25))
		var tip=p+turn*rng.randf_range(0.34,0.62)+Vector3.UP*0.10
		var side=turn.cross(Vector3.UP).normalized()*0.045
		quad(st,p,(p+tip)*0.5+side,tip,(p+tip)*0.5-side)
	st.generate_normals()
	var mat=material(color)
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh_at(st.commit(),mat,Vector3.ZERO)

func bamboo(at: Vector3, height: float) -> void:
	var stem=material(Color("5b7050"))
	var node_mat=material(Color("899571"))
	var lean=Vector3(rng.randf_range(-0.55,0.55),0,rng.randf_range(-0.55,0.55))
	beam(at,at+Vector3.UP*height+lean,0.055,stem,0.70)
	for i in range(1,7):
		var t=i/7.0
		var p=at+Vector3.UP*height*t+lean*t
		cylinder(p,0.067,0.035,Color("899571"),8)
		if i<3: continue
		var a=rng.randf()*TAU
		var end=p+Vector3(sin(a)*0.75,0.22,cos(a)*0.75)
		beam(p,end,0.018,node_mat,0.25)
		leaf_spray(end,Vector3(sin(a),0.15,cos(a)),Color("4c6d49"))

func autumn_tree(at: Vector3, height: float, tree_seed: int) -> void:
	var random=RandomNumberGenerator.new()
	random.seed=tree_seed
	var bark=surface("wood",Color("787164"))
	beam(at,at+Vector3(0.1,height*0.6,0),0.25,bark,0.65)
	beam(at+Vector3(0.1,height*0.6,0),at+Vector3(0.35,height,0),0.16,bark,0.35)
	var leaves=SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for branch in 11:
		var a=TAU*branch/11.0+random.randf_range(-0.25,0.25)
		var start=at+Vector3(0.15,height*random.randf_range(0.45,0.82),0)
		var end=at+Vector3(sin(a)*random.randf_range(1.5,3.1),height*random.randf_range(0.76,1.03),cos(a)*random.randf_range(1.5,3.1))
		beam(start,end,0.11,bark,0.18)
		for cluster in 22:
			var center=end+Vector3(random.randf_range(-1.2,1.2),random.randf_range(-0.35,0.65),random.randf_range(-1.2,1.2))
			for leaf in 16:
				var p=center+Vector3(random.randf_range(-0.42,0.42),random.randf_range(-0.22,0.22),random.randf_range(-0.42,0.42))
				var size=random.randf_range(0.07,0.16)
				var tint=Color("b96d2d").lerp(Color("dfb34e"),random.randf())
				if random.randf()<0.12: tint=Color("7b4930")
				leaves.set_color(tint)
				var axis=Vector3(random.randf_range(-1,1),random.randf_range(-0.3,0.8),random.randf_range(-1,1)).normalized()
				var side=axis.cross(Vector3.UP).normalized()*size*0.52
				quad(leaves,p-axis*size,p+side,p+axis*size,p-side)
	leaves.generate_normals()
	var mat=material(Color.WHITE).duplicate()
	mat.vertex_color_use_as_albedo=true;mat.vertex_color_is_srgb=true;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh_at(leaves.commit(),mat,Vector3.ZERO)

func mountain(center: Vector3, width: float, height: float, color: Color, mountain_seed: int) -> MeshInstance3D:
	var random=RandomNumberGenerator.new()
	random.seed=mountain_seed
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Array[float]=[]
	for i in 41:
		var t=i/40.0
		heights.append(height*(0.30+0.70*pow(sin(t*PI),0.55))*(0.78+random.randf()*0.24))
	for i in 40:
		var x0=(i/40.0-0.5)*width
		var x1=((i+1)/40.0-0.5)*width
		st.set_color(color.lerp(color.darkened(0.15),random.randf()*0.7))
		quad(st,Vector3(x0,heights[i],0),Vector3(x0,-8,0),Vector3(x1,-8,0),Vector3(x1,heights[i+1],0))
	st.generate_normals()
	var mat=material(Color.WHITE).duplicate()
	mat.vertex_color_use_as_albedo=true;mat.vertex_color_is_srgb=true;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	return mesh_at(st.commit(),mat,center)

func _build_surroundings() -> void:
	for side in [-1,1]:
		for i in 17:
			bamboo(Vector3(side*rng.randf_range(13.4,17.5),-0.35,rng.randf_range(-13,11)),rng.randf_range(4.2,7.5))
	autumn_tree(Vector3(-10.8,-0.3,-8.3),7.4,198)
	autumn_tree(Vector3(11.5,-0.3,-10.2),8.2,729)
	autumn_tree(Vector3(-17,-0.3,4),7.7,334)
	var rock_mat=surface("stone",Color("7d8371"))
	for i in 22:
		var side=1 if i%2 else -1
		var rock=SphereMesh.new()
		rock.radius=0.55;rock.height=1.1;rock.radial_segments=9;rock.rings=5
		var node=mesh_at(rock,rock_mat,Vector3(side*rng.randf_range(10,11.6),-0.12,rng.randf_range(-9,9)))
		node.scale=Vector3(rng.randf_range(0.7,1.6),rng.randf_range(0.4,0.9),rng.randf_range(0.6,1.2))
		node.rotation=Vector3(0.2,rng.randf()*TAU,0.15)
	# Fallen leaves stay around the margins, leaving the combat centre clear.
	var leaves=SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 215:
		var a=rng.randf()*TAU
		var r=rng.randf_range(2.8,7.8) if i%5==0 else rng.randf_range(7.8,10.3)
		var p=Vector3(sin(a)*r,0.014,cos(a)*r)
		var axis=Vector3(sin(a+1.1),0,cos(a+1.1))*0.09
		var side=axis.rotated(Vector3.UP,PI*0.5)*0.4
		leaves.set_color(Color("a27337").lerp(Color("c29f53"),rng.randf()))
		quad(leaves,p-axis,p+side,p+axis,p-side)
	leaves.generate_normals()
	var leaf_mat=material(Color.WHITE).duplicate()
	leaf_mat.vertex_color_use_as_albedo=true;leaf_mat.vertex_color_is_srgb=true;leaf_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh_at(leaves.commit(),leaf_mat,Vector3.ZERO)

func _build_cavalry_lighting() -> void:
	var world = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("597b88")
	sky_mat.sky_horizon_color = Color("b8c6c3")
	sky_mat.ground_horizon_color = Color("a2ada5")
	sky_mat.ground_bottom_color = Color("465457")
	sky_mat.sky_curve = 0.20
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c9cc")
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color("a4b9bb")
	env.fog_light_energy = 0.72
	env.fog_density = 0.008
	world.environment = env
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -32, 0)
	sun.light_color = Color("ffe1ae")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 24
	sun.shadow_bias = 0.035
	add_child(sun)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-23, 145, 0)
	fill.light_color = Color("8ab4cb")
	fill.light_energy = 0.22
	add_child(fill)
