extends RefCounted

const THUNDER_RUSH = {
	"zhaoyun": {"clips": ["DuelThunderDragonSnap", "DuelThunderDragonDrive"], "description": "轻点收枪 · 换脚双刺", "short_range": 1.35},
	"machao": {"clips": ["DuelThunderTigerDrive"], "description": "沉肩压枪 · 踏步贯刺", "short_range": 1.60},
	"zhangfei": {"clips": ["DuelThunderSerpentBrace", "DuelThunderSerpentDrive"], "description": "扎根架矛 · 挡击后反刺更强", "short_range": 1.35},
}

# Keep guard, travel and damage on the original profiles. The fighter copies
# the selected pose at input time, so crossing this distance mid-skill is safe.
static func thunder_rush(role: String, profile: Dictionary, animation_names: Dictionary, gap: float) -> Dictionary:
	if not THUNDER_RUSH.has(role):
		return profile
	var plan: Dictionary = THUNDER_RUSH[role]
	var clips: Array = plan.clips
	for clip in clips:
		if not animation_names.has(clip):
			return profile
	profile["description"] = plan.description
	profile["thunder_spear"] = true
	# Keep the shorter chamber when there is no room to drive the full shaft.
	if gap <= float(plan.short_range):
		return profile
	profile["clip"] = clips[0]
	for index in profile.get("stages", []).size():
		profile.stages[index]["clip"] = clips[index]
	for index in profile.get("hits", []).size():
		profile.hits[index]["clip"] = clips[index]
	if role == "zhaoyun":
		# Strike resolution sees the previous drawn tip. Include the tick that
		# consumes the first phrase's last extended pose.
		profile.hits[0]["active"] = Vector2(profile.hits[0].active.x, 0.17)
	return profile

# Duel-only spells use the wielder's actual equipment. Traveling entities own
# contact; the animation envelope cannot deal a duplicate invisible melee hit.
static func for_skill(role: String, id: String, fallback: Dictionary, mounted: bool) -> Dictionary:
	var p = fallback.duplicate(true)
	if id == "ultimate":
		var plans = {
			"zhaoyun": {"name":"七曜龙矛", "description":"七矛三轮 · 长矛齐射 · 横移避锋", "charge":"DragonGather", "clip":"DragonNeedle", "windup":0.52,
				"special":{"type":"weapon_array","formation":"spear_volley","weapon_id":"equipped","count":7,"weapon_length":3.5,"damage":10.0,"speed":16.0,"radius":0.20,"interval":0.075,"max_distance":21.0,"knockback":1.5,"hit_stun":0.13,"heavy":false}},
			"machao": {"name":"西凉铁骑", "description":"六骑列阵 · 三路冲锋 · 横穿离阵", "charge":"TigerSet", "clip":"TigerDrive", "windup":0.62,
				"special":{"type":"cavalry","count":6,"damage":12.0,"speed":11.0,"radius":0.58,"lane_spacing":0.85,"max_distance":24.0,"knockback":2.7,"hit_stun":0.20,"heavy":true}},
			"guanyu": {"name":"青龙刀阵", "description":"三刀错峰 · 斜列斩进 · 闪出刀路", "charge":"CrescentGather", "clip":"CrescentLow", "windup":0.62,
				"special":{"type":"weapon_array","formation":"diagonal_cleave","weapon_id":"equipped","count":3,"weapon_length":3.3,"damage":24.0,"speed":12.0,"radius":0.30,"interval":0.18,"max_distance":20.0,"knockback":4.0,"hit_stun":0.28,"heavy":true,"guard_cost":44.0}},
			"zhangfei": {"name":"蛇矛破军", "description":"五矛分进 · 两翼收束 · 及时离阵", "charge":"SerpentWard", "clip":"SerpentLong", "windup":0.56,
				"special":{"type":"weapon_array","formation":"ground_pincer","weapon_id":"equipped","count":5,"weapon_length":3.5,"damage":14.0,"speed":13.0,"radius":0.22,"interval":0.09,"max_distance":20.0,"knockback":2.7,"hit_stun":0.21,"heavy":true}},
			"lubu": {"name":"无双方天阵", "description":"六戟包夹 · 预示后合围 · 冲出阵心", "charge":"HalberdGather", "clip":"HalberdDrop", "windup":0.62,
				"special":{"type":"weapon_array","formation":"halberd_encircle","weapon_id":"equipped","count":6,"weapon_length":3.5,"damage":12.0,"speed":10.0,"radius":0.24,"interval":0.055,"telegraph":0.55,"max_distance":20.0,"knockback":2.8,"hit_stun":0.22,"heavy":true}},
			"xuchu": {"name":"虎啸回刃", "description":"三刃回旋 · 分时抛回 · 离手可策马", "charge":"BruteGather", "clip":"BruteExecution", "windup":0.55,
				"special":{"type":"weapon_array","formation":"returning_fan","weapon_id":"equipped","count":3,"weapon_length":1.7,"damage":22.0,"speed":14.0,"radius":0.28,"interval":0.14,"max_distance":16.0,"knockback":1.4,"finisher_knockback":4.8,"hit_stun":0.24,"heavy":true}}
		}
		if plans.has(role):
			var plan: Dictionary = plans[role]
			var start: float = plan.windup
			p.merge({"name":plan.name,"description":plan.description,"kind":"sequence","charge_clip":plan.charge,"windup":start,"duration":start+0.92,
				"hits":[_beat(start,plan.clip,0.78,Vector2(start+0.20,start+0.34))],"radius":0.0,"reach":24.0,"chase":false,"rooted":false,"motion":[],"special":plan.special.duplicate(true)},true)
			p.special["trigger"] = "release"
	elif role == "guanyu" and id == "rush":
		p.merge({"name":"青龙裂地","description":"贴地刀气 · 向前推进 · 命中击退","kind":"sequence","clip":"CrescentGather","duration":1.15,
			"active":Vector2(0.46,0.6),"damage":0.0,"reach":12.0,"lunge":0.0,"shape":"sector",
			"stages":[{"start":0.0,"clip":"CrescentGather","duration":0.26},{"start":0.26,"clip":"CrescentLow","duration":0.74}],
			"special":{"type":"shockwave","trigger":"release","damage":30.0,"speed":9.0,"radius":1.2,"max_distance":12.0,"knockback":7.2,"hit_stun":0.48,"heavy":true}},true)
	elif role == "zhangfei" and id == "counter":
		p.merge({"name":"喝断长坂","description":"蓄势震吼 · 扩散冲击 · 强推近敌","kind":"roar","clip":"SerpentVoice","duration":1.04,
			"active":Vector2(0.32,0.44),"damage":0.0,"reach":5.0,"radius":5.0,
			"special":{"type":"roar","trigger":"release","damage":18.0,"speed":10.0,"radius":5.0,"max_distance":5.0,"knockback":9.0,"hit_stun":0.6,"heavy":true,"guard_cost":58.0,"unparryable":true}},true)
	elif role == "xuchu" and id == "rush":
		p.merge({"name":"回旋断刃","description":"抛当前兵器 · 回手后接招","kind":"sequence","clip":"BruteGather","duration":1.06,
			"active":Vector2(0.32,0.46),"damage":0.0,"reach":12.0,"lunge":0.0,"motion":[],
			"stages":[{"start":0.0,"clip":"BruteGather","duration":0.24},{"start":0.24,"clip":"BruteShoulder","duration":0.7}],
			"special":{"type":"returning_blade","trigger":"release","count":1,"damage":30.0,"speed":13.0,"radius":0.32,"max_distance":10.0,"knockback":4.6,"hit_stun":0.3,"heavy":true}},true)
	if p.has("special"):
		p["external_only"] = true
		p["fx_style"] = "duel_" + String(p.special.type)
		for hit in p.get("hits",[]):
			hit["external_only"] = true
			hit["damage"] = 0.0
	return p

