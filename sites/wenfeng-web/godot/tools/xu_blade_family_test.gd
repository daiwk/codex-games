extends SceneTree

# Main's actual actors, swept melee resolver and returning-blade entities.
# No synthetic receive_strike, skill callbacks, pose writes or attack-clock writes.
var game
var report_path = "/private/tmp/wenfeng-xu-blade-family-results.json"
var case_name = "boot"
var checks: Array = []
var failures: Array = []
var cases: Array = []
var actions: Array = []
var impacts: Array = []
var handoffs: Array = []
var timeline: Array = []
var tracked_nodes: Array = []
var last_sample: Dictionary = {}
var closed_fingers: Dictionary = {}
var peak_entities = 0
var premature_held = false
var observed = false
var core_only = false
var grip_only = false
var wall_only = false
var next_cancel_tick: Dictionary = {}

class CancelTickObserver extends Node:
	var host
	func _physics_process(_delta: float) -> void:
		if host==null or not host.observed or host.case_name!="U allblocked environment": return
		if not host.next_cancel_tick.is_empty(): return
		var cancelled=host.events("cast_cancelled")
		if not cancelled.is_empty() and Engine.get_physics_frames()>int(cancelled[0].physics_frame):
			host.next_cancel_tick=host.snapshot()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): report_path = arg.trim_prefix("--output=")
		if arg == "--core-only": core_only = true
		if arg == "--grip-only": grip_only = true
		if arg == "--wall-only": wall_only = true
	call_deferred("run")

func point(v: Vector3) -> Array: return [v.x, v.y, v.z]

func snapshot() -> Dictionary:
	return {"frame":Engine.get_physics_frames(),"state":game.player.state,"clip":game.player.current_clip,
		"animation":str(game.player.animation_player.current_animation),"combo":game.player.combo,"time":game.player.action_time,
		"hp":game.player.hp,"enemy_hp":game.enemy.hp,"position":point(game.player.position),
		"family":game.player.blade_family_status(),"held_visible":game.player.weapon_mesh.is_visible_in_tree(),
		"thrown":game.player.duel_weapon_is_thrown(),"entities":game.specials.entity_count()}

func frames(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame
		if not is_instance_valid(game): continue
		last_sample = snapshot()
		if not observed: continue
		timeline.append(last_sample.duplicate(true))
		peak_entities = maxi(peak_entities,game.specials.entity_count())
		for group in game.specials.groups.values():
			if is_instance_valid(group.node) and not tracked_nodes.has(group.node): tracked_nodes.append(group.node)
			if game.player.weapon_mesh.is_visible_in_tree():
				for entity in group.entities:
					if entity.get("launched",true) and not entity.done: premature_held = true

func wait_until(predicate: Callable, limit = 600) -> bool:
	for _i in limit:
		if predicate.call(): return true
		await frames(1)
	return bool(predicate.call())

func verify(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"case":case_name,"label":label,"passed":passed,"detail":detail,"state":snapshot()})
	if not passed: failures.append(case_name+": "+label)
	print("PASS " if passed else "FAIL ",case_name," / ",label)
	write_report(false)

func on_action(actor, action: String) -> void:
	if not observed: return
	actions.append({"actor":"player" if actor==game.player else "enemy","action":action,"combo":actor.combo,
		"clip":actor.current_clip,"frame":Engine.get_physics_frames(),"prior":last_sample.duplicate(true)})

func on_impact(actor, outcome: String, at: Vector3) -> void:
	if not observed: return
	impacts.append({"actor":"player" if actor==game.player else "enemy","outcome":outcome,
		"hp":actor.hp,"at":point(at),"frame":Engine.get_physics_frames(),"attacker_time":actor.opponent.action_time})

func on_handoff(kind: String, fighter, context: Dictionary) -> void:
	if observed and fighter==game.player:
		var row=context.duplicate(true);row["kind"]=kind;row["physics_frame"]=Engine.get_physics_frames()
		if kind=="cast_cancelled":row["observed_state"]=snapshot()
		handoffs.append(row)

func events(kind: String) -> Array:
	return handoffs.filter(func(x):return x.kind==kind)

func light_actions() -> Array:
	return actions.filter(func(x):return x.actor=="player" and x.action=="light")

func ready() -> bool:
	return game.player.state=="idle" and not game.player.blade_family.action_active and str(game.player.animation_player.current_animation).ends_with("XuBladeReady")

