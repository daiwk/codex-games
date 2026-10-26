extends "res://scripts/arena.gd"

# A mounted pass needs room to accelerate, clear the opponent and turn back.
# All geometry is local/procedural; the foot courtyard and RPG stay unchanged.
func _build_lighting() -> void:
	super._build_lighting()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.fog_density=0.0035

func _build_court() -> void:
	var field = box(Vector3(0,-0.22,0),Vector3(110,0.44,110),Color("77745a"))
	var shader = Shader.new()
	shader.code = """shader_type spatial;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world.xz; float n=fract(sin(dot(floor(p*1.8),vec2(127.1,311.7)))*43758.5453);
 float track=1.0-smoothstep(2.2,3.8,abs(length(p)-22.5));
 vec3 earth=mix(vec3(.20,.24,.18),vec3(.36,.32,.22),n*.24+.38);
 ALBEDO=mix(earth,vec3(.37,.32,.23),track*.45);ROUGHNESS=.97;
}"""
	var material = ShaderMaterial.new()
	material.shader=shader
	field.material_override=material
	var floor_body=StaticBody3D.new()
	floor_body.collision_layer=1
	var shape=CollisionShape3D.new()
	var slab=BoxShape3D.new()
	slab.size=Vector3(110,0.5,110)
	shape.shape=slab;shape.position.y=-0.25
	floor_body.add_child(shape);add_child(floor_body)
	ring(28.7,0.035,Vector3(0,.018,0),Color("b9a67e"))
	for i in 64:
		var a=TAU*i/64.0
		var p=Vector3(sin(a)*32.5,0,cos(a)*32.5)
		box(p+Vector3.UP*.70,Vector3(.18,1.40,.18),Color("564b39"))
		for h in [.45,1.03]:
			var rail=box(p+Vector3.UP*h,Vector3(3.30,.11,.12),Color("74634b"))
			rail.rotation.y=a
	for i in 8:
		var a=TAU*i/8.0
		var marker=box(Vector3(sin(a)*28.7,.025,cos(a)*28.7),Vector3(.18,.04,1.3),Color("c4b184"))
		marker.rotation.y=a

func _build_gate() -> void:
	for x in [-7.0,7.0]:
		box(Vector3(x,2.2,-36),Vector3(.7,4.4,.7),Color("4c4e40"))
	box(Vector3(0,4.5,-36),Vector3(16,.6,1.2),Color("35463f"))
	var title=Label3D.new();title.text="问锋 · 演武马场";title.font=load("res://assets/fonts/WenfengSerif.otf")
	title.position=Vector3(0,4.52,-35.3);title.font_size=80;title.pixel_size=.008;title.modulate=Color("d2bb86")
	add_child(title)

func _build_surroundings() -> void:
	for i in 12:
		var a=TAU*i/12.0
		var p=Vector3(sin(a)*34.5,0,cos(a)*34.5)
		cylinder(p+Vector3.UP*2.5,.06,5.0,Color("897b53"),8)
		var flag=box(p+Vector3(.65,4.2,0),Vector3(1.3,1.1,.025),Color("5e3333") if i%2 else Color("34544c"))
		flag.rotation.y=a
	for i in 14:
		var a=TAU*i/14.0
		var mesh=SphereMesh.new()
		mesh.radius=18.0;mesh.height=36.0;mesh.radial_segments=20;mesh.rings=8
		var hill=mesh_at(mesh,material(Color("64756b")),Vector3(sin(a)*83,-5.0,cos(a)*83))
		hill.scale=Vector3(1.5,.47+sin(i*2.3)*.12,.8)
		hill.rotation.y=a
