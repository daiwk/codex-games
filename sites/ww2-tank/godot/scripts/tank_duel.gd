extends Node3D

const Arena = preload("res://scripts/arena.gd")
const Tank = preload("res://scripts/duel_tank.gd")
const TankAI = preload("res://scripts/tank_ai.gd")
const Infantry = preload("res://scripts/infantry_unit.gd")
const Aircraft = preload("res://scripts/aircraft_unit.gd")
const Bomb = preload("res://scripts/aircraft_bomb.gd")
const DuelHUD = preload("res://scripts/duel_hud.gd")
const Effects = preload("res://scripts/duel_effects.gd")
const BOLT_MODEL := preload("res://assets/metal-bolt.glb")
const TANK_ROSTER := [
	{"id": "default", "name": "默认坦克", "model": "res://assets/tank.glb",
		"preview": "res://assets/previews/tank-default.webp", "attack": 28, "defense": 10, "health": 100},
	{"id": "panther_g", "name": "豹式 G 型", "model": "res://assets/tank-panther-g.glb",
		"preview": "res://assets/previews/tank-panther-g.webp", "attack": 34, "defense": 6, "health": 90},
	{"id": "m26_pershing", "name": "M26 潘兴", "model": "res://assets/tank-m26-pershing.glb",
		"preview": "res://assets/previews/tank-m26-pershing.webp", "attack": 29, "defense": 14, "health": 105},
	{"id": "centurion_mk3", "name": "百夫长 Mk.3", "model": "res://assets/tank-centurion-mk3.glb",
		"preview": "res://assets/previews/tank-centurion-mk3.webp", "attack": 24, "defense": 20, "health": 116},
]

const ALLY_SPAWNS := [Vector3(-18, 0, 29), Vector3(-11, 0, 34), Vector3(5, 0, 29), Vector3(15, 0, 29)]
const ENEMY_TANK_COLUMNS := [[-14, 14], [-24, 0, 18], [-25, -9, 9, 24]]
const ALLY_INFANTRY_SPAWNS := [Vector3(-3, 0, 21), Vector3(13, 0, 22)]
const ENEMY_INFANTRY_SPAWNS := [Vector3(-7, 0, -20), Vector3(17, 0, -19)]
const ALLY_AIR_SPAWNS := [Vector3(-22, 8.8, 27), Vector3(22, 9.6, 25)]
const ENEMY_AIR_SPAWNS := [Vector3(21, 9.0, -27), Vector3(-23, 9.6, -25)]
const STAGES := [
	{"id": "plains", "name": "平原", "allied": Vector3i(4, 1, 1), "enemy": Vector3i(2, 1, 1),
		"boss_model": 1, "boss_health": 150, "boss_attack": 35},
	{"id": "hills", "name": "山丘", "allied": Vector3i(5, 2, 1), "enemy": Vector3i(3, 2, 1),
		"boss_model": 2, "boss_health": 190, "boss_attack": 44},
	{"id": "coast", "name": "海边", "allied": Vector3i(4, 2, 2), "enemy": Vector3i(4, 2, 2),
		"boss_model": 3, "boss_health": 240, "boss_attack": 52},
]
const WAVES_PER_STAGE := 3
const REPAIR_SECONDS := 9.0
const ALLY_REPAIR_FRACTION := 0.65
const SPAWN_CLEARANCE_SQUARED := 36.0
const MOUSE_SENSITIVITY := 0.0029
const START_PITCH := -0.04
const SIGHT_HEIGHT := 0.63
const CHASE_DISTANCE := 10.1
const CHASE_RISE := 1.9
const CHASE_WALL_GAP := 0.38
const SIGHT_FOCUS_DISTANCE := 24.0
const AI_COVER_CLEARANCE := 3.0
const SHELL_SPEED := 28.0
const SHELL_LIFETIME := 1.9
const BOMB_COOLDOWN := 5.0
const BOMB_RADIUS := 7.0
const BOMB_UNIT_DAMAGE := 68
const BOMB_BUILDING_DAMAGE := 124
const WEB_LOCK_TIMEOUT_MS := 1250
const WEB_PHASES := ["intro", "active", "paused", "result", "takeover", "switch"]

enum Phase { INTRO, ACTIVE, PAUSED, RESULT, TAKEOVER, SWITCH }

class Shell extends Node3D:
	var direction: Vector3
	var shooter_rid: RID
	var shooter_team: int
	var damage: int
	var lifetime := SHELL_LIFETIME

var _phase := Phase.INTRO
var _arena: Arena
var _arena_stage := -1
var _stage_index := 0
var _hud: DuelHUD
var _camera: Camera3D
var _round: Node3D
var _effects: Effects
var _player: Tank
var _controlled: BattleUnit
var _boss: Tank
var _allies: Array[BattleUnit] = []
var _enemies: Array[BattleUnit] = []
var _ally_brains: Array[TankAI] = []
var _enemy_brains: Array[TankAI] = []
var _allied_support: Array[BattleUnit] = []
var _enemy_support: Array[BattleUnit] = []
var _takeover_choices: Array[BattleUnit] = []
var _switch_resume_lock := false
var _building_target := {}
var _tank_models := {}
var _round_tanks := Vector2i(0, 1)
var _shells: Array[Shell] = []
var _bombs: Array[Bomb] = []
var _wave := 0
var _repair_left := -1.0
var _repair_used := false
var _outcome := ""
var _elapsed := 0.0
var _fire_released := false
var _look_yaw := 0.0
var _look_pitch := START_PITCH
var _look_locked := false
var _look_input_frame := 0
var _view_kick := 0.0
var _ai_grid := AStarGrid2D.new()
var _web_host: JavaScriptObject
var _web_capture_deadline := 0
var _web_had_lock := false
var _web_snapshot_delay := 0.0


