class_name MenuKit
extends RefCounted
## Shared menu building blocks. Every control made here works the same with
## mouse and keyboard/gamepad: hovering focuses it, arrows/WASD/D-pad move the
## focus, and Enter/Space/Z/A or a mouse click confirms.


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	return theme


static func panel(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.layout_direction = Control.LAYOUT_DIRECTION_LTR
	p.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.1, 0.96)
	style.border_color = Color("#6f7fb8")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", style)
	p.theme = make_theme()
	return p


static func label(text: String, font_size := 15, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, min_width := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 40)
	b.focus_mode = Control.FOCUS_ALL
	hover_focus(b)
	b.focus_entered.connect(func() -> void: Sfx.play("ui_move"))
	b.pressed.connect(func() -> void:
		Sfx.play("ui_confirm")
		on_press.call())
	return b


## Mouse hover moves keyboard focus, so mouse and keyboard never disagree.
static func hover_focus(c: Control) -> void:
	c.focus_mode = Control.FOCUS_ALL
	c.mouse_entered.connect(func() -> void:
		if c.is_visible_in_tree():
			c.grab_focus())


static func center(node: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(node)
	return cc
