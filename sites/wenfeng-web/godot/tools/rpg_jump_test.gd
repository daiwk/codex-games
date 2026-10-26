extends SceneTree

# Reproducible RPG jump/controller suite. Run with -- --rpg-test.
# Initial run:58/59; airborne horse replacement collision was the sole failure.
# Its production fix passed the focused10-check horse-swap suite; original raw
# failure report is retained separately. Assertions below remain unchanged.
var game:Node3D
var checks=[]
var failures=[]
var events=[]
var cases=[]
var context=""
func _initialize():call_deferred("run")
func frames(n):
	for i in n:await physics_frame
func check(name,ok,details=null):
	checks.append({"name":name,"passed":ok,"details":details})
	if not ok:failures.append(name);print("RPG_JUMP_FAIL ",name," ",details)
func record_skill(actor,id,stage):
	if actor!=game.player:return
	events.append({"case":context,"id":id,"stage":stage,"jump":actor.jump_status(),"state":actor.state,"clip":actor.current_clip,"action_time":actor.action_time,"stamina":actor.stamina,"energy":actor.energy})
func bind_player():
	if not game.player.skill_triggered.is_connected(record_skill):game.player.skill_triggered.connect(record_skill)
func press(code):
	var ev=InputEventKey.new();ev.physical_keycode=code;ev.keycode=code;ev.pressed=true;Input.parse_input_event(ev);await frames(2);ev=InputEventKey.new();ev.physical_keycode=code;ev.keycode=code;ev.pressed=false;Input.parse_input_event(ev);await frames(1)
func fresh():
	game.command("return_to_camp");bind_player();await frames(8)
func start_air():
	await press(KEY_V)
	for i in 40:
		if game.player.jump_status().airborne:return true
		await frames(1)
	return false
func wait_land():
	for i in 140:
		await frames(1)
		if not game.player.is_jumping() and game.player.is_on_floor():return true
	return false
func skill_case(item,id,key):
	await fresh();game.command("equip",item);await frames(3)
	context=item+"/air/"+id;events=[]
	var f=game.player;f.energy=100.0
	var stats_before={"stamina":f.stamina,"energy":f.energy}
	check(context+" real V launches",await start_air(),f.jump_status())
	var y_before=f.position.y
	await press(key)
	check(context+" actual controller starts while airborne",not events.is_empty() and events[0].stage=="start" and bool(events[0].jump.airborne),events.duplicate(true))
	var spent_energy=f.energy;var spent_stamina=f.stamina
	check(context+" correct resource spent",spent_energy<1 if id=="ultimate" else spent_stamina<99,{"before":stats_before,"after_energy":spent_energy,"after_stamina":spent_stamina,"profile_cost":f.skill_cost(id)})
	var peak=f.position.y;var sampled=[]
	for i in 300:
		await frames(1);peak=maxf(peak,f.position.y)
		if i%12==0:sampled.append({"tick":i,"y":f.position.y,"jump":f.jump_status(),"state":f.state,"clip":f.current_clip,"time":f.action_time})
		if not events.is_empty() and events[-1].stage=="complete" and not f.is_jumping():break
	var release=false;var complete=false;var released_air=false
	for e in events:
		if e.stage in ["release","strike","finish"]:release=true;released_air=released_air or bool(e.jump.airborne)
		if e.stage=="complete":complete=true
	check(context+" real release and complete lifecycle",release and complete,events.duplicate(true))
	check(context+" floor landing recovers",f.is_on_floor() and not f.is_jumping() and peak>.9,{"peak":peak,"jump":f.jump_status(),"grounded":f.is_on_floor()})
	cases.append({"case":context,"weapon":f.weapon_id,"events":events.duplicate(true),"released_while_airborne":released_air,"peak":peak,"samples":sampled})