func _ready() -> void:
	_build_view()

	_hud = DuelHUD.new()
	_hud.start_requested.connect(_start_round)
	_hud.restart_requested.connect(_restart_from_menu)
	_hud.next_stage_requested.connect(_next_stage)
	_hud.resume_requested.connect(_resume_round)
	_hud.selection_requested.connect(_show_selection)
	_hud.takeover_requested.connect(_takeover_unit)
	_hud.switch_cancelled.connect(_cancel_switch)
	add_child(_hud)
	_hud.configure_roster(TANK_ROSTER)

	_reset_round()
	_hud.show_intro()
	if OS.has_feature("web"):
		_web_host = JavaScriptBridge.get_interface("window")
		if _web_host != null and _web_host.stonewallReady != null:
			_web_host.stonewallReady()
		else:
			_web_host = null


func _process(delta: float) -> void:
	if _web_host == null:
		return
	var locked := bool(_web_host.stonewallPointerLocked())
	if _phase == Phase.ACTIVE and _look_locked:
		if locked:
			_web_had_lock = true
		elif _web_had_lock:
			_pause_round()
		elif Time.get_ticks_msec() >= _web_capture_deadline:
			_set_view_lock(false)

	_web_snapshot_delay -= delta
	if _web_snapshot_delay <= 0.0:
		_web_snapshot_delay = 0.1
		var selected := _hud.selected_tanks()
		var aircraft := _controlled as Aircraft
		var stage: Dictionary = STAGES[_stage_index]
		var player_state := _unit_snapshot(_controlled)
		player_state.merge({
			"hull_yaw": _controlled.rotation.y,
			"gun_yaw": Tank.yaw_towards(_controlled.shot_direction()),
			"gun_pitch": asin(_controlled.shot_direction().y),
			"reload": _controlled.reload_fraction(),
		})
		_web_host.stonewallState(JSON.stringify({
			"ready": true,
			"phase": WEB_PHASES[_phase],
			"pointer_locked": locked,
			"view_locked": _look_locked,
			"seconds": _elapsed,
			"arena": {"width": Arena.ARENA_HALF_SIZE.x * 2.0, "depth": Arena.ARENA_HALF_SIZE.y * 2.0,
				"type": stage["id"]},
			"stage": _stage_index + 1,
			"stage_name": stage["name"],
			"total_stages": STAGES.size(),
			"team_slots": {"allies": _slots_snapshot(stage["allied"]), "enemies": _slots_snapshot(stage["enemy"])},
			"buildings": _arena.building_snapshots(),
			"aimed_building": _building_target,
			"support": {
				"allies": _allied_support.map(_unit_snapshot),
				"enemies": _enemy_support.map(_unit_snapshot),
			},
			"selection": {"player": TANK_ROSTER[selected.x]["id"], "enemy": TANK_ROSTER[selected.y]["id"]},
			"player": player_state,
			"starting_tank": _unit_snapshot(_player),
			"allies": _allies.map(_unit_snapshot),
			"enemies": _enemies.map(_unit_snapshot),
			"takeover_choices": _takeover_choices.map(_unit_snapshot),
			"wave": _wave,
			"total_waves": WAVES_PER_STAGE,
			"intermission": {
				"active": _repair_left >= 0.0,
				"seconds": maxf(0.0, _repair_left),
				"repair_available": _can_repair(),
				"repaired": _repair_used,
			},
			"outcome": _outcome,
			"shells": _shells.size(),
			"bomb_available": _can_drop_bomb(aircraft),
			"bombs": _bombs.map(func(bomb: Bomb) -> Dictionary:
				var at := bomb.global_position
				return {"x": at.x, "y": at.y, "z": at.z,
					"team": "ally" if bomb.team == BattleUnit.FRIENDLY_LAYER else "enemy"}),
			"views": {"main": "third_person"},
			"menu": _web_menu(),
		}))


func _unit_snapshot(unit: BattleUnit) -> Dictionary:
	var state := {
		"id": str(unit.get_instance_id()),
		"x": unit.position.x, "y": unit.position.y, "z": unit.position.z,
		"name": unit.display_name, "kind": unit.kind,
		"health": unit.health, "max_health": unit.max_health,
		"attack": unit.attack, "defense": unit.defense, "boss": unit == _boss,
	}
	if unit is Tank:
		state["tank"] = (unit as Tank).model_id
	elif unit is Aircraft:
		state["bomb_cooldown"] = (unit as Aircraft).bomb_cooldown_left
	return state


func _slots_snapshot(slots: Vector3i) -> Dictionary:
	return {"tanks": slots.x, "infantry": slots.y, "aircraft": slots.z}


func _web_menu() -> Variant:
	if _phase == Phase.ACTIVE:
		return null
	var viewport_size := get_viewport().get_visible_rect().size
	var menu := {"width": viewport_size.x, "height": viewport_size.y,
		"buttons": _rect_coordinates(_hud.menu_button_rects())}
	if _phase == Phase.INTRO:
		menu["choices"] = [_rect_coordinates(_hud.selection_choice_rects(0)),
			_rect_coordinates(_hud.selection_choice_rects(1))]
	elif _phase == Phase.TAKEOVER or _phase == Phase.SWITCH:
		menu["choice_count"] = _takeover_choices.size()
		menu["capture"] = _phase == Phase.TAKEOVER or _switch_resume_lock
	return menu


