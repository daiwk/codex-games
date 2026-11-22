extends Node3D

const Arena = preload("res://scripts/campaign_arena.gd")
const Mission = preload("res://scripts/campaign_mission.gd")
const Difficulty = preload("res://scripts/campaign_difficulty.gd")
const Waypoints = preload("res://scripts/campaign_waypoints.gd")
const Tank = preload("res://scripts/duel_tank.gd")
const TankAI = preload("res://scripts/tank_ai.gd")
const Infantry = preload("res://scripts/infantry_unit.gd")
const Aircraft = preload("res://scripts/aircraft_unit.gd")
const Bomb = preload("res://scripts/aircraft_bomb.gd")
const BossAbility = preload("res://scripts/boss_ability.gd")
const DuelHUD = preload("res://scripts/duel_hud.gd")
const Effects = preload("res://scripts/duel_effects.gd")
const BOLT_MODEL := preload("res://assets/metal-bolt.glb")
const TANK_ROSTER := [
	{"id": "default", "name": "默认坦克", "model": "res://assets/tank.glb",
		"attack": 28, "defense": 10, "health": 100},
	{"id": "panther_g", "name": "豹式 G 型", "model": "res://assets/tank-panther-g.glb",
		"attack": 34, "defense": 6, "health": 90},
	{"id": "m26_pershing", "name": "M26 潘兴", "model": "res://assets/tank-m26-pershing.glb",
		"attack": 29, "defense": 14, "health": 105},
	{"id": "centurion_mk3", "name": "百夫长 Mk.3", "model": "res://assets/tank-centurion-mk3.glb",
		"attack": 24, "defense": 20, "health": 116},
	{"id": "leopard_2a8", "name": "豹 2A8", "model": "res://assets/tank-leopard-2a8.glb",
		"attack": 30, "defense": 14, "health": 108},
	{"id": "m1a2_sepv3", "name": "M1A2 SEP v3", "model": "res://assets/tank-m1a2-sepv3.glb",
		"attack": 30, "defense": 18, "health": 110},
]
const PLAYER_TANK := 4
const ENEMY_TANK_ORDER := [5, 1, 4, 2, 0, 3]

const BOSS_PROFILES := {
	"plains": {"model": 1, "health": 150, "attack": 35},
	"hills": {"model": 2, "health": 190, "attack": 44},
	"coast": {"model": 3, "health": 240, "attack": 52},
}
const ALLY_START := Vector2(-9, 33)
const FORMATION_REFRESH := 0.30
const SUPPLY_NOTICE_SECONDS := 4.8
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
const AIRSTRIKE_UNIT_DAMAGE := 82
const AIRSTRIKE_BUILDING_DAMAGE := 158
const BURST_DAMAGE_FACTOR := 0.63
const WEB_LOCK_TIMEOUT_MS := 1250
const WEB_PHASES := ["intro", "active", "paused", "result", "takeover", "switch"]
const STAGE_LIGHTS := [
	[Color("#6e9cbb"), Color("#d9dac0"), Color("#fff0cd"), Vector3(-43, -48, 0), 0.0040],
	[Color("#597f9b"), Color("#ccd9db"), Color("#edf4fc"), Vector3(-47, 39, 0), 0.0055],
	[Color("#638494"), Color("#c1d0cf"), Color("#f4f2e6"), Vector3(-53, -65, 0), 0.0048],
]

enum Phase { INTRO, ACTIVE, PAUSED, RESULT, TAKEOVER, SWITCH }

class Shell extends Node3D:
	var direction: Vector3
	var shooter_rid: RID
	var shooter_team: int
	var damage: int
	var lifetime := SHELL_LIFETIME

