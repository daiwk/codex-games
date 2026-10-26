extends RefCounted

# Six physical move sets. Source motions are CC0 KayKit / UAL2; signature
# poses and stage paths are authored for this project. No skill uses attack tempo.

const ZHAOYUN = {
	"rush": {
		"name": "游龙双探",
		"description": "侧步换势 · 高低双刺",
		"fx_style": "dragon_double",
		"kind": "sequence",
		"clip": "DragonNeedle",
		"duration": 0.96,
		"active": Vector2(0.1, 0.58),
		"damage": 19.0,
		"reach": 3.8,
		"cost": 24.0,
		"cooldown": 5.0,
		"shape": "line",
		"heavy": false,
		"guard_cost": 36.0,
		"lunge": 0.0,
		"half_width": 0.48,
		"stages": [
			{"start": 0, "clip": "DragonNeedle", "duration": 0.38},
			{"start": 0.4, "clip": "DragonLow", "duration": 0.44}
		],
		"hits": [
			{"start": 0, "clip": "DragonNeedle", "clip_duration": 0.38, "active": Vector2(0.1, 0.16), "damage": 10.0, "shape": "line"},
			{"start": 0.4, "clip": "DragonLow", "clip_duration": 0.44, "active": Vector2(0.51, 0.58), "damage": 12.0, "shape": "line"}
		],
		"motion": [
			{"start": 0.03, "end": 0.15, "speed": 7.0, "direction": "forward"},
			{"start": 0.43, "end": 0.58, "speed": 5.0, "direction": "forward"}
		]
	},
	"counter": {"name": "回风掠影", "description": "横闪避击 · 转腕还刺", "fx_style": "dragon_slip", "kind": "evade", "clip": "DragonSlip", "duration": 0.98, "active": Vector2(0.41, 0.5), "damage": 18.0, "reach": 3.8, "cost": 20.0, "cooldown": 6.5, "shape": "line", "heavy": false, "guard_cost": 36.0, "lunge": 0.0, "half_width": 0.5, "strike_clip": "DragonHigh", "strike_start": 0.28, "dodge_side": 1.0, "return_lunge": 5.5},
	"ultimate": {
		"name": "七进游龙",
		"description": "五段高低连刺 · 换势追身",
		"fx_style": "dragon_flurry",
		"kind": "sequence",
		"charge_clip": "DragonGather",
		"windup": 0.42,
		"duration": 2.85,
		"hits": [
			{"start": 0.42, "clip": "DragonNeedle", "clip_duration": 0.36, "active": Vector2(0.51, 0.57), "damage": 8.0, "shape": "line"},
			{"start": 0.8, "clip": "DragonLow", "clip_duration": 0.36, "active": Vector2(0.89, 0.95), "damage": 8.0, "shape": "line"},
			{"start": 1.18, "clip": "DragonHigh", "clip_duration": 0.36, "active": Vector2(1.27, 1.33), "damage": 9.0, "shape": "line"},
			{"start": 1.56, "clip": "DragonNeedle", "clip_duration": 0.36, "active": Vector2(1.65, 1.71), "damage": 10.0, "shape": "line"},
			{"start": 2.0, "clip": "DragonLow", "clip_duration": 0.56, "active": Vector2(2.14, 2.24), "damage": 17.0, "shape": "line", "guard_cost": 40.0, "knockback": 0.8}
		],
		"cost": 100.0,
		"radius": 0.0,
		"reach": 3.8,
		"half_width": 0.55,
		"guard_cost": 32.0,
		"chase": true,
		"chase_speed": 6.5
	}
}