func _rect_coordinates(rects: Array[Rect2]) -> Array:
	var result := []
	for rect in rects:
		result.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	return result


func _build_view() -> void:
	var lighting := WorldEnvironment.new()
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#668a9b")
	sky_material.sky_horizon_color = Color("#c8d0c4")
	sky_material.ground_horizon_color = Color("#b9bda0")
	sky_material.ground_bottom_color = Color("#60644b")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e1e5db")
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_light_color = Color("#b7c2b5")
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.28
	lighting.environment = environment
	add_child(lighting)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -33, 0)
	sun.light_color = Color("#fff5e7")
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)

	_camera = Camera3D.new()
	_camera.name = "BattleCamera"
	_camera.fov = 62.0
	_camera.near = 0.055
	_camera.far = 160.0
	_camera.cull_mask = 1
	add_child(_camera)
	_camera.make_current()


func _build_ai_grid() -> void:
	var navigable_extent := Vector2i(Arena.ARENA_HALF_SIZE - Vector2.ONE * AI_COVER_CLEARANCE)
	_ai_grid.region = Rect2i(-navigable_extent, navigable_extent * 2 + Vector2i.ONE)
	_ai_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_ai_grid.update()
	_ai_grid.fill_solid_region(_ai_grid.region, false)
	for cover: Rect2 in _arena.cover_rects:
		var padded := cover.grow(AI_COVER_CLEARANCE)
		var first := Vector2i(ceili(padded.position.x), ceili(padded.position.y))
		var last := Vector2i(floori(padded.end.x), floori(padded.end.y))
		_ai_grid.fill_solid_region(Rect2i(first, last - first + Vector2i.ONE))


func _on_building_destroyed(at: Vector3) -> void:
	_build_ai_grid()
	_effects.building_collapse(at)
	_web_snapshot_delay = 0.0


func _load_arena() -> void:
	if is_instance_valid(_arena):
		remove_child(_arena)
		_arena.queue_free()
	_arena = Arena.new()
	_arena.configure(_stage_index)
	add_child(_arena)
	_arena.building_destroyed.connect(_on_building_destroyed)
	_arena_stage = _stage_index


func _reset_round() -> void:
	if is_instance_valid(_round):
		remove_child(_round)
		_round.queue_free()
	if _arena_stage != _stage_index:
		_load_arena()
	else:
		_arena.reset_buildings()
	_build_ai_grid()
	_shells.clear()
	_bombs.clear()
	_allies.clear()
	_enemies.clear()
	_ally_brains.clear()
	_enemy_brains.clear()
	_allied_support.clear()
	_enemy_support.clear()
	_takeover_choices.clear()
	_switch_resume_lock = false
	_building_target = {}
	_boss = null
	_wave = 0
	_repair_left = -1.0
	_repair_used = false
	_outcome = ""
	_round = Node3D.new()
	_round.name = "Round"
	add_child(_round)

	_round_tanks = _hud.selected_tanks()
	_player = _add_tank("Player", Arena.PLAYER_SPAWN, 0.0, true, TANK_ROSTER[_round_tanks.x], Tank.FRIENDLY_LAYER)
	_controlled = _player
	_ally_brains.append(TankAI.new(_player, _ai_grid, 0.85))
	_add_team_marker(_player, "队友", Color("#9fd8c4")).hide()
	_effects = Effects.new()
	_round.add_child(_effects)
	_elapsed = 0.0
	_fire_released = false
	_look_yaw = _player.rotation.y
	_look_pitch = START_PITCH
	_view_kick = 0.0
	_player.point_gun(_look_yaw, _look_pitch, 1.0)
	_update_view(_player)
	var stage: Dictionary = STAGES[_stage_index]
	_hud.set_stage(_stage_index + 1, STAGES.size(), stage["name"], WAVES_PER_STAGE,
		stage["allied"], stage["enemy"])
	_hud.set_controlled_unit(_controlled.display_name, _controlled.kind, _controlled.max_health)
	_update_hud()


func _add_tank(tank_name: String, spawn: Vector3, heading: float, is_player: bool, profile: Dictionary, layer: int) -> Tank:
	var path: String = profile["model"]
	if not _tank_models.has(path):
		_tank_models[path] = load(path) as PackedScene
	var tank := Tank.new()
	tank.name = tank_name
	tank.position = spawn
	tank.rotation.y = heading
	tank.configure(_tank_models[path], is_player, profile, layer)
	_round.add_child(tank)
	return tank


func _start_round() -> void:
	var lock_mouse := _phase != Phase.ACTIVE or _look_locked
	_reset_round()
	_spawn_allies()
	_advance_wave()
	_resume_round(lock_mouse)


func _next_stage() -> void:
	if _phase != Phase.RESULT or _outcome != "stage_clear" or _stage_index + 1 >= STAGES.size():
		return
	_stage_index += 1
	_start_round()


func _restart_from_menu() -> void:
	if _phase == Phase.RESULT and _outcome == "win":
		_stage_index = 0
	_start_round()