var _phase := Phase.INTRO
var _arena: Arena
var _mission: Mission
var _waypoints: Waypoints
var _region := 0
var _hud: DuelHUD
var _camera: Camera3D
var _environment: Environment
var _sun: DirectionalLight3D
var _round: Node3D
var _effects: Effects
var _player: Tank
var _controlled: BattleUnit
var _bosses: Dictionary[Tank, BossAbility] = {}
var _allies: Array[BattleUnit] = []
var _enemies: Array[BattleUnit] = []
var _ally_brains: Array[TankAI] = []
var _enemy_brains: Array[TankAI] = []
var _allied_support: Array[BattleUnit] = []
var _enemy_support: Array[BattleUnit] = []
var _landing_members: Array[BattleUnit] = []
var _takeover_choices: Array[BattleUnit] = []
var _switch_resume_lock := false
var _building_target := {}
var _tank_models := {}
var _difficulty := Difficulty.DEFAULT
var _shells: Array[Shell] = []
var _bombs: Array[Bomb] = []
var _formation_left := 0.0
var _supply_notice_left := 0.0
var _hud_refresh_left := 0.0
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
	_hud.restart_requested.connect(_start_round)
	_hud.resume_requested.connect(_resume_round)
	_hud.selection_requested.connect(_show_selection)
	_hud.takeover_requested.connect(_takeover_unit)
	_hud.switch_cancelled.connect(_cancel_switch)
	add_child(_hud)
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
		_web_snapshot_delay = 0.15
		var rule: Dictionary = Difficulty.LEVELS[_difficulty]
		var aircraft := _controlled as Aircraft
		var bounds := _arena.navigation_region(0.0)
		var destination := Mission.DEFENSE_POINT if _mission.defending else _mission.next_destination(_controlled.position.z)
		var boss := _active_boss()
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
			"arena": {"width": bounds.size.x - 1, "depth": bounds.size.y - 1,
				"type": "continuous", "forward": "negative z"},
			"region": Mission.REGIONS[_region],
			"team_slots": {"allies": _slots_snapshot(Mission.ALLIED_FORCE), "enemies": _slots_snapshot(_deployed_enemies())},
			"mission": {"encounters": _mission.encounter_count, "supplied": _mission.supplied,
				"destination": {"x": destination.x, "z": destination.y}, "defending": _mission.defending,
				"landing_wave": _mission.landing_wave, "landing_total": Mission.LANDING_WAVES.size(),
				"landing_enemies": _living_units(_landing_members).size(), "landing_delay": _mission.landing_delay},
			"buildings": _arena.building_snapshots(),
			"aimed_building": _building_target,
			"support": {
				"allies": _allied_support.map(_unit_snapshot),
				"enemies": _enemy_support.map(_unit_snapshot),
			},
			"difficulty": {"id": rule["id"], "label": rule["label"], "level": _difficulty,
				"attack_multiplier": rule["attack"], "defense_adjustment": rule["defense"]},
			"player": player_state,
			"starting_tank": _unit_snapshot(_player),
			"allies": _allies.map(_unit_snapshot),
			"enemies": _enemies.map(_unit_snapshot),
			"takeover_choices": _takeover_choices.map(_unit_snapshot),
			"boss_ability": _bosses[boss].snapshot() if boss != null else {},
			"outcome": _outcome,
			"shells": _shells.size(),
			"bomb_available": _can_drop_bomb(aircraft),
			"bombs": _bombs.map(func(bomb: Bomb) -> Dictionary:
				var at := bomb.global_position
				return {"x": at.x, "y": at.y, "z": at.z,
					"team": "ally" if bomb.team == BattleUnit.FRIENDLY_LAYER else "enemy",
					"source": "airstrike" if bomb.is_airstrike else "aircraft"}),
			"views": {"main": "third_person"},
			"menu": _web_menu(),
		}))


func _unit_snapshot(unit: BattleUnit) -> Dictionary:
	var state := {
		"id": str(unit.get_instance_id()),
		"x": unit.position.x, "y": unit.position.y, "z": unit.position.z,
		"name": unit.display_name, "kind": unit.kind,
		"health": unit.health, "max_health": unit.max_health,
		"attack": unit.attack, "defense": unit.defense, "boss": unit is Tank and _bosses.has(unit),
	}
	if unit is Tank:
		state["tank"] = (unit as Tank).model_id
	elif unit is Aircraft:
		var aircraft := unit as Aircraft
		state["airframe"] = aircraft.airframe_id
		state["bomb_cooldown"] = aircraft.bomb_cooldown_left
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
		menu["choices"] = _rect_coordinates(_hud.difficulty_choice_rects())
	elif _phase == Phase.TAKEOVER or _phase == Phase.SWITCH:
		menu["choice_count"] = _hud.takeover_visible_count()
		menu["choice_start"] = _hud.takeover_index_for_key(1)
		menu["page_buttons"] = _rect_coordinates(_hud.takeover_page_button_rects())
		menu["capture"] = _phase == Phase.TAKEOVER or _switch_resume_lock
	return menu


func _rect_coordinates(rects: Array[Rect2]) -> Array:
	var result := []
	for rect in rects:
		result.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	return result


func _build_view() -> void:
	var lighting := WorldEnvironment.new()
	_environment = Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.ground_bottom_color = Color("#60644b")
	var sky := Sky.new()
	sky.sky_material = sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("#e1e5db")
	_environment.ambient_light_energy = 0.55
	_environment.fog_enabled = true
	_environment.fog_sky_affect = 0.28
	lighting.environment = _environment
	add_child(lighting)

	_sun = DirectionalLight3D.new()
	_sun.light_energy = 0.78
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 110.0
	add_child(_sun)

	_camera = Camera3D.new()
	_camera.name = "BattleCamera"
	_camera.fov = 62.0
	_camera.near = 0.055
	_camera.far = 205.0
	_camera.cull_mask = 1
	add_child(_camera)
	_camera.make_current()


func _set_stage_lighting() -> void:
	var palette: Array = STAGE_LIGHTS[_region]
	var sky_material := _environment.sky.sky_material as ProceduralSkyMaterial
	var horizon: Color = palette[1]
	sky_material.sky_top_color = palette[0]
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon.darkened(0.10)
	_environment.fog_light_color = horizon
	_environment.fog_density = palette[4]
	_sun.light_color = palette[2]
	_sun.rotation_degrees = palette[3]


