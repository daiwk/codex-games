extends Control

signal confirmed

const PAPER := Color("#f3e5c8")
const MUTED := Color("#c2c5ac")
const BRASS := Color("#e8bc70")
const INK := Color("#18201b")
const PANEL := Color("#1f2922")
const BORDER := Color("#626955")

var _roster: Array
var _selected := Vector2i(0, 1)
var _portraits: Array[TextureRect] = []
var _names: Array[Label] = []
var _stats: Array[Label] = []
var _choice_buttons: Array = [[], []]
var _start: Button


func configure(roster: Array) -> void:
	_roster = roster
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _surface(PANEL, BORDER, 24))
	add_child(frame)
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -510
	frame.offset_right = 510
	frame.offset_top = -316
	frame.offset_bottom = 316
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 11)
	frame.add_child(stack)

	stack.add_child(_label("二战：装甲战线", 40, PAPER))
	stack.add_child(_label("带领坦克、步兵和飞机迎击 5 波敌军。敌军逐波增强，第 5 波有首领。", 16, MUTED))
	var gallery := HBoxContainer.new()
	gallery.add_theme_constant_override("separation", 16)
	gallery.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(gallery)
	_build_slot(gallery, 0, "我的坦克", Color("#9fd8c4"))
	_build_slot(gallery, 1, "敌军常规坦克 · 基础属性", Color("#e59a7e"))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	stack.add_child(footer)
	var keys := _label("WASD 移动   鼠标瞄准   空格开火   B 飞机投弹   H 恢复   Q 切换友军   Tab 鼠标", 15, MUTED)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(keys)
	_start = _button("开始对战", BRASS, true)
	_start.custom_minimum_size = Vector2(214, 47)
	_start.pressed.connect(confirmed.emit)
	footer.add_child(_start)
	_select(0, _selected.x)
	_select(1, _selected.y)


func selection() -> Vector2i:
	return _selected


func start_rect() -> Rect2:
	return _start.get_global_rect()


func choice_rects(side: int) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for button: Button in _choice_buttons[side]:
		result.append(button.get_global_rect())
	return result


func _build_slot(parent: Control, side: int, title: String, tint: Color) -> void:
	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_stylebox_override("panel", _surface(Color("#151d18"), BORDER, 16))
	parent.add_child(slot)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	slot.add_child(stack)
	stack.add_child(_label(title, 18, tint))

	var preview := PanelContainer.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_theme_stylebox_override("panel", _surface(Color("#27342c"), Color("#37483b"), 5))
	stack.add_child(preview)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size.y = 170
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(portrait)
	_portraits.append(portrait)

	var name_label := _label("", 24, PAPER)
	stack.add_child(name_label)
	_names.append(name_label)
	var stats := _label("", 16, tint)
	stack.add_child(stats)
	_stats.append(stats)
	var choices := GridContainer.new()
	choices.columns = 2
	choices.add_theme_constant_override("h_separation", 7)
	choices.add_theme_constant_override("v_separation", 7)
	stack.add_child(choices)
	for index in _roster.size():
		var button := _button(_roster[index]["name"], tint)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select.bind(side, index))
		choices.add_child(button)
		_choice_buttons[side].append(button)


func _select(side: int, index: int) -> void:
	_selected[side] = index
	var chosen: Dictionary = _roster[index]
	_names[side].text = chosen["name"]
	_stats[side].text = "攻击 %d     防御 %d%%     生命 %d" % [chosen["attack"], chosen["defense"], chosen["health"]]
	_portraits[side].texture = load(chosen["preview"]) as Texture2D
	for i in _choice_buttons[side].size():
		var button: Button = _choice_buttons[side][i]
		button.set_pressed_no_signal(i == index)


func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label


func _button(value: String, tint: Color, emphasized := false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 39
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	var color := INK if emphasized else PAPER
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color)
	button.add_theme_color_override("font_focus_color", color)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_hover_pressed_color", INK)
	var face := tint if emphasized else PANEL
	button.add_theme_stylebox_override("normal", _surface(face, BORDER, 7))
	button.add_theme_stylebox_override("hover", _surface(face.lightened(0.13), tint, 7))
	button.add_theme_stylebox_override("pressed", _surface(tint, tint, 7))
	button.add_theme_stylebox_override("hover_pressed", _surface(tint.lightened(0.1), tint, 7))
	button.add_theme_stylebox_override("focus", _surface(Color.TRANSPARENT, tint, 0))
	return button


func _surface(fill: Color, rim: Color, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = rim
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box
