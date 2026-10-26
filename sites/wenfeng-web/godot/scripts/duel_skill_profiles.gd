extends RefCounted

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

static func _beat(start: float, clip: String, duration: float, active: Vector2) -> Dictionary:
	return {"start":start,"clip":clip,"clip_duration":duration,"active":active,"damage":0.0,"shape":"sector","reach":24.0,"external_only":true}