func _spawn_allies() -> void:
	var slots: Vector3i = STAGES[_stage_index]["allied"]
	var occupied := _living_friendlies()
	var health_scale := 1.95 if _stage_index == STAGES.size() - 1 else 1.70
	for index in range(slots.x - 1):
		var profile: Dictionary = TANK_ROSTER[index].duplicate()
		profile["health"] = roundi(int(profile["health"]) * health_scale)
		profile["attack"] = roundi(int(profile["attack"]) * 0.95)
		var spawn := _ground_spawn(ALLY_SPAWNS[index], occupied)
		var tank := _add_tank("Ally%d" % (index + 1), spawn, 0.0, false, profile, Tank.FRIENDLY_LAYER)
		tank.reload_time = 2.0
		tank.reload_left = 0.55 + 0.22 * index
		_add_team_marker(tank, "队友 %d" % (index + 1), Color("#9fd8c4"))
		_allies.append(tank)
		_ally_brains.append(TankAI.new(tank, _ai_grid, 0.76))
		occupied.append(tank)


func _advance_wave() -> void:
	_wave += 1
	_repair_left = -1.0
	_repair_used = false
	var stage: Dictionary = STAGES[_stage_index]
	var enemy_slots: Vector3i = stage["enemy"]
	var allied_slots: Vector3i = stage["allied"]
	var rank := _stage_index * WAVES_PER_STAGE + _wave - 1
	var base: Dictionary = TANK_ROSTER[_round_tanks.y]
	var occupied := _living_friendlies()
	for slot in enemy_slots.x:
		var is_boss := _wave == WAVES_PER_STAGE and slot == floori(enemy_slots.x * 0.5)
		var profile: Dictionary = TANK_ROSTER[stage["boss_model"]].duplicate() if is_boss else base.duplicate()
		profile["health"] = stage["boss_health"] if is_boss else roundi(int(base["health"]) * (0.80 + rank * 0.060))
		profile["attack"] = stage["boss_attack"] if is_boss else roundi(int(base["attack"]) * (0.72 + rank * 0.055))
		if is_boss:
			profile["defense"] = 24
		var column: float = ENEMY_TANK_COLUMNS[_stage_index][slot]
		var spawn := _ground_spawn(Arena.ENEMY_SPAWN + Vector3(column, 0.0, 0.0), occupied)
		var tank := _add_tank("Boss" if is_boss else "Enemy%d" % (slot + 1), spawn, PI, false, profile, Tank.HOSTILE_LAYER)
		tank.reload_time = 2.55 - _stage_index * 0.19 if is_boss else 2.65 - rank * 0.10375
		tank.reload_left = 0.75 + 0.20 * slot
		tank.max_speed = 4.9 + rank * 0.085
		if is_boss:
			_boss = tank
		_add_team_marker(tank, "小 Boss" if is_boss else "敌军 %d" % (slot + 1),
			Color("#ffc275") if is_boss else Color("#ffab93"))
		_enemies.append(tank)
		_enemy_brains.append(TankAI.new(tank, _ai_grid, 0.43 if is_boss else 1.17 - rank * 0.082))
		occupied.append(tank)
	_deploy_support(allied_slots, enemy_slots, 0.81 + rank * 0.052, occupied)
	_update_hud()


func _deploy_support(allied_slots: Vector3i, enemy_slots: Vector3i, strength: float, occupied: Array[BattleUnit]) -> void:
	var allied_strength := 1.50 if _stage_index == STAGES.size() - 1 else 1.32
	for slot in range(allied_slots.y + allied_slots.z):
		if slot < _allied_support.size() and _allied_support[slot].health > 0:
			continue
		var ally := _add_support(true, slot, allied_slots.y, allied_strength, occupied)
		if slot < _allied_support.size():
			_allied_support[slot].queue_free()
			_allied_support[slot] = ally
		else:
			_allied_support.append(ally)
	for slot in range(enemy_slots.y + enemy_slots.z):
		var enemy := _add_support(false, slot, enemy_slots.y, strength, occupied)
		_enemy_support.append(enemy)


func _add_support(friendly: bool, slot: int, infantry_slots: int, strength: float, occupied: Array[BattleUnit]) -> BattleUnit:
	var is_aircraft := slot >= infantry_slots
	var index := slot - infantry_slots if is_aircraft else slot
	var positions := ALLY_AIR_SPAWNS if friendly else ENEMY_AIR_SPAWNS
	if not is_aircraft:
		positions = ALLY_INFANTRY_SPAWNS if friendly else ENEMY_INFANTRY_SPAWNS
	var preferred: Vector3 = positions[index]
	var spawn := _air_spawn(preferred, occupied) if is_aircraft else _ground_spawn(preferred, occupied)
	var unit: BattleUnit = Aircraft.new() if is_aircraft else Infantry.new()
	unit.position = spawn
	unit.rotation.y = 0.0 if friendly else PI
	var layer := BattleUnit.FRIENDLY_LAYER if friendly else BattleUnit.HOSTILE_LAYER
	var title := ("战机 %d" if is_aircraft else "步兵 %d") % (index + 1)
	if is_aircraft:
		(unit as Aircraft).configure(layer, strength, title)
	else:
		(unit as Infantry).configure(layer, strength, title)
	_round.add_child(unit)
	var color := Color("#9fd8c4") if friendly else Color("#ffab93")
	_add_team_marker(unit, ("我军 " if friendly else "敌军 ") + title, color, 1.8 if is_aircraft else 2.04)
	occupied.append(unit)
	return unit


func _air_spawn(preferred: Vector3, occupied: Array[BattleUnit]) -> Vector3:
	for offset in [0.0, -10.0, 10.0, -16.0, 16.0]:
		var candidate := preferred + Vector3(offset, 0.0, 0.0)
		var blocked := false
		for unit in occupied:
			if unit.kind == "aircraft" and candidate.distance_squared_to(unit.position) < 64.0:
				blocked = true
				break
		if not blocked:
			return candidate
	return preferred