func nodes_removed() -> bool:
	for node in tracked_nodes:
		if is_instance_valid(node) and node.is_inside_tree(): return false
	return true

func finger_error() -> float:
	var error=0.0
	for bone in closed_fingers:
		error=maxf(error,rad_to_deg(game.player.skeleton.get_bone_pose_rotation(bone).angle_to(closed_fingers[bone])))
	return error

func setup(label: String, gap: float, opponent = "zhaoyun", equipped_weapon = "") -> void:
	observed=false
	game.return_to_menu()
	game.select_character("xuchu")
	if equipped_weapon != "": game.select_weapon(equipped_weapon)
	game.select_opponent(opponent)
	game.start_match()
	game.testing=true # Main skips automatic keyboard polling and hitstop; actors/contacts run normally.
	game.ai_enabled=false
	game.fx.muted=true
	game.phase="fight"
	game.paused=false
	game.round_time=90.0
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	game._clear_combat_input()
	for actor in [game.player,game.enemy]:
		actor.enabled=true;actor.set_physics_process(true);actor.input_move=Vector3.ZERO;actor.wants_block=false
		actor.hp=1000.0;actor.stamina=100.0;actor.energy=100.0
	game.player.position=Vector3(0,.015,-gap*.5)
	game.enemy.position=Vector3(0,.015,gap*.5)
	game.player.rotation.y=0.0
	game.enemy.rotation.y=PI
	game.lock_on=true
	game.camera_axis_ready=false
	await frames(20)
	case_name=label;actions=[];impacts=[];handoffs=[];timeline=[];tracked_nodes=[];peak_entities=0;premature_held=false
	next_cancel_tick.clear()
	closed_fingers.clear()
	for bone in game.player.skeleton.get_bone_count():
		var name=str(game.player.skeleton.get_bone_name(bone))
		if "RightHand" in name and not name.ends_with("RightHand"):
			closed_fingers[bone]=game.player.skeleton.get_bone_pose_rotation(bone)
	game.player.action_started.connect(on_action)
	game.enemy.action_started.connect(on_action)
	game.player.impact_received.connect(on_impact)
	game.enemy.impact_received.connect(on_impact)
	observed=true

func save_case(fixture: String) -> void:
	cases.append({"name":case_name,"fixture":fixture,"actions":actions.duplicate(true),"impacts":impacts.duplicate(true),
		"handoffs":handoffs.duplicate(true),"peak_entities":peak_entities,"timeline":timeline.duplicate(true),"final":snapshot()})
	observed=false
	write_report(false)

func core() -> void:
	await setup("J continuous three hits",1.15)
	verify("first real light request accepted",game.player.request_light())
	await frames(2)
	verify("second press buffers real next attack",game.player.request_light())
	var second=await wait_until(func():return light_actions().size()>=2)
	verify("second light starts",second)
	if second: verify("third press buffers final attack",game.player.request_light())
	var done=await wait_until(func():return light_actions().size()>=3 and ready())
	var sequence=[]
	for action in light_actions():sequence.append(action.combo)
	verify("three starts remain J1 J2 J3",done and sequence==[0,1,2],sequence)
	verify("real contact damages nearby opponent",game.enemy.hp<1000.0,impacts)
	var hp=game.enemy.hp
	await frames(30)
	verify("normal finish holds Ready without delayed damage",ready() and is_equal_approx(hp,game.enemy.hp) and game.specials.groups.is_empty())
	save_case("Both bodies on flat Main arena,1.15m apart,facing each other; enemy passive,HP1000 prevents round exit; three actual request_light calls.")

	await setup("J late repeat",4.0)
	verify("first light starts",game.player.request_light())
	# The compiled source's recovery segment is the user-visible late-input fixture.
	# Its boundary schedules the press; no expected implementation clock is asserted.
	var recovery=float(game.player.blade_family.data.clips.XuBladeJ1.segments[1].output_start)
	var in_recovery=await wait_until(func():return game.player.blade_family.action_active and game.player.blade_family.source_time>recovery)
	verify("press occurs after authored cut entered recovery",in_recovery)
	if in_recovery: verify("late press accepted",game.player.request_light())
	var repeated=await wait_until(func():return light_actions().size()>=2)
	var seq=[]
	for action in light_actions():seq.append(action.combo)
	verify("late press starts a new J1, never J2",repeated and seq==[0,0],seq)
	if repeated:
		var prior=light_actions()[1].prior
		var full=game.player.blade_family.duration("XuBladeJ1")
		verify("authored recovery completes before repeated J1",float(prior.family.elapsed)>=full-3.0/60.0,{"prior":prior,"full_source_seconds":full})
	verify("repeated J1 finishes Ready",await wait_until(ready))
	save_case("4m passive target keeps hit reactions out of timing case; single repeat press after compiled authored recovery begins,not a chain-window press.")

	await setup("E real front guard and cut",1.15,"xuchu")
	var hp_before=game.player.hp
	verify("real guard request accepted",game.player.request_skill("counter"))
	verify("front opponent real light accepted",game.enemy.request_light())
	var blocked=await wait_until(func():return impacts.any(func(x):return x.actor=="player" and x.outcome=="block"),180)
	verify("actual swept front strike is blocked",blocked and is_equal_approx(hp_before,game.player.hp),impacts)
	verify("scheduled physical retaliation contacts opponent",await wait_until(func():return impacts.any(func(x):return x.actor=="enemy" and x.hp<1000.0),240),impacts)
	verify("guard and cut recover Ready",await wait_until(ready))
	save_case("Two actual Xu actors1.15m apart,facing each other. E and opposing real request_light start together; no synthetic strike or forced counter flag.")

