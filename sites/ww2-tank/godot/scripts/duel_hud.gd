extends CanvasLayer

signal start_requested
signal restart_requested
signal resume_requested
signal selection_requested
signal takeover_requested(index: int)
signal switch_cancelled

const INK := Color("18201b")
const SURFACE := Color("202920f5")
const LINE := Color("636956")
const PAPER := Color("f3e5c8")
const SUBTLE := Color("bac0a7")
const BRASS := Color("e8bc70")
const ALLIED := Color("9fd8c4")
const OPPONENT := Color("e59a7e")
const WARNING := Color("ffc275")
const BUNDLED_FONT := preload("res://assets/fonts/StonewallSans.otf")
const DifficultySelection := preload("res://scripts/difficulty_selection.gd")
const TANK_CONTROLS := "WASD 驾驶   鼠标瞄准   空格开火   Q 切换   Tab 鼠标"
const INFANTRY_CONTROLS := "WASD 步行   鼠标瞄准   空格开火   Q 切换   Tab 鼠标"
const AIRCRAFT_CONTROLS := "WASD 飞行   鼠标调航向   空格开火   B 投弹   Q 切换"
const TAKEOVER_PAGE_SIZE := 7
const BOSS_ABILITY_NAMES := {
	"burst": "火炮连发",
	"reinforcements": "呼叫援军",
	"airstrike": "呼叫空袭",
}

class AimReticle extends Control:
	var aligned := false

	func _draw() -> void:
		var tint := Color("f4d69c") if aligned else Color("fff2d4a8")
		var outline := Color("171e18d9")
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 32, outline, 3.0, true)
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 32, tint, 1.25, true)
		for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(axis * 14.0, axis * 20.0, outline, 4.0, true)
			draw_line(axis * 14.0, axis * 20.0, tint, 2.0, true)
		if aligned:
			draw_circle(Vector2.ZERO, 2.0, tint)

class MissionBearing extends Control:
	var angle := 0.0

	func _draw() -> void:
		var center := size * 0.5
		var points := PackedVector2Array()
		for corner: Vector2 in [Vector2(0, -7), Vector2(5, 5), Vector2(0, 3), Vector2(-5, 5)]:
			points.append(center + corner.rotated(angle))
		draw_colored_polygon(points, BRASS)

var _root: Control
var _board: Control
var _menu: ColorRect
var _menu_card: PanelContainer
var _takeover_card: PanelContainer
var _takeover_heading: Label
var _takeover_description: Label
var _takeover_buttons: Array[Button] = []
var _takeover_cancel: Button
var _takeover_nav: HBoxContainer
var _takeover_prev: Button
var _takeover_next: Button
var _takeover_page_label: Label
var _takeover_candidates: Array[Dictionary] = []
var _takeover_page := 0
var _selection: DifficultySelection
var _heading: Label
var _description: Label
var _primary: Button
var _secondary: Button
var _reticle: AimReticle
var _player_title: Label
var _player_health: ProgressBar
var _player_number: Label
var _region_label: Label
var _objective_title: Label
var _mission_bearing: MissionBearing
var _mission_measure: Label
var _mission_progress: ProgressBar
var _supply_panel: PanelContainer
var _supply_notice: Label
var _ally_count: Label
var _enemy_count: Label
var _allied_support: Label
var _enemy_support: Label
var _boss_panel: PanelContainer
var _boss_health: ProgressBar
var _boss_number: Label
var _boss_ability_panel: PanelContainer
var _boss_ability_title: Label
var _boss_ability_status: Label
var _boss_ability_style: StyleBoxFlat
var _building_panel: PanelContainer
var _building_title: Label
var _building_health: ProgressBar
var _building_number: Label
var _bomb_panel: PanelContainer
var _bomb_status: Label
var _clock: Label
var _mouse_status: Label
var _controls: Label
var _reload: ProgressBar
var _reload_label: Label
var _region_name := "平原"
var _allied_slots := Vector3i(10, 20, 5)
var _enemy_slots := Vector3i.ZERO
var _controlled_kind := "tank"
var _player_down := false
var _screen := "intro"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui_theme := Theme.new()
	ui_theme.default_font = _interface_font()
	_root.theme = ui_theme
	_selection = DifficultySelection.new()
	_build_board()
	_build_menu()
	show_intro()