func _ground_spawn(preferred: Vector3, occupied: Array[BattleUnit]) -> Vector3:
	var cell := Vector2i(roundi(preferred.x), roundi(preferred.z))
	if _spawn_is_clear(cell, occupied):
		return preferred
	var best := preferred
	var closest := INF
	for z in range(_ai_grid.region.position.y, _ai_grid.region.end.y):
		for x in range(_ai_grid.region.position.x, _ai_grid.region.end.x):
			var candidate := Vector2i(x, z)
			var distance := cell.distance_squared_to(candidate)
			if distance < closest and _spawn_is_clear(candidate, occupied):
				closest = distance
				best = Vector3(x, 0.0, z)
	return best


func _spawn_is_clear(cell: Vector2i, occupied: Array[BattleUnit]) -> bool:
	if _ai_grid.is_point_solid(cell):
		return false
	var position := Vector3(cell.x, 0.0, cell.y)
	for tank in occupied:
		if position.distance_squared_to(tank.position) < SPAWN_CLEARANCE_SQUARED:
			return false
	return true


func _add_team_marker(unit: BattleUnit, title: String, color: Color, height := 3.18) -> Label3D:
	var marker := Label3D.new()
	marker.name = "TeamMarker"
	marker.text = title
	marker.font = DuelHUD.BUNDLED_FONT
	marker.font_size = 34
	marker.outline_size = 8
	marker.pixel_size = 0.0105
	marker.modulate = color
	marker.outline_modulate = Color("#141711")
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.position.y = height
	unit.add_child(marker)
	return marker


func _living_units(units: Array[BattleUnit]) -> Array[BattleUnit]:
	return units.filter(func(unit: BattleUnit) -> bool: return unit.health > 0)


func _living_friendlies() -> Array[BattleUnit]:
	var allies := _living_units(_allies)
	if _player.health > 0:
		allies.push_front(_player)
	allies.append_array(_living_units(_allied_support))
	return allies


func _living_enemies() -> Array[BattleUnit]:
	var enemies := _living_units(_enemies)
	enemies.append_array(_living_units(_enemy_support))
	return enemies


func _count_kind(units: Array[BattleUnit], kind: String) -> int:
	var count := 0
	for unit in units:
		if unit.health > 0 and unit.kind == kind:
			count += 1
	return count


func _update_hud() -> void:
	_hud.update_battle(_controlled.health, _controlled.reload_fraction(), _elapsed, _wave,
		_living_units(_allies).size() + int(_player.health > 0), _living_units(_enemies).size(),
		_boss.health if is_instance_valid(_boss) else 0, _boss.max_health if is_instance_valid(_boss) else 0)
	_hud.set_support_counts(_count_kind(_allied_support, "infantry"), _count_kind(_enemy_support, "infantry"),
		_count_kind(_allied_support, "aircraft"), _count_kind(_enemy_support, "aircraft"))
	_hud.set_intermission(_repair_left, _can_repair(), _repair_used)
	var aircraft := _controlled as Aircraft
	var bomb_visible := aircraft != null and aircraft.health > 0
	_hud.set_bomb_status(bomb_visible, aircraft.bomb_cooldown_left if bomb_visible else 0.0,
		_can_drop_bomb(aircraft))
	_building_target = {}
	if _phase == Phase.ACTIVE and _controlled.health > 0:
		var start := _camera.global_position
		var end := start - _camera.global_basis.z * SHELL_SPEED * SHELL_LIFETIME
		var hit := _cast_ray(start, end, BattleUnit.BATTLE_MASK, _controlled.get_rid())
		_building_target = _arena.building_info(hit.get("collider"))
	_hud.set_building_target(_building_target)


func _show_selection() -> void:
	_phase = Phase.INTRO
	_stage_index = 0
	_set_view_lock(false)
	_reset_round()
	_hud.show_intro()


func _show_takeover(voluntary := false) -> void:
	_takeover_choices = _living_friendlies()
	if voluntary:
		_takeover_choices.erase(_controlled)
		if _takeover_choices.is_empty():
			return
	_switch_resume_lock = _look_locked
	_phase = Phase.SWITCH if voluntary else Phase.TAKEOVER
	_set_view_lock(false)
	var cards: Array[Dictionary] = []
	for unit in _takeover_choices:
		cards.append(_unit_snapshot(unit))
	_hud.show_takeover(cards, voluntary)
	if not voluntary:
		_update_view(_takeover_choices[0])
	_update_hud()


func _takeover_unit(index: int) -> void:
	var switching := _phase == Phase.SWITCH
	if not switching and _phase != Phase.TAKEOVER:
		return
	if index < 0 or index >= _takeover_choices.size():
		return
	if switching:
		_return_control_to_ai()
	_controlled = _takeover_choices[index]
	_takeover_choices.clear()
	var marker := _controlled.get_node_or_null("TeamMarker") as Label3D
	if marker != null:
		marker.hide()
	var direction := _controlled.shot_direction()
	_look_yaw = Tank.yaw_towards(direction)
	_look_pitch = clampf(asin(direction.y), -0.65, 0.75)
	var tank := _controlled as Tank
	if tank != null:
		tank.turret_turn_speed = 14.0
		_look_pitch = START_PITCH
		tank.point_gun(_look_yaw, _look_pitch, 1.0)
	_view_kick = 0.0
	_hud.set_controlled_unit(_controlled.display_name, _controlled.kind, _controlled.max_health)
	_update_view(_controlled)
	_resume_round(_switch_resume_lock if switching else true)
	_update_hud()


