extends Control
class_name DuelHUD
const Roster = preload("res://scripts/roster.gd")

const INK = Color("142e38")
const PAPER = Color("eee9d8")
const GOLD = Color("d7bb83")
const JADE = Color("9ccfc9")
const MUTED = Color("9aafb0")
var game: Node
var body_font: Font
var display_font: Font
var menu: Control
var pause_panel: Control
var result_panel: Control
var buttons: Dictionary = {}
var displayed_hp = [120.0, 120.0]
var menu_enemy: Label
var menu_role_title: Label
var menu_role_identity: Label
var menu_role_skills: Array[Label] = []
var menu_mode_hint: Label
var menu_move_hint: Label
var menu_horse_colors: Control
var pause_skills: Label
var result_title: Label
var result_subtitle: Label
var last_phase = ""
var top_veil: GradientTexture2D
var bottom_veil: GradientTexture2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_font = load("res://assets/fonts/WenfengSans.otf")
	display_font = load("res://assets/fonts/WenfengSerif.otf")
	top_veil = _gradient(false)
	bottom_veil = _gradient(true)
	_build_menu()
	_build_pause()
	_build_results()

func _gradient(reverse: bool) -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	gradient.colors = PackedColorArray([Color(0.018, 0.029, 0.031, 0.86), Color(0.018, 0.029, 0.031, 0.38), Color(0.018, 0.029, 0.031, 0.0)])
	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 256
	texture.fill_from = Vector2(0, 1 if reverse else 0)
	texture.fill_to = Vector2(0, 0 if reverse else 1)
	return texture

