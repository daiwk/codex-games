extends Control
class_name RPGHUD

const Progress = preload("res://scripts/rpg_progress.gd")
const PAPER = Color("eee9d8")
const GOLD = Color("d7bb83")
const JADE = Color("9ccfc9")
const MUTED = Color("9aafb0")
const INK = Color(0.025, 0.065, 0.08, 0.90)

class MapCanvas extends Control:
	var snapshot: Dictionary = {}
	var map_font: Font
	var show_names = false

	func point(value: Variant) -> Vector2:
		var location = Vector3.ZERO
		if value is Vector3:
			location = value
		elif value is Array and value.size() >= 3:
			location = Vector3(float(value[0]), float(value[1]), float(value[2]))
		var bounds: Array = snapshot.get("map_bounds", [-155.0, -155.0, 155.0, 155.0])
		if bounds.size() != 4:
			bounds = [-155.0, -155.0, 155.0, 155.0]
		var fraction = Vector2((location.x - float(bounds[0])) / maxf(float(bounds[2]) - float(bounds[0]), 1.0), (location.z - float(bounds[1])) / maxf(float(bounds[3]) - float(bounds[1]), 1.0))
		return Vector2(10, 10) + fraction.clamp(Vector2.ZERO, Vector2.ONE) * (size - Vector2(20, 20))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.045, 0.12, 0.13, 0.94))
		for index in range(1, 5):
			var at = float(index) / 5.0
			draw_line(Vector2(size.x * at, 0), Vector2(size.x * at, size.y), Color(0.55, 0.72, 0.67, 0.11))
			draw_line(Vector2(0, size.y * at), Vector2(size.x, size.y * at), Color(0.55, 0.72, 0.67, 0.11))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.65, 0.69, 0.52, 0.45), false)
		for poi in snapshot.get("pois", []):
			if not poi is Dictionary or not bool(poi.get("discovered", false)):
				continue
			var at = point(poi.get("position", Vector3.ZERO))
			var tint = Color("9ccfc9") if poi.get("kind", "") == "camp" else Color("d7bb83")
			if bool(poi.get("defeated", false)):
				tint = Color("778c89")
			if poi.get("kind", "") == "camp":
				draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), tint)
			else:
				draw_circle(at, 3.5 if show_names else 3.0, tint)
			if show_names and map_font != null:
				draw_string(map_font, at + Vector2(8, -5), String(poi.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 130, 13, tint)
		var quest: Dictionary = snapshot.get("quest", {})
		if quest.has("target_position"):
			var objective = point(quest.target_position)
			draw_arc(objective, 9.0 if show_names else 7.0, 0, TAU, 28, Color("e9c883"), 1.5, true)
			draw_line(objective + Vector2(-4, 0), objective + Vector2(4, 0), Color("e9c883"), 1.5, true)
			draw_line(objective + Vector2(0, -4), objective + Vector2(0, 4), Color("e9c883"), 1.5, true)
		var player: Dictionary = snapshot.get("player", {})
		var at = point(player.get("position", Vector3.ZERO))
		var facing = float(player.get("facing", 0.0))
		var direction = Vector2(sin(facing), cos(facing))
		var side = Vector2(direction.y, -direction.x)
		draw_circle(at, 9, Color(0.02, 0.06, 0.07, 0.85))
		draw_colored_polygon(PackedVector2Array([at + direction * 8, at - direction * 5 + side * 5, at - direction * 5 - side * 5]), Color("b5e5de"))
		if map_font != null:
			draw_string(map_font, Vector2(size.x * 0.5 - 7, 17), "北", HORIZONTAL_ALIGNMENT_LEFT, 20, 12, Color("9aafb0"))

var game: Node
var body_font: Font
var display_font: Font
var _base: Control
var _data: Dictionary = {}
var _built = false
var _name_label: Label
var _health_text: Label
var _hp: ProgressBar
var _stamina: ProgressBar
var _xp: ProgressBar
var _xp_text: Label
var _region: Label
var _quest_title: Label
var _quest_detail: Label
var _boss_title: Label
var _boss_panel: Panel
var _boss_names: Array[Label] = []
var _boss_states: Array[Label] = []
var _target_panel: Panel
var _target_name: Label
var _target_hp: ProgressBar
var _lock_status: Label
var _key_hint: Label
var _interaction_panel: Panel
var _interaction: Label
var _toast_panel: Panel
var _toast: Label
var _save_label: Label
var _mini_map: MapCanvas
var _large_map: MapCanvas
var _map_overlay: Control
var _map_legend: Label
var _inventory_overlay: Control
var _inventory_rows: VBoxContainer
var _inventory_stats: Label
var _inventory_slots: Label
var _inventory_signature = ""
var _horse_buttons: Dictionary = {}
var _dialogue_overlay: Control
var _speaker: Label
var _dialogue_text: RichTextLabel
var _dialogue_page: Label
var _dialogue_next: Button
var _pause_overlay: Control
var _dead_overlay: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_font = load("res://assets/fonts/WenfengSans.otf")
	display_font = load("res://assets/fonts/WenfengSerif.otf")
	_base = Control.new()
	_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	_build_status()
	_build_journal()
	_build_map()
	_build_inventory()
	_build_dialogue()
	_build_pause()
	_build_defeat()
	_built = true
	refresh(_data)

func _style(background: Color, border: Color = Color(0.55, 0.65, 0.60, 0.48)) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

func _panel(parent: Node, rect: Rect2, interactive = false) -> Panel:
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(INK))
	parent.add_child(panel)
	return panel