func start_throw(kind: String) -> bool:
	if kind=="U": return game.player.request_ultimate()
	return game.player.request_skill("rush")

func throw_case(kind: String) -> void:
	await setup(kind+" real release return catch",6.0)
	verify("real cast request accepted",start_throw(kind))
	var released=await wait_until(func():return not events("released").is_empty(),240)
	verify("real entity release hides held weapon",released and game.player.duel_weapon_is_thrown() and not game.player.weapon_mesh.is_visible_in_tree())
	var finished=await wait_until(func():return not events("caught").is_empty() and game.specials.groups.is_empty() and ready(),900)
	await frames(12)
	var launches=events("released");var catches=events("caught");var unique={};var order=[]
	for event in catches:unique[int(event.index)]=true;order.append(int(event.index))
	var count=3 if kind=="U" else 1
	verify("all real blade entities are caught exactly once",finished and launches.size()==count and catches.size()==count and unique.size()==count,{"launched":launches,"caught":catches,"actual_order":order})
	if kind=="U":
		var launch_frames={}
		for event in launches:launch_frames[int(event.frame)]=true
		verify("three blades share one real throw release",peak_entities==3 and launch_frames.size()==1,{"peak":peak_entities,"release_frames":launch_frames.keys()})
	verify("held weapon stays hidden until actual last catch",not premature_held and not catches.is_empty() and bool(catches[-1].last),{"premature_held":premature_held,"caught":catches})
	verify("last catch restores held weapon and closed fingers",game.player.weapon_mesh.is_visible_in_tree() and not game.player.duel_weapon_is_thrown() and game.player.blade_family.hand_open<.001 and finger_error()<1.0,{"hand_open":game.player.blade_family.hand_open,"finger_error_degrees":finger_error()})
	verify("actual flight nodes leave tree",game.specials.groups.is_empty() and nodes_removed())
	save_case("Both bodies6m apart,passive target,HP1000; actual skill/ultimate request,energy100 is explicit U gate fixture. Return/catch order is observed,not assumed.")

func light_armor_case() -> void:
	await setup("Q existing light armor",6.0)
	verify("real throw begins",start_throw("Q"))
	verify("live blade releases before incoming attack",await wait_until(func():return not events("released").is_empty(),240))
	game.enemy.position=game.player.position-game.player.forward()*1.1
	game.enemy.rotation.y=game.player.rotation.y
	game.enemy.velocity=Vector3.ZERO
	verify("nearby opponent real light accepted",game.enemy.request_light())
	verify("actual light contact damages owner",await wait_until(func():return impacts.any(func(x):return x.actor=="player" and x.hp<1000.0),180),impacts)
	verify("existing light armor retains cast and in-flight entity",game.player.state=="skill" and game.player.duel_weapon_is_thrown() and game.specials.entity_count()>0)
	verify("uninterrupted blade completes actual catch",await wait_until(func():return not events("caught").is_empty() and game.specials.groups.is_empty() and ready(),600))
	await frames(12)
	verify("armored cast finally restores held weapon and fingers",game.player.weapon_mesh.is_visible_in_tree() and game.player.blade_family.hand_open<.001 and finger_error()<1.0)
	save_case("Same Q6m release; opposing normal J relocated1.1m behind clear of outgoing lane. Existing rush light armor is deliberately preserved: damage applies but should not cancel cast. Later actual return/catch must occur.")

