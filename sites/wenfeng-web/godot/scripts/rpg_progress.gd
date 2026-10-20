extends RefCounted
class_name RPGProgress

const SAVE_VERSION = 1
const MAX_LEVEL = 20
const POSITION_LIMIT = 160.0
const BOSSES: Array[Dictionary] = [
	{"id": "machao", "name": "马超", "title": "西凉试锋", "level": 2, "xp": 90, "weapon": "serpent_spear", "equipment": "machao_bracers", "position": Vector3(-52, 0, 70)},
	{"id": "xuchu", "name": "许褚", "title": "虎痴守关", "level": 4, "xp": 160, "weapon": "xuchu_saber", "equipment": "xuchu_armor", "position": Vector3(-92, 0, 8)},
	{"id": "zhangfei", "name": "张飞", "title": "长坂惊雷", "level": 6, "xp": 240, "weapon": "serpent_spear", "equipment": "zhangfei_spear", "position": Vector3(-25, 0, -45)},
	{"id": "guanyu", "name": "关羽", "title": "青龙问道", "level": 8, "xp": 320, "weapon": "guandao", "equipment": "guanyu_blade", "position": Vector3(58, 0, -75)},
	{"id": "lubu", "name": "吕布", "title": "辕门无双", "level": 10, "xp": 450, "weapon": "halberd", "equipment": "lubu_halberd", "position": Vector3(102, 0, -5)},
]
const ITEMS: Dictionary = {
	"starter": {"name": "行旅蛇矛", "slot": "weapon", "weapon_id": "serpent_spear", "attack": 0, "hp": 0, "armor": 0, "description": "随身长矛，双手进刺。", "boss": ""},
	"machao_bracers": {"name": "西凉护腕", "slot": "bracers", "attack": 4, "hp": 0, "armor": 0, "description": "攻击 +4", "boss": "machao"},
	"xuchu_armor": {"name": "虎痴战甲", "slot": "armor", "attack": 0, "hp": 50, "armor": 3, "description": "生命 +50 · 护甲 +3", "boss": "xuchu"},
	"zhangfei_spear": {"name": "丈八蛇矛", "slot": "weapon", "weapon_id": "serpent_spear", "attack": 8, "hp": 0, "armor": 0, "description": "攻击 +8 · 双手突刺", "boss": "zhangfei"},
	"guanyu_blade": {"name": "青龙偃月刀", "slot": "weapon", "weapon_id": "guandao", "attack": 13, "hp": 0, "armor": 0, "description": "攻击 +13 · 长刀横扫", "boss": "guanyu"},
	"lubu_halberd": {"name": "方天画戟", "slot": "weapon", "weapon_id": "halberd", "attack": 20, "hp": 0, "armor": 0, "description": "攻击 +20 · 画戟劈扫", "boss": "lubu"},
}

var level: int = 1
var xp: int = 0
var defeated: Array = []
var inventory: Array = ["starter"]
var equipped: Dictionary = {"weapon": "starter", "bracers": "", "armor": ""}
var horse_color: String = "white"
var position: Vector3 = Vector3.ZERO
var quest_started: bool = false
var kills: int = 0

func xp_to_next() -> int:
	return 0 if level >= MAX_LEVEL else 60 + (level - 1) * 30

func grant_xp(amount: int) -> int:
	if amount <= 0 or level >= MAX_LEVEL:
		return 0
	# A single award cannot overflow a signed integer; reaching level 20 takes
	# far less than this cap, even from a fresh save.
	xp += mini(amount, 1000000)
	var gained = 0
	while level < MAX_LEVEL and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
	if level == MAX_LEVEL:
		xp = 0
	return gained

func can_challenge(id: String) -> bool:
	var index = _boss_index(id)
	if index < 0 or index != defeated.size() or level < int(BOSSES[index].level):
		return false
	for previous in index:
		if defeated[previous] != BOSSES[previous].id:
			return false
	return true

func defeat_boss(id: String) -> Dictionary:
	if not can_challenge(id):
		return {}
	var boss: Dictionary = BOSSES[_boss_index(id)]
	var item_id: String = boss.equipment
	defeated.append(id)
	if item_id not in inventory:
		inventory.append(item_id)
	quest_started = true
	var gained = grant_xp(int(boss.xp))
	return {"boss": id, "item": item_id, "xp": int(boss.xp), "levels": gained}

func equip_item(id: String) -> bool:
	if not ITEMS.has(id) or id not in inventory:
		return false
	var slot: String = ITEMS[id].slot
	equipped[slot] = id
	return true