func _build_ai_grid() -> void:
	_ai_grid.region = _arena.navigation_region(AI_COVER_CLEARANCE)
	_ai_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_ai_grid.update()
	_ai_grid.fill_solid_region(_ai_grid.region, false)
	for cover: Rect2 in _arena.cover_rects:
		var padded := cover.grow(AI_COVER_CLEARANCE)
		var first := Vector2i(ceili(padded.position.x), ceili(padded.position.y))
		var last := Vector2i(floori(padded.end.x), floori(padded.end.y))
		var cells := Rect2i(first, last - first + Vector2i.ONE).intersection(_ai_grid.region)
		if cells.has_area():
			_ai_grid.fill_solid_region(cells)


func _on_building_destroyed(at: Vector3) -> void:
	_build_ai_grid()
	_effects.building_collapse(at)
	_web_snapshot_delay = 0.0


func _load_arena() -> void:
	_arena = Arena.new()
	add_child(_arena)
	_arena.building_destroyed.connect(_on_building_destroyed)
	_waypoints = Waypoints.new()
	add_child(_waypoints)
	_waypoints.build(_arena.ground_height)


func _reset_round() -> void:
	if is_instance_valid(_round):
		remove_child(_round)
		_round.queue_free()
	if _arena == null:
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
	_landing_members.clear()
	_bosses.clear()
	_takeover_choices.clear()
	_switch_resume_lock = false
	_building_target = {}
	_mission = Mission.new()
	_region = 0
	_set_stage_lighting()
	_formation_left = 0.0
	_supply_notice_left = 0.0
	_hud_refresh_left = 0.0
	_hud.set_supply_notice("")
	_outcome = ""
	_round = Node3D.new()
	_round.name = "Round"
	add_child(_round)

	_difficulty = _hud.selected_difficulty()
	var start := _arena.position_on_ground(ALLY_START)
	_player = _add_tank("Player", start, 0.0, true, TANK_ROSTER[PLAYER_TANK], Tank.FRIENDLY_LAYER)
	_controlled = _player
	_ally_brains.append(TankAI.new(_player, _ai_grid, 0.85))
	_add_team_marker(_player, "坦克 1", Color("#9fd8c4")).hide()
	_effects = Effects.new()
	_round.add_child(_effects)
	_elapsed = 0.0
	_fire_released = false
	_look_yaw = 0.0
	_look_pitch = START_PITCH
	_view_kick = 0.0
	_player.point_gun(_look_yaw, _look_pitch, 1.0)
	_update_view(_player)
	_hud.set_controlled_unit(_controlled.display_name, _controlled.kind, _controlled.max_health)
	_waypoints.show_destination(Mission.SUPPLY_POINTS[0], true)
	_update_hud()


func _add_tank(tank_name: String, spawn: Vector3, heading: float, is_player: bool, profile: Dictionary, layer: int) -> Tank:
	var path: String = profile["model"]
	if not _tank_models.has(path):
		_tank_models[path] = load(path) as PackedScene
	var tank := Tank.new()
	tank.name = tank_name
	tank.position = spawn
	tank.rotation.y = heading
	tank.terrain_height = _arena.ground_height
	tank.configure(_tank_models[path], is_player, profile, layer)
	if layer == BattleUnit.HOSTILE_LAYER:
		Difficulty.apply_to_enemy(tank, _difficulty)
	_round.add_child(tank)
	tank.update_hull_pose(1.0)
	return tank


func _start_round() -> void:
	var lock_mouse := _phase != Phase.ACTIVE or _look_locked
	_reset_round()
	_spawn_allies()
	_update_formation()
	_resume_round(lock_mouse)
	_update_hud()


func _spawn_allies() -> void:
	var slots := Mission.ALLIED_FORCE
	var occupied := _living_friendlies()
	for index in range(slots.x - 1):
		var profile: Dictionary = TANK_ROSTER[index % TANK_ROSTER.size()].duplicate()
		profile["health"] = roundi(int(profile["health"]) * 1.56)
		var column := float(index % 6) - 2.5
		var preferred := Vector3(column * 13.0, 0.0, 33.0 - floorf(index / 6.0) * 8.0)
		var spawn := _ground_spawn(preferred, occupied, "tank")
		var tank := _add_tank("Ally%d" % (index + 1), spawn, 0.0, false, profile, Tank.FRIENDLY_LAYER)
		tank.reload_time = 2.0
		tank.reload_left = 0.55 + 0.12 * index
		_add_team_marker(tank, "坦克 %d" % (index + 2), Color("#9fd8c4"))
		_allies.append(tank)
		_ally_brains.append(TankAI.new(tank, _ai_grid, 0.76))
		occupied.append(tank)
	for index in slots.y:
		var column := float(index % 5) - 2.0
		var preferred := Vector3(column * 15.0 + 1.5, 0.0, 21.0 + floorf(index / 5.0) * 4.4)
		_allied_support.append(_add_support(true, "infantry", index, 1.46, preferred, occupied))
	for index in slots.z:
		var preferred := Vector3((index - 2.0) * 16.5, 9.0, 23.0 + (index % 2) * 5.0)
		_allied_support.append(_add_support(true, "aircraft", index, 1.15, preferred, occupied))


