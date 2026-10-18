extends RefCounted

# Character identity controls mechanics; the independently chosen weapon still
# modifies basic attacks. Each skill carries its own animation and hit geometry.
const ZHAOYUN = {
	"rush": {"name": "游龙突刺", "description": "直线突刺 · 窄域追身", "cost": 22.0, "cooldown": 4.5,
		"kind": "thrust", "clip": "DragonThrust", "duration": 0.84, "active": Vector2(0.19, 0.36),
		"damage": 20.0, "reach": 3.8, "half_width": 0.48, "shape": "line", "heavy": false,
		"guard_cost": 16.0, "lunge": 10.5, "dash_from": 0.04, "dash_to": 0.25},
	"counter": {"name": "回风掠影", "description": "闪身避击 · 随后还刺", "cost": 20.0, "cooldown": 6.5,
		"kind": "evade", "clip": "CloudStep", "strike_clip": "DragonThrust", "strike_start": 0.25,
		"duration": 0.85, "active": Vector2(0.35, 0.44), "damage": 16.0, "reach": 3.8,
		"half_width": 0.50, "shape": "line", "heavy": false, "guard_cost": 14.0, "lunge": 0.0},
	"ultimate": {"name": "龙吟破阵", "description": "五段连刺 · 追身可打断", "cost": 100.0,
		"kind": "chase", "windup": 0.45, "duration": 2.60, "radius": 0.0,
		"reach": 3.8, "half_width": 0.50, "guard_cost": 18.0, "charge_clip": "DragonCharge",
		"hits": [
			{"start": 0.45, "clip": "DragonThrust", "clip_duration": 0.36, "active": Vector2(0.54, 0.60), "damage": 8.0,
				"shape": "line", "reach": 3.8, "half_width": 0.50},
			{"start": 0.81, "clip": "DragonCross", "clip_duration": 0.36, "active": Vector2(0.90, 0.96), "damage": 8.0,
				"shape": "line", "reach": 3.8, "half_width": 0.50},
			{"start": 1.17, "clip": "DragonBackCut", "clip_duration": 0.36, "active": Vector2(1.26, 1.32), "damage": 9.0,
				"shape": "line", "reach": 3.8, "half_width": 0.50},
			{"start": 1.53, "clip": "DragonThrust", "clip_duration": 0.36, "active": Vector2(1.62, 1.68), "damage": 10.0,
				"shape": "line", "reach": 3.8, "half_width": 0.50},
			{"start": 1.94, "clip": "DragonCross", "clip_duration": 0.50, "active": Vector2(2.06, 2.15), "damage": 17.0,
				"shape": "line", "reach": 3.8, "half_width": 0.50, "guard_cost": 32.0, "knockback": 0.8},
		]},
}

const MACHAO = {
	"rush": {"name": "破军重刺", "description": "双手重刺 · 抗轻击削防", "cost": 28.0, "cooldown": 6.0,
		"kind": "thrust", "clip": "TigerThrust", "duration": 1.05, "active": Vector2(0.23, 0.45),
		"damage": 30.0, "reach": 4.0, "shape": "line", "half_width": 0.60,
		"heavy": true, "guard_cost": 48.0, "light_armor": true, "lunge": 5.8, "dash_from": 0.08, "dash_to": 0.28},
	"counter": {"name": "虎啸震阵", "description": "近身战吼 · 震退破防", "cost": 26.0, "cooldown": 9.0,
		"kind": "roar", "clip": "TigerRoar", "duration": 1.05, "active": Vector2(0.42, 0.55),
		"damage": 8.0, "reach": 2.75, "radial": true, "shape": "radial", "heavy": true,
		"guard_cost": 40.0, "force_guardbreak": true, "break_stun": 0.70, "hit_stun": 0.70,
		"knockback": 2.3, "unparryable": true, "wave": true, "lunge": 0.0},
	"ultimate": {"name": "烈虎穿阵", "description": "蓄力三刺 · 重枪直线破防", "cost": 100.0,
		"kind": "chase", "windup": 0.82, "duration": 2.95, "radius": 0.0,
		"reach": 4.1, "half_width": 0.60, "guard_cost": 36.0, "charge_clip": "TigerCharge",
		"hits": [
			{"start": 0.82, "clip": "TigerThrust", "clip_duration": 0.56, "active": Vector2(0.95, 1.06), "damage": 18.0,
				"shape": "line", "reach": 4.1, "half_width": 0.60, "guard_cost": 32.0},
			{"start": 1.43, "clip": "TigerThrust", "clip_duration": 0.60, "active": Vector2(1.57, 1.68), "damage": 19.0,
				"shape": "line", "reach": 4.1, "half_width": 0.60, "guard_cost": 36.0, "knockback": 0.5},
			{"start": 2.08, "clip": "TigerFinish", "clip_duration": 0.68, "active": Vector2(2.24, 2.37), "damage": 25.0,
				"shape": "line", "reach": 4.1, "half_width": 0.60, "guard_cost": 62.0,
				"force_guardbreak": true, "break_stun": 0.90, "knockback": 3.1, "hit_stun": 0.60},
		]},
}