func show_intro() -> void:
	_screen = "intro"
	_board.hide()
	_reticle.hide()
	_building_panel.hide()
	_bomb_panel.hide()
	_boss_ability_panel.hide()
	_supply_panel.hide()
	_menu_card.hide()
	_takeover_card.hide()
	_selection.show()
	_menu.show()


func selected_difficulty() -> int:
	return _selection.selection()


func select_difficulty(index: int) -> void:
	_selection.select(index)


func difficulty_choice_rects() -> Array[Rect2]:
	return _selection.choice_rects()


func set_controlled_unit(title: String, kind: String, max_health: int) -> void:
	_controlled_kind = kind
	_player_title.text = "玩家 · " + title
	_player_health.max_value = max_health
	if kind != "aircraft":
		_bomb_panel.hide()
	match kind:
		"infantry":
			_controls.text = INFANTRY_CONTROLS
		"aircraft":
			_controls.text = AIRCRAFT_CONTROLS
		_:
			_controls.text = TANK_CONTROLS


func set_support_counts(allied_infantry: int, enemy_infantry: int, allied_aircraft: int, enemy_aircraft: int) -> void:
	_allied_support.text = "步兵 %d / %d\n飞机 %d / %d" % [allied_infantry, _allied_slots.y, allied_aircraft, _allied_slots.z]
	_enemy_support.text = "步兵 %d / %d\n飞机 %d / %d" % [enemy_infantry, _enemy_slots.y,
		enemy_aircraft, _enemy_slots.z]


func set_mission_forces(allied_slots: Vector3i, enemy_slots: Vector3i) -> void:
	_allied_slots = allied_slots
	_enemy_slots = enemy_slots


func set_mission(region: String, objective: String, distance_m := -1.0, defense_left := -1.0, defense_total := 0.0) -> void:
	_region_name = region
	_region_label.text = "%s · %s" % [region, _selection.selection_label()]
	_objective_title.text = objective
	if defense_left >= 0.0:
		_mission_measure.text = "下一波 %d 秒" % ceili(defense_left)
	elif distance_m >= 0.0:
		_mission_measure.text = "距离 %d 米" % ceili(distance_m)
	else:
		_mission_measure.text = ""
	_mission_measure.visible = not _mission_measure.text.is_empty()
	_mission_progress.visible = defense_left >= 0.0 and defense_total > 0.0
	if _mission_progress.visible:
		_mission_progress.value = clampf(1.0 - defense_left / defense_total, 0.0, 1.0)


func set_mission_bearing(angle: float) -> void:
	_mission_bearing.visible = is_finite(angle)
	if _mission_bearing.visible:
		_mission_bearing.angle = angle
		_mission_bearing.queue_redraw()


func set_supply_notice(message: String) -> void:
	_supply_notice.text = message
	_supply_panel.visible = _screen == "active" and not message.is_empty()


func show_active() -> void:
	_screen = "active"
	_takeover_card.hide()
	_menu.hide()
	_board.show()
	_reticle.visible = not _player_down


func show_pause() -> void:
	_open_menu("pause", "战役暂停", "可以继续当前战役，或从平原重新出发。", "继续战役", true)


func show_takeover(candidates: Array[Dictionary], voluntary := false) -> void:
	_screen = "takeover"
	_reticle.hide()
	_building_panel.hide()
	_bomb_panel.hide()
	_boss_ability_panel.hide()
	_supply_panel.hide()
	_selection.hide()
	_menu_card.hide()
	_takeover_heading.text = "切换操控单位" if voluntary else "接管友军"
	_takeover_description.text = (
		"点击或按 1–7 选择本页友军。按 Q 或 Esc 返回。" if voluntary
		else "当前单位已失去战斗能力。点击或按 1–7 接管本页友军。"
	)
	_takeover_candidates = candidates
	_takeover_page = 0
	_takeover_cancel.visible = voluntary
	_update_takeover_page()
	_takeover_card.show()
	_menu.show()