func _deploy_enemy_force(center: Vector2, slots: Vector3i, rank: int, boss_kind := "", landing := false) -> void:
	slots = Difficulty.enemy_force(slots, _difficulty)
	var occupied := _living_friendlies()
	occupied.append_array(_living_enemies())
	var attack_scale := 0.88 if landing else 1.0
	for slot in slots.x:
		var is_boss := not boss_kind.is_empty() and slot == floori(slots.x * 0.5)
		var base: Dictionary = TANK_ROSTER[ENEMY_TANK_ORDER[(slot + rank) % ENEMY_TANK_ORDER.size()]]
		var profile := base.duplicate()
		profile["health"] = roundi(int(base["health"]) * (0.82 + rank * 0.048))
		profile["attack"] = roundi(int(base["attack"]) * (0.76 + rank * 0.048) * attack_scale)
		if is_boss:
			var boss_profile: Dictionary = BOSS_PROFILES[boss_kind]
			profile = TANK_ROSTER[boss_profile["model"]].duplicate()
			profile["health"] = boss_profile["health"]
			profile["attack"] = boss_profile["attack"]
			profile["defense"] = 24
		var spread := 11.5 if landing else 9.4
		var offset := (float(slot) - float(slots.x - 1) * 0.5) * spread
		var preferred := Vector3(center.x + offset, 0.0, center.y + (slot % 2) * 4.0)
		var spawn := _ground_spawn(preferred, occupied, "tank")
		var tank := _add_tank("Boss_%s" % boss_kind if is_boss else "Enemy%d" % (_enemies.size() + 1),
			spawn, PI, false, profile, Tank.HOSTILE_LAYER)
		tank.reload_time = 2.48 - minf(0.30, rank * 0.04) if is_boss else 2.59 - rank * 0.082
		tank.reload_left = 0.75 + 0.20 * slot
		tank.max_speed = 4.9 + rank * 0.085
		if is_boss:
			var ability := BossAbility.new()
			_round.add_child(ability)
			ability.begin(boss_kind)
			_bosses[tank] = ability
		_add_team_marker(tank, "首领" if is_boss else "敌军坦克",
			Color("#ffc275") if is_boss else Color("#ffab93"))
		_enemies.append(tank)
		_enemy_brains.append(TankAI.new(tank, _ai_grid, 0.43 if is_boss else 1.16 - rank * 0.068))
		occupied.append(tank)
		if landing:
			_landing_members.append(tank)
	var strength := 0.84 + rank * 0.046
	if landing:
		strength = 0.89 + (rank - Mission.ROUTE_ENCOUNTERS.size()) * 0.042
	for index in slots.y:
		var offset := (float(index % 7) - 3.0) * (7.0 if landing else 5.6)
		var preferred := Vector3(center.x + offset, 0.0, center.y + 5.7 + floorf(index / 7.0) * 3.7)
		var unit := _add_support(false, "infantry", index, strength, preferred, occupied)
		_enemy_support.append(unit)
		if landing:
			_landing_members.append(unit)
	for index in slots.z:
		var offset := (index - (slots.z - 1.0) * 0.5) * 23.0 + 7.0
		var preferred := Vector3(center.x + offset, 9.5, center.y - 4.0 + index * 2.5)
		var unit := _add_support(false, "aircraft", index, strength, preferred, occupied)
		_enemy_support.append(unit)
		if landing:
			_landing_members.append(unit)
	_web_snapshot_delay = 0.0


func _add_support(friendly: bool, kind: String, index: int, strength: float, preferred: Vector3,
		occupied: Array[BattleUnit]) -> BattleUnit:
	var is_aircraft := kind == "aircraft"
	var spawn := _air_spawn(preferred, occupied) if is_aircraft else _ground_spawn(preferred, occupied, kind)
	var unit: BattleUnit = Aircraft.new() if is_aircraft else Infantry.new()
	unit.position = spawn
	unit.rotation.y = 0.0 if friendly else PI
	unit.terrain_height = _arena.ground_height
	var layer := BattleUnit.FRIENDLY_LAYER if friendly else BattleUnit.HOSTILE_LAYER
	if is_aircraft:
		var aircraft := unit as Aircraft
		var frame := Aircraft.Airframe.F35A if index % 2 == 0 else Aircraft.Airframe.PROPELLER
		var aircraft_name := "F-35A %d" if frame == Aircraft.Airframe.F35A else "战机 %d"
		aircraft.set_flight_bounds(_flight_bounds())
		aircraft.configure(layer, strength, aircraft_name % (index + 1), frame)
	else:
		(unit as Infantry).configure(layer, strength, "步兵 %d" % (index + 1))
	if not friendly:
		Difficulty.apply_to_enemy(unit, _difficulty)
	_round.add_child(unit)
	var color := Color("#9fd8c4") if friendly else Color("#ffab93")
	_add_team_marker(unit, unit.display_name, color, 1.8 if is_aircraft else 2.04)
	occupied.append(unit)
	return unit