func stats() -> Dictionary:
	var hp = 120 + (level - 1) * 12
	var attack = 18 + (level - 1) * 2
	var armor = 0
	for slot in ["weapon", "bracers", "armor"]:
		var item: Dictionary = ITEMS.get(equipped.get(slot, ""), {})
		hp += int(item.get("hp", 0))
		attack += int(item.get("attack", 0))
		armor += int(item.get("armor", 0))
	var weapon: Dictionary = ITEMS.get(equipped.get("weapon", "starter"), ITEMS.starter)
	return {"hp": hp, "attack": attack, "damage_scale": float(attack) / 18.0, "armor": armor, "weapon_id": weapon.get("weapon_id", "serpent_spear")}

func to_dict() -> Dictionary:
	var saved_position = _clamp_position(position) if position.is_finite() else Vector3.ZERO
	return {"version": SAVE_VERSION, "level": level, "xp": xp,
		"defeated": defeated.duplicate(), "inventory": inventory.duplicate(), "equipped": equipped.duplicate(),
		"horse_color": horse_color, "position": [saved_position.x, saved_position.y, saved_position.z],
		"quest_started": quest_started, "kills": kills}

func load_dict(data: Dictionary) -> bool:
	# Parse into temporary values first. A corrupt/foreign/future save must
	# never partially overwrite a running character or manufacture boss loot.
	var required = ["version", "level", "xp", "defeated", "inventory", "equipped", "horse_color", "position", "quest_started", "kills"]
	if data.size() != required.size():
		return false
	for key in required:
		if not data.has(key):
			return false
	for key in ["version", "level", "xp", "kills"]:
		if not _integer_number(data[key]):
			return false
	if float(data.version) != SAVE_VERSION or float(data.kills) < 0.0 or float(data.kills) > 1000000000.0:
		return false
	if not data.defeated is Array or not data.inventory is Array or not data.equipped is Dictionary:
		return false
	if not data.quest_started is bool or not data.horse_color is String or data.horse_color not in ["white", "brown"]:
		return false
	if not data.position is Array or data.position.size() != 3:
		return false
	for component in data.position:
		if not _finite_number(component):
			return false
	var next_level = int(clampf(float(data.level), 1.0, float(MAX_LEVEL)))
	var next_xp = int(clampf(float(data.xp), 0.0, float(59 + (next_level - 1) * 30))) if next_level < MAX_LEVEL else 0
	var next_defeated: Array = data.defeated.duplicate()
	if next_defeated.size() > BOSSES.size():
		return false
	for index in next_defeated.size():
		if not next_defeated[index] is String or next_defeated[index] != BOSSES[index].id:
			return false
	if not next_defeated.is_empty():
		if not data.quest_started or next_level < int(BOSSES[next_defeated.size() - 1].level):
			return false
	var expected_items: Array = ["starter"]
	for id in next_defeated:
		expected_items.append(BOSSES[_boss_index(id)].equipment)
	var next_inventory: Array = data.inventory.duplicate()
	if next_inventory.size() != expected_items.size():
		return false
	var seen: Array = []
	for item in next_inventory:
		if not item is String or item not in expected_items or item in seen:
			return false
		seen.append(item)
	var next_equipped: Dictionary = data.equipped.duplicate()
	if next_equipped.size() != 3:
		return false
	for slot in ["weapon", "bracers", "armor"]:
		if not next_equipped.has(slot) or not next_equipped[slot] is String:
			return false
		var item: String = next_equipped[slot]
		if item.is_empty() and slot != "weapon":
			continue
		if item not in next_inventory or not ITEMS.has(item) or ITEMS[item].slot != slot:
			return false
	var next_position = _clamp_position(Vector3(float(data.position[0]), float(data.position[1]), float(data.position[2])))
	level = next_level
	xp = next_xp
	defeated = next_defeated
	inventory = next_inventory
	equipped = next_equipped
	horse_color = data.horse_color
	position = next_position
	quest_started = data.quest_started
	kills = int(data.kills)
	return true

func _boss_index(id: String) -> int:
	for index in BOSSES.size():
		if BOSSES[index].id == id:
			return index
	return -1

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer_number(value: Variant) -> bool:
	return _finite_number(value) and floorf(float(value)) == float(value)

func _clamp_position(value: Vector3) -> Vector3:
	return Vector3(clampf(value.x, -POSITION_LIMIT, POSITION_LIMIT), clampf(value.y, -20.0, 60.0), clampf(value.z, -POSITION_LIMIT, POSITION_LIMIT))