func _update_takeover_page() -> void:
	var pages := maxi(1, ceili(float(_takeover_candidates.size()) / TAKEOVER_PAGE_SIZE))
	for slot in TAKEOVER_PAGE_SIZE:
		var button := _takeover_buttons[slot]
		var index := takeover_index_for_key(slot + 1)
		button.visible = index >= 0
		if index < 0:
			continue
		var candidate := _takeover_candidates[index]
		button.text = "%d    %s    ·    %s    ·    生命 %d / %d" % [
			slot + 1, candidate["name"], _kind_label(candidate["kind"]), candidate["health"], candidate["max_health"],
		]
	_takeover_nav.visible = pages > 1
	_takeover_prev.disabled = _takeover_page == 0
	_takeover_next.disabled = _takeover_page + 1 >= pages
	_takeover_page_label.text = "第 %d / %d 页 · %d 个单位" % [_takeover_page + 1, pages, _takeover_candidates.size()]
	var half_height := (_takeover_card.get_combined_minimum_size().y + 20.0) * 0.5
	_takeover_card.offset_top = -half_height
	_takeover_card.offset_bottom = half_height


func turn_takeover_page(delta: int) -> void:
	if _screen != "takeover":
		return
	var last_page := maxi(0, ceili(float(_takeover_candidates.size()) / TAKEOVER_PAGE_SIZE) - 1)
	var page := clampi(_takeover_page + delta, 0, last_page)
	if page == _takeover_page:
		return
	_takeover_page = page
	_update_takeover_page()


func takeover_index_for_key(number: int) -> int:
	var index := _takeover_page * TAKEOVER_PAGE_SIZE + number - 1
	return index if number >= 1 and number <= TAKEOVER_PAGE_SIZE and index < _takeover_candidates.size() else -1


func takeover_visible_count() -> int:
	return clampi(_takeover_candidates.size() - _takeover_page * TAKEOVER_PAGE_SIZE, 0, TAKEOVER_PAGE_SIZE)


func takeover_page_button_rects() -> Array[Rect2]:
	if not _takeover_nav.is_visible_in_tree():
		return []
	return [_takeover_prev.get_global_rect(), _takeover_next.get_global_rect()]


func _select_takeover_slot(number: int) -> void:
	var index := takeover_index_for_key(number)
	if index >= 0:
		takeover_requested.emit(index)


func show_result(outcome: String) -> void:
	match outcome:
		"win":
			_open_menu("result", "任务成功", "我军守住了海滩，已击退全部登陆部队。", "重开战役")
		"loss":
			_open_menu("result", "任务失败", "%s · 我军已全灭，未能守住海滩。" % _region_name, "重开战役")
		_:
			_open_menu("result", "任务失败", "双方最后的单位同时倒下，滩头防线失守。", "重开战役")


func update_battle(
	player_health: int, reload_fraction: float, seconds: float,
	allied_tanks: int, enemy_tanks: int, boss_health: int = 0, boss_max_health: int = 0
) -> void:
	_player_health.value = player_health
	_player_number.text = "%d / %d" % [player_health, int(_player_health.max_value)]
	_ally_count.text = "坦克 %d / %d" % [allied_tanks, _allied_slots.x]
	_enemy_count.text = "坦克 %d / %d" % [enemy_tanks, _enemy_slots.x]
	var elapsed := maxi(0, floori(seconds))
	_clock.text = "%02d:%02d" % [floori(elapsed / 60.0), elapsed % 60]
	_boss_panel.visible = boss_health > 0 and boss_max_health > 0
	if _boss_panel.visible:
		_boss_health.max_value = boss_max_health
		_boss_health.value = boss_health
		_boss_number.text = "%d / %d" % [boss_health, boss_max_health]
	_player_down = player_health <= 0
	if _player_down:
		_bomb_panel.hide()
	_reticle.visible = not _player_down and _screen == "active"
	_reload.visible = not _player_down
	_reload_label.visible = not _player_down
	_reload.value = clampf(reload_fraction, 0.0, 1.0)
	var ready := reload_fraction >= 0.999
	_reload_label.text = "可开火" if ready else "装填中"
	_reload_label.modulate = Color.WHITE if ready else SUBTLE