func _flight_bounds() -> Rect2:
	return Rect2(-Arena.X_LIMIT + 2.0, Arena.SHORE_Z - 9.0, Arena.X_LIMIT * 2.0 - 4.0,
		Arena.START_Z - Arena.SHORE_Z + 7.0)


func _air_spawn(preferred: Vector3, occupied: Array[BattleUnit]) -> Vector3:
	var bounds := _flight_bounds()
	var candidate := preferred
	for offset in [0.0, -10.0, 10.0, -16.0, 16.0]:
		candidate.x = clampf(preferred.x + offset, bounds.position.x, bounds.end.x)
		candidate.z = clampf(preferred.z, bounds.position.y, bounds.end.y)
		candidate.y = maxf(0.0, _ground_point(candidate).y) + preferred.y
		var blocked := false
		for unit in occupied:
			if unit.kind == "aircraft" and candidate.distance_squared_to(unit.position) < 64.0:
				blocked = true
				break
		if not blocked:
			break
	return candidate


func _ground_point(at: Vector3) -> Vector3:
	return _arena.position_on_ground(Vector2(at.x, at.z))


func _ground_spawn(preferred: Vector3, occupied: Array[BattleUnit], kind: String) -> Vector3:
	var cell := Vector2i(roundi(preferred.x), roundi(preferred.z))
	cell = cell.clamp(_ai_grid.region.position, _ai_grid.region.end - Vector2i.ONE)
	if _spawn_is_clear(cell, occupied, kind):
		return _arena.position_on_ground(Vector2(cell))
	for radius in range(1, 24):
		for offset in range(-radius, radius + 1):
			for side in [-1, 1]:
				var row := cell + Vector2i(offset, radius * side)
				if _spawn_is_clear(row, occupied, kind):
					return _arena.position_on_ground(Vector2(row))
				var column := cell + Vector2i(radius * side, offset)
				if _spawn_is_clear(column, occupied, kind):
					return _arena.position_on_ground(Vector2(column))
	return _arena.position_on_ground(Vector2(cell))


func _spawn_is_clear(cell: Vector2i, occupied: Array[BattleUnit], kind: String) -> bool:
	if not _ai_grid.region.has_point(cell) or _ai_grid.is_point_solid(cell):
		return false
	for unit in occupied:
		if unit.kind == "aircraft":
			continue
		var other := Vector2(unit.position.x, unit.position.z)
		var clearance := 1.65
		if kind == "tank" or unit.kind == "tank":
			clearance = 6.0 if kind == unit.kind else 3.45
		if Vector2(cell).distance_squared_to(other) < clearance * clearance:
			return false
	return true


func _add_team_marker(unit: BattleUnit, title: String, color: Color, height := 3.18) -> Label3D:
	var marker := Label3D.new()
	marker.name = "TeamMarker"
	marker.text = title
	marker.font = DuelHUD.BUNDLED_FONT
	marker.font_size = 30
	marker.outline_size = 7
	marker.pixel_size = 0.0070 if unit.kind == "infantry" else 0.0084
	marker.visibility_range_end = 60.0 if title == "首领" or unit.kind == "aircraft" else 38.0
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


func _spawn_boss_reinforcements(call_index: int, boss: Tank) -> void:
	var occupied := _living_friendlies()
	occupied.append_array(_living_enemies())
	var side := -1.0 if call_index == 1 else 1.0
	var approach := boss.position + Vector3(side * 9.0, 0.0, -11.0)
	var spawn := _ground_spawn(approach, occupied, "tank")
	var profile: Dictionary = TANK_ROSTER[0].duplicate()
	profile["name"] = "援军坦克"
	profile["health"] = 64
	profile["attack"] = 24
	var tank := _add_tank("ReserveTank%d" % call_index, spawn, PI, false, profile, Tank.HOSTILE_LAYER)
	tank.reload_left = 1.2
	tank.reload_time = 2.6
	tank.max_speed = 5.5
	_add_team_marker(tank, "援军坦克", Color("#ffc275"))
	_enemies.append(tank)
	_enemy_brains.append(TankAI.new(tank, _ai_grid, 0.87))
	occupied.append(tank)
	_enemy_support.append(_add_support(false, "infantry", call_index - 1, 1.08,
		approach + Vector3(side * 4.0, 0.0, 5.0), occupied))
	_web_snapshot_delay = 0.0


func _boss_strike_target(boss: Tank, allies: Array[BattleUnit]) -> BattleUnit:
	const STRIKE_TARGET_LIMIT_SQUARED := 76.0 * 76.0
	if _controlled.health > 0 and _controlled.kind != "aircraft" \
			and boss.position.distance_squared_to(_controlled.position) <= STRIKE_TARGET_LIMIT_SQUARED:
		return _controlled
	var target: BattleUnit
	var nearest := STRIKE_TARGET_LIMIT_SQUARED
	for ally in allies:
		if ally.kind == "aircraft":
			continue
		var distance := boss.position.distance_squared_to(ally.position)
		if distance < nearest:
			target = ally
			nearest = distance
	return target


