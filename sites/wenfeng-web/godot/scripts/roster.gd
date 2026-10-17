extends RefCounted

const IDS = ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu"]
const CHARACTERS = {
	"zhaoyun": {"name": "赵云", "courtesy": "子龙", "style": "游斗追击", "color": "49d5ee",
		"identity": "以退为进，窄角突刺；连环追击考验距离与时机。", "weapons": ["sword", "saber"], "opponent": "machao", "distance": 1.85},
	"machao": {"name": "马超", "courtesy": "孟起", "style": "刚猛压制", "color": "ff9844",
		"identity": "横扫压近，震阵破防；蓄势重砸封锁近身区域。", "weapons": ["sword", "saber"], "opponent": "zhaoyun", "distance": 1.85},
	"guanyu": {"name": "关羽", "courtesy": "云长", "style": "长刀制域", "color": "78ddb2",
		"identity": "青龙刀双手横扫，以长制短；拖刀避锋，回身重斩。", "weapons": ["guandao"], "opponent": "zhangfei", "distance": 2.65},
	"zhangfei": {"name": "张飞", "courtesy": "翼德", "style": "蛇矛破阵", "color": "c9a2f3",
		"identity": "丈八蛇矛双手突刺，直取中路；长坂怒喝震退近敌。", "weapons": ["serpent_spear"], "opponent": "guanyu", "distance": 2.85},
	"lubu": {"name": "吕布", "courtesy": "奉先", "style": "画戟无双", "color": "f17e8c", "scale": 2.20,
		"identity": "方天画戟双手劈扫，横纵相接；旋戟连斩，锋压四方。", "weapons": ["halberd"], "opponent": "guanyu", "distance": 2.70},
}
const WEAPONS = {
	"sword": {"name": "剑 · 灵巧", "path": "res://onehand_sword.glb", "reach": 2.12},
	"saber": {"name": "刀 · 刚猛", "path": "res://onehand_saber.glb", "reach": 2.02},
	"guandao": {"name": "青龙偃月刀 · 双手", "path": "res://assets/weapons/guandao.glb", "reach": 3.35, "blade_start": 0.72},
	"serpent_spear": {"name": "丈八蛇矛 · 双手", "path": "res://assets/weapons/serpent_spear.glb", "reach": 3.65, "blade_start": 0.84},
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
