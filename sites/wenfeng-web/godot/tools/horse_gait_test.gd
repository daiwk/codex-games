extends SceneTree
const Horse = preload("res://scripts/horse_visual.gd")
var rows: Array = []
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run_probe")
func frames(count: int) -> void:
	for i in count: await physics_frame
func run_probe() -> void:
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	var holder = Node3D.new()
	root.add_child(holder)
	for color in Horse.COLORS:
		var horse = Horse.new()
		horse.setup("guanyu",color)
		holder.add_child(horse)
		await frames(3)
		var rig = horse._skeleton
		for speed in [1.8,3.0,4.8,8.2]:
			horse.reset_motion()
			for i in 75:
				horse.update_motion(1.0/60.0,speed,0.0)
				await frames(1)
			var samples: Array = []
			var max_bone_error = 0.0
			var length_pairs: Array = []
			for side in ["L","R"]:
				for pair in [["FrontUpperLeg.","FrontLowerLeg."],["FrontLowerLeg.","FrontLowerLeg."],["BackLeg.","BackUpperLeg."],["BackUpperLeg.","BackLowerLeg."],["BackLowerLeg.","BackLowerLeg."]]:
					var a = rig.find_bone(pair[0]+side)
					var b = rig.find_bone(pair[1]+side+("_end" if pair[0]==pair[1] else ""))
					length_pairs.append([a,b,rig.get_bone_global_rest(a).origin.distance_to(rig.get_bone_global_rest(b).origin)])
			for i in 120:
				horse.update_motion(1.0/60.0,speed,0.0)
				await frames(1)
				var front = rig.get_bone_global_pose(rig.find_bone("IKFrontLeg.L")).origin - rig.get_bone_global_pose(rig.find_bone("FrontLowerLeg.L")).origin
				var rear = rig.get_bone_global_pose(rig.find_bone("IKBackLeg.L")).origin - rig.get_bone_global_pose(rig.find_bone("BackLowerLeg.L")).origin
				# Godot sanitises punctuation in imported names; handle either form.
				if front.length_squared()<.000001 or rear.length_squared()<.000001: failures.append("missing limb sample")
				samples.append([atan2(front.z,-front.y),atan2(rear.z,-rear.y),horse.saddle_height()])
				for pair in length_pairs:
					var length = rig.get_bone_global_pose(pair[0]).origin.distance_to(rig.get_bone_global_pose(pair[1]).origin)
					max_bone_error = maxf(max_bone_error,absf(length-pair[2]))
			var lo = samples[0].duplicate()
			var hi = samples[0].duplicate()
			for sample in samples:
				for axis in 3:
					lo[axis]=minf(lo[axis],sample[axis]);hi[axis]=maxf(hi[axis],sample[axis])
			var gait: float = horse._animation_tree.get("parameters/Gait/blend_position")
			var cadence: float = horse._animation_tree.get("parameters/Cadence/scale")
			var report={"color":color,"target_speed":speed,"motion_speed":horse._motion_speed,"gait_position":gait,"gallop_weight":clampf((gait-1.8)/5.4,0,1),"cadence":cadence,"front_shin_degrees":rad_to_deg(hi[0]-lo[0]),"rear_shin_degrees":rad_to_deg(hi[1]-lo[1]),"saddle_bob":hi[2]-lo[2],"maximum_limb_length_error":max_bone_error}
			if max_bone_error>0.00001: failures.append(color+" bone length changed")
			if speed==1.8 and report.gallop_weight>.001: failures.append(color+" slow walk lost")
			if speed==4.8:
				if report.gallop_weight<.999: failures.append(color+" cruise still blends Walk")
				if report.front_shin_degrees<75 or report.rear_shin_degrees<90 or report.saddle_bob<.25: failures.append(color+" cruise lacks authored gallop amplitude")
			if speed==8.2 and cadence<1.40: failures.append(color+" sprint cadence too slow")
			rows.append(report)
			print("GAIT CASE ",JSON.stringify(report))
		var cadence_samples: Array = []
		for speed in [3.39,3.4,3.41]:
			horse._motion_speed=speed
			horse.update_motion(0.0,speed,0.0)
			cadence_samples.append(float(horse._animation_tree.get("parameters/Cadence/scale")))
		if absf(cadence_samples[2]-cadence_samples[0])>.01: failures.append(color+" cadence discontinuity")
		for i in 90:
			horse.update_motion(1.0/60.0,8.2,0.0,true)
			await frames(1)
		if horse._motion_speed>.01:failures.append(color+" defeated horse still gallops")
		horse.reset_motion()
		if float(horse._animation_tree.get("parameters/Gait/blend_position"))!=0:failures.append(color+" reset retains run")
		horse.queue_free()
		await frames(3)
	holder.queue_free()
	await frames(3)
	print("GAIT NATIVE RESULT ",JSON.stringify({"rows":rows,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