const MACHAO = {
	"rush": {"name": "伏虎冲枪", "description": "伏枪压肩 · 一线冲阵", "fx_style": "tiger_couch", "kind": "thrust", "clip": "TigerCouch", "duration": 1.05, "active": Vector2(0.23, 0.45), "damage": 30.0, "reach": 4.0, "cost": 28.0, "cooldown": 6.0, "shape": "line", "heavy": true, "guard_cost": 48.0, "lunge": 5.8, "half_width": 0.6, "light_armor": true, "dash_from": 0.08, "dash_to": 0.28},
	"counter": {
		"name": "铁骑蓄锋",
		"description": "沉肩蓄枪 · 抗轻击穿甲",
		"fx_style": "tiger_charge",
		"kind": "charge",
		"clip": "TigerSet",
		"duration": 1.75,
		"active": Vector2(0.92, 1.08),
		"damage": 36.0,
		"reach": 4.1,
		"cost": 29.0,
		"cooldown": 9.0,
		"shape": "line",
		"heavy": true,
		"guard_cost": 66.0,
		"lunge": 0.0,
		"half_width": 0.56,
		"light_armor": true,
		"armor_window": Vector2(0.18, 1.1),
		"stages": [
			{"start": 0, "clip": "TigerSet", "duration": 0.72},
			{"start": 0.72, "clip": "TigerDrive", "duration": 0.85}
		],
		"motion": [
			{"start": 0.78, "end": 1.05, "speed": 5.5, "direction": "forward"}
		],
		"force_guardbreak": true,
		"break_stun": 0.65
	},
	"ultimate": {
		"name": "铁骑贯阵",
		"description": "长蓄一枪 · 全力贯阵破防",
		"fx_style": "tiger_breakthrough",
		"kind": "sequence",
		"charge_clip": "TigerSet",
		"windup": 1.1,
		"duration": 2.65,
		"hits": [
			{"start": 1.1, "clip": "TigerCommit", "clip_duration": 1.15, "active": Vector2(1.4, 1.6), "damage": 64.0, "shape": "line", "reach": 4.2, "half_width": 0.62, "guard_cost": 95.0, "force_guardbreak": true, "break_stun": 1.0, "knockback": 3.4, "hit_stun": 0.7}
		],
		"cost": 100.0,
		"radius": 0.0,
		"reach": 3.8,
		"half_width": 0.55,
		"guard_cost": 32.0,
		"motion": [
			{"start": 1.3, "end": 1.5, "speed": 10.5, "direction": "forward"}
		],
		"armor_from": 0.55
	}
}

const GUANYU = {
	"rush": {"name": "青龙贴地", "description": "低身大开合 · 长刀封路", "fx_style": "crescent_low", "kind": "sweep", "clip": "CrescentLow", "duration": 1.18, "active": Vector2(0.4, 0.74), "damage": 29.0, "reach": 3.55, "cost": 29.0, "cooldown": 6.5, "shape": "sector", "heavy": true, "guard_cost": 48.0, "lunge": 1.4, "min_dot": -0.4, "wave": true},
	"counter": {"name": "拖刀回斩", "description": "后撤拖刀 · 回身重斩", "fx_style": "crescent_draw", "kind": "evade", "clip": "CrescentDrag", "duration": 1.08, "active": Vector2(0.54, 0.78), "damage": 27.0, "reach": 3.45, "cost": 25.0, "cooldown": 8.0, "shape": "sector", "heavy": true, "guard_cost": 44.0, "lunge": 0.0, "min_dot": -0.1, "strike_clip": "CrescentReturn", "strike_start": 0.3, "return_lunge": 2.8, "wave": true},
	"ultimate": {
		"name": "青龙偃月",
		"description": "拖刀起势 · 斜劈接整身回旋",
		"fx_style": "crescent_cross",
		"kind": "sequence",
		"charge_clip": "CrescentGather",
		"windup": 0.7,
		"duration": 2.8,
		"hits": [
			{"start": 0.7, "clip": "CrescentSplit", "clip_duration": 0.9, "active": Vector2(0.98, 1.18), "damage": 26.0, "shape": "sector", "reach": 3.6, "min_dot": -0.12, "fx_style": "crescent_split", "guard_cost": 48.0},
			{"start": 1.35, "clip": "CrescentOrbit", "clip_duration": 1.2, "active": Vector2(1.7, 2.1), "damage": 34.0, "shape": "radial", "radial": true, "reach": 3.6, "fx_style": "crescent_orbit", "guard_cost": 76.0, "knockback": 2.6}
		],
		"cost": 100.0,
		"radius": 3.6,
		"reach": 3.8,
		"half_width": 0.55,
		"guard_cost": 32.0,
		"motion": [
			{"start": 0.8, "end": 1.12, "speed": 1.7, "direction": "forward"},
			{"start": 1.43, "end": 1.88, "speed": 1.2, "direction": "forward"}
		]
	}
}

