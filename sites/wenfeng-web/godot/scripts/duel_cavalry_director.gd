extends RefCounted

var phase="approach"
var clock=0.0
var think=0.0
var side=1.0
var pass_attacked=false
var previous_state=""
var pass_heading=Vector3.FORWARD
var blocked_time=0.0
var disengage_heading=Vector3.RIGHT

func reset() -> void:
	phase="approach";clock=0.0;think=0.0;side=1.0;pass_attacked=false;previous_state="";pass_heading=Vector3.FORWARD;blocked_time=0.0;disengage_heading=Vector3.RIGHT

func update(game:Node, delta:float) -> void:
	var rider:DuelFighter=game.enemy
	var target:DuelFighter=game.player
	clock+=delta;think-=delta
	var offset=(target.position-rider.position).slide(Vector3.UP)
	var gap=offset.length()
	var heading=rider.forward()
	var toward=offset.normalized() if gap>.01 else heading
	var bearing=heading.signed_angle_to(toward,Vector3.UP)
	var edge=Vector2(rider.position.x,rider.position.z).length()>23.0
	var outward=rider.position.slide(Vector3.UP).normalized().dot(heading)>0.1
	rider.wants_block=false
	if rider.hp<=0:return
	# A close body collision must lead to a real withdrawal, rather than
	# cycling approach/pass while repeatedly trying to ride through a horse.
	if phase not in ["back_out","peel_away"]:
		blocked_time=blocked_time+delta if gap<1.9 and rider.mount_speed<.65 else 0.0
		if blocked_time>.65:
			phase="back_out";clock=0.0;blocked_time=0.0
			disengage_heading=heading.rotated(Vector3.UP,side*PI*.55)
			if edge and disengage_heading.dot(rider.position)>0.0:
				disengage_heading=heading.rotated(Vector3.UP,-side*PI*.55)
	elif phase=="back_out" and ((clock>.9 and absf(heading.signed_angle_to(disengage_heading,Vector3.UP))<.20) or clock>2.2):
		phase="peel_away";clock=0.0
	elif phase=="peel_away" and ((clock>1.5 and gap>3.2) or clock>3.0):
		phase="turn";clock=0.0;pass_attacked=false
	if edge and outward and phase not in ["escape","back_out","peel_away"]:
		phase="escape";clock=0.0
	if phase=="escape" and Vector2(rider.position.x,rider.position.z).length()<21.0:
		phase="turn";clock=0.0
	if phase=="approach" and gap<7.0 and absf(bearing)<.8 and rider.mount_speed>3.5:
		phase="pass";clock=0.0
		pass_heading=(target.position+target.velocity.slide(Vector3.UP)*.22+Vector3(-toward.z,0,toward.x)*side*1.45-rider.position).slide(Vector3.UP).normalized()
	if phase=="pass" and ((offset.dot(heading)<-.45 and gap<7.0) or clock>2.5):
		phase="extend";clock=0.0
	elif phase=="extend" and (clock>1.1 or edge):
		phase="turn";clock=0.0
	elif phase=="turn" and absf(bearing)<.65 and clock>.25 and not (edge and outward):
		phase="approach";clock=0.0;pass_attacked=false;side*=-1.0
	var predicted=target.position+target.velocity.slide(Vector3.UP).limit_length(10.0)*.35
	var lane=Vector3(-toward.z,0,toward.x)*side*1.45
	var goal=predicted+lane
	var goal_flat=Vector2(goal.x,goal.z).limit_length(25.5)
	goal.x=goal_flat.x;goal.z=goal_flat.y
	if phase=="pass":goal=rider.position+pass_heading*14.0
	elif phase=="extend":goal=rider.position+heading*14.0
	elif phase=="escape":goal=Vector3.ZERO
	elif phase in ["back_out","peel_away"]:goal=rider.position+disengage_heading*14.0
	var desired=(goal-rider.position).slide(Vector3.UP).normalized()
	var error=heading.signed_angle_to(desired,Vector3.UP)
	var steering=clampf(error*1.9,-1.0,1.0)
	var throttle=1.0
	var brake=false
	if phase=="turn":
		throttle=(-.8 if rider.mount_speed>4.0 else .12) if absf(error)>.9 else 1.0
		brake=absf(error)>.9 and rider.mount_speed>5.5
	elif phase=="escape":
		throttle=(-.9 if rider.mount_speed>3.5 else .12) if absf(error)>.75 else 1.0
		brake=absf(error)>.75 and rider.mount_speed>5.0
	elif phase=="back_out":
		throttle=-1.0 if clock<.6 else 0.0
		brake=clock>=.6
		steering=0.0 if clock<.6 else clampf(error*1.9,-1.0,1.0)
	if rider.stamina<24.0 and phase not in ["back_out","peel_away"]:
		throttle=.15;phase="recover"
	elif phase=="recover" and rider.stamina>55.0:
		phase="turn";clock=0.0
	if phase=="recover":
		steering=clampf(error,-.7,.7);throttle=.15
	rider.call("set_cavalry_input",throttle,steering,brake)
	previous_state=rider.state
	if phase in ["back_out","peel_away"]:return
	if rider.state not in ["idle","move","block"] or think>0.0:return
	think=[.23,.16,.11][game.difficulty]
	rider.call("set_cavalry_attack_side",0)
	if phase=="approach" and gap>6 and gap<18 and absf(bearing)<.65 and rider.skill_ready("ultimate"):
		if rider.request_ultimate():return
	if phase not in ["approach","pass"]:
		if gap<3.3 and absf(bearing)<1.35 and rider.stamina>26:
			rider.request_light()
		return
	var closing=maxf(0.0,(rider.velocity-target.velocity).dot(toward))
	if gap>8 and absf(error)<.14 and rider.mount_charge_cooldown<=0 and rider.stamina>58:
		rider.request_dodge(heading)
	# Start the committed swing shortly before the paths cross. Each real
	# blade still must touch; a predictive distance is never a guaranteed hit.
	var heavy=closing<3.0 and gap<3.0 and rider.stamina>55 and game.rng.randf()<.18
	var profile:Dictionary=rider.call("_heavy_attack_profile") if heavy else rider.call("_weapon_adjusted_attack",rider.call("_light_attacks")[0])
	var launch=clampf(2.05+closing*(float(profile.active.x)+.035),2.4,6.5)
	if not pass_attacked and gap<launch and offset.dot(heading)>-.5 and absf(bearing)<1.45:
		var ok=rider.request_heavy() if heavy else rider.request_light()
		if ok:pass_attacked=true
	elif gap<3.0 and target.state in ["attack","skill"] and game.rng.randf()<.24:
		rider.wants_block=true