func run():
	Engine.physics_ticks_per_second=60;Engine.time_scale=1.0
	game=load("res://tools/rpg_jump_controller.gd").new();root.add_child(game);current_scene=game;await frames(8);game.fx.muted=true
	while game.phase=="dialogue":game.command("continue_dialogue")
	game.progress.inventory.append("guanyu_blade");game.progress.inventory.append("lubu_halberd");bind_player();await frames(8)
	check("V mapped physical key",InputMap.action_has_event("jump",make_key(KEY_V)))
	await fresh();var f=game.player;var before=f.stamina
	check("V real controller launches from floor",await start_air(),f.jump_status());check("jump costs no stamina",is_equal_approx(before,f.stamina),[before,f.stamina]);check("no airborne double jump",not f.request_jump(),f.jump_status());check("basic V real floor landing",await wait_land(),f.jump_status())
	for item in ["starter","guanyu_blade","lubu_halberd"]:
		for skill in [["rush",KEY_Q],["counter",KEY_E],["ultimate",KEY_U]]:await skill_case(item,skill[0],skill[1])
	for overlay in ["toggle_pause","toggle_map"]:
		await fresh();await start_air();await frames(8);var y=f.position.y;var clock=f.jump_status().elapsed
		game.command(overlay);await frames(12)
		check(overlay+" freezes real height and jump clock",game.paused and is_equal_approx(y,f.position.y) and is_equal_approx(clock,f.jump_status().elapsed),[y,f.position.y,clock,f.jump_status().elapsed])
		game.command(overlay);check(overlay+" resume finishes jump",await wait_land(),f.jump_status())
	await fresh();await start_air();await frames(10);var prior=game.player;var old_id=prior.get_instance_id();var high=prior.position.y
	game.command("horse_color","brown");bind_player();await frames(10);f=game.player
	check("airborne station horse replacement grounded once",high>.3 and f.get_instance_id()!=old_id and f.horse_color=="brown" and f.is_on_floor() and not f.is_jumping() and f.position.y<.1,{"old_height":high,"new_height":f.position.y,"color":f.horse_color,"jump":f.jump_status()})
	await fresh();f=game.player;await start_air();await frames(8);game.command("return_to_camp");await frames(10)
	check("camp reset clears jump and velocity",not f.is_jumping() and f.is_on_floor() and f.velocity.y<=0 and game.phase=="explore",f.jump_status())
	await fresh();f=game.player;await start_air();await frames(8)
	var attacker=game.enemies.values()[0]
	f.receive_strike(attacker,{"damage":99999.0,"heavy":true,"guard_cost":0.0});await frames(2)
	check("fatal airborne hit enters actual defeat",f.hp<=0 and game.dead and game.phase=="defeat" and not f.enabled,{"hp":f.hp,"phase":game.phase,"y":f.position.y})
	check("disabled dead actor still lands by gravity",await wait_land(),{"jump":f.jump_status(),"y":f.position.y,"on_floor":f.is_on_floor()})
	game.command("return_to_camp");await frames(8);check("defeat reset returns grounded ready",not game.dead and game.phase=="explore" and game.player.jump_status().can_jump,game.player.jump_status())
	game._reset_hit_feedback();paused=false
	var result={"completed":true,"passed":failures.is_empty(),"checks":checks.size(),"failures":failures,"results":checks,"cases":cases,"scope":"Complete RPGMain/controller/world/UI with only autonomous enemy requests and all save read/write isolated in a temporary subclass. Real physical-key V/Q/E/U through Input.parse_input_event, actual gravity/capsule floor, real skill start/release/complete/resources, actual pause/map/camp/death/horse-color commands. Test preconditions seed two earned equipment IDs and energy100 for U; no injected airborne position or velocity, no changed hit bounds. Airborne start is required, but authored long windup may finish after landing; this fixture does not claim every release is airborne or certify actual damage/hand anatomy."}
	FileAccess.open("/private/tmp/wenfeng-rpg-jump-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("RPG_JUMP_DONE ",checks.size()-failures.size(),"/",checks.size()," ",failures);quit(1 if failures.size() else 0)
func make_key(code):
	var ev=InputEventKey.new();ev.physical_keycode=code;return ev
