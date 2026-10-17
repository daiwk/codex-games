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
		"kind": "thrust", "clip": "SerpentThrust", "duration": 0.94, "active": Vector2(0.34, 0.57),
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
			{"start": 0.65, "clip": "SerpentThrust", "clip_duration": 0.50, "active": Vector2(0.86, 1.03), "damage": 16.0},
			{"start": 1.18, "clip": "SerpentThrust", "clip_duration": 0.50, "active": Vector2(1.39, 1.56), "damage": 18.0},
			{"start": 1.77, "clip": "SerpentThrust", "clip_duration": 0.65, "active": Vector2(2.05, 2.25), "damage": 25.0},
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

static func for_character(id: String) -> Dictionary:
	return {"zhaoyun": ZHAOYUN, "machao": MACHAO, "guanyu": GUANYU, "zhangfei": ZHANGFEI, "lubu": LUBU}.get(id, ZHAOYUN)
