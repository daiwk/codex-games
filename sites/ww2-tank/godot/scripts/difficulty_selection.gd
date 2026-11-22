extends Control

signal confirmed

const Difficulty := preload("res://scripts/campaign_difficulty.gd")
const DESCRIPTIONS := [
	"敌军较少，攻击和防御较低",
	"敌军保持常规编制和战力",
	"敌军更多，攻击和防御更高",
]
const PAPER := Color("#f3e5c8")
const MUTED := Color("#c2c5ac")
const BRASS := Color("#e8bc70")
const PANEL := Color("#1f2922")
const BORDER := Color("#626955")

var _selected := Difficulty.DEFAULT
var _buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _surface(PANEL, BORDER, 27))
	add_child(frame)
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -454
	frame.offset_right = 454
	frame.offset_top = -204
	frame.offset_bottom = 204
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 15)
	frame.add_child(stack)

	var accent := ColorRect.new()
	accent.color = BRASS
	accent.custom_minimum_size = Vector2(42, 3)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(accent)
	stack.add_child(_label("二战：装甲战线", 40, PAPER))
	stack.add_child(_label("率领 10 辆坦克、20 名步兵和 5 架飞机穿越平原与群山，守住滩头。", 18, MUTED))

	var heading := HBoxContainer.new()
	stack.add_child(heading)
	var prompt := _label("选择难度", 22, PAPER)
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(prompt)
	heading.add_child(_label("点击或按 1–3 直接出发", 16, MUTED))
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	stack.add_child(choices)
	for index in Difficulty.LEVELS.size():
		_add_choice(choices, index)
	_select_style()

	var keys := _label("WASD 移动   鼠标瞄准   空格开火   B 飞机投弹   Q 切换友军   Tab 鼠标", 15, MUTED)
	keys.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keys.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack.add_child(keys)


func selection() -> int:
	return _selected


func selection_label() -> String:
	return Difficulty.LEVELS[_selected]["label"]


func select(index: int) -> void:
	if index >= 0 and index < Difficulty.LEVELS.size():
		_selected = index
		_select_style()


func choice_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for button in _buttons:
		result.append(button.get_global_rect())
	return result


func _add_choice(parent: HBoxContainer, index: int) -> void:
	var button := Button.new()
	button.custom_minimum_size.y = 106
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_confirm.bind(index))
	parent.add_child(button)
	_buttons.append(button)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 7)
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 15
	content.offset_right = -15
	var title := _label("%d  %s" % [index + 1, Difficulty.LEVELS[index]["label"]], 27, BRASS)
	var description := _label(DESCRIPTIONS[index], 16, PAPER)
	content.add_child(title)
	content.add_child(description)


func _confirm(index: int) -> void:
	select(index)
	confirmed.emit()


func _select_style() -> void:
	for index in _buttons.size():
		var button := _buttons[index]
		var selected := index == _selected
		var face := Color("#303d31") if selected else Color("#18221c")
		button.add_theme_stylebox_override("normal", _surface(face, BRASS if selected else BORDER, 0))
		button.add_theme_stylebox_override("hover", _surface(Color("#3d4938"), BRASS, 0))
		button.add_theme_stylebox_override("pressed", _surface(Color("#45513c"), BRASS, 0))
		button.add_theme_stylebox_override("focus", _surface(Color.TRANSPARENT, PAPER, 0))


func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label


func _surface(fill: Color, rim: Color, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = rim
	box.set_border_width_all(1)
	box.set_corner_radius_all(9)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box
