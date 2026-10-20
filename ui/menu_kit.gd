class_name MenuKit
extends RefCounted
## Shared menu building blocks. Every control made here works the same with
## mouse and keyboard/gamepad: hovering focuses it, arrows/WASD/D-pad move the
## focus, and Enter/Space/Z/A or a mouse click confirms.


const FOCUS_COLOR := Color("#ffd36b")


## One look for every menu: a single clear highlight on the focused control.
## Hover has no look of its own (hovering moves the focus), so the mouse and
## the keyboard can never highlight two different buttons.
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	var normal := _box(Color(0.08, 0.09, 0.13), Color(0, 0, 0, 0), 0)
	var focus := _box(Color(1.0, 0.83, 0.42, 0.14), FOCUS_COLOR, 2)
	var pressed := _box(Color(1.0, 0.83, 0.42, 0.3), FOCUS_COLOR, 2)
	var disabled := _box(Color(0.06, 0.06, 0.09), Color(0, 0, 0, 0), 0)
	for type in ["Button", "CheckBox"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, normal)
		theme.set_stylebox("hover_pressed", type, normal)
		theme.set_stylebox("pressed", type, pressed if type == "Button" else normal)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_focus_color", type, FOCUS_COLOR)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_hover_pressed_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color(1, 1, 1, 0.35))
	theme.set_stylebox("focus", "HSlider", focus)
	return theme


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(4)
	b.set_content_margin_all(6)
	return b


## Explicit focus links for a menu laid out in rows (each row is an Array of
## controls, left to right). Up/Down move between rows (same column, clamped)
## and wrap from the last row to the first and back, so the top and bottom
## items are always reachable. Left/Right move inside a row; single-control
## rows keep Left/Right for themselves (e.g. sliders).
static func link_rows(rows: Array, wrap := true) -> void:
	var flat: Array[Control] = []
	for row in rows:
		for c in row:
			flat.append(c)
	for r in rows.size():
		var row: Array = rows[r]
		for i in row.size():
			var c: Control = row[i]
			var up_r := r - 1 if r > 0 else (rows.size() - 1 if wrap else r)
			var down_r := r + 1 if r < rows.size() - 1 else (0 if wrap else r)
			var up: Control = rows[up_r][mini(i, rows[up_r].size() - 1)]
			var down: Control = rows[down_r][mini(i, rows[down_r].size() - 1)]
			c.focus_neighbor_top = c.get_path_to(up)
			c.focus_neighbor_bottom = c.get_path_to(down)
			if row.size() > 1:
				c.focus_neighbor_left = c.get_path_to(row[maxi(i - 1, 0)])
				c.focus_neighbor_right = c.get_path_to(row[mini(i + 1, row.size() - 1)])
	for i in flat.size():
		flat[i].focus_next = flat[i].get_path_to(flat[(i + 1) % flat.size()])
		flat[i].focus_previous = flat[i].get_path_to(flat[(i - 1 + flat.size()) % flat.size()])


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
		if c.is_visible_in_tree() and not c.has_focus():
			c.grab_focus())


static func center(node: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(node)
	return cc
