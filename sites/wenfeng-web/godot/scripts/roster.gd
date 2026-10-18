extends RefCounted

const IDS = ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu", "xuchu"]
const CHARACTERS = {
	"zhaoyun": {"name": "赵云", "courtesy": "子龙", "style": "游斗追击", "color": "49d5ee",
		"identity": "亮银枪双手追刺，以退为进；连环进枪考验距离与时机。", "weapons": ["zhaoyun_spear"], "opponent": "machao", "distance": 2.65},
	"machao": {"name": "马超", "courtesy": "孟起", "style": "刚猛压制", "color": "ff9844",
		"identity": "虎头枪双手重刺，震阵破防；蓄势连刺直贯中路。", "weapons": ["machao_spear"], "opponent": "zhaoyun", "distance": 2.80},
	"guanyu": {"name": "关羽", "courtesy": "云长", "style": "长刀制域", "color": "78ddb2",
		"identity": "青龙刀双手横扫，以长制短；拖刀避锋，回身重斩。", "weapons": ["guandao"], "opponent": "zhangfei", "distance": 2.65},
	"zhangfei": {"name": "张飞", "courtesy": "翼德", "style": "蛇矛破阵", "color": "c9a2f3",
		"identity": "丈八蛇矛双手突刺，直取中路；长坂怒喝震退近敌。", "weapons": ["serpent_spear"], "opponent": "guanyu", "distance": 2.85},
	"lubu": {"name": "吕布", "courtesy": "奉先", "style": "画戟无双", "color": "f17e8c", "scale": 2.20,
		"identity": "方天画戟双手劈扫，横纵相接；旋戟连斩，锋压四方。", "weapons": ["halberd"], "opponent": "guanyu", "distance": 2.70},
	"xuchu": {"name": "许褚", "courtesy": "仲康", "style": "虎痴重刃", "color": "d8ad63", "scale": 2.15,
		"identity": "重刀横斩，虎威震阵；可选专用大刀、单手刀或剑。", "weapons": ["xuchu_saber", "saber", "sword"], "opponent": "machao", "distance": 1.95},
}
const WEAPONS = {
	"sword": {"name": "剑 · 灵巧", "path": "res://onehand_sword.glb", "reach": 2.12},
	"saber": {"name": "刀 · 刚猛", "path": "res://onehand_saber.glb", "reach": 2.02},
	"zhaoyun_spear": {"name": "龙胆亮银枪 · 双手", "path": "res://assets/weapons/zhaoyun_spear.glb", "reach": 3.45, "blade_start": 0.88, "thrust_only": true},
	"machao_spear": {"name": "虎头湛金枪 · 双手", "path": "res://assets/weapons/machao_spear.glb", "reach": 3.65, "blade_start": 0.85, "thrust_only": true},
	"xuchu_saber": {"name": "许褚大刀", "path": "res://assets/weapons/xuchu_saber.glb", "reach": 2.45, "blade_base": 30.0, "blade_tip": 99.0},
	"guandao": {"name": "青龙偃月刀 · 双手", "path": "res://assets/weapons/guandao.glb", "reach": 3.35, "blade_start": 0.72, "edge_forward": true},
	"serpent_spear": {"name": "丈八蛇矛 · 双手", "path": "res://assets/weapons/serpent_spear.glb", "reach": 3.65, "blade_start": 0.81, "thrust_only": true},
	"halberd": {"name": "方天画戟 · 双手", "path": "res://assets/weapons/halberd.glb", "reach": 3.55, "blade_start": 0.70},
}

static func character(id: String) -> Dictionary:
	return CHARACTERS.get(id, CHARACTERS.zhaoyun)

static func weapon_choices(id: String) -> Array:
	return character(id).weapons

static func resolve_weapon(id: String, selected: String) -> String:
	var choices = weapon_choices(id)
	return selected if selected in choices else String(choices[0])

static func weapon_name(id: String) -> String:
	return String(WEAPONS.get(id, WEAPONS.sword).name)