func _label(parent: Node, text: String, rect: Rect2, font_size = 16, color = PAPER, display = false) -> Label:
	var label = Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", display_font if display else body_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, rect: Rect2, action: String, payload: Variant = null, prominent = false) -> Button:
	var button = Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", body_font)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("142e38") if prominent else PAPER)
	button.add_theme_color_override("font_hover_color", Color("142e38") if prominent else GOLD)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style(GOLD if prominent else Color(0.08, 0.17, 0.18, 0.94)))
	button.add_theme_stylebox_override("hover", _style(Color("ead4a4") if prominent else Color("284b50"), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("c4a66b") if prominent else Color("345a5b"), GOLD))
	button.add_theme_stylebox_override("disabled", _style(Color(0.07, 0.12, 0.13, 0.88)))
	button.pressed.connect(func(): _command(action, payload))
	parent.add_child(button)
	return button

func _bar(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(Color(0.02, 0.055, 0.06, 0.95), Color(0.3, 0.46, 0.43, 0.40)))
	bar.add_theme_stylebox_override("fill", _style(color, color))
	parent.add_child(bar)
	# Setting size before the theme is applied retains the default font's
	# 27-pixel minimum even after percentage text is disabled. Size it last.
	bar.size = rect.size
	return bar

func _overlay(dim = 0.36) -> Control:
	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.01, 0.035, 0.04, dim)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(veil)
	overlay.visible = false
	return overlay

func _build_status() -> void:
	var status = _panel(_base, Rect2(28, 24, 352, 124))
	_name_label = _label(status, "赵云  ·  Lv.1", Rect2(16, 9, 240, 31), 24, PAPER, true)
	_health_text = _label(status, "120 / 120", Rect2(222, 19, 113, 23), 13, JADE)
	_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp = _bar(status, Rect2(16, 49, 320, 12), Color("78b7a2"))
	_stamina = _bar(status, Rect2(16, 68, 320, 6), Color("b6bd91"))
	_xp = _bar(status, Rect2(16, 85, 320, 4), GOLD)
	_xp_text = _label(status, "历练  0 / 60", Rect2(16, 96, 320, 19), 11, MUTED)
	_target_panel = _panel(_base, Rect2(464, 28, 352, 67))
	_target_name = _label(_target_panel, "", Rect2(14, 8, 324, 26), 17, GOLD)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_hp = _bar(_target_panel, Rect2(18, 43, 316, 8), Color("bd7771"))
	_lock_status = _label(_base, "", Rect2(402, 95, 476, 17), 11, JADE)
	_lock_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lock_status.add_theme_color_override("font_outline_color", Color(0.0, 0.025, 0.03, 0.95))
	_lock_status.add_theme_constant_override("outline_size", 3)
	_toast_panel = _panel(_base, Rect2(402, 128, 476, 42))
	_toast = _label(_toast_panel, "", Rect2(12, 8, 452, 26), 15, GOLD)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_panel = _panel(_base, Rect2(390, 674, 500, 48))
	_interaction = _label(_interaction_panel, "", Rect2(12, 11, 476, 28), 17, PAPER)
	_interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var keys = _panel(_base, Rect2(16, 748, 920, 32))
	_key_hint = _label(keys, "", Rect2(12, 7, 896, 23), 12, PAPER)
	_button(_base, "行囊  I", Rect2(950, 748, 94, 32), "toggle_inventory")
	_button(_base, "舆图  M", Rect2(1052, 748, 94, 32), "toggle_map")
	_button(_base, "暂歇  Esc", Rect2(1154, 748, 98, 32), "toggle_pause")