const GUANYU = {
	"rush": {"name": "青龙横扫", "description": "双手旋斩 · 长刀封路", "cost": 29.0, "cooldown": 6.5,
		"kind": "sweep", "clip": "CrescentSweep", "duration": 1.18, "active": Vector2(0.40, 0.74),
		"damage": 29.0, "reach": 3.55, "shape": "sector", "min_dot": -0.40, "heavy": true,
		"guard_cost": 48.0, "wave": true, "lunge": 1.4},
	"counter": {"name": "拖刀回斩", "description": "后撤避锋 · 回身重斩", "cost": 25.0, "cooldown": 8.0,
		"kind": "evade", "clip": "CrescentStep", "strike_clip": "CrescentCounter", "strike_start": 0.28,
		"duration": 1.08, "active": Vector2(0.54, 0.78), "damage": 25.0, "reach": 3.45,
		"shape": "sector", "min_dot": -0.10, "heavy": true, "guard_cost": 40.0, "wave": true, "lunge": 0.0},
	"ultimate": {"name": "青龙偃月", "description": "两段旋斩 · 横断近身区域", "cost": 100.0,
		"kind": "cleave", "windup": 0.72, "duration": 2.50, "radius": 3.55,
		"charge_clip": "CrescentCharge", "release_clip": "CrescentFinish", "release_duration": 1.55,
		"hits": [
			{"start": 0.72, "active": Vector2(1.00, 1.15), "damage": 24.0, "reach": 3.55, "shape": "radial", "radial": true, "guard_cost": 42.0, "knockback": 0.5},
			{"start": 1.30, "active": Vector2(1.62, 1.82), "damage": 34.0, "reach": 3.55, "shape": "radial", "radial": true, "guard_cost": 72.0, "knockback": 2.6},
		]},
}

const ZHANGFEI = {
	"rush": {"name": "蛇矛突刺", "description": "双手进矛 · 直取中路", "cost": 26.0, "cooldown": 5.6,
		"kind": "thrust", "clip": "SerpentThrust", "duration": 0.94, "active": Vector2(0.22, 0.43),
		"damage": 25.0, "reach": 4.1, "half_width": 0.56, "shape": "line", "heavy": true,
		"guard_cost": 32.0, "lunge": 8.5, "dash_from": 0.06, "dash_to": 0.27},
	"counter": {"name": "长坂怒喝", "description": "持矛震喝 · 震退近敌", "cost": 28.0, "cooldown": 10.0,
		"kind": "roar", "clip": "SerpentBrace", "duration": 1.12, "active": Vector2(0.38, 0.55),
		"damage": 9.0, "reach": 2.55, "shape": "radial", "radial": true, "heavy": true,
		"guard_cost": 45.0, "force_guardbreak": true, "break_stun": 0.65, "hit_stun": 0.65,
		"knockback": 2.8, "unparryable": true, "wave": true, "lunge": 0.0},
	"ultimate": {"name": "燕人破军", "description": "三段追刺 · 长矛直线破阵", "cost": 100.0,
		"kind": "chase", "windup": 0.65, "duration": 2.65, "radius": 0.0, "reach": 4.2, "half_width": 0.62,
		"guard_cost": 28.0, "charge_clip": "SerpentCharge",
		"hits": [
			{"start": 0.65, "clip": "SerpentThrust", "clip_duration": 0.50, "active": Vector2(0.77, 0.87), "damage": 16.0},
			{"start": 1.18, "clip": "SerpentThrust", "clip_duration": 0.50, "active": Vector2(1.30, 1.40), "damage": 18.0},
			{"start": 1.77, "clip": "SerpentThrust", "clip_duration": 0.65, "active": Vector2(1.93, 2.08), "damage": 25.0},
		]},
}

