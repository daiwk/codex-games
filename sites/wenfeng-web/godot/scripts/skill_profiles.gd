extends RefCounted

# Character identity controls mechanics; the independently chosen weapon still
# modifies basic attacks. Each skill carries its own animation and hit geometry.
const ZHAOYUN = {
	"rush": {"name": "游龙突刺", "description": "直线突刺 · 窄域追身", "cost": 22.0, "cooldown": 4.5,
		"kind": "thrust", "clip": "DragonThrust", "duration": 0.72, "active": Vector2(0.30, 0.47),
		"damage": 20.0, "reach": 3.1, "half_width": 0.48, "shape": "line", "heavy": false,
		"guard_cost": 16.0, "lunge": 10.5, "dash_from": 0.04, "dash_to": 0.25},
	"counter": {"name": "回风掠影", "description": "闪身避击 · 随后还刺", "cost": 20.0, "cooldown": 6.5,
		"kind": "evade", "clip": "CloudStep", "strike_clip": "DragonThrust", "strike_start": 0.25,
		"duration": 0.85, "active": Vector2(0.40, 0.55), "damage": 16.0, "reach": 3.0,
		"half_width": 0.50, "shape": "line", "heavy": false, "guard_cost": 14.0, "lunge": 0.0},
	"ultimate": {"name": "龙吟破阵", "description": "五段追击 · 窄域可打断", "cost": 100.0,
		"kind": "chase", "windup": 0.45, "duration": 2.55, "radius": 0.0, "charge_clip": "DragonCharge",
		"hits": [
			{"start": 0.45, "clip": "DragonThrust", "clip_duration": 0.34, "active": Vector2(0.65, 0.77), "damage": 8.0},
			{"start": 0.79, "clip": "DragonCross", "clip_duration": 0.34, "active": Vector2(0.99, 1.11), "damage": 8.0},
			{"start": 1.13, "clip": "DragonBackCut", "clip_duration": 0.34, "active": Vector2(1.33, 1.45), "damage": 9.0},
			{"start": 1.47, "clip": "DragonThrust", "clip_duration": 0.34, "active": Vector2(1.67, 1.79), "damage": 10.0},
			{"start": 1.86, "clip": "DragonCross", "clip_duration": 0.48, "active": Vector2(2.07, 2.19), "damage": 17.0},
		]},
}

const MACHAO = {
	"rush": {"name": "破军横扫", "description": "宽弧重斩 · 抗轻击削防", "cost": 28.0, "cooldown": 6.0,
		"kind": "sweep", "clip": "TigerSweep", "duration": 1.05, "active": Vector2(0.46, 0.68),
		"damage": 30.0, "reach": 2.65, "shape": "sector", "min_dot": -0.15,
		"heavy": true, "guard_cost": 60.0, "wave": true, "lunge": 1.3},
	"counter": {"name": "虎啸震阵", "description": "近身战吼 · 震退破防", "cost": 26.0, "cooldown": 9.0,
		"kind": "roar", "clip": "TigerRoar", "duration": 1.05, "active": Vector2(0.42, 0.55),
		"damage": 8.0, "reach": 2.75, "radial": true, "shape": "radial", "heavy": true,
		"guard_cost": 40.0, "force_guardbreak": true, "break_stun": 0.70, "hit_stun": 0.70,
		"knockback": 2.3, "unparryable": true, "wave": true, "lunge": 0.0},
	"ultimate": {"name": "烈虎断岳", "description": "蓄力震地 · 单击破防", "cost": 100.0,
		"kind": "slam", "windup": 1.0, "duration": 2.60, "radius": 3.8,
		"charge_clip": "TigerCharge", "release_clip": "TigerSlam", "release_duration": 1.10,
		"hits": [{"start": 1.0, "active": Vector2(1.30, 1.50), "damage": 58.0,
			"reach": 3.8, "radial": true, "shape": "radial", "guard_cost": 100.0,
			"guard_chip": 12.0, "force_guardbreak": true, "break_stun": 1.15,
			"knockback": 4.8, "hit_stun": 0.80}]},
}

static func for_character(id: String) -> Dictionary:
	return ZHAOYUN if id == "zhaoyun" else MACHAO