func _build_journal() -> void:
	var region_panel = _panel(_base, Rect2(28, 158, 228, 29))
	_region = _label(region_panel, "长坂原野", Rect2(12, 3, 204, 24), 14, JADE, true)
	var journal = _panel(_base, Rect2(28, 194, 352, 98))
	_quest_title = _label(journal, "初入原野", Rect2(15, 9, 322, 27), 18, GOLD, true)
	_quest_detail = _label(journal, "前往营地，与守营军士交谈。", Rect2(15, 42, 322, 44), 13, PAPER)
	_quest_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_detail.max_lines_visible = 2
	_quest_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var bosses = _panel(_base, Rect2(28, 534, 282, 188))
	_boss_panel = bosses
	_boss_title = _label(bosses, "五将试锋  ·  0 / 5", Rect2(15, 10, 252, 25), 16, GOLD, true)
	for index in 5:
		_boss_names.append(_label(bosses, "", Rect2(16, 46 + index * 25, 120, 22), 14, PAPER))
		var state = _label(bosses, "", Rect2(130, 46 + index * 25, 136, 22), 12, MUTED)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_boss_states.append(state)

func _build_map() -> void:
	var minimap_panel = _panel(_base, Rect2(1028, 24, 224, 222))
	_label(minimap_panel, "原野舆图", Rect2(14, 9, 125, 24), 15, GOLD, true)
	_button(minimap_panel, "M  展开", Rect2(142, 7, 70, 26), "toggle_map").add_theme_font_size_override("font_size", 11)
	_mini_map = MapCanvas.new()
	_mini_map.position = Vector2(14, 42)
	_mini_map.size = Vector2(196, 166)
	_mini_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_map.map_font = body_font
	minimap_panel.add_child(_mini_map)
	_save_label = _label(_base, "", Rect2(1030, 254, 222, 21), 11, PAPER)
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_save_label.add_theme_color_override("font_outline_color", Color(0.0, 0.025, 0.03, 0.9))
	_save_label.add_theme_constant_override("outline_size", 3)
	_map_overlay = _overlay(0.48)
	var map_panel = _panel(_map_overlay, Rect2(256, 74, 768, 652), true)
	_label(map_panel, "长坂舆图", Rect2(24, 15, 500, 36), 27, PAPER, true)
	_button(map_panel, "收起  M", Rect2(646, 16, 98, 33), "toggle_map")
	_large_map = MapCanvas.new()
	_large_map.position = Vector2(24, 68)
	_large_map.size = Vector2(520, 520)
	_large_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_large_map.map_font = body_font
	_large_map.show_names = true
	map_panel.add_child(_large_map)
	_label(map_panel, "行旅标记", Rect2(568, 78, 174, 26), 18, GOLD, true)
	_map_legend = _label(map_panel, "", Rect2(568, 120, 174, 416), 14, PAPER)
	_map_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(map_panel, "青色为子龙  ·  方点为营地  ·  金环为下一目标", Rect2(24, 608, 714, 24), 12, MUTED)