func _update_boss_abilities(allies: Array[BattleUnit], delta: float) -> void:
	for boss: Tank in _bosses:
		var ability: BossAbility = _bosses[boss]
		var target: BattleUnit = _boss_strike_target(boss, allies) if boss.name == "Boss_coast" else null
		ability.advance(delta, boss.health > 0, target, _ground_point,
			_fire_boss_burst.bind(boss), _spawn_boss_reinforcements.bind(boss), _release_boss_bomb)


func _active_boss() -> Tank:
	var focus: Tank
	var closest := 82.0 * 82.0
	for boss: Tank in _bosses:
		if boss.health <= 0 and _bosses[boss].snapshot().get("status") != "active":
			continue
		var distance := boss.position.distance_squared_to(_controlled.position)
		if distance < closest:
			focus = boss
			closest = distance
	return focus


func _fire_boss_burst(boss: Tank) -> void:
	_fire(boss, BURST_DAMAGE_FACTOR)


func _release_boss_bomb(origin: Vector3) -> void:
	_spawn_bomb(origin, BattleUnit.HOSTILE_LAYER, true)


func _deployed_enemies() -> Vector3i:
	var infantry := 0
	var aircraft := 0
	for unit in _enemy_support:
		if unit.kind == "infantry":
			infantry += 1
		else:
			aircraft += 1
	return Vector3i(_enemies.size(), infantry, aircraft)


func _count_kind(units: Array[BattleUnit], kind: String) -> int:
	var count := 0
	for unit in units:
		if unit.health > 0 and unit.kind == kind:
			count += 1
	return count


func _update_hud() -> void:
	var boss := _active_boss()
	_hud.update_boss_ability(_bosses[boss].snapshot() if boss != null else {}, boss != null and boss.health > 0)
	_hud.set_mission_forces(Mission.ALLIED_FORCE, _deployed_enemies())
	_hud.update_battle(_controlled.health, _controlled.reload_fraction(), _elapsed,
		_living_units(_allies).size() + int(_player.health > 0), _living_units(_enemies).size(),
		boss.health if boss != null else 0, boss.max_health if boss != null else 0)
	_hud.set_support_counts(_count_kind(_allied_support, "infantry"), _count_kind(_enemy_support, "infantry"),
		_count_kind(_allied_support, "aircraft"), _count_kind(_enemy_support, "aircraft"))
	_update_mission_hud()
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


func _update_mission_hud() -> void:
	var region: String = Mission.REGIONS[_region]
	var at := Vector2(_controlled.position.x, _controlled.position.z)
	if _mission.defending:
		var offset := Mission.DEFENSE_POINT - at
		var away := offset.length() > Mission.DEFENSE_RADIUS + 7.0
		_waypoints.show_destination(Mission.DEFENSE_POINT, away)
		if away:
			_set_objective_bearing(offset)
		else:
			_hud.set_mission_bearing(NAN)
		region = Mission.REGIONS[2]
		if _mission.landing_delay >= 0.0:
			var preparing := _mission.landing_wave == 0
			var message := "准备防守，首批登陆部队即将到达" if preparing else "下一批登陆部队即将到达"
			var total := Mission.LANDING_PREP if preparing else Mission.LANDING_DELAY
			_hud.set_mission(region, message, -1.0, _mission.landing_delay, total)
		else:
			_hud.set_mission(region, "阻击登陆部队 %d / %d" % [_mission.landing_wave, Mission.LANDING_WAVES.size()],
				offset.length() if away else -1.0)
		return

	var destination := _mission.next_destination(at.y)
	var objective := "前往滩头防线"
	var supply_index: int = Mission.SUPPLY_POINTS.find(destination)
	if supply_index >= 0:
		objective = "向补给点 %d 推进" % (supply_index + 1)
	var offset := destination - at
	_hud.set_mission(region, objective, offset.length())
	_set_objective_bearing(offset)
	_waypoints.show_destination(destination, true)


func _set_objective_bearing(offset: Vector2) -> void:
	var bearing := Tank.yaw_towards(Vector3(offset.x, 0.0, offset.y))
	_hud.set_mission_bearing(-angle_difference(_look_yaw, bearing))


