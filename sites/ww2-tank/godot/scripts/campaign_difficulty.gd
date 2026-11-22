extends RefCounted

const DEFAULT := 1
const LEVELS := [
	{"id": "easy", "label": "简单", "units": Vector3i(-1, -2, -1), "attack": 0.85, "defense": -5},
	{"id": "normal", "label": "普通", "units": Vector3i.ZERO, "attack": 1.0, "defense": 0},
	{"id": "hard", "label": "困难", "units": Vector3i(1, 1, 0), "attack": 1.08, "defense": 5},
]


static func enemy_force(base: Vector3i, level: int) -> Vector3i:
	var change: Vector3i = LEVELS[level]["units"]
	return (base + change).max(Vector3i(1, 0, 0))


static func enemy_attack(base: int, level: int) -> int:
	return maxi(1, roundi(base * float(LEVELS[level]["attack"])))


static func apply_to_enemy(unit: BattleUnit, level: int) -> void:
	unit.attack = enemy_attack(unit.attack, level)
	unit.defense = clampi(unit.defense + int(LEVELS[level]["defense"]), 0, 95)