func _build_inventory() -> void:
	_inventory_overlay = _overlay(0.16)
	var inventory_panel = _panel(_inventory_overlay, Rect2(838, 284, 414, 438), true)
	_label(inventory_panel, "行囊", Rect2(18, 10, 110, 35), 26, PAPER, true)
	for index in 2:
		var color = "white" if index == 0 else "brown"
		var button = _button(inventory_panel, "白马" if index == 0 else "棕马", Rect2(138 + index * 78, 13, 70, 30), "horse_color", color)
		button.add_theme_font_size_override("font_size", 12)
		button.toggle_mode = true
		_horse_buttons[color] = button
	_button(inventory_panel, "I  收起", Rect2(310, 13, 86, 30), "toggle_inventory")
	_inventory_stats = _label(inventory_panel, "", Rect2(18, 55, 378, 23), 13, GOLD)
	_inventory_slots = _label(inventory_panel, "", Rect2(18, 83, 378, 23), 11, MUTED)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(14, 116)
	scroll.size = Vector2(386, 274)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_panel.add_child(scroll)
	_inventory_rows = VBoxContainer.new()
	_inventory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_rows.add_theme_constant_override("separation", 7)
	scroll.add_child(_inventory_rows)
	_label(inventory_panel, "护腕 / 战甲同时穿戴  ·  换马需在驿站附近", Rect2(18, 406, 378, 22), 11, MUTED)

func _build_dialogue() -> void:
	_dialogue_overlay = _overlay(0.06)
	var card = _panel(_dialogue_overlay, Rect2(280, 508, 720, 216), true)
	_speaker = _label(card, "", Rect2(22, 13, 506, 31), 23, GOLD, true)
	_dialogue_text = RichTextLabel.new()
	_dialogue_text.position = Vector2(22, 57)
	_dialogue_text.size = Vector2(676, 100)
	_dialogue_text.bbcode_enabled = false
	_dialogue_text.add_theme_font_override("normal_font", body_font)
	_dialogue_text.add_theme_font_size_override("normal_font_size", 18)
	_dialogue_text.add_theme_color_override("default_color", PAPER)
	_dialogue_text.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_child(_dialogue_text)
	_dialogue_page = _label(card, "", Rect2(22, 174, 380, 23), 12, MUTED)
	_dialogue_next = _button(card, "继续  Enter", Rect2(536, 168, 162, 34), "continue_dialogue", null, true)