const ZHANGFEI = {
	"rush": {
		"name": "丈八镇关",
		"description": "扎根架矛 · 挡击后反刺更强",
		"fx_style": "serpent_brace",
		"kind": "brace",
		"clip": "SerpentWard",
		"duration": 1.6,
		"active": Vector2(0.75, 0.91),
		"damage": 24.0,
		"reach": 4.1,
		"cost": 27.0,
		"cooldown": 7.0,
		"shape": "line",
		"heavy": true,
		"guard_cost": 40.0,
		"lunge": 0.0,
		"half_width": 0.57,
		"guard_window": Vector2(0.05, 0.52),
		"counter_bonus": 1.6,
		"stages": [
			{"start": 0, "clip": "SerpentWard", "duration": 0.52},
			{"start": 0.52, "clip": "SerpentRoot", "duration": 0.9}
		],
		"rooted": true
	},
	"counter": {"name": "长坂怒喝", "description": "持矛震喝 · 震退近敌", "fx_style": "serpent_roar", "kind": "roar", "clip": "SerpentVoice", "duration": 1.12, "active": Vector2(0.38, 0.55), "damage": 9.0, "reach": 2.55, "cost": 28.0, "cooldown": 10.0, "shape": "radial", "heavy": true, "guard_cost": 45.0, "lunge": 0.0, "radial": true, "force_guardbreak": true, "break_stun": 0.65, "hit_stun": 0.65, "knockback": 2.8, "unparryable": true, "wave": true, "rooted": true},
	"ultimate": {
		"name": "燕人镇阵",
		"description": "震喝定敌 · 扎根长矛贯刺",
		"fx_style": "serpent_bastion",
		"kind": "sequence",
		"charge_clip": "SerpentWard",
		"windup": 0.55,
		"duration": 2.9,
		"hits": [
			{"start": 0.55, "clip": "SerpentVoice", "clip_duration": 0.9, "active": Vector2(0.9, 1.08), "damage": 13.0, "shape": "radial", "radial": true, "reach": 2.7, "fx_style": "serpent_shock", "guard_cost": 62.0, "force_guardbreak": true, "break_stun": 0.95, "knockback": 0.2, "hit_stun": 0.75},
			{"start": 1.55, "clip": "SerpentLong", "clip_duration": 1.0, "active": Vector2(1.8, 1.97), "damage": 46.0, "shape": "line", "reach": 4.2, "half_width": 0.62, "fx_style": "serpent_anchor", "guard_cost": 78.0, "knockback": 2.8, "hit_stun": 0.65}
		],
		"cost": 100.0,
		"radius": 0.0,
		"reach": 3.8,
		"half_width": 0.55,
		"guard_cost": 32.0,
		"rooted": true
	}
}

const LUBU = {
	"rush": {"name": "画戟撩天", "description": "沉腰起戟 · 由下向上挑击", "fx_style": "halberd_rise", "kind": "sweep", "clip": "HalberdRise", "duration": 1.15, "active": Vector2(0.36, 0.6), "damage": 28.0, "reach": 3.6, "cost": 27.0, "cooldown": 6.4, "shape": "sector", "heavy": true, "guard_cost": 48.0, "lunge": 1.8, "min_dot": 0.3, "wave": true, "knockback": 1.2, "hit_stun": 0.58},
	"counter": {
		"name": "辕门回旋",
		"description": "短进换位 · 旋戟扫开围攻",
		"fx_style": "halberd_orbit",
		"kind": "sweep",
		"clip": "HalberdWheel",
		"duration": 1.35,
		"active": Vector2(0.46, 0.85),
		"damage": 25.0,
		"reach": 3.7,
		"cost": 27.0,
		"cooldown": 7.8,
		"shape": "sector",
		"heavy": true,
		"guard_cost": 42.0,
		"lunge": 0.0,
		"min_dot": -0.6,
		"wave": true,
		"motion": [
			{"start": 0.05, "end": 0.23, "speed": 5.3, "direction": "forward"},
			{"start": 0.46, "end": 0.7, "speed": 1.0, "direction": "forward"}
		]
	},
	"ultimate": {
		"name": "无双乱舞",
		"description": "挑击开势 · 旋戟 · 重落戟",
		"fx_style": "halberd_dance",
		"kind": "sequence",
		"charge_clip": "HalberdGather",
		"windup": 0.66,
		"duration": 3.3,
		"hits": [
			{"start": 0.66, "clip": "HalberdRise", "clip_duration": 0.75, "active": Vector2(0.95, 1.1), "damage": 17.0, "shape": "sector", "reach": 3.7, "min_dot": 0.2, "fx_style": "halberd_lift", "guard_cost": 36.0},
			{"start": 1.3, "clip": "HalberdWheel", "clip_duration": 1.1, "active": Vector2(1.58, 1.85), "damage": 20.0, "shape": "radial", "radial": true, "reach": 3.7, "fx_style": "halberd_spin", "guard_cost": 44.0, "knockback": 0.3},
			{"start": 2.1, "clip": "HalberdDrop", "clip_duration": 1.05, "active": Vector2(2.45, 2.65), "damage": 29.0, "shape": "sector", "reach": 3.8, "min_dot": 0.1, "fx_style": "halberd_drop", "guard_cost": 78.0, "knockback": 3.0, "hit_stun": 0.7}
		],
		"cost": 100.0,
		"radius": 3.7,
		"reach": 3.8,
		"half_width": 0.55,
		"guard_cost": 32.0,
		"motion": [
			{"start": 0.73, "end": 1.03, "speed": 1.9, "direction": "forward"},
			{"start": 2.15, "end": 2.49, "speed": 2.4, "direction": "forward"}
		]
	}
}