func lifecycle(kind: String) -> void:
	await setup("Q lifecycle "+kind,6.0)
	verify("real throw begins",start_throw("Q"))
	verify("live blade exists before cancellation",await wait_until(func():return not events("released").is_empty(),240))
	var catches_before=events("caught").size()
	if kind=="reset": game.start_match()
	elif kind=="menu": game.return_to_menu()
	else:
		# Controlled incoming-hit fixture: relocate the opponent,not the blade or owner.
		# Its real normal attack must then pass the unchanged Main contact resolver.
		game.enemy.position=game.player.position-game.player.forward()*1.1
		game.enemy.rotation.y=game.player.rotation.y
		game.enemy.velocity=Vector3.ZERO
		if kind=="death": game.player.hp=1.0
		verify("nearby opponent real heavy accepted",game.enemy.request_heavy())
		verify("actual opposing attack reaches owner",await wait_until(func():return impacts.any(func(x):return x.actor=="player" and x.outcome in ["hit","heavy_hit"]),180),impacts)
	await frames(8)
	verify("cancellation clears entities and real nodes",game.specials.groups.is_empty() and nodes_removed())
	verify("cancellation restores held weapon and hand layer",game.player.weapon_mesh.is_visible_in_tree() and not game.player.duel_weapon_is_thrown() and game.player.blade_family.hand_open<.001)
	verify("cancellation does not invent caught callbacks",events("caught").size()==catches_before,handoffs)
	if kind=="death":verify("actual incoming contact is lethal",game.player.hp<=0.0)
	save_case("Actual Q releases at6m. Reset/menu use actual Main lifecycle; hit/death move opposing body to1.1m behind (clear of outgoing blade lane) and request its real heavy (bypasses existing light armor). Death starts ownerHP1; no synthetic receive_strike/catch callbacks.")

func legacy_grip_protection() -> void:
	for airborne_request in [false,true]:
		var weapon="xuchu_saber" if airborne_request else "saber"
		await setup("Legacy air K grip" if airborne_request else "Other weapon K grip",4.0,"zhaoyun",weapon)
		var q=game.player.grip_config.rotation_xyzw
		var original=Quaternion(q[0],q[1],q[2],q[3]).normalized()
		var before=rad_to_deg(game.player.grip.quaternion.angle_to(original))
		var airborne_ok=true
		if airborne_request:
			airborne_ok=game.player.request_jump()
			airborne_ok=airborne_ok and await wait_until(func():return game.player.is_jumping() and not game.player.is_on_floor(),120)
		var cuts=[]
		game.player.strike_requested.connect(func(actor,profile):
			if cuts.is_empty() and bool(profile.get("heavy",false)):
				cuts.append({"frame":Engine.get_physics_frames(),"clip":actor.current_clip,"source_K":bool(profile.get("xu_ual1_k",false)),"grip_error_degrees":rad_to_deg(actor.grip.quaternion.angle_to(original)),"source_family":actor.blade_family_status(),"jumping_at_cut":actor.is_jumping()}))
		var accepted=game.player.request_heavy()
		var emitted=await wait_until(func():return not cuts.is_empty(),240)
		verify("real legacy K restores original equipment frame before its effective cut",airborne_ok and accepted and emitted and not bool(cuts[0].source_K) and float(cuts[0].grip_error_degrees)<.1,{"weapon":weapon,"airborne_request":airborne_request,"ready_grip_difference_degrees":before,"first_actual_cut":cuts[0] if emitted else {}})
		save_case("4m passive target. Actual selected weapon and request_heavy; air case first requests a real jump and waits for capsule airborne. Only effective legacy K cut frame must use original Grip; other anatomical-family states are not constrained.")