func update_boss_ability(info: Dictionary, boss_alive := true) -> void:
	var skill_id := str(info.get("id", ""))
	var title: String = BOSS_ABILITY_NAMES.get(skill_id, "")
	var status := str(info.get("status", ""))
	var incoming_strike := skill_id == "airstrike" and status == "active"
	_boss_ability_panel.visible = _screen == "active" and not title.is_empty() and (boss_alive or incoming_strike)
	if not _boss_ability_panel.visible:
		return
	_boss_ability_title.text = title
	var seconds := float(info.get("seconds_remaining", 0.0))
	var alert := status == "warning" or status == "active"
	_boss_ability_status.modulate = WARNING if alert else Color.WHITE
	_boss_ability_style.border_color = OPPONENT if alert else LINE
	match status:
		"warning":
			match skill_id:
				"airstrike":
					_boss_ability_status.text = "撤出标记区 · %.1f 秒" % seconds
				"reinforcements":
					_boss_ability_status.text = "援军即将抵达 · %.1f 秒" % seconds
				_:
					_boss_ability_status.text = "即将连发 · %.1f 秒" % seconds
		"active":
			_boss_ability_status.text = "空袭进行中" if skill_id == "airstrike" else "连发中"
		"cooldown":
			_boss_ability_status.text = "冷却 %d 秒" % ceili(seconds)
		"spent":
			_boss_ability_status.text = "援军已用尽"
		"ready":
			_boss_ability_status.text = "随时发动"
		_:
			_boss_ability_status.text = "准备中"


func set_aim(active_alignment: bool) -> void:
	if _reticle.aligned != active_alignment:
		_reticle.aligned = active_alignment
		_reticle.queue_redraw()


func set_building_target(info: Dictionary) -> void:
	var health := int(info.get("health", 0))
	var maximum := int(info.get("max_health", 0))
	_building_panel.visible = _screen == "active" and health > 0 and maximum > 0
	if _building_panel.visible:
		_building_title.text = str(info.get("name", "建筑耐久"))
		_building_health.max_value = maximum
		_building_health.value = health
		_building_number.text = "%d / %d" % [health, maximum]


func set_bomb_status(visible: bool, seconds_remaining: float, available: bool) -> void:
	_bomb_panel.visible = visible and _controlled_kind == "aircraft" and _screen == "active" and not _player_down
	if not _bomb_panel.visible:
		return
	if available:
		_bomb_status.text = "可投弹"
	elif seconds_remaining > 0.0:
		_bomb_status.text = "冷却 %d 秒" % ceili(seconds_remaining)
	else:
		_bomb_status.text = "暂不可投弹"
	_bomb_status.modulate = ALLIED if available else Color.WHITE


func set_mouse_locked(look_locked: bool) -> void:
	_mouse_status.text = "鼠标已锁定" if look_locked else "鼠标已释放"


func menu_button_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _screen == "intro":
		return difficulty_choice_rects()
	if _screen == "takeover":
		for button in _takeover_buttons:
			if button.is_visible_in_tree() and not button.disabled:
				rects.append(button.get_global_rect())
		if _takeover_cancel.is_visible_in_tree() and not _takeover_cancel.disabled:
			rects.append(_takeover_cancel.get_global_rect())
		return rects
	for button in [_primary, _secondary]:
		if button.is_visible_in_tree() and not button.disabled:
			rects.append(button.get_global_rect())
	return rects


