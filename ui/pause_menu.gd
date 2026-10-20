class_name PauseMenu
extends CanvasLayer
## In-game pause menu (Esc / P / gamepad Start): Resume, Inventory, Settings,
## Quit to title. The game simulation is paused while it is open. Works with
## mouse and keyboard/gamepad.

var game: Node
var root: Control
var panel: PanelContainer
var settings: SettingsPanel
var resume_button: Button


func setup(p_game: Node) -> void:
	game = p_game
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	panel = MenuKit.panel(Vector2(360, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(MenuKit.label("PAUSED", 24, Color("#ffd43b")))
	resume_button = MenuKit.button("Resume", close)
	box.add_child(resume_button)
	box.add_child(MenuKit.button("Inventory", func() -> void:
		close()
		game.inventory.toggle()))
	box.add_child(MenuKit.button("Settings", func() -> void:
		panel.visible = false
		settings.open()))
	box.add_child(MenuKit.button("Quit to title", func() -> void: game.quit_to_title()))
	root.add_child(MenuKit.center(panel))
	settings = SettingsPanel.new()
	settings.visible = false
	settings.handle_cancel = false # Esc is the pause key; handled in toggle().
	settings.closed.connect(func() -> void:
		panel.visible = true
		resume_button.grab_focus())
	root.add_child(MenuKit.center(settings))
	root.visible = false


func is_open() -> bool:
	return root != null and root.visible


## Pause key: opens the menu, steps back from Settings, or resumes.
func toggle() -> void:
	if not is_open():
		root.visible = true
		panel.visible = true
		settings.visible = false
		resume_button.grab_focus()
	elif settings.visible:
		if not settings.is_rebinding():
			settings.close()
	else:
		close()


func close() -> void:
	root.visible = false
	get_viewport().gui_release_focus()
