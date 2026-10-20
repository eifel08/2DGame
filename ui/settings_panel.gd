class_name SettingsPanel
extends PanelContainer
## Settings: audio volumes, screen shake, fullscreen and key bindings. Used
## by the title screen and the pause menu. Mouse and keyboard both work;
## to rebind, confirm a key button, then press the new key (Esc cancels).

signal closed

var _first: Control
var _key_buttons := {} ## action -> Button
var _rebinding := ""
var _sliders := {}
var _checks := {}
var back_button: Button
var handle_cancel := true ## Close on ui_cancel (Esc) when not rebinding.


func _init() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	custom_minimum_size = Vector2(620, 470)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.1, 0.97)
	style.border_color = Color("#6f7fb8")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	theme = MenuKit.make_theme()
	_build()


func open() -> void:
	visible = true
	refresh()
	focus_first()


func focus_first() -> void:
	_first.grab_focus()


func close() -> void:
	_rebinding = ""
	visible = false
	closed.emit()


func refresh() -> void:
	for key in _sliders:
		_sliders[key].set_value_no_signal(Settings.get(key))
	for key in _checks:
		_checks[key].set_pressed_no_signal(Settings.get(key))
	for action in _key_buttons:
		_key_buttons[action].text = Settings.key_name(action)


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(MenuKit.label("SETTINGS", 20, Color("#ffd43b")))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var rows := [] # Focus order, top to bottom (see MenuKit.link_rows).
	box.add_child(MenuKit.label("AUDIO", 12, Color("#7fa2ff")))
	for row in [["master_volume", "Master volume"], ["music_volume", "Music volume"], ["sfx_volume", "Effects volume"]]:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MenuKit.hover_focus(slider)
		var key: String = row[0]
		slider.value_changed.connect(func(v: float) -> void:
			Settings.set_value(key, v)
			Sfx.play("ui_move"))
		_sliders[key] = slider
		box.add_child(_row(row[1], slider))
		rows.append([slider])
		if _first == null:
			_first = slider

	box.add_child(MenuKit.label("DISPLAY", 12, Color("#7fa2ff")))
	for row in [["screen_shake", "Screen shake"], ["fullscreen", "Fullscreen"]]:
		var check := CheckBox.new()
		check.text = row[1]
		MenuKit.hover_focus(check)
		var key: String = row[0]
		check.toggled.connect(func(on: bool) -> void:
			Settings.set_value(key, on)
			Sfx.play("ui_confirm"))
		_checks[key] = check
		box.add_child(check)
		rows.append([check])

	box.add_child(MenuKit.label("CONTROLS  (confirm a key, then press the new key)", 12, Color("#7fa2ff")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for action in Settings.REBINDABLE:
		if not InputMap.has_action(action):
			continue
		grid.add_child(MenuKit.label(Settings.LABELS.get(action, action), 13))
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 30)
		MenuKit.hover_focus(b)
		var a := action
		b.pressed.connect(func() -> void: _start_rebind(a))
		_key_buttons[action] = b
		grid.add_child(b)
		if rows[-1].size() == 1 and rows[-1][0] in _key_buttons.values() and rows[-1][0] != b:
			rows[-1].append(b) # Two key buttons per grid row.
		else:
			rows.append([b])

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	root.add_child(buttons)
	var reset := MenuKit.button("Reset controls", func() -> void:
		Settings.reset_controls()
		refresh(), 200)
	back_button = MenuKit.button("Back", close, 200)
	buttons.add_child(reset)
	buttons.add_child(back_button)
	rows.append([reset, back_button])
	MenuKit.link_rows(rows)
	# Down also steps Reset -> Back, so the last button is reachable with Down
	# alone; from Back it wraps to the top.
	reset.focus_neighbor_bottom = reset.get_path_to(back_button)
	back_button.focus_neighbor_bottom = back_button.get_path_to(_first)
	_first.focus_neighbor_top = _first.get_path_to(back_button)


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := MenuKit.label(text, 14)
	l.custom_minimum_size.x = 170
	row.add_child(l)
	row.add_child(control)
	return row


func _start_rebind(action: String) -> void:
	_rebinding = action
	_key_buttons[action].text = "Press a key..."
	Sfx.play("ui_confirm")


func is_rebinding() -> bool:
	return _rebinding != ""


func _input(event: InputEvent) -> void:
	if not visible or _rebinding == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var action := _rebinding
	_rebinding = ""
	if event.physical_keycode != KEY_ESCAPE:
		Settings.rebind(action, event.physical_keycode)
	refresh()
	_key_buttons[action].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and handle_cancel and _rebinding == "" and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