func _build_board() -> void:
	_board = Control.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var player_panel := _panel(_board, Control.PRESET_TOP_LEFT, Rect2(30, 24, 277, 74))
	_player_number = _label("100 / 100", 16, PAPER)
	_player_health = _bar(100.0, ALLIED)
	_player_title = _health_display(player_panel, "玩家坦克", ALLIED, _player_number, _player_health)
	_build_mission_panels()
	_build_battle_footer()
	_reticle = AimReticle.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_reticle)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _build_mission_panels() -> void:
	var center := _panel(_board, Control.PRESET_CENTER_TOP, Rect2(-188, 24, 376, 105))
	var center_stack := VBoxContainer.new()
	center_stack.add_theme_constant_override("separation", 2)
	center.add_child(center_stack)
	_region_label = _label("", 16, PAPER)
	_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_stack.add_child(_region_label)
	_objective_title = _label("", 21, BRASS)
	_objective_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	center_stack.add_child(_objective_title)
	var mission_details := HBoxContainer.new()
	mission_details.add_theme_constant_override("separation", 12)
	mission_details.alignment = BoxContainer.ALIGNMENT_CENTER
	center_stack.add_child(mission_details)
	_clock = _label("00:00", 14, PAPER)
	mission_details.add_child(_clock)
	var routing := HBoxContainer.new()
	routing.add_theme_constant_override("separation", 3)
	mission_details.add_child(routing)
	_mission_bearing = MissionBearing.new()
	_mission_bearing.custom_minimum_size = Vector2(17, 18)
	_mission_bearing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	routing.add_child(_mission_bearing)
	_mission_measure = _label("", 14, BRASS)
	routing.add_child(_mission_measure)
	_mission_progress = _bar(1.0, ALLIED)
	_mission_progress.custom_minimum_size.y = 4.0
	center_stack.add_child(_mission_progress)
	_mouse_status = _label("", 14, SUBTLE)
	mission_details.add_child(_mouse_status)
	set_mouse_locked(false)
	set_mission("平原", "沿路线推进")
	set_mission_bearing(NAN)

	var unit_panel := _panel(_board, Control.PRESET_TOP_RIGHT, Rect2(-307, 24, 277, 124))
	var unit_counts := GridContainer.new()
	unit_counts.columns = 2
	unit_counts.add_theme_constant_override("h_separation", 16)
	unit_counts.add_theme_constant_override("v_separation", 3)
	unit_panel.add_child(unit_counts)
	var allies := _label("友军", 17, ALLIED)
	allies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_counts.add_child(allies)
	unit_counts.add_child(_label("敌军", 17, OPPONENT))
	_ally_count = _label("", 16, PAPER)
	_ally_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_counts.add_child(_ally_count)
	_enemy_count = _label("", 16, PAPER)
	_enemy_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_counts.add_child(_enemy_count)
	_allied_support = _label("", 16, SUBTLE)
	unit_counts.add_child(_allied_support)
	_enemy_support = _label("", 16, SUBTLE)
	unit_counts.add_child(_enemy_support)
	set_support_counts(_allied_slots.y, 0, _allied_slots.z, 0)

	_boss_panel = _panel(_board, Control.PRESET_CENTER_TOP, Rect2(-185, 137, 370, 66))
	_boss_number = _label("", 16, PAPER)
	_boss_health = _bar(1.0, OPPONENT)
	_health_display(_boss_panel, "敌军首领", OPPONENT, _boss_number, _boss_health)
	_boss_panel.hide()
	_boss_ability_panel = _panel(_board, Control.PRESET_CENTER_TOP, Rect2(-185, 209, 370, 46))
	_boss_ability_style = _style(SURFACE, LINE, 8, 9.0)
	_boss_ability_panel.add_theme_stylebox_override("panel", _boss_ability_style)
	var ability_row := HBoxContainer.new()
	ability_row.add_theme_constant_override("separation", 12)
	_boss_ability_panel.add_child(ability_row)
	_boss_ability_title = _label("", 17, OPPONENT)
	_boss_ability_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_row.add_child(_boss_ability_title)
	_boss_ability_status = _label("", 16, PAPER)
	ability_row.add_child(_boss_ability_status)
	_boss_ability_panel.hide()
	_supply_panel = _panel(_board, Control.PRESET_CENTER_TOP, Rect2(-198, 264, 396, 46))
	_supply_panel.add_theme_stylebox_override("panel", _style(SURFACE, ALLIED, 8, 9.0))
	_supply_notice = _label("", 16, ALLIED)
	_supply_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_supply_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_supply_panel.add_child(_supply_notice)
	_supply_panel.hide()