func _label(parent: Node, text: String, at: Vector2, font_size: int, color: Color = PAPER, width = 400.0, display = false) -> Label:
	var label = Label.new()
	label.text = text
	label.position = at
	label.size.x = width
	label.add_theme_font_override("font", display_font if display else body_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _style(color: Color, border: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style

func _button(parent: Node, text: String, rect: Rect2, callback: Callable, prominent = false) -> Button:
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_override("font", body_font)
	button.add_theme_font_size_override("font_size", 18 if prominent else 16)
	button.add_theme_color_override("font_color", INK if prominent else PAPER)
	button.add_theme_color_override("font_hover_color", INK if prominent else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", INK if prominent else GOLD)
	button.add_theme_stylebox_override("normal", _style(GOLD if prominent else Color(0.11, 0.20, 0.23, 0.92), Color("4e6568")))
	button.add_theme_stylebox_override("hover", _style(Color("ead4a4") if prominent else Color("2d4c52"), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("c4a66b") if prominent else Color("2a474c"), GOLD))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _full_rect(parent: Node, color: Color) -> ColorRect:
	var panel = ColorRect.new()
	panel.color = color
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu)
	var veil = _full_rect(menu, Color.WHITE)
	var shader = Shader.new()
	shader.code = """shader_type canvas_item;void fragment(){float a=0.97*(1.0-smoothstep(0.28,0.66,UV.x));COLOR=vec4(0.028,0.070,0.087,a);}"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	veil.material = mat
	_label(menu, "一 对 一  ·  步 战 / 马 战", Vector2(50, 48), 13, JADE)
	_label(menu, "问锋", Vector2(44, 77), 90, PAPER, 400, true)
	_label(menu, "DUEL OF BLADES", Vector2(53, 185), 16, GOLD)
	_label(menu, "一招有进退，一刃定胜负。", Vector2(52, 230), 18, PAPER)
	_label(menu, "出战武将  /  1—6", Vector2(52, 282), 13, MUTED)
	for i in Roster.IDS.size():
		var id: String = Roster.IDS[i]
		var role: Dictionary = Roster.character(id)
		buttons[id] = _button(menu, "%s / %s" % [role.name, role.courtesy], Rect2(52 + (i % 3) * 125, 312 + (i / 3) * 49, 114, 41), func(): game.select_character(id))
		buttons[id].add_theme_font_size_override("font_size", 14)
		buttons[id].toggle_mode = true
	_label(menu, "掌中兵刃", Vector2(52, 414), 13, MUTED)
	buttons.sword = _button(menu, "剑  ·  灵巧", Rect2(52, 441, 176, 44), func(): _select_weapon_slot(0))
	buttons.saber = _button(menu, "刀  ·  刚猛", Rect2(240, 441, 176, 44), func(): _select_weapon_slot(1))
	buttons.weapon3 = _button(menu, "剑  ·  灵巧", Rect2(302, 441, 114, 44), func(): _select_weapon_slot(2))
	buttons.sword.toggle_mode = true
	buttons.saber.toggle_mode = true
	buttons.weapon3.toggle_mode = true
	_label(menu, "对手强度", Vector2(52, 505), 13, MUTED)
	for i in 3:
		var index = i
		var button = _button(menu, ["切磋", "争锋", "宗师"][i], Rect2(52 + i * 125, 532, 114, 36), func(): game.difficulty = index)
		button.toggle_mode = true
		buttons["difficulty" + str(i)] = button
	menu_enemy = _label(menu, "", Vector2(52, 579), 12, MUTED)
	_button(menu, "入场拔刃    →", Rect2(52, 605, 364, 57), func(): game.start_match(), true)
	menu_move_hint = _label(menu, "WASD 移动    J 轻击    K 重击    Space 闪避", Vector2(52, 683), 12, PAPER)
	_label(menu, "Q / E 武将技能    U 战意绝技 · 空中可出招", Vector2(52, 710), 12, GOLD)
	_label(menu, "L / Shift 格挡  ·  V 跳跃  ·  Enter 开始", Vector2(52, 744), 11, MUTED)
	_label(menu, "青石为界  ·  点到为止", Vector2(956, 742), 14, PAPER, 280, true)
	var role_panel = Panel.new()
	role_panel.position = Vector2(568, 40)
	role_panel.size = Vector2(660, 198)
	role_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.065, 0.08, 0.90), Color("496669")))
	menu.add_child(role_panel)
	menu_role_title = _label(role_panel, "", Vector2(22, 14), 27, JADE, 616, true)
	menu_role_identity = _label(role_panel, "", Vector2(22, 54), 13, PAPER, 616)
	for i in 3:
		var line = _label(role_panel, "", Vector2(22, 89 + i * 29), 12, MUTED, 616)
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		menu_role_skills.append(line)
	_label(menu, "对战方式  /  B 切换", Vector2(568, 263), 12, MUTED, 154)
	buttons.mode_foot = _button(menu, "步战 · 游斗", Rect2(730, 252, 164, 42), func(): game.select_combat_mode("foot"))
	buttons.mode_mounted = _button(menu, "马战 · 冲阵", Rect2(906, 252, 164, 42), func(): game.select_combat_mode("mounted"))
	buttons.mode_foot.toggle_mode = true
	buttons.mode_mounted.toggle_mode = true
	menu_horse_colors = Control.new()
	menu_horse_colors.position = Vector2(568, 309)
	menu_horse_colors.size = Vector2(660, 40)
	menu_horse_colors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_horse_colors.visible = false
	menu.add_child(menu_horse_colors)
	var horse_backdrop = Panel.new()
	horse_backdrop.position = Vector2(-4, -4)
	horse_backdrop.size = Vector2(668, 48)
	horse_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horse_backdrop.add_theme_stylebox_override("panel", _style(Color(0.025, 0.065, 0.08, 0.90), Color("496669")))
	menu_horse_colors.add_child(horse_backdrop)
	_label(menu_horse_colors, "己方坐骑", Vector2(0, 12), 12, JADE, 76)
	_label(menu_horse_colors, "对手坐骑", Vector2(332, 12), 12, GOLD, 76)
	buttons.horse_brown = _button(menu_horse_colors, "棕马", Rect2(84, 0, 94, 40), func(): game.select_horse_color("brown"))
	buttons.horse_white = _button(menu_horse_colors, "白马", Rect2(190, 0, 94, 40), func(): game.select_horse_color("white"))
	buttons.enemy_horse_brown = _button(menu_horse_colors, "棕马", Rect2(416, 0, 94, 40), func(): game.select_horse_color("brown", true))
	buttons.enemy_horse_white = _button(menu_horse_colors, "白马", Rect2(522, 0, 94, 40), func(): game.select_horse_color("white", true))
	for id in ["horse_brown", "horse_white", "enemy_horse_brown", "enemy_horse_white"]:
		buttons[id].toggle_mode = true
	menu_mode_hint = _label(menu, "", Vector2(568, 307), 12, PAPER, 660)
	menu_mode_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	menu_mode_hint.add_theme_constant_override("outline_size", 4)
	menu_mode_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	menu_mode_hint.add_theme_constant_override("shadow_offset_x", 1)
	menu_mode_hint.add_theme_constant_override("shadow_offset_y", 2)
	_label(menu, "对阵武将", Vector2(568, 654), 12, MUTED)
	var enemy_button_width = (660.0 - 10.0 * (Roster.IDS.size() - 1)) / Roster.IDS.size()
	for i in Roster.IDS.size():
		var id: String = Roster.IDS[i]
		var button = _button(menu, String(Roster.character(id).name), Rect2(568 + i * (enemy_button_width + 10), 681, enemy_button_width, 36), func(): game.select_opponent(id))
		button.toggle_mode = true
		buttons["enemy_" + id] = button

func _select_weapon_slot(index: int) -> void:
	var choices = Roster.weapon_choices(game.character_id)
	if index < choices.size():
		game.select_weapon(String(choices[index]))

func _overlay() -> Control:
	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_full_rect(overlay, Color(0.015, 0.035, 0.045, 0.76))
	return overlay

func _build_pause() -> void:
	pause_panel = _overlay()
	_label(pause_panel, "暂歇", Vector2(525, 196), 64, PAPER, 300, true)
	_label(pause_panel, "刀锋暂收，战意未尽。", Vector2(523, 280), 16, MUTED, 380)
	_button(pause_panel, "继续决斗", Rect2(480, 346, 320, 52), func(): game.toggle_pause(), true)
	_button(pause_panel, "重新对决", Rect2(480, 415, 320, 48), func(): game.start_match())
	_button(pause_panel, "返回选将", Rect2(480, 481, 320, 48), func(): game.return_to_menu())
	_button(pause_panel, "收刃休息", Rect2(480, 547, 320, 48), func(): game.get_node("WebBridge").close_game())
	_label(pause_panel, "Esc 继续    ·    Tab / 中键 锁定    ·    F 全屏", Vector2(484, 642), 13, MUTED)
	pause_skills = _label(pause_panel, "", Vector2(400, 680), 12, GOLD, 560)
	pause_skills.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_results() -> void:
	result_panel = _overlay()
	result_title = _label(result_panel, "胜", Vector2(556, 161), 100, GOLD, 300, true)
	result_subtitle = _label(result_panel, "", Vector2(428, 300), 21, PAPER, 470)
	result_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(result_panel, "胜负已分，锋芒尚在。", Vector2(492, 354), 17, MUTED)
	_button(result_panel, "再战一场   /   R", Rect2(480, 429, 320, 56), func(): game.start_match(), true)
	_button(result_panel, "返回选将", Rect2(480, 506, 320, 48), func(): game.return_to_menu())
	_button(result_panel, "收刃休息", Rect2(480, 571, 320, 44), func(): game.get_node("WebBridge").close_game())

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player):
		return
	menu.visible = game.phase == "menu"
	pause_panel.visible = game.paused
	result_panel.visible = game.phase == "match_end" and not game.paused
	if menu.visible:
		var mounted: bool = game.combat_mode == "mounted"
		buttons.mode_foot.set_pressed_no_signal(not mounted)
		buttons.mode_mounted.set_pressed_no_signal(mounted)
		menu_horse_colors.visible = mounted
		buttons.horse_brown.set_pressed_no_signal(game.horse_color == "brown")
		buttons.horse_white.set_pressed_no_signal(game.horse_color == "white")
		buttons.enemy_horse_brown.set_pressed_no_signal(game.enemy_horse_color == "brown")
		buttons.enemy_horse_white.set_pressed_no_signal(game.enemy_horse_color == "white")
		menu_mode_hint.position.y = 365 if mounted else 307
		menu_mode_hint.text = "W/S 调速 · A/D 转马 · Space 催马 · V 跳跃" if mounted else "移动周旋 · 自动面向对手 · Space 闪避"
		menu_move_hint.text = "W/S 调速  A/D 转马  X 刹车  Z/C 左右出招" if mounted else "WASD 移动  J / K 出招  Space 闪避  Tab 锁定"
		for id in Roster.IDS:
			buttons[id].set_pressed_no_signal(game.character_id == id)
			buttons["enemy_" + id].set_pressed_no_signal(game.enemy.character_id == id)
		var choices = Roster.weapon_choices(game.character_id)
		var weapon_button_width = (364.0 - 12.0 * (choices.size() - 1)) / choices.size()
		for i in 3:
			var button: Button = [buttons.sword, buttons.saber, buttons.weapon3][i]
			button.visible = i < choices.size()
			if button.visible:
				button.text = Roster.weapon_name(String(choices[i]))
				button.position.x = 52 + i * (weapon_button_width + 12)
				button.size.x = weapon_button_width
				button.set_pressed_no_signal(game.weapon_id == choices[i])
		for i in 3:
			buttons["difficulty" + str(i)].set_pressed_no_signal(game.difficulty == i)
		menu_enemy.text = "对阵  %s · %s  /  九十息一回合" % [game.fighter_name(game.enemy.character_id), Roster.weapon_name(game.enemy.weapon_id)]
		_update_role_preview()
	if pause_panel.visible:
		pause_skills.text = "Q %s   ·   E %s   ·   U %s" % [game.player.skill_name("rush"), game.player.skill_name("counter"), game.player.ultimate_name()]
	if result_panel.visible:
		result_title.text = "胜" if game.scores[0] == 2 else "惜败"
		result_title.position.x = 556 if game.scores[0] == 2 else 490
		result_subtitle.text = "%s  ·  %s  %d : %d  %s" % ["马战" if game.combat_mode == "mounted" else "步战", game.fighter_name(game.player.character_id), game.scores[0], game.scores[1], game.fighter_name(game.enemy.character_id)]
	for i in 2:
		var fighter = game.player if i == 0 else game.enemy
		displayed_hp[i] = lerpf(displayed_hp[i], fighter.hp, 1.0 - exp(-delta * 12.0))
	queue_redraw()

func _role_color(fighter) -> Color:
	return Color(Roster.character(fighter.character_id).color)

func _update_role_preview() -> void:
	var fighter = game.player
	var role: Dictionary = Roster.character(fighter.character_id)
	menu_role_title.text = "%s  ·  %s" % [game.fighter_name(fighter.character_id), role.style]
	menu_role_title.add_theme_color_override("font_color", _role_color(fighter))
	menu_role_identity.text = String(role.identity)
	for i in 2:
		var id = "rush" if i == 0 else "counter"
		menu_role_skills[i].text = "%s  %s  ·  %s  /  %d 体力 · %.1f 秒冷却" % ["Q" if i == 0 else "E", fighter.skill_name(id), fighter.skill_description(id), int(fighter.skill_cost(id)), fighter.skill_cooldown(id)]
	menu_role_skills[2].text = "U  %s  ·  %s  /  100 战意" % [fighter.ultimate_name(), fighter.skill_description("ultimate")]
	menu_role_skills[2].add_theme_color_override("font_color", _role_color(fighter))

func _text(at: Vector2, text: String, font_size: int, color: Color = PAPER, serif = false) -> void:
	var font = display_font if serif else body_font
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.015, 0.025, 0.025, 0.48))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _fit_copy(text: String, font_size: int, width: float) -> String:
	if body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var clipped = text
	while not clipped.is_empty() and body_font.get_string_size(clipped + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		clipped = clipped.substr(0, clipped.length() - 1)
	return clipped + "…"

func _skill_card(rect: Rect2, key: String, id: String) -> void:
	var fighter = game.player
	var cost: float = fighter.skill_cost(id)
	var cooldown: float = float(fighter.cooldowns.get(id, 0.0))
	var ready: bool = fighter.skill_ready(id) and game.phase == "fight" and not game.paused
	var active: bool = fighter.state == "skill" and fighter.skill_id == id
	var accent = _role_color(fighter) if ready or active else MUTED
	var border = Color(accent, 0.65 if ready or active else 0.23)
	draw_rect(rect, Color(0.022, 0.034, 0.035, 0.78))
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), border, 1.0, true)
	var key_rect = Rect2(rect.position + Vector2(10, 12), Vector2(28, 28))
	draw_rect(key_rect, Color(accent, 0.12 if ready or active else 0.05))
	draw_rect(key_rect, Color(accent, 0.55), false, 1.0)
	_text(key_rect.position + Vector2(8, 21), key, 16, accent)
	_text(rect.position + Vector2(49, 27), fighter.skill_name(id), 16, PAPER if ready or active else MUTED, true)
	var status = "就绪 · %d 体力" % int(cost) if ready else "伺机 · %d 体力" % int(cost)
	if cooldown > 0.05:
		status = "冷却  %.1f 秒" % cooldown
	elif fighter.stamina < cost:
		status = "体力不足 · 需 %d" % int(cost)
	if active:
		status = "收势中" if fighter.skill_stage == "recovery" else "施展中"
	_text(rect.position + Vector2(49, 45), status, 10, accent if ready or active else MUTED)
	var progress: float = clampf(1.0 - cooldown / maxf(fighter.skill_cooldown(id), 0.01), 0.0, 1.0)
	var bar = Rect2(rect.position + Vector2(10, rect.size.y - 7), Vector2(rect.size.x - 20, 2))
	draw_rect(bar, Color(0.18, 0.28, 0.29, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), Color(accent, 0.9 if ready or active else 0.4))

func _ultimate_card(rect: Rect2) -> void:
	var fighter = game.player
	var energy: float = clampf(fighter.energy, 0.0, 100.0)
	var charged: bool = energy >= 99.99
	var ready: bool = fighter.skill_ready("ultimate") and game.phase == "fight" and not game.paused
	var active: bool = fighter.state == "ultimate"
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
	var accent = _role_color(fighter)
	draw_rect(rect.grow(3), Color(accent, 0.05 + pulse * 0.10) if charged else Color.TRANSPARENT)
	draw_rect(rect, Color(0.025, 0.035, 0.035, 0.82))
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(accent, 0.65 + pulse * 0.25 if charged else 0.3), 1.0, true)
	var key_rect = Rect2(rect.position + Vector2(10, 12), Vector2(28, 28))
	draw_rect(key_rect, Color(accent, 0.22 if charged else 0.07))
	draw_rect(key_rect, Color(accent, 0.85 if charged else 0.35), false, 1.0)
	_text(key_rect.position + Vector2(8, 21), "U", 16, accent)
	_text(rect.position + Vector2(49, 27), fighter.ultimate_name(), 17, PAPER if charged or active else MUTED, true)
	var status = "战意 %d / 100 · 攻防积攒" % int(energy)
	if charged:
		status = "战意已满 · 按 U 施展" if ready else "战意已满 · 伺机出招"
	if active:
		status = "蓄势" if fighter.skill_stage == "windup" else "绝技施展中"
	_text(rect.position + Vector2(49, 45), status, 10, accent if charged or active else MUTED)
	var bar = Rect2(rect.position + Vector2(10, rect.size.y - 7), Vector2(rect.size.x - 20, 2))
	draw_rect(bar, Color(0.18, 0.28, 0.29, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * energy / 100.0, bar.size.y)), accent)
	for tick in [0.25, 0.5, 0.75]:
		var x: float = bar.position.x + bar.size.x * tick
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.03, 0.07, 0.08, 0.8), 1.0)

func _ultimate_warning() -> void:
	if game.phase != "fight" or game.paused:
		return
	var fighter = game.enemy if game.enemy.state == "ultimate" and game.enemy.skill_stage == "windup" else game.player
	if fighter.state != "ultimate" or fighter.skill_stage != "windup":
		return
	var hostile: bool = fighter == game.enemy
	var accent = _role_color(fighter)
	var rect = Rect2(438, 215, 404, 76)
	draw_rect(rect, Color(0.035, 0.065, 0.08, 0.90))
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(accent, 0.75), 1.5, true)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color(accent, 0.35), 1.0, true)
	var title: String = fighter.ultimate_name()
	var width = display_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
	_text(Vector2((1280 - width) * 0.5, 250), title, 27, accent, true)
	var tactic = "连续追击 · 可打断" if bool(fighter.skill_profile("ultimate").get("chase", fighter.skill_profile("ultimate").kind == "chase")) else ("重击蓄势 · 转向脱离 / 冲刺" if game.combat_mode == "mounted" else "重击蓄势 · 后撤脱离 / 闪避")
	var special: Dictionary = fighter.skill_profile("ultimate").get("special", {})
	match String(special.get("formation", special.get("type",""))):
		"spear_volley": tactic = "三轮长矛 · 横移离开矛路"
		"cavalry": tactic = "六骑冲阵 · 横穿离开阵线"
		"diagonal_cleave": tactic = "三刀错峰 · 闪出斜列刀路"
		"ground_pincer": tactic = "两翼收束 · 提前离开夹击线"
		"halberd_encircle": tactic = "六戟合围 · 射出前离开阵心"
		"returning_fan": tactic = "三刃抛回 · 侧向避开回旋"
	var subtitle = ("对手 · " if hostile else "己方 · ") + tactic
	var subtitle_width = body_font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(Vector2((1280 - subtitle_width) * 0.5, 276), subtitle, 12, PAPER)

func _draw() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player) or game.phase == "menu":
		return
	# The shallow top veil makes the duel readable against sky and gate alike.
	draw_texture_rect(top_veil, Rect2(0, 0, 1280, 158), false)
	for i in 2:
		var fighter = game.player if i == 0 else game.enemy
		var x = 52.0 if i == 0 else 796.0
		var color = JADE if i == 0 else GOLD
		var name_text = game.fighter_name(fighter.character_id)
		_text(Vector2(x, 57), name_text, 29, PAPER, true)
		var equipment = Roster.weapon_name(fighter.weapon_id)
		if game.combat_mode == "mounted":
			var horse_color: String = game.horse_color if i == 0 else game.enemy_horse_color
			equipment += " · " + ("棕马" if horse_color == "brown" else "白马")
		_text(Vector2(x + 85, 55), ("你  /  " if i == 0 else "对手  /  ") + equipment, 12, MUTED)
		draw_rect(Rect2(x, 80, 432, 13), Color(0.02, 0.06, 0.075, 0.83))
		var width = 432 * displayed_hp[i] / 120.0
		var fill_x = x if i == 0 else x + 432 - width
		draw_rect(Rect2(fill_x, 80, width, 13), color)
		draw_rect(Rect2(x, 102, 432, 4), Color(0.02, 0.06, 0.075, 0.8))
		var sw = 432 * fighter.stamina / 100.0
		draw_rect(Rect2(x if i == 0 else x + 432 - sw, 102, sw, 4), Color("d0bd8b") if fighter.stamina > 25 else Color("c77d62"))
		var energy_width: float = 432 * clampf(fighter.energy, 0.0, 100.0) / 100.0
		draw_rect(Rect2(x, 113, 432, 3), Color(0.02, 0.06, 0.075, 0.8))
		draw_rect(Rect2(x if i == 0 else x + 432 - energy_width, 113, energy_width, 3), _role_color(fighter))
		_text(Vector2(x, 138), "体力 %d    战意 %d%s" % [fighter.stamina, fighter.energy, " · 绝技就绪" if fighter.energy >= 99.99 else ""], 11, GOLD if fighter.energy >= 99.99 else MUTED)
		for point in 2:
			draw_circle(Vector2(x + 403 + point * 22, 133), 4.0, color if game.scores[i] > point else Color("445c60"))
	_text(Vector2(596, 31), "问锋 · 马战" if game.combat_mode == "mounted" else "问锋 · 步战", 13, GOLD, true)
	_text(Vector2(603, 83), "%02d" % int(ceil(game.round_time)), 43, PAPER)
	_text(Vector2(590, 113), "第 %d 回合" % game.round_number, 13, MUTED)
	if game.combat_mode == "mounted":
		var cooldown: float = maxf(0.0, game.player.mount_charge_cooldown)
		var charge_status = "冲刺冷却 %.1f 秒" % cooldown if cooldown > 0.05 else "冲刺就绪"
		_text(Vector2(52, 164), "骑速 %.1f 米/秒  ·  %s" % [float(game.player.call("cavalry_status").get("signed_speed",game.player.mount_speed)) if game.player.has_method("cavalry_status") else game.player.mount_speed, charge_status], 12, JADE)
	if game.phase in ["countdown", "round_end"]:
		var title = ""
		var subtitle = ""
		if game.phase == "countdown":
			title = str(int(ceil(game.phase_clock))) if game.phase_clock > 0.7 else "拔刃"
			subtitle = "第 %d 回合  /  三局两胜" % game.round_number
		else:
			title = "此局得胜" if game.last_winner == 0 else "此局落败"
			subtitle = "%d  :  %d" % [game.scores[0], game.scores[1]]
		var width = display_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		_text(Vector2((1280 - width) / 2.0, 314), title, 64, GOLD, true)
		var subwidth = body_font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(Vector2((1280 - subwidth) / 2.0, 350), subtitle, 16, PAPER)
	if game.toast_time > 0.0 and game.phase == "fight":
		var text: String = game.toast
		var width = body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		_text(Vector2((1280 - width) / 2.0, 191), text, 19, GOLD)
	if game.lock_active() and game.phase == "fight" and is_instance_valid(game.camera):
		var target = game.enemy.global_position + Vector3.UP * (2.55 if game.combat_mode == "mounted" else 1.20)
		if not game.camera.is_position_behind(target):
			var screen = game.camera.unproject_position(target)
			var color = Color(JADE, 0.95)
			draw_arc(screen, 12.0, 0.0, TAU, 32, Color(JADE, 0.65), 1.2, true)
			draw_circle(screen, 2.5, color)
			for side in [-1, 1]:
				draw_line(screen + Vector2(side * 26, -7), screen + Vector2(side * 31, 0), color, 1.5, true)
				draw_line(screen + Vector2(side * 31, 0), screen + Vector2(side * 26, 7), color, 1.5, true)
	if game.lock_active():
		_text(Vector2(569, 146), "锁定 · " + game.fighter_name(game.enemy.character_id), 12, JADE)
	if game.combat_mode == "mounted":
		var offset: Vector3 = game.enemy.position-game.player.position
		var bearing = game.player.forward().signed_angle_to(offset.slide(Vector3.UP).normalized(),Vector3.UP)
		var direction = "前方" if absf(bearing)<0.55 else ("后方" if absf(bearing)>2.5 else ("左侧" if bearing>0 else "右侧"))
		var status: Dictionary = game.player.call("cavalry_status") if game.player.has_method("cavalry_status") else {}
		var aim = int(status.get("attack_side",0))
		_text(Vector2(52,188),"对手 %s · %d米  |  出手 %s" % [direction,offset.length(),"右侧" if aim<0 else ("左侧" if aim>0 else "前方")],12,PAPER)
	_ultimate_warning()
	draw_texture_rect(bottom_veil, Rect2(0, 690, 1280, 110), false)
	_text(Vector2(52, 738), "W/S 调速  A/D 转马  X 刹车" if game.combat_mode == "mounted" else ("W/S 进退  A/D 绕敌  J/K 出招" if game.lock_active() else "WASD 移动  J 连击  K 重击"), 12, PAPER)
	_text(Vector2(52, 764), "Z/C 左右击 · Space 催马 · V 跳跃" if game.combat_mode == "mounted" else "L 格挡 · Space 闪避 · V 跳跃 · Esc 暂停", 11, MUTED)
	_skill_card(Rect2(460, 716, 210, 64), "Q", "rush")
	_skill_card(Rect2(682, 716, 210, 64), "E", "counter")
	_ultimate_card(Rect2(904, 716, 324, 64))