func _return_control_to_ai() -> void:
	_controlled.resume_ai()
	var marker := _controlled.get_node_or_null("TeamMarker") as Label3D
	if marker != null:
		marker.show()
	for brain in _ally_brains:
		if brain.tank == _controlled:
			brain.resume()
			break


func _cancel_switch() -> void:
	if _phase != Phase.SWITCH:
		return
	_takeover_choices.clear()
	_resume_round(_switch_resume_lock)
	_update_hud()


func _resume_round(lock_mouse := true) -> void:
	_phase = Phase.ACTIVE
	_fire_released = false
	_hud.show_active()
	_set_view_lock(lock_mouse)


func _pause_round() -> void:
	_phase = Phase.PAUSED
	_hud.show_pause()
	_set_view_lock(false)


func _set_view_lock(locked: bool) -> void:
	_look_locked = locked
	_hud.set_mouse_locked(locked)
	_web_snapshot_delay = 0.0
	if locked:
		# Ignore the pointer jump when the window recenters it on capture.
		_look_input_frame = Engine.get_process_frames() + 3
		_web_had_lock = false
		_web_capture_deadline = Time.get_ticks_msec() + WEB_LOCK_TIMEOUT_MS
		if _web_host == null:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif _web_host != null:
		_web_host.stonewallReleasePointer()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if _phase != Phase.ACTIVE:
		return
	var key := event as InputEventKey
	if key != null and key.physical_keycode == KEY_TAB and key.pressed and not key.echo \
			and not key.ctrl_pressed and not key.meta_pressed and not key.alt_pressed:
		_set_view_lock(not _look_locked)
		get_viewport().set_input_as_handled()
		return
	var mouse := event as InputEventMouseMotion
	if mouse == null or not _look_locked or Engine.get_process_frames() < _look_input_frame:
		return
	if _web_host != null and not _web_had_lock:
		return
	var motion := mouse.screen_relative
	_look_yaw = wrapf(_look_yaw - motion.x * MOUSE_SENSITIVITY, -PI, PI)
	_look_pitch = clampf(_look_pitch - motion.y * MOUSE_SENSITIVITY, -0.65, 0.75)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return
	if (_phase == Phase.TAKEOVER or _phase == Phase.SWITCH) \
			and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_7:
		_takeover_unit(event.physical_keycode - KEY_1)
	elif event.physical_keycode == KEY_Q:
		if _phase == Phase.ACTIVE:
			_show_takeover(true)
		elif _phase == Phase.SWITCH:
			_cancel_switch()
	elif event.physical_keycode == KEY_H:
		_repair_player()
	elif event.physical_keycode == KEY_B:
		_drop_bomb()
	elif event.physical_keycode == KEY_R and _phase != Phase.INTRO:
		_start_round()
	elif event.is_action_pressed("ui_cancel"):
		if _phase == Phase.SWITCH:
			_cancel_switch()
		elif _phase == Phase.ACTIVE:
			_pause_round()
		elif _phase == Phase.PAUSED and _web_host == null:
			_resume_round()
	elif event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
		if _phase == Phase.INTRO:
			_start_round()
		elif _phase == Phase.RESULT:
			if _outcome == "stage_clear":
				_next_stage()
			else:
				_restart_from_menu()
		elif _phase == Phase.PAUSED:
			_resume_round()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _phase == Phase.ACTIVE:
		_pause_round()


func _physics_process(delta: float) -> void:
	if _phase != Phase.ACTIVE:
		return

	_elapsed += delta
	if _controlled.health > 0:
		_controlled.update_reload(delta)
		_update_player(delta)
	_advance_bombs(delta)

	if _repair_left >= 0.0:
		_repair_left -= delta
		if _repair_left <= 0.0:
			_advance_wave()
	else:
		var allies_alive := _living_friendlies()
		var enemies_alive := _living_enemies()
		_update_ai_team(_ally_brains, enemies_alive, delta)
		_update_ai_team(_enemy_brains, allies_alive, delta)
		_update_support_team(_allied_support, enemies_alive, delta)
		_update_support_team(_enemy_support, allies_alive, delta)
		_advance_shells(delta)
		_check_wave_outcome()
	_update_hud()


func _check_wave_outcome() -> void:
	var enemies_down := _living_enemies().is_empty()
	var final_wave := _wave == WAVES_PER_STAGE
	if _living_friendlies().is_empty():
		_finish_round("draw" if enemies_down and final_wave else "loss")
	elif enemies_down:
		if final_wave:
			_finish_round("win" if _stage_index + 1 == STAGES.size() else "stage_clear")
		else:
			_start_intermission()
	if _phase == Phase.ACTIVE and _controlled.health == 0:
		_show_takeover()


func _start_intermission() -> void:
	_clear_shells()
	_enemy_brains.clear()
	_boss = null
	for tank in _enemies:
		tank.queue_free()
	_enemies.clear()
	for unit in _enemy_support:
		unit.queue_free()
	_enemy_support.clear()
	_repair_left = REPAIR_SECONDS
	_repair_used = false
	for ally in _living_friendlies():
		if ally != _controlled:
			ally.health = mini(ally.max_health, ally.health + roundi(ally.max_health * ALLY_REPAIR_FRACTION))
	_web_snapshot_delay = 0.0


func _can_repair() -> bool:
	return _phase == Phase.ACTIVE and _repair_left > 0.0 and not _repair_used \
		and _controlled.health > 0 and _controlled.health < _controlled.max_health


