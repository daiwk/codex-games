extends "res://tools/duel_specials_test.gd"

func write_report(completed: bool) -> void:
	FileAccess.open("/private/tmp/wenfeng-duel-return-integrated-latest.json",FileAccess.WRITE).store_string(JSON.stringify({"completed":completed,"passed":completed and failures.is_empty(),"checks":checks.size(),"failures":failures,"results":checks,"cases":cases,"scope":"Latest single-hand origin and currently equipped return-mesh fix. Three actual Xu equipment choices through Main menu selection; full real request_skill release/catch callbacks, actual HP/weapon visibility. Earlier207 report and bone=-1 log retained separately."},"\t"))

func spawn_wait(limit=230) -> bool:
	var present=await super.spawn_wait(limit)
	if not present:return false
	var group:Dictionary=game.specials.groups.values()[0]
	verify(requested_weapon+" projectile identifies current actual equipment",group.get("weapon_id","")==requested_weapon and game.player.weapon_id==requested_weapon,{"projectile":group.get("weapon_id",""),"actor":game.player.weapon_id})
	var rig:Skeleton3D=game.player.skeleton
	var index=-1
	for i in rig.get_bone_count():
		if rig.get_bone_name(i).ends_with("RightHand"):index=i;break
	var hand=rig.to_global(rig.get_bone_global_pose(index).origin)
	var launch:Vector3=group.entities[0].origin
	verify(requested_weapon+" launches near actual animated hand",index>=0 and launch.distance_to(hand)<.15,{"bone":index,"launch":point(launch),"hand":point(hand),"distance":launch.distance_to(hand)})
	return present

func run() -> void:
	Engine.physics_ticks_per_second=60
	Engine.time_scale=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.testing=true;game.fx.muted=true;game.ai_enabled=false
	game.specials.hit_requested.connect(contact)
	await frames(8)
	for weapon in ["xuchu_saber","saber","sword"]:
		requested_weapon=weapon
		await exercise(["xuchu","rush","returning_blade",6.0,1],"foot","hit")
	write_report(true)
	game._reset_hit_feedback()
	print("RETURN INTEGRATED DONE ",checks.size()," checks ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