func _build_battle_footer() -> void:
	_building_panel = _panel(_board, Control.PRESET_CENTER_BOTTOM, Rect2(-158, -151, 316, 67))
	_building_number = _label("", 16, PAPER)
	_building_health = _bar(1.0, BRASS)
	_building_title = _health_display(_building_panel, "建筑耐久", BRASS, _building_number, _building_health)
	_building_panel.hide()
	_bomb_panel = _panel(_board, Control.PRESET_BOTTOM_RIGHT, Rect2(-275, -72, 245, 52))
	var bomb_row := HBoxContainer.new()
	_bomb_panel.add_child(bomb_row)
	var bomb_title := _label("B  投弹", 17, BRASS)
	bomb_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bomb_row.add_child(bomb_title)
	_bomb_status = _label("", 15, PAPER)
	bomb_row.add_child(_bomb_status)
	_bomb_panel.hide()
	var footer := _panel(_board, Control.PRESET_CENTER_BOTTOM, Rect2(-307, -72, 614, 52))
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 17)
	footer.add_child(footer_row)
	_controls = _label(TANK_CONTROLS, 15, SUBTLE)
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(_controls)
	_reload_label = _label("可开火", 15, BRASS)
	_reload_label.custom_minimum_size.x = 53.0
	footer_row.add_child(_reload_label)
	_reload = _bar(1.0, BRASS)
	_reload.custom_minimum_size.x = 83.0
	_reload.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_row.add_child(_reload)


func _build_menu() -> void:
	_menu = ColorRect.new()
	_menu.color = Color("1116109e")
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_card = _panel(_menu, Control.PRESET_CENTER_LEFT, Rect2(48, -168, 424, 336))
	var surface := _style(SURFACE, LINE, 12)
	surface.content_margin_left = 28.0
	surface.content_margin_right = 28.0
	surface.content_margin_top = 25.0
	surface.content_margin_bottom = 25.0
	_menu_card.add_theme_stylebox_override("panel", surface)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	_menu_card.add_child(stack)
	var accent := ColorRect.new()
	accent.color = BRASS
	accent.custom_minimum_size = Vector2(41, 3)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(accent)
	_heading = _label("", 46, PAPER)
	stack.add_child(_heading)
	_description = _label("", 17, SUBTLE)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_description)
	var keys := _label("WASD 移动　 鼠标瞄准　 空格开火\nQ 切换单位　 B 飞机投弹　 Tab 鼠标\nEsc 暂停　 R 重开战役", 15, SUBTLE)
	keys.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keys.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(keys)
	_primary = _button(true)
	_primary.pressed.connect(_on_primary)
	stack.add_child(_primary)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 9)
	stack.add_child(actions)
	_secondary = _button(false)
	_secondary.text = "重开战役"
	_secondary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary.pressed.connect(func() -> void: restart_requested.emit())
	actions.add_child(_secondary)
	var selection_button := _button(false)
	selection_button.text = "更换难度"
	selection_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_button.pressed.connect(func() -> void: selection_requested.emit())
	actions.add_child(selection_button)

	_selection.confirmed.connect(func() -> void: start_requested.emit())
	_menu.add_child(_selection)
	_build_takeover_menu()


func _build_takeover_menu() -> void:
	_takeover_card = _panel(_menu, Control.PRESET_CENTER, Rect2(-284, -263, 568, 526))
	_takeover_card.add_theme_stylebox_override("panel", _style(SURFACE, LINE, 12, 24.0))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	_takeover_card.add_child(stack)
	_takeover_heading = _label("", 37, PAPER)
	stack.add_child(_takeover_heading)
	_takeover_description = _label("", 16, SUBTLE)
	stack.add_child(_takeover_description)
	var takeover_list := VBoxContainer.new()
	takeover_list.add_theme_constant_override("separation", 7)
	stack.add_child(takeover_list)
	for slot in TAKEOVER_PAGE_SIZE:
		var button := _button(false)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_takeover_slot.bind(slot + 1))
		takeover_list.add_child(button)
		_takeover_buttons.append(button)
	_takeover_nav = HBoxContainer.new()
	_takeover_nav.add_theme_constant_override("separation", 8)
	stack.add_child(_takeover_nav)
	_takeover_prev = _button(false)
	_takeover_prev.text = "上一页"
	_takeover_prev.tooltip_text = "PgUp"
	_takeover_prev.focus_mode = Control.FOCUS_NONE
	_takeover_prev.pressed.connect(turn_takeover_page.bind(-1))
	_takeover_nav.add_child(_takeover_prev)
	_takeover_page_label = _label("", 16, SUBTLE)
	_takeover_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_takeover_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_takeover_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_takeover_nav.add_child(_takeover_page_label)
	_takeover_next = _button(false)
	_takeover_next.text = "下一页"
	_takeover_next.tooltip_text = "PgDn"
	_takeover_next.focus_mode = Control.FOCUS_NONE
	_takeover_next.pressed.connect(turn_takeover_page.bind(1))
	_takeover_nav.add_child(_takeover_next)
	_takeover_cancel = _button(false)
	_takeover_cancel.text = "返回当前单位"
	_takeover_cancel.pressed.connect(switch_cancelled.emit)
	stack.add_child(_takeover_cancel)
	_takeover_card.hide()