# Footwork and both hands are authored on one clock. The FX timeline uses
# these same beats and only the held blade can resolve a hit.
static func guan_foot_skill(id: String, fallback: Dictionary) -> Dictionary:
	var profile = fallback.duplicate(true)
	profile.merge({"guan_blade": true, "physical_blade": true, "motion": [], "lunge": 0.0, "wave": false, "min_dot": -1.0, "reach": 3.65}, true)
	match id:
		"rush":
			profile.merge({"name": "偃月风暴", "description": "双手转杆 · 两道旋斩", "kind": "sequence",
				"clip": "GuanCrescentQ", "duration": 1.78, "guan_fx": "rotary", "shape": "sector",
				"active": Vector2(0.45, 1.26), "hits": [
					{"active": Vector2(0.45, 0.60), "damage": 14.0, "knockback": 0.22, "hit_stun": 0.24, "guard_cost": 19.0},
					{"active": Vector2(1.08, 1.26), "damage": 19.0, "knockback": 2.5, "hit_stun": 0.36, "guard_cost": 29.0}
				]}, true)
		"counter":
			profile.erase("strike_clip")
			profile.merge({"name": "拖刀回斩", "description": "撤步让锋 · 踏回斜斩", "clip": "GuanCrescentE",
				"duration": 1.31, "active": Vector2(0.68, 0.86), "guan_fx": "counter"}, true)
		"ultimate":
			profile.merge({"name": "青龙裂空", "description": "踏步举刀 · 一劈裂空", "charge_clip": "GuanCrescentUCharge",
				"windup": 0.76, "duration": 2.11, "radius": 0.0, "guan_fx": "dragon", "hits": [
					{"start": 0.76, "clip": "GuanCrescentU", "clip_duration": 1.35, "active": Vector2(1.23, 1.42),
						"guan_ground_beat": 1.40,
						"damage": 58.0, "guard_cost": 76.0, "knockback": 4.4, "hit_stun": 0.58,
						"shape": "sector", "min_dot": -1.0, "guan_blade": true, "physical_blade": true, "guan_fx": "dragon"}
				]}, true)
	return profile

static func _beat(start: float, clip: String, duration: float, active: Vector2) -> Dictionary:
	return {"start":start,"clip":clip,"clip_duration":duration,"active":active,"damage":0.0,"shape":"sector","reach":24.0,"external_only":true}