const XUCHU = {
	"rush": {
		"name": "虎痴逼斩",
		"description": "肩进压身 · 近身冲刀",
		"fx_style": "brute_close",
		"kind": "sweep",
		"clip": "BruteShoulder",
		"duration": 1.2,
		"active": Vector2(0.4, 0.68),
		"damage": 30.0,
		"reach": 2.4,
		"cost": 29.0,
		"cooldown": 6.2,
		"shape": "sector",
		"heavy": true,
		"guard_cost": 56.0,
		"lunge": 0.0,
		"min_dot": 0.15,
		"light_armor": true,
		"armor_window": Vector2(0.15, 0.72),
		"motion": [
			{"start": 0.06, "end": 0.3, "speed": 4.5, "direction": "forward"}
		]
	},
	"counter": {
		"name": "架刀反震",
		"description": "架刀挡击 · 贴身斜劈反震",
		"fx_style": "brute_rebuke",
		"kind": "brace",
		"clip": "BruteGuard",
		"duration": 1.65,
		"active": Vector2(0.91, 1.13),
		"damage": 27.0,
		"reach": 2.65,
		"cost": 27.0,
		"cooldown": 8.5,
		"shape": "sector",
		"heavy": true,
		"guard_cost": 54.0,
		"lunge": 0.0,
		"min_dot": 0.05,
		"guard_window": Vector2(0.04, 0.52),
		"counter_bonus": 1.4,
		"stages": [
			{"start": 0, "clip": "BruteGuard", "duration": 0.56},
			{"start": 0.56, "clip": "BruteRebuke", "duration": 0.9}
		],
		"motion": [
			{"start": 0.62, "end": 0.84, "speed": 2.8, "direction": "forward"}
		]
	},
	"ultimate": {
		"name": "虎痴断岳",
		"description": "深蹲举刀 · 跨步重劈震地",
		"fx_style": "brute_execution",
		"kind": "sequence",
		"charge_clip": "BruteGather",
		"windup": 0.95,
		"duration": 2.65,
		"hits": [
			{"start": 0.95, "clip": "BruteExecution", "clip_duration": 1.3, "active": Vector2(1.42, 1.62), "damage": 62.0, "shape": "radial", "radial": true, "reach": 3.1, "fx_style": "brute_impact", "guard_cost": 100.0, "guard_chip": 12.0, "force_guardbreak": true, "break_stun": 1.1, "knockback": 4.4, "hit_stun": 0.8}
		],
		"cost": 100.0,
		"radius": 3.1,
		"reach": 3.8,
		"half_width": 0.55,
		"guard_cost": 32.0,
		"motion": [
			{"start": 1.02, "end": 1.38, "speed": 3.2, "direction": "forward"}
		],
		"armor_from": 0.55
	}
}

static func for_character(id: String) -> Dictionary:
	return {"zhaoyun": ZHAOYUN, "machao": MACHAO, "guanyu": GUANYU, "zhangfei": ZHANGFEI, "lubu": LUBU, "xuchu": XUCHU}.get(id, ZHAOYUN)