const LUBU = {
	"rush": {"name": "辕门戟扫", "description": "双手旋戟 · 宽弧削防", "cost": 30.0, "cooldown": 6.8,
		"kind": "sweep", "clip": "HalberdSweep", "duration": 1.22, "active": Vector2(0.42, 0.77),
		"damage": 31.0, "reach": 3.70, "shape": "sector", "min_dot": -0.35, "heavy": true,
		"guard_cost": 52.0, "wave": true, "lunge": 1.5},
	"counter": {"name": "画戟挑刺", "description": "跨步进戟 · 直挑中路", "cost": 24.0, "cooldown": 7.2,
		"kind": "thrust", "clip": "HalberdThrust", "duration": 1.02, "active": Vector2(0.37, 0.63),
		"damage": 23.0, "reach": 3.95, "half_width": 0.58, "shape": "line", "heavy": true,
		"guard_cost": 36.0, "lunge": 7.8, "dash_from": 0.07, "dash_to": 0.28},
	"ultimate": {"name": "无双乱舞", "description": "三段旋戟 · 连斩四方", "cost": 100.0,
		"kind": "cleave", "windup": 0.82, "duration": 2.90, "radius": 3.70,
		"charge_clip": "HalberdCharge", "release_clip": "HalberdFinish", "release_duration": 1.95,
		"hits": [
			{"start": 0.82, "active": Vector2(1.05, 1.20), "damage": 17.0, "reach": 3.70, "shape": "radial", "radial": true, "guard_cost": 32.0, "knockback": 0.3},
			{"start": 1.38, "active": Vector2(1.65, 1.80), "damage": 18.0, "reach": 3.70, "shape": "radial", "radial": true, "guard_cost": 36.0, "knockback": 0.4},
			{"start": 2.00, "active": Vector2(2.30, 2.48), "damage": 29.0, "reach": 3.70, "shape": "radial", "radial": true, "guard_cost": 70.0, "knockback": 3.0},
		]},
}

const XUCHU = {
	"rush": {"name": "虎痴横斩", "description": "重刀横斩 · 抗轻击削防", "cost": 30.0, "cooldown": 6.4,
		"kind": "sweep", "clip": "TigerCleave", "duration": 1.12, "active": Vector2(0.18, 0.33),
		"damage": 29.0, "reach": 2.8, "shape": "sector", "min_dot": -0.15,
		"heavy": true, "guard_cost": 52.0, "light_armor": true, "wave": true, "lunge": 1.4},
	"counter": {"name": "虎威震喝", "description": "近身怒喝 · 震退破防", "cost": 27.0, "cooldown": 9.5,
		"kind": "roar", "clip": "BruteRoar", "duration": 1.10, "active": Vector2(0.43, 0.56),
		"damage": 8.0, "reach": 2.75, "shape": "radial", "radial": true, "heavy": true,
		"guard_cost": 42.0, "force_guardbreak": true, "break_stun": 0.70, "hit_stun": 0.70,
		"knockback": 2.5, "unparryable": true, "wave": true, "lunge": 0.0},
	"ultimate": {"name": "虎痴断岳", "description": "蓄力重斩 · 震地破防", "cost": 100.0,
		"kind": "slam", "windup": 0.95, "duration": 2.65, "radius": 3.8,
		"charge_clip": "BruteCharge", "release_clip": "BruteFinish", "release_duration": 1.10,
		"hits": [{"start": 0.95, "active": Vector2(1.49, 1.63), "damage": 60.0,
			"reach": 3.8, "shape": "radial", "radial": true, "guard_cost": 100.0,
			"guard_chip": 12.0, "force_guardbreak": true, "break_stun": 1.10,
			"knockback": 4.4, "hit_stun": 0.80}]},
}

static func for_character(id: String) -> Dictionary:
	return {"zhaoyun": ZHAOYUN, "machao": MACHAO, "guanyu": GUANYU, "zhangfei": ZHANGFEI, "lubu": LUBU, "xuchu": XUCHU}.get(id, ZHAOYUN)