func _repair_player() -> void:
	if _can_repair():
		_controlled.health = _controlled.max_health
		_repair_used = true
		_web_snapshot_delay = 0.0
		_update_hud()


func _clear_shells() -> void:
	for shell in _shells:
		shell.queue_free()
	_shells.clear()


func _can_drop_bomb(aircraft: Aircraft) -> bool:
	return aircraft != null and aircraft.health > 0 and _phase == Phase.ACTIVE \
		and _repair_left < 0.0 and aircraft.bomb_cooldown_left <= 0.0


func _drop_bomb() -> void:
	_launch_bomb(_controlled as Aircraft)


func _launch_bomb(aircraft: Aircraft) -> void:
	if not _can_drop_bomb(aircraft):
		return
	var bomb := Bomb.new()
	bomb.position = _round.to_local(aircraft.bomb_origin())
	bomb.team = aircraft.collision_layer
	_round.add_child(bomb)
	_bombs.append(bomb)
	aircraft.bomb_cooldown_left = BOMB_COOLDOWN
	_web_snapshot_delay = 0.0


func _advance_bombs(delta: float) -> void:
	for team in [_allied_support, _enemy_support]:
		for unit: BattleUnit in team:
			var aircraft := unit as Aircraft
			if aircraft != null:
				aircraft.bomb_cooldown_left = maxf(0.0, aircraft.bomb_cooldown_left - delta)
	for index in range(_bombs.size() - 1, -1, -1):
		var bomb := _bombs[index]
		var hit := bomb.advance(delta)
		if hit.is_empty() and bomb.position.y > -3.0:
			continue
		_bombs.remove_at(index)
		if not hit.is_empty():
			_explode_bomb(hit["position"], bomb.team)
		bomb.queue_free()


func _explode_bomb(at: Vector3, team: int) -> void:
	_effects.bomb_blast(at)
	_arena.damage_buildings_in_area(at, BOMB_RADIUS, BOMB_BUILDING_DAMAGE)
	var targets := _living_enemies() if team == BattleUnit.FRIENDLY_LAYER else _living_friendlies()
	for unit in targets:
		var distance := at.distance_to(unit.target_point())
		if distance < BOMB_RADIUS:
			var damage := roundi(BOMB_UNIT_DAMAGE * lerpf(1.0, 0.28, distance / BOMB_RADIUS))
			_damage_unit(unit, damage, team)
	_web_snapshot_delay = 0.0


func _update_player(delta: float) -> void:
	var axes := Input.get_vector("tank_left", "tank_right", "tank_forward", "tank_reverse")
	var controlled_tank := _controlled as Tank
	var aligned := true
	if controlled_tank != null:
		var view_forward := -_camera.global_basis.z
		view_forward.y = 0.0
		view_forward = view_forward.normalized()
		var view_right := view_forward.cross(Vector3.UP)
		controlled_tank.drive_direction(view_right * axes.x - view_forward * axes.y, axes.y > 0.1, delta)
		aligned = controlled_tank.point_gun(_look_yaw, _look_pitch, delta) < 0.08
	else:
		_controlled.drive_player(axes, _look_yaw, _look_pitch, delta)
	_view_kick = move_toward(_view_kick, 0.0, 0.68 * delta)
	_update_view(_controlled)
	_hud.set_aim(_controlled.reload_left <= 0.0 and aligned)

	if _repair_left >= 0.0 or not Input.is_action_pressed("tank_fire"):
		_fire_released = true
	elif _fire_released and _controlled.reload_left <= 0.0:
		if controlled_tank != null:
			_fire(controlled_tank)
		else:
			_fire_support(_controlled)


func _update_view(follow: BattleUnit) -> void:
	var forward := follow.shot_direction()
	var eyes := follow.target_point() + Vector3.UP * 0.42
	var distance := CHASE_DISTANCE
	var rise := CHASE_RISE
	var tank := follow as Tank
	if tank != null:
		eyes = tank.gun_pivot_position() + Vector3.UP * SIGHT_HEIGHT
	elif follow.kind == "infantry":
		distance = 4.8
		rise = 1.3
	else:
		distance = 12.3
		rise = 2.4
	var horizontal := Vector3(forward.x, 0.0, forward.z).normalized()
	var chase_offset := -horizontal * (distance + _view_kick) + Vector3.UP * rise
	var chase_distance := chase_offset.length()
	var wall := _cast_ray(eyes, eyes + chase_offset, Tank.WORLD_LAYER, follow.get_rid())
	if not wall.is_empty():
		var contact: Vector3 = wall["position"]
		chase_distance = maxf(0.0, eyes.distance_to(contact) - CHASE_WALL_GAP)
	_camera.global_position = eyes + chase_offset.normalized() * chase_distance
	_camera.look_at(eyes + forward * SIGHT_FOCUS_DISTANCE)


func _update_ai_team(brains: Array[TankAI], opponents: Array[BattleUnit], delta: float) -> void:
	for brain in brains:
		if brain.tank != _controlled and brain.tank.health > 0 and brain.update(delta, opponents):
			_fire(brain.tank)


func _update_support_team(units: Array[BattleUnit], opponents: Array[BattleUnit], delta: float) -> void:
	for unit in units:
		if unit == _controlled or unit.health <= 0:
			continue
		unit.update_reload(delta)
		var fire_gun := unit.update_ai(opponents, _ai_grid, delta)
		var aircraft := unit as Aircraft
		if _can_drop_bomb(aircraft) and aircraft.wants_bomb(opponents):
			_launch_bomb(aircraft)
		if fire_gun:
			_fire_support(unit)