func _build_pause() -> void:
	_pause_overlay = _overlay(0.62)
	var panel = _panel(_pause_overlay, Rect2(436, 206, 408, 368), true)
	_label(panel, "暂歇", Rect2(24, 18, 360, 60), 44, PAPER, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(panel, "收锋听风，待马再行。", Rect2(24, 87, 360, 28), 15, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(panel, "继续行旅  /  Esc", Rect2(44, 140, 320, 48), "toggle_pause", null, true)
	_button(panel, "返回营地整备", Rect2(44, 202, 320, 44), "return_to_camp")
	_button(panel, "返回封面", Rect2(44, 260, 320, 44), "return_to_menu")
	_label(panel, "I 行囊    ·    M 舆图", Rect2(44, 326, 320, 22), 12, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_defeat() -> void:
	_dead_overlay = _overlay(0.58)
	var panel = _panel(_dead_overlay, Rect2(420, 244, 440, 304), true)
	_label(panel, "暂且收锋", Rect2(24, 22, 392, 55), 38, PAPER, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(panel, "重整行装，再踏征途。", Rect2(24, 94, 392, 32), 17, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(panel, "回营再战", Rect2(60, 156, 320, 48), "return_to_camp", null, true)
	_button(panel, "返回封面", Rect2(60, 222, 320, 42), "return_to_menu")

func refresh(data: Dictionary) -> void:
	_data = data
	if not _built:
		return
	var player: Dictionary = data.get("player", {})
	var level = int(player.get("level", 1))
	_name_label.text = "%s  ·  Lv.%d" % [player.get("name", "赵云"), level]
	var maximum_hp = maxf(1.0, float(player.get("max_hp", 120)))
	var health = clampf(float(player.get("hp", maximum_hp)), 0.0, maximum_hp)
	_set_bar(_hp, health, maximum_hp)
	_set_bar(_stamina, float(player.get("stamina", 100)), float(player.get("max_stamina", 100)))
	var next_xp = int(player.get("xp_to_next", 60))
	_set_bar(_xp, float(player.get("xp", 0)) if next_xp > 0 else 1.0, float(next_xp) if next_xp > 0 else 1.0)
	_health_text.text = "%d / %d" % [ceili(health), ceili(maximum_hp)]
	var experience = "历练已满" if next_xp <= 0 else "历练 %d/%d" % [int(player.get("xp", 0)), next_xp]
	_xp_text.text = "%s  ·  体力 %d  ·  战意 %d/100" % [experience, ceili(float(player.get("stamina", 100))), floori(float(player.get("energy", 0)))]
	_region.text = String(data.get("region", "长坂原野"))
	var quest: Dictionary = data.get("quest", {})
	_quest_title.text = String(quest.get("title", "初入原野"))
	_quest_detail.text = String(quest.get("detail", "前往营地，与守营军士交谈。"))
	var target: Dictionary = data.get("target", {})
	var lock_on: Dictionary = data.get("lock_on", {})
	var locked = bool(lock_on.get("active", false))
	_lock_status.text = "已锁定 · %s · %.1f m    R 切换" % [String(lock_on.get("name", "目标")), float(lock_on.get("distance", 0.0))] if locked else "Tab / 中键点击锁定目标"
	_lock_status.add_theme_color_override("font_color", JADE if locked else MUTED)
	_key_hint.text = "W/S 进退 · A/D 绕敌  J/K 攻击  L 格挡  Space 冲刺  Q/E/U 技能  Tab/中键 解锁  R 切换 · 远离/死亡自动解锁" if locked else "WASD 策马  J/K 攻击  L 格挡  Space 冲刺  Q/E/U 技能  Tab/中键 锁定  R 切换"
	_target_panel.visible = not target.is_empty()
	_target_name.text = "%s  ·  Lv.%d" % [target.get("name", ""), int(target.get("level", 1))]
	_set_bar(_target_hp, float(target.get("hp", 0)), float(target.get("max_hp", 1)))
	var interaction_text = String(data.get("interaction", ""))
	_interaction_panel.visible = not interaction_text.is_empty()
	_interaction.text = "F   ·   " + interaction_text
	var toast_text = String(data.get("toast", ""))
	_toast_panel.visible = not toast_text.is_empty()
	_toast.text = toast_text
	_save_label.text = String(data.get("save_label", ""))
	_refresh_bosses(data)
	_mini_map.snapshot = data
	_large_map.snapshot = data
	_mini_map.queue_redraw()
	_large_map.queue_redraw()
	var is_dead = bool(data.get("dead", false))
	# The controller pauses physics while either inventory or map is open.
	# Those are their own overlays, rather than the explicit Esc pause menu.
	var is_paused = bool(data.get("paused", false)) and not bool(data.get("inventory_open", false)) and not bool(data.get("map_open", false)) and not is_dead
	var dialogue: Dictionary = data.get("dialogue", {})
	var speaking = not dialogue.is_empty() and not is_paused and not is_dead
	_dead_overlay.visible = is_dead
	_pause_overlay.visible = is_paused
	_dialogue_overlay.visible = speaking
	_map_overlay.visible = bool(data.get("map_open", false)) and not speaking and not is_paused and not is_dead
	_inventory_overlay.visible = bool(data.get("inventory_open", false)) and not _map_overlay.visible and not speaking and not is_paused and not is_dead
	_base.visible = not _map_overlay.visible and not is_paused and not is_dead
	_boss_panel.visible = not speaking
	_interaction_panel.visible = not interaction_text.is_empty() and not speaking and not _inventory_overlay.visible
	_target_panel.visible = not target.is_empty() and not speaking
	_lock_status.visible = (locked or not target.is_empty()) and data.get("phase", "") == "explore" and not speaking and not _inventory_overlay.visible
	if speaking:
		_speaker.text = String(dialogue.get("speaker", "行旅客"))
		_dialogue_text.text = String(dialogue.get("text", ""))
		var index = int(dialogue.get("index", 1))
		var total = maxi(1, int(dialogue.get("total", 1)))
		var page = clampi(index + (1 if int(dialogue.get("index_base", 1)) == 0 else 0), 1, total)
		_dialogue_page.text = "%d / %d    ·    Enter 继续" % [page, total]
		_dialogue_next.text = "继续  Enter" if page < total else "收起  Enter"
	if _inventory_overlay.visible:
		_refresh_inventory(data, player)
	if _map_overlay.visible:
		_refresh_map_legend(data)

func _set_bar(bar: ProgressBar, amount: float, maximum: float) -> void:
	bar.max_value = maxf(maximum, 1.0)
	bar.value = clampf(amount, 0.0, bar.max_value)

func _refresh_bosses(data: Dictionary) -> void:
	var states: Dictionary = {}
	for boss in data.get("bosses", []):
		if boss is Dictionary and boss.has("id"):
			states[String(boss.id)] = boss
	var count = 0
	for index in Progress.BOSSES.size():
		var original: Dictionary = Progress.BOSSES[index]
		var boss: Dictionary = states.get(original.id, original)
		var won = bool(boss.get("defeated", false))
		var available = bool(boss.get("available", false))
		count += 1 if won else 0
		var color = JADE if won else GOLD if available else PAPER if bool(boss.get("is_next", false)) else MUTED
		_boss_names[index].text = ("✓  " if won else "%d  " % [index + 1]) + String(boss.get("name", original.name))
		_boss_names[index].add_theme_color_override("font_color", color)
		_boss_states[index].text = "已会 · 装备入囊" if won else "Lv.%d · 可挑战" % int(original.level) if available else "Lv.%d · 待试锋" % int(original.level)
		_boss_states[index].add_theme_color_override("font_color", color)
	_boss_title.text = "五将试锋  ·  %d / 5" % count

func _refresh_inventory(data: Dictionary, player: Dictionary) -> void:
	var inventory: Array = data.get("inventory", ["starter"])
	var equipped: Dictionary = data.get("equipped", {"weapon": "starter", "bracers": "", "armor": ""})
	for color in _horse_buttons:
		_horse_buttons[color].set_pressed_no_signal(color == data.get("horse_color", "white"))
	_inventory_stats.text = "攻击 %d    生命 %d    护甲 %d" % [int(player.get("attack", 18)), int(player.get("max_hp", 120)), int(player.get("armor", 0))]
	var weapon: Dictionary = Progress.ITEMS.get(equipped.get("weapon", "starter"), Progress.ITEMS.starter)
	_inventory_slots.text = "兵刃 · %s     护腕 / 战甲独立装配" % weapon.name
	var signature = JSON.stringify([inventory, equipped])
	if signature == _inventory_signature:
		return
	_inventory_signature = signature
	for child in _inventory_rows.get_children():
		_inventory_rows.remove_child(child)
		child.queue_free()
	for value in inventory:
		var id = String(value)
		if not Progress.ITEMS.has(id):
			continue
		var item: Dictionary = Progress.ITEMS[id]
		var selected = equipped.get(item.slot, "") == id
		var row = _panel(_inventory_rows, Rect2(0, 0, 366, 66), true)
		row.custom_minimum_size = Vector2(366, 66)
		if selected:
			row.add_theme_stylebox_override("panel", _style(Color(0.11, 0.23, 0.23, 0.96), Color(0.65, 0.74, 0.58, 0.72)))
		_label(row, String(item.name), Rect2(12, 7, 256, 24), 16, GOLD if selected else PAPER)
		_label(row, String(item.description), Rect2(12, 36, 256, 20), 11, MUTED)
		var button = _button(row, "已装配" if selected else "装配", Rect2(284, 17, 70, 32), "equip", id)
		button.add_theme_font_size_override("font_size", 12)
		button.disabled = selected

func _refresh_map_legend(data: Dictionary) -> void:
	var lines: Array[String] = ["▲ 子龙当前位置", "◇ 下一目标", ""]
	for poi in data.get("pois", []):
		if poi is Dictionary and bool(poi.get("discovered", false)):
			lines.append(("□ " if poi.get("kind", "") == "camp" else "· ") + String(poi.get("name", "")))
	lines.append("")
	lines.append(String(data.get("quest", {}).get("detail", "循路探索，发现原野各处。")))
	_map_legend.text = "\n".join(lines)

func _command(action: String, payload: Variant = null) -> void:
	if is_instance_valid(game) and game.has_method("command"):
		game.command(action, payload)