func _show_selection() -> void:
	_phase = Phase.INTRO
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
	var selecting_unit := _phase == Phase.TAKEOVER or _phase == Phase.SWITCH
	if _phase == Phase.INTRO and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3:
		_hud.select_difficulty(event.physical_keycode - KEY_1)
		_start_round()
	elif selecting_unit and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_7:
		_takeover_unit(_hud.takeover_index_for_key(event.physical_keycode - KEY_1 + 1))
	elif selecting_unit and event.physical_keycode == KEY_PAGEUP:
		_hud.turn_takeover_page(-1)
		_web_snapshot_delay = 0.0
	elif selecting_unit and event.physical_keycode == KEY_PAGEDOWN:
		_hud.turn_takeover_page(1)
		_web_snapshot_delay = 0.0
	elif event.physical_keycode == KEY_Q:
		if _phase == Phase.ACTIVE:
			_show_takeover(true)
		elif _phase == Phase.SWITCH:
			_cancel_switch()
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
			_start_round()
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

	_formation_left -= delta
	if _formation_left <= 0.0:
		_formation_left = FORMATION_REFRESH
		_update_formation()

	var allies_alive := _living_friendlies()
	_update_route(allies_alive, delta)
	var enemies_alive := _living_enemies()
	_update_ai_team(_ally_brains, enemies_alive, delta)
	_update_ai_team(_enemy_brains, allies_alive, delta)
	_update_support_team(_allied_support, enemies_alive, delta)
	_update_support_team(_enemy_support, allies_alive, delta)
	_advance_bombs(delta)
	_advance_shells(delta)
	_update_boss_abilities(_living_friendlies(), delta)
	_check_mission_outcome()
	_hud_refresh_left -= delta
	if _hud_refresh_left <= 0.0 and _phase == Phase.ACTIVE:
		_hud_refresh_left = 0.10
		_update_hud()


func _route_position(allies: Array[BattleUnit]) -> Vector2:
	var controlled_at := Vector2(_controlled.position.x, _controlled.position.z)
	if _controlled.kind != "aircraft" and _controlled.health > 0:
		return controlled_at
	var lead: BattleUnit
	for unit in allies:
		if unit.kind != "aircraft" and (lead == null or unit.position.z < lead.position.z):
			lead = unit
	return Vector2(lead.position.x, lead.position.z) if lead != null else controlled_at


func _update_formation() -> void:
	var anchor := Vector2(_controlled.position.x, _controlled.position.z)
	if _mission.defending:
		anchor = Mission.DEFENSE_POINT
	elif _controlled.kind == "aircraft":
		var column := _route_position(_living_friendlies())
		anchor.y = clampf(anchor.y, column.y - 23.0, column.y + 12.0)
		anchor.x = lerpf(anchor.x, _arena.road_center(anchor.y), 0.45)
	else:
		anchor.x = lerpf(anchor.x, _arena.road_center(anchor.y), 0.18)

	for index in _ally_brains.size():
		var tank := _ally_brains[index].tank
		if tank.health > 0:
			var offset := Vector2((float(index % 5) - 2.0) * 10.3, 5.0 + floorf(index / 5.0) * 10.5)
			tank.formation_goal = _formation_slot(anchor + offset)
	for index in _allied_support.size():
		var unit := _allied_support[index]
		if unit.health <= 0:
			continue
		if unit.kind == "aircraft":
			var wing := index - Mission.ALLIED_FORCE.y
			var offset := Vector2((wing - 2.0) * 17.5, -12.0 - (wing % 2) * 8.5)
			unit.formation_goal = _arena.position_on_ground(anchor + offset)
		else:
			var offset := Vector2((float(index % 7) - 3.0) * 7.4 + 3.2, -4.5 + floorf(index / 7.0) * 8.5)
			unit.formation_goal = _formation_slot(anchor + offset)


func _formation_slot(at: Vector2) -> Vector3:
	var cell := Vector2i(at.round()).clamp(_ai_grid.region.position, _ai_grid.region.end - Vector2i.ONE)
	if not _ai_grid.is_point_solid(cell):
		return _arena.position_on_ground(Vector2(cell))
	var best := cell
	var distance := INF
	for width in range(1, 9):
		for z in range(-width, width + 1):
			for x in [-width, width]:
				var candidate := cell + Vector2i(x, z)
				var space := Vector2(candidate).distance_squared_to(at)
				if space < distance and _ai_grid.region.has_point(candidate) and not _ai_grid.is_point_solid(candidate):
					best = candidate
					distance = space
		for x in range(-width + 1, width):
			for z in [-width, width]:
				var candidate := cell + Vector2i(x, z)
				var space := Vector2(candidate).distance_squared_to(at)
				if space < distance and _ai_grid.region.has_point(candidate) and not _ai_grid.is_point_solid(candidate):
					best = candidate
					distance = space
		if distance < INF:
			break
	return _arena.position_on_ground(Vector2(best))


func _update_route(allies: Array[BattleUnit], delta: float) -> void:
	var column := _route_position(allies)
	var region := _mission.region_at(column.y)
	if region != _region:
		_region = region
		_set_stage_lighting()
	var encounter := _mission.next_encounter(column.y)
	if not encounter.is_empty():
		_deploy_enemy_force(encounter["center"], encounter["force"], _mission.encounter_count - 1,
			encounter.get("boss", ""))

	var points: Array[Vector2] = [column]
	if _controlled.kind == "aircraft":
		for unit in allies:
			if unit.kind != "aircraft":
				points.append(Vector2(unit.position.x, unit.position.z))
	for point in points:
		if _mission.take_supply(point) >= 0:
			_resupply_survivors(allies)
		if _mission.reach_defense(point):
			_formation_left = 0.0
			_resupply_survivors(allies, "滩头补给完成，准备阻击登陆")
			_web_snapshot_delay = 0.0

	if _supply_notice_left > 0.0:
		_supply_notice_left = maxf(0.0, _supply_notice_left - delta)
		if _supply_notice_left == 0.0:
			_hud.set_supply_notice("")
	if _mission.advance_landing(delta, _living_units(_landing_members).size()):
		var wave := _mission.landing_wave
		var boss_kind := "coast" if wave == Mission.LANDING_WAVES.size() else ""
		_deploy_enemy_force(Vector2(0, Mission.LANDING_Z), Mission.LANDING_WAVES[wave - 1],
			Mission.ROUTE_ENCOUNTERS.size() + wave - 1, boss_kind, true)