func allblocked_environment_case() -> void:
	await setup("U allblocked environment",2.3,"zhaoyun","xuchu_saber")
	# Exact physical fixture from the independently rendered allblocked case.
	var wall=StaticBody3D.new()
	wall.name="QA_Layer1_ThrowWall"
	wall.collision_layer=1;wall.collision_mask=0
	wall.position=Vector3(0,1.5,0.65)
	var collider=CollisionShape3D.new()
	var shape=BoxShape3D.new();shape.size=Vector3(4,3,.15)
	collider.shape=shape;wall.add_child(collider);game.add_child(wall)
	await frames(2)
	var owner_hp=game.player.hp;var enemy_hp=game.enemy.hp
	verify("actual U request accepted behind real layer1 wall",game.player.request_ultimate())
	var cancelled=await wait_until(func():return not events("cast_cancelled").is_empty(),240)
	await wait_until(func():return not next_cancel_tick.is_empty(),3)
	var cancellations=events("cast_cancelled")
	verify("environment rejects cast without released or caught",cancelled and cancellations.size()==1 and str(cancellations[0].reason)=="environment_blocked" and events("released").is_empty() and events("caught").is_empty(),handoffs)
	var next_tick_ok=not next_cancel_tick.is_empty()
	if next_tick_ok:
		next_tick_ok=int(next_cancel_tick.frame)==int(cancellations[0].physics_frame)+1 and next_cancel_tick.state not in ["skill","ultimate"] and float(next_cancel_tick.family.hand_open)<.001
	verify("next physics tick exits cast with closed hand layer",next_tick_ok,{"cancel":cancellations,"next_tick":next_cancel_tick})
	await frames(12)
	var held_always=true
	for sample in timeline:held_always=held_always and bool(sample.held_visible) and not bool(sample.thrown)
	verify("held weapon remains visible for whole blocked cast",held_always and game.player.weapon_mesh.is_visible_in_tree(),{"samples":timeline.size(),"held_always":held_always})
	var tree_flights=[]
	for node in game.specials.get_children():
		if str(node.name).begins_with("DuelSpecial_"):tree_flights.append(str(node.name))
	verify("blocked U leaves no live entities or flight tree nodes",peak_entities==0 and game.specials.groups.is_empty() and nodes_removed() and tree_flights.is_empty(),{"peak_entities":peak_entities,"tree_flights":tree_flights})
	verify("blocked U produces no contact damage",is_equal_approx(owner_hp,game.player.hp) and is_equal_approx(enemy_hp,game.enemy.hp) and impacts.is_empty(),impacts)
	save_case("Actual layer1 StaticBody3D wall center(0,1.5,.65),BoxShape(4,3,.15),mask0; bodies2.3m apart facing each other. Real request_ultimate with energy100. Wall alters physical world only; no callbacks or entity flags injected.")
	wall.queue_free();await frames(2)

func write_report(completed: bool) -> void:
	var report={"completed":completed,"passed":completed and failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,
		"scope":"Actual canonical Main/actors/contact resolver,request_light/request_skill/request_ultimate and actual returning-blade entities. Fixtures declared per case. All InputMap events removed. AI disabled/testing suppresses automatic input/hitstop; no motion/clock/collision callback injection.",
		"runtime_sha256":{}}
	for path in ["res://scripts/duel_actor.gd","res://scripts/xu_blade_family.gd","res://scripts/duel_specials.gd","res://scripts/blade_hand_pose.gd","res://assets/motion/xuchu_blade_family.glb"]:
		report.runtime_sha256[path]=FileAccess.get_sha256(path)
	var file=FileAccess.open(report_path,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"))

func run() -> void:
	Engine.physics_ticks_per_second=60
	Engine.time_scale=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.testing=true;game.ai_enabled=false;game.fx.muted=true
	game.specials.blade_released.connect(func(fighter,context):on_handoff("released",fighter,context))
	game.specials.begin_blade_return.connect(func(fighter,context):on_handoff("return",fighter,context))
	game.specials.complete_blade_catch.connect(func(fighter,context):on_handoff("caught",fighter,context))
	game.specials.blade_cast_cancelled.connect(func(fighter,context):on_handoff("cast_cancelled",fighter,context))
	var cancel_observer=CancelTickObserver.new();cancel_observer.host=self;cancel_observer.process_physics_priority=1000;root.add_child(cancel_observer)
	if not grip_only and not wall_only: await core()
	if not core_only and not grip_only and not wall_only:
		await throw_case("Q")
		await throw_case("U")
		await light_armor_case()
		for kind in ["reset","menu","hit","death"]:await lifecycle(kind)
	if not core_only and not wall_only: await legacy_grip_protection()
	if not core_only and not grip_only: await allblocked_environment_case()
	write_report(true)
	observed=false
	game.queue_free()
	await frames(2)
	print("XU_BLADE_FAMILY_DONE ",checks.size()," checks; ",failures.size()," failures; ",report_path)
	quit(0 if failures.is_empty() else 1)