func _fire(tank: Tank) -> void:
	tank.reload_left = tank.reload_time
	var muzzle := tank.muzzle_position()
	var direction := tank.muzzle_direction()
	var pivot := tank.gun_pivot_position()
	if tank == _controlled:
		_view_kick = 0.115
	var obstruction := _cast_ray(pivot, muzzle, Tank.BATTLE_MASK, tank.get_rid())
	if not obstruction.is_empty():
		_register_impact(obstruction, tank.attack, tank.collision_layer, true)
		return

	_effects.muzzle_flash(muzzle, direction)
	if tank == _controlled:
		direction = _sight_shot_direction(tank, muzzle, direction, SHELL_SPEED * SHELL_LIFETIME)
	var shell := Shell.new()
	shell.direction = direction
	shell.shooter_rid = tank.get_rid()
	shell.shooter_team = tank.collision_layer
	shell.damage = tank.attack
	shell.position = muzzle
	var bolt := BOLT_MODEL.instantiate() as Node3D
	bolt.name = "BoltModel"
	shell.add_child(bolt)

	var tracer := MeshInstance3D.new()
	var tracer_mesh := CylinderMesh.new()
	tracer_mesh.top_radius = 0.004
	tracer_mesh.bottom_radius = 0.018
	tracer_mesh.height = 0.42
	tracer_mesh.radial_segments = 6
	tracer_mesh.rings = 1
	tracer.mesh = tracer_mesh
	tracer.rotation.x = PI * 0.5
	# The bolt's tip is at the ray origin and its base is at local Z = 0.66.
	tracer.position.z = 0.87
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color("#fff097bf") if tank.collision_layer == Tank.FRIENDLY_LAYER else Color("#ffae75bf")
	tracer.material_override = material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.add_child(tracer)
	_round.add_child(shell)
	shell.look_at(muzzle + direction)
	_shells.append(shell)


func _fire_support(unit: BattleUnit) -> void:
	unit.reload_left = unit.reload_time
	var from := unit.shot_origin()
	var direction := unit.shot_direction()
	var aircraft := unit.kind == "aircraft"
	var range_limit := Aircraft.AI_FIRE_RANGE if aircraft else Infantry.SHOT_RANGE
	var obstruction := _cast_ray(unit.target_point(), from, BattleUnit.BATTLE_MASK, unit.get_rid())
	if not obstruction.is_empty():
		_register_impact(obstruction, unit.attack, unit.collision_layer)
		return
	if unit == _controlled:
		_view_kick = 0.045 if aircraft else 0.035
		direction = _sight_shot_direction(unit, from, direction, range_limit)
	var end := from + direction * range_limit
	var hit := _cast_ray(from, end, BattleUnit.BATTLE_MASK, unit.get_rid())
	if not hit.is_empty():
		end = hit["position"]
		_register_impact(hit, unit.attack, unit.collision_layer)
	_effects.small_shot(from, end, unit.collision_layer == BattleUnit.FRIENDLY_LAYER, aircraft)


func _sight_shot_direction(unit: BattleUnit, muzzle: Vector3, barrel_direction: Vector3, range_limit: float) -> Vector3:
	var origin := _camera.global_position
	var sight_target := origin - _camera.global_basis.z * range_limit
	var hit := _cast_ray(origin, sight_target, BattleUnit.BATTLE_MASK, unit.get_rid())
	if not hit.is_empty():
		sight_target = hit["position"]
	# Converge the shell on the sight line while still allowing nearby cover to intercept it.
	var from_muzzle := sight_target - muzzle
	if from_muzzle.dot(barrel_direction) > 0.1:
		return from_muzzle.normalized()
	return barrel_direction


func _advance_shells(delta: float) -> void:
	for index in range(_shells.size() - 1, -1, -1):
		var shell := _shells[index]
		var next := shell.position + shell.direction * SHELL_SPEED * delta
		var hit := _cast_ray(shell.position, next, Tank.BATTLE_MASK, shell.shooter_rid)
		if not hit.is_empty():
			_register_impact(hit, shell.damage, shell.shooter_team, true)
		shell.lifetime -= delta
		if not hit.is_empty() or shell.lifetime <= 0.0:
			_shells.remove_at(index)
			shell.queue_free()
		else:
			shell.position = next


func _cast_ray(from: Vector3, to: Vector3, layers: int, excluded: RID) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, layers, [excluded])
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _register_impact(hit: Dictionary, damage: int, shooter_team: int, cannon := false) -> void:
	var collider: Object = hit["collider"]
	if cannon:
		_arena.damage_building(collider, damage)
	var target := collider as BattleUnit
	var vehicle := is_instance_valid(target) and target.kind != "infantry"
	_effects.impact(hit["position"], hit["normal"], vehicle)
	_damage_unit(target, damage, shooter_team)


func _damage_unit(target: BattleUnit, damage: int, shooter_team: int) -> void:
	if is_instance_valid(target) and target.health > 0 and target.collision_layer != shooter_team:
		target.take_hit(damage)
		if target.health == 0 and target.kind != "infantry":
			_effects.wreck(target.target_point())


func _finish_round(outcome: String) -> void:
	_phase = Phase.RESULT
	_outcome = outcome
	_clear_shells()
	for bomb in _bombs:
		bomb.queue_free()
	_bombs.clear()
	_set_view_lock(false)
	if outcome == "stage_clear":
		_hud.show_stage_clear(STAGES[_stage_index]["name"], STAGES[_stage_index + 1]["name"])
	else:
		_hud.show_result(outcome, _wave)
