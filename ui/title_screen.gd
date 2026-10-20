class_name TitleScreen
extends Control
## Title screen: Play (save slot selection) and Settings. Everything works
## with mouse and keyboard/gamepad. Choosing a slot loads it (or starts a new
## game in an empty slot) and switches to scenes/game.tscn.

const GAME_SCENE := "res://scenes/game.tscn"

var main_panel: PanelContainer
var slots_panel: PanelContainer
var settings: SettingsPanel
var play_button: Button
var settings_button: Button
var quit_button: Button
var back_button: Button
var slot_buttons: Array[Button] = []
var delete_buttons: Array[Button] = []
var change_scene := true ## Tests set false and read `chosen_slot` instead.
var chosen_slot := -1
var _confirm_delete := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	var bg := ColorRect.new()
	bg.color = Color("#090b1a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_main()
	_build_slots()
	settings = SettingsPanel.new()
	settings.visible = false
	settings.closed.connect(show_main)
	add_child(MenuKit.center(settings))
	show_main()


func _build_main() -> void:
	main_panel = MenuKit.panel(Vector2(420, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	main_panel.add_child(box)
	var title := MenuKit.label("2DGame", 44, Color("#ffd36b"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := MenuKit.label("A metroidvania core", 14, Color(1, 1, 1, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	play_button = MenuKit.button("Play", show_slots)
	settings_button = MenuKit.button("Settings", show_settings)
	quit_button = MenuKit.button("Quit", func() -> void: get_tree().quit())
	box.add_child(play_button)
	box.add_child(settings_button)
	box.add_child(quit_button)
	MenuKit.link_rows([[play_button], [settings_button], [quit_button]])
	var hint := MenuKit.label("Mouse, or arrows + Enter", 11, Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(MenuKit.center(main_panel))


func _build_slots() -> void:
	slots_panel = MenuKit.panel(Vector2(640, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	slots_panel.add_child(box)
	box.add_child(MenuKit.label("CHOOSE A SAVE SLOT", 20, Color("#ffd43b")))
	var rows := []
	for i in Saves.SLOT_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var slot := i
		var b := MenuKit.button("", func() -> void: choose_slot(slot), 460)
		var d := MenuKit.button("Delete", func() -> void: delete_slot(slot), 130)
		row.add_child(b)
		row.add_child(d)
		box.add_child(row)
		slot_buttons.append(b)
		delete_buttons.append(d)
		rows.append([b, d])
	back_button = MenuKit.button("Back", show_main)
	box.add_child(back_button)
	rows.append([back_button])
	MenuKit.link_rows(rows)
	add_child(MenuKit.center(slots_panel))


func show_main() -> void:
	main_panel.visible = true
	slots_panel.visible = false
	settings.visible = false
	play_button.grab_focus()


func show_slots() -> void:
	main_panel.visible = false
	slots_panel.visible = true
	_confirm_delete = -1
	refresh_slots()
	slot_buttons[0].grab_focus()


func show_settings() -> void:
	main_panel.visible = false
	slots_panel.visible = false
	settings.open()


func refresh_slots() -> void:
	for i in slot_buttons.size():
		slot_buttons[i].text = Saves.summary(i)
		delete_buttons[i].disabled = not Saves.has_slot(i)
		delete_buttons[i].text = "Confirm?" if _confirm_delete == i else "Delete"


func choose_slot(slot: int) -> void:
	chosen_slot = slot
	Saves.start_slot(slot)
	if change_scene:
		get_tree().change_scene_to_file(GAME_SCENE)


## First press asks for confirmation, the second deletes.
func delete_slot(slot: int) -> void:
	if _confirm_delete == slot:
		Saves.delete_slot(slot)
		_confirm_delete = -1
	else:
		_confirm_delete = slot
	refresh_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and slots_panel.visible:
		get_viewport().set_input_as_handled()
		show_main()
		return
	# Safety net: if nothing holds the focus (e.g. a click on the background),
	# the first arrow or confirm press focuses the panel's first button.
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and owner.is_visible_in_tree():
		return
	for action in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"]:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			_focus_default()
			return


func _focus_default() -> void:
	if slots_panel.visible:
		slot_buttons[0].grab_focus()
	elif settings.visible:
		settings.focus_first()
	else:
		play_button.grab_focus()