func _resupply_survivors(allies: Array[BattleUnit], message := "补给完成，幸存友军已恢复满生命") -> void:
	for ally in allies:
		if ally.health > 0:
			ally.health = ally.max_health
	_hud.set_supply_notice(message)
	_supply_notice_left = SUPPLY_NOTICE_SECONDS
	_web_snapshot_delay = 0.0


func _check_mission_outcome() -> void:
	if _living_friendlies().is_empty():
		_finish_round("loss")
	elif _mission.beach_held(_living_units(_landing_members).size()):
		_finish_round("win")
	elif _controlled.health == 0:
		_show_takeover()


func _clear_shells() -> void:
	for shell in _shells:
		shell.queue_free()
	_shells.clear()


func _can_drop_bomb(aircraft: Aircraft) -> bool:
	return aircraft != null and aircraft.health > 0 and _phase == Phase.ACTIVE \
		and aircraft.bomb_cooldown_left <= 0.0


func _drop_bomb() -> void:
	_launch_bomb(_controlled as Aircraft)


func _launch_bomb(aircraft: Aircraft) -> void:
	if not _can_drop_bomb(aircraft):
		return
	_spawn_bomb(aircraft.bomb_origin(), aircraft.collision_layer)
	aircraft.bomb_cooldown_left = BOMB_COOLDOWN


func _spawn_bomb(origin: Vector3, team: int, airstrike := false) -> void:
	var bomb := Bomb.new()
	bomb.position = _round.to_local(origin)
	bomb.team = team
	bomb.is_airstrike = airstrike
	_round.add_child(bomb)
	_bombs.append(bomb)
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
			_explode_bomb(hit["position"], bomb.team, bomb.is_airstrike)
		bomb.queue_free()


func _explode_bomb(at: Vector3, team: int, airstrike := false) -> void:
	_effects.bomb_blast(at)
	var radius := BossAbility.STRIKE_RADIUS if airstrike else BOMB_RADIUS
	var attack_level := _difficulty if team == BattleUnit.HOSTILE_LAYER else Difficulty.DEFAULT
	var building_damage := AIRSTRIKE_BUILDING_DAMAGE if airstrike else BOMB_BUILDING_DAMAGE
	_arena.damage_buildings_in_area(at, radius, Difficulty.enemy_attack(building_damage, attack_level))
	var base_damage := Difficulty.enemy_attack(AIRSTRIKE_UNIT_DAMAGE if airstrike else BOMB_UNIT_DAMAGE, attack_level)
	var targets := _living_enemies() if team == BattleUnit.FRIENDLY_LAYER else _living_friendlies()
	for unit in targets:
		if airstrike and unit.kind == "aircraft":
			continue
		var distance := at.distance_to(unit.target_point())
		if distance < radius:
			var damage := roundi(base_damage * lerpf(1.0, 0.28, distance / radius))
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

	if not Input.is_action_pressed("tank_fire"):
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
			if _bosses.has(brain.tank) and not _bosses[brain.tank].allow_cannon():
				brain.tank.reload_left = 0.18
				continue
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


func _fire(tank: Tank, damage_scale := 1.0) -> void:
	tank.reload_left = tank.reload_time
	var damage := roundi(tank.attack * damage_scale)
	var muzzle := tank.muzzle_position()
	var direction := tank.muzzle_direction()
	var pivot := tank.gun_pivot_position()
	if tank == _controlled:
		_view_kick = 0.115
	var obstruction := _cast_ray(pivot, muzzle, Tank.BATTLE_MASK, tank.get_rid())
	if not obstruction.is_empty():
		_register_impact(obstruction, damage, tank.collision_layer, true)
		return

	_effects.muzzle_flash(muzzle, direction)
	if tank == _controlled:
		direction = _sight_shot_direction(tank, muzzle, direction, SHELL_SPEED * SHELL_LIFETIME)
	var shell := Shell.new()
	shell.direction = direction
	shell.shooter_rid = tank.get_rid()
	shell.shooter_team = tank.collision_layer
	shell.damage = damage
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
	for ability: BossAbility in _bosses.values():
		ability.cancel()
	for bomb in _bombs:
		bomb.queue_free()
	_bombs.clear()
	_set_view_lock(false)
	_hud.show_result(outcome)
