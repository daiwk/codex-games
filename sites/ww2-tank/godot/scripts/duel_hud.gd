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
const BUNDLED_FONT := preload("res://assets/fonts/StonewallSans.otf")
const TankSelection := preload("res://scripts/tank_selection.gd")
const TANK_CONTROLS := "WASD 驾驶   鼠标瞄准   空格开火   Q 切换   Tab 鼠标"
const INFANTRY_CONTROLS := "WASD 步行   鼠标瞄准   空格开火   Q 切换   Tab 鼠标"
const AIRCRAFT_CONTROLS := "W/S 前后   A/D 横移   鼠标调航向   空格开火   Q 切换"

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

var _root: Control
var _board: Control
var _menu: ColorRect
var _menu_card: PanelContainer
var _takeover_card: PanelContainer
var _takeover_heading: Label
var _takeover_description: Label
var _takeover_list: VBoxContainer
var _takeover_buttons: Array[Button] = []
var _takeover_cancel: Button
var _selection: TankSelection
var _heading: Label
var _description: Label
var _primary: Button
var _secondary: Button
var _reticle: AimReticle
var _player_title: Label
var _player_health: ProgressBar
var _player_number: Label
var _wave_title: Label
var _ally_count: Label
var _enemy_count: Label
var _allied_support: Label
var _enemy_support: Label
var _boss_panel: PanelContainer
var _boss_health: ProgressBar
var _boss_number: Label
var _building_panel: PanelContainer
var _building_title: Label
var _building_health: ProgressBar
var _building_number: Label
var _clock: Label
var _mouse_status: Label
var _controls: Label
var _reload: ProgressBar
var _reload_label: Label
var _intermission_panel: PanelContainer
var _intermission_title: Label
var _repair_status: Label
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
	_build_board()
	_build_menu()
	show_intro()


func show_intro() -> void:
	_screen = "intro"
	_board.hide()
	_reticle.hide()
	_intermission_panel.hide()
	_building_panel.hide()
	_menu_card.hide()
	_takeover_card.hide()
	_selection.show()
	_menu.show()


func configure_roster(roster: Array) -> void:
	_selection.configure(roster)


func selected_tanks() -> Vector2i:
	return _selection.selection()


func selection_choice_rects(side: int) -> Array[Rect2]:
	return _selection.choice_rects(side)


func set_controlled_unit(title: String, kind: String, max_health: int) -> void:
	_controlled_kind = kind
	_player_title.text = "玩家 · " + title
	_player_health.max_value = max_health
	match kind:
		"infantry":
			_controls.text = INFANTRY_CONTROLS
		"aircraft":
			_controls.text = AIRCRAFT_CONTROLS
		_:
			_controls.text = TANK_CONTROLS


func set_support_counts(allied_infantry: int, enemy_infantry: int, allied_aircraft: int, enemy_aircraft: int) -> void:
	_allied_support.text = "步兵 %d / 2\n飞机 %d / 1" % [allied_infantry, allied_aircraft]
	_enemy_support.text = "步兵 %d / 2\n飞机 %d / 1" % [enemy_infantry, enemy_aircraft]


func show_active() -> void:
	_screen = "active"
	_takeover_card.hide()
	_menu.hide()
	_board.show()
	_reticle.visible = not _player_down


func show_pause() -> void:
	_open_menu("pause", "对战暂停", "可以继续当前对战，或从头再来一局。", "继续对战", true)


func show_takeover(candidates: Array[Dictionary], voluntary := false) -> void:
	_screen = "takeover"
	_reticle.hide()
	_intermission_panel.hide()
	_building_panel.hide()
	_selection.hide()
	_menu_card.hide()
	_takeover_heading.text = "切换操控单位" if voluntary else "接管友军"
	_takeover_description.text = (
		"点击友军或按 1–7 切换。按 Q 或 Esc 返回当前单位。" if voluntary
		else "当前单位已失去战斗能力。点击友军或按 1–7 接管。"
	)
	_takeover_cancel.visible = voluntary
	for button in _takeover_buttons:
		_takeover_list.remove_child(button)
		button.queue_free()
	_takeover_buttons.clear()
	for index in candidates.size():
		var candidate := candidates[index]
		var button := _button(false)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%d    %s    ·    %s    ·    生命 %d / %d" % [
			index + 1, candidate["name"], _kind_label(candidate["kind"]), candidate["health"], candidate["max_health"],
		]
		button.pressed.connect(takeover_requested.emit.bind(index))
		_takeover_list.add_child(button)
		_takeover_buttons.append(button)
	var half_height := (_takeover_card.get_combined_minimum_size().y + 20.0) * 0.5
	_takeover_card.offset_top = -half_height
	_takeover_card.offset_bottom = half_height
	_takeover_card.show()
	_menu.show()


func show_result(outcome: String, wave: int) -> void:
	_intermission_panel.hide()
	match outcome:
		"win":
			_open_menu("result", "胜利", "已击退全部 5 波敌军，首领已被击毁。", "再打一局")
		"loss":
			_open_menu("result", "战败", "第 %d 波，己方全部单位已退出战斗。" % wave, "再打一局")
		_:
			_open_menu("result", "平局", "第 %d 波，双方最后的单位同时倒下。" % wave, "再打一局")


