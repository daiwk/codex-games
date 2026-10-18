extends RefCounted

# Mounted attacks keep the existing weapon-specific authored upper-body clips.
# Leg placement is handled after animation by RiderPose, never by walking clips.
static func profile(id: String, thrust: bool, reach: float) -> Dictionary:
	if id == "rush":
		var data = {"name": "马上突刺" if thrust else "马上横斩", "description": "直线进枪 · 骑速加成" if thrust else "掠阵挥刃 · 骑速加成",
			"cost": 26.0, "cooldown": 6.0, "kind": "thrust" if thrust else "sweep", "clip": "Attack1",
			"duration": 1.02, "active": Vector2(0.22, 0.48) if thrust else Vector2(0.20, 0.42),
			"damage": 27.0, "reach": reach + 0.40, "heavy": true, "guard_cost": 40.0,
			"lunge": 4.0, "dash_from": 0.06, "dash_to": 0.28, "wave": true}
		data.merge({"shape": "line", "half_width": 0.72} if thrust else {"shape": "sector", "min_dot": -0.28})
		return data
	if id == "counter":
		return {"name": "勒马震喝", "description": "近身震喝 · 打断与破防", "cost": 25.0, "cooldown": 8.0,
			"kind": "roar", "clip": "Block", "duration": 0.95, "active": Vector2(0.36, 0.50),
			"damage": 7.0, "reach": 2.85, "shape": "radial", "radial": true, "heavy": true,
			"guard_cost": 40.0, "force_guardbreak": true, "break_stun": 0.65, "hit_stun": 0.50,
			"knockback": 1.4, "unparryable": true, "wave": true, "lunge": 0.0}
	var hits: Array = []
	for index in 3:
		var start = 0.48 + index * 0.66
		var hit = {"start": start, "clip": "Attack%d" % (index + 1), "clip_duration": 0.65,
			"active": Vector2(start + (0.16 if thrust else 0.13), start + 0.35), "damage": [16.0, 18.0, 24.0][index],
			"reach": reach + 0.5, "shape": "line" if thrust else "sector", "min_dot": -0.25,
			"half_width": 0.78, "guard_cost": 30.0 if index < 2 else 58.0}
		hits.append(hit)
	return {"name": "疾风连刺" if thrust else "横扫千军", "description": "三段进枪 · 追敌破阵" if thrust else "三段挥刃 · 掠阵连斩",
		"cost": 100.0, "kind": "chase", "windup": 0.48, "duration": 2.65, "radius": 0.0,
		"reach": reach + 0.5, "half_width": 0.78, "guard_cost": 30.0, "charge_clip": "Idle", "hits": hits}