func _open_menu(screen: String, heading: String, description: String, action: String, can_restart := false) -> void:
	_screen = screen
	_heading.text = heading
	_description.text = description
	_primary.text = action
	_secondary.visible = can_restart
	_reticle.hide()
	_building_panel.hide()
	_bomb_panel.hide()
	_boss_ability_panel.hide()
	_supply_panel.hide()
	_selection.hide()
	_takeover_card.hide()
	_menu_card.show()
	_menu.show()


func _on_primary() -> void:
	match _screen:
		"pause":
			resume_requested.emit()
		"result":
			restart_requested.emit()


func _kind_label(kind: String) -> String:
	match kind:
		"infantry":
			return "步兵"
		"aircraft":
			return "飞机"
		_:
			return "坦克"


func _health_display(panel: PanelContainer, title: String, tint: Color, number: Label, bar: ProgressBar) -> Label:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	panel.add_child(stack)
	var row := HBoxContainer.new()
	stack.add_child(row)
	var name_label := _label(title, 18, tint)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(number)
	stack.add_child(bar)
	return name_label


func _panel(parent: Control, preset: int, offsets: Rect2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(SURFACE, LINE, 8))
	parent.add_child(panel)
	panel.set_anchors_preset(preset)
	panel.offset_left = offsets.position.x
	panel.offset_top = offsets.position.y
	panel.offset_right = offsets.end.x
	panel.offset_bottom = offsets.end.y
	return panel


func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _interface_font() -> Font:
	if OS.has_feature("web"):
		return BUNDLED_FONT
	for family in ["Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "Arial Unicode MS"]:
		var path := OS.get_system_font_path(family)
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var font := FontFile.new()
		if font.load_dynamic_font(path) == OK and font.has_char("坦".unicode_at(0)):
			return font
	return BUNDLED_FONT


func _bar(maximum: float, tint: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.max_value = maximum
	bar.step = 0.0
	bar.value = maximum
	bar.show_percentage = false
	bar.custom_minimum_size.y = 7.0
	bar.add_theme_stylebox_override("background", _style(INK, INK, 3, 0.0))
	bar.add_theme_stylebox_override("fill", _style(tint, tint, 3, 0.0))
	return bar


func _button(emphasized: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 43.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	var base := BRASS if emphasized else INK
	var type_color := INK if emphasized else PAPER
	button.add_theme_color_override("font_color", type_color)
	button.add_theme_color_override("font_hover_color", type_color)
	button.add_theme_color_override("font_pressed_color", type_color)
	button.add_theme_color_override("font_focus_color", type_color)
	button.add_theme_stylebox_override("normal", _style(base, LINE, 6, 6.0))
	button.add_theme_stylebox_override("hover", _style(base.lightened(0.12), LINE, 6, 6.0))
	button.add_theme_stylebox_override("pressed", _style(base.darkened(0.1), LINE, 6, 6.0))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, PAPER, 6, 0.0))
	return button


func _style(fill: Color, rim: Color, radius: int, inset := 12.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = rim
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = inset + minf(inset, 4.0)
	style.content_margin_right = style.content_margin_left
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	return style
