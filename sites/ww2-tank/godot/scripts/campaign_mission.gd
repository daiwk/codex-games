extends RefCounted

const Arena = preload("res://scripts/campaign_arena.gd")
const ALLIED_FORCE := Vector3i(10, 20, 5)
const REGIONS := ["平原", "群山", "滩头"]
const SUPPLY_POINTS := Arena.SUPPLY_POINTS
const SUPPLY_RADIUS := 10.5
const DEFENSE_POINT := Arena.DEFENSE_POINT
const DEFENSE_RADIUS := 18.0
const LANDING_PREP := 8.0
const LANDING_DELAY := 6.0
const ROUTE_ENCOUNTERS := [
	{"trigger": 13.0, "center": Vector2(3, -14), "force": Vector3i(3, 5, 1)},
	{"trigger": -15.0, "center": Vector2(0, -45), "force": Vector3i(3, 6, 1), "boss": "plains"},
	{"trigger": -51.0, "center": Vector2(-4, -78), "force": Vector3i(4, 7, 1)},
	{"trigger": -86.0, "center": Vector2(2, -112), "force": Vector3i(4, 8, 2)},
	{"trigger": -123.0, "center": Vector2(3, -151), "force": Vector3i(5, 9, 2), "boss": "hills"},
	{"trigger": -177.0, "center": Vector2(-5, -204), "force": Vector3i(3, 6, 1)},
]
const LANDING_WAVES := [Vector3i(3, 6, 1), Vector3i(4, 7, 1), Vector3i(5, 8, 2)]
const LANDING_Z := -236.0

var encounter_count := 0
var supplied := [false, false, false]
var defending := false
var landing_wave := 0
var landing_delay := -1.0


func region_at(z: float) -> int:
	if z > -50.0:
		return 0
	return 1 if z > -178.0 else 2


func next_encounter(z: float) -> Dictionary:
	if encounter_count >= ROUTE_ENCOUNTERS.size() or z > float(ROUTE_ENCOUNTERS[encounter_count]["trigger"]):
		return {}
	var encounter: Dictionary = ROUTE_ENCOUNTERS[encounter_count]
	encounter_count += 1
	return encounter


func take_supply(at: Vector2) -> int:
	for index in SUPPLY_POINTS.size():
		var point: Vector2 = SUPPLY_POINTS[index]
		if not supplied[index] and at.distance_squared_to(point) <= SUPPLY_RADIUS * SUPPLY_RADIUS:
			supplied[index] = true
			return index
	return -1


func next_destination(z: float) -> Vector2:
	for index in SUPPLY_POINTS.size():
		var point: Vector2 = SUPPLY_POINTS[index]
		if not supplied[index] and z >= point.y - 15.0:
			return point
	return DEFENSE_POINT


func reach_defense(at: Vector2) -> bool:
	if defending or encounter_count < ROUTE_ENCOUNTERS.size() \
			or at.distance_squared_to(DEFENSE_POINT) > DEFENSE_RADIUS * DEFENSE_RADIUS:
		return false
	defending = true
	landing_delay = LANDING_PREP
	return true


func advance_landing(delta: float, landing_alive: int) -> bool:
	if not defending or landing_alive > 0 or landing_wave >= LANDING_WAVES.size():
		return false
	if landing_delay < 0.0:
		landing_delay = LANDING_DELAY
	landing_delay = maxf(0.0, landing_delay - delta)
	if landing_delay > 0.0:
		return false
	landing_wave += 1
	landing_delay = -1.0
	return true


func beach_held(landing_alive: int) -> bool:
	return defending and landing_wave == LANDING_WAVES.size() and landing_alive == 0