func update_battle(
	player_health: int, reload_fraction: float, seconds: float, wave: int,
	allied_tanks: int, enemy_tanks: int, boss_health: int = 0, boss_max_health: int = 0
) -> void:
	_player_health.value = player_health
	_player_number.text = "%d / %d" % [player_health, int(_player_health.max_value)]
	_wave_title.text = "第 %d / 5 波" % wave
	_ally_count.text = "坦克 %d / 5" % allied_tanks
	_enemy_count.text = "坦克 %d / 3" % enemy_tanks
	var elapsed := maxi(0, floori(seconds))
	_clock.text = "%02d:%02d" % [floori(elapsed / 60.0), elapsed % 60]
	_boss_panel.visible = boss_health > 0 and boss_max_health > 0
	if _boss_panel.visible:
		_boss_health.max_value = boss_max_health
		_boss_health.value = boss_health
		_boss_number.text = "%d / %d" % [boss_health, boss_max_health]
	_player_down = player_health <= 0
	_reticle.visible = not _player_down and _screen == "active"
	_reload.visible = not _player_down
	_reload_label.visible = not _player_down
	_reload.value = clampf(reload_fraction, 0.0, 1.0)
	var ready := reload_fraction >= 0.999
	_reload_label.text = "可开火" if ready else "装填中"
	_reload_label.modulate = Color.WHITE if ready else SUBTLE


func set_intermission(seconds_remaining: float, repair_available: bool, repair_used: bool) -> void:
	_intermission_panel.visible = seconds_remaining >= 0.0
	if not _intermission_panel.visible:
		return
	_intermission_title.text = "下一波将在 %d 秒后开始" % ceili(seconds_remaining)
	if _player_down:
		_repair_status.text = "接管友军后可恢复该单位的生命"
	elif repair_used:
		_repair_status.text = "本轮恢复已用"
	elif repair_available:
		var action := "治疗" if _controlled_kind == "infantry" else "修理"
		_repair_status.text = "H  %s%s，恢复全部生命" % [action, _kind_label(_controlled_kind)]
	else:
		_repair_status.text = "当前单位生命已满"


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


func set_mouse_locked(look_locked: bool) -> void:
	_mouse_status.text = "鼠标已锁定" if look_locked else "鼠标已释放"


func menu_button_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _screen == "intro":
		rects.append(_selection.start_rect())
		return rects
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
	_build_wave_panels()
	_build_battle_footer()
	_reticle = AimReticle.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_reticle)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _build_wave_panels() -> void:
	var center := _panel(_board, Control.PRESET_CENTER_TOP, Rect2(-120, 24, 240, 74))
	var center_stack := VBoxContainer.new()
	center_stack.add_theme_constant_override("separation", 2)
	center.add_child(center_stack)
	_wave_title = _label("第 1 / 5 波", 22, BRASS)
	_wave_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_stack.add_child(_wave_title)
	var wave_details := HBoxContainer.new()
	wave_details.add_theme_constant_override("separation", 12)
	wave_details.alignment = BoxContainer.ALIGNMENT_CENTER
	center_stack.add_child(wave_details)
	_clock = _label("00:00", 14, PAPER)
	wave_details.add_child(_clock)
	_mouse_status = _label("", 14, SUBTLE)
	wave_details.add_child(_mouse_status)
	set_mouse_locked(false)

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
	_ally_count = _label("坦克 5 / 5", 16, PAPER)
	_ally_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_counts.add_child(_ally_count)
	_enemy_count = _label("坦克 3 / 3", 16, PAPER)
	_enemy_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_counts.add_child(_enemy_count)
	_allied_support = _label("", 16, SUBTLE)
	unit_counts.add_child(_allied_support)
	_enemy_support = _label("", 16, SUBTLE)
	unit_counts.add_child(_enemy_support)
	set_support_counts(2, 2, 1, 1)

	_boss_panel = _panel(_board, Control.PRESET_CENTER_TOP, Rect2(-185, 111, 370, 66))
	_boss_number = _label("", 16, PAPER)
	_boss_health = _bar(1.0, OPPONENT)
	_health_display(_boss_panel, "敌军首领", OPPONENT, _boss_number, _boss_health)
	_boss_panel.hide()

	_intermission_panel = _panel(_board, Control.PRESET_CENTER_TOP, Rect2(-202, 190, 404, 88))
	var intermission_stack := VBoxContainer.new()
	intermission_stack.add_theme_constant_override("separation", 5)
	_intermission_panel.add_child(intermission_stack)
	_intermission_title = _label("", 23, BRASS)
	_intermission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intermission_stack.add_child(_intermission_title)
	_repair_status = _label("", 16, PAPER)
	_repair_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intermission_stack.add_child(_repair_status)
	_intermission_panel.hide()


func _build_battle_footer() -> void:
	_building_panel = _panel(_board, Control.PRESET_CENTER_BOTTOM, Rect2(-158, -151, 316, 67))
	_building_number = _label("", 16, PAPER)
	_building_health = _bar(1.0, BRASS)
	_building_title = _health_display(_building_panel, "建筑耐久", BRASS, _building_number, _building_health)
	_building_panel.hide()
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
	var keys := _label("WASD 移动　 鼠标瞄准　 空格开火\nQ 切换单位　 H 休整恢复　 Tab 鼠标\nEsc 暂停　 R 从第一波重开", 15, SUBTLE)
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
	_secondary.text = "重新开始"
	_secondary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary.pressed.connect(func() -> void: restart_requested.emit())
	actions.add_child(_secondary)
	var select_tanks := _button(false)
	select_tanks.text = "换坦克"
	select_tanks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_tanks.pressed.connect(func() -> void: selection_requested.emit())
	actions.add_child(select_tanks)

	_selection = TankSelection.new()
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
	_takeover_list = VBoxContainer.new()
	_takeover_list.add_theme_constant_override("separation", 7)
	stack.add_child(_takeover_list)
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
