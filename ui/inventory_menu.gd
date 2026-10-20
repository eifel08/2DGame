class_name InventoryMenu
extends CanvasLayer
## Inventory window (I / Tab / Esc, gamepad Back) with two tabs:
##   Status    - currency, current/max health, current/max energy
##   Abilities - the 4 equipped hotkey slots (top) and every unlocked ability (bottom)
## Swapping is allowed only at a checkpoint: select a slot, then an ability.
## The game simulation is paused while the window is open.

var game: Node
var panel: PanelContainer
var tabs: TabContainer
var status_labels := {}
var slot_buttons: Array[Button] = []
var slot_stripes: Array[ColorRect] = []
var pool_grid: GridContainer
var info_label: Label
var notice_label: Label
var selected_slot := 0


func setup(p_game: Node) -> void:
	game = p_game
	_build()
	panel.visible = false
	Events.loadout_changed.connect(func() -> void:
		if is_open():
			refresh())


func is_open() -> bool:
	return panel.visible


func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		refresh()
		slot_buttons[selected_slot].grab_focus()
	else:
		get_viewport().gui_release_focus()


# ---------- Refresh ----------

func refresh() -> void:
	var p: Player = game.player
	var h := p.health
	status_labels.currency.text = "%d" % game.player_data.currency
	status_labels.health.text = "%d / %d" % [ceili(h.health), roundi(h.get_max_health())]
	status_labels.energy.text = "%d / %d" % [floori(h.energy), roundi(h.get_max_energy())]

	var manager: UltimateManager = game.ultimates
	var can_swap := manager.can_change_loadout()
	for slot in slot_buttons.size():
		var ability := manager.get_slot(slot)
		var btn := slot_buttons[slot]
		if ability:
			btn.text = "[%d]  %s\n%d energy" % [slot + 1, ability.display_name, roundi(ability.get_cost())]
			btn.tooltip_text = "%s — %s" % [ability.kind, ability.description]
			slot_stripes[slot].color = Config.energy_tier_color(ability.get_cost())
		else:
			btn.text = "[%d]  (empty)" % (slot + 1)
			slot_stripes[slot].color = Color(1, 1, 1, 0.15)
		btn.button_pressed = slot == selected_slot

	for child in pool_grid.get_children():
		child.queue_free()
	for ability in manager.unlocked_abilities():
		var btn := Button.new()
		var equipped_slot := manager.slot_of(ability.id)
		var tag := "  (slot %d)" % (equipped_slot + 1) if equipped_slot >= 0 else ""
		btn.text = "%s%s\n%d energy" % [ability.display_name, tag, roundi(ability.get_cost())]
		btn.custom_minimum_size = Vector2(200, 46)
		btn.add_theme_color_override("font_color", Config.energy_tier_color(ability.get_cost()))
		btn.disabled = not can_swap
		btn.tooltip_text = ability.description
		var ability_id := ability.id
		btn.pressed.connect(func() -> void: _on_pool_pressed(ability_id))
		btn.focus_entered.connect(func() -> void: _show_info(ability))
		btn.mouse_entered.connect(func() -> void: _show_info(ability))
		pool_grid.add_child(btn)

	if can_swap:
		notice_label.text = "At a checkpoint: select a slot above, then choose an ability below."
		notice_label.add_theme_color_override("font_color", Color("#8dffb0"))
	else:
		notice_label.text = "Abilities can only be swapped while resting at a checkpoint."
		notice_label.add_theme_color_override("font_color", Color("#ffb3b3"))
	var current := manager.get_slot(selected_slot)
	if current:
		_show_info(current)


func _show_info(ability: UltimateAbility) -> void:
	info_label.text = "%s — %s\n%s" % [ability.display_name, ability.kind, ability.description]


func _on_slot_pressed(slot: int) -> void:
	selected_slot = slot
	refresh()


func _on_pool_pressed(ability_id: String) -> void:
	if game.ultimates.equip(selected_slot, ability_id):
		refresh()
		slot_buttons[selected_slot].grab_focus()


# ---------- Construction ----------

func _build() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330.0
	panel.offset_right = 330.0
	panel.offset_top = -210.0
	panel.offset_bottom = 210.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.1, 0.96)
	style.border_color = Color("#6f7fb8")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.default_font_size = 13
	panel.theme = theme
	add_child(panel)

	var root := VBoxContainer.new()
	panel.add_child(root)
	var title := Label.new()
	title.text = "INVENTORY        (I / Tab / Esc to close)"
	title.add_theme_color_override("font_color", Color("#ffd43b"))
	root.add_child(title)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_status_tab())
	tabs.add_child(_build_abilities_tab())


func _build_status_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Status"
	box.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(_spacer(8))
	box.add_child(grid)
	for row in [["currency", "Shards", Color("#ffd36b")], ["health", "Health", Color("#ff5e6c")], ["energy", "Energy", Color("#4fd1ff")]]:
		var name_label := Label.new()
		name_label.text = row[1]
		name_label.add_theme_color_override("font_color", row[2])
		name_label.add_theme_font_size_override("font_size", 18)
		grid.add_child(name_label)
		var value_label := Label.new()
		value_label.add_theme_font_size_override("font_size", 18)
		grid.add_child(value_label)
		status_labels[row[0]] = value_label
	var note := Label.new()
	note.text = "Max health and max energy can grow with future upgrades."
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	box.add_child(_spacer(12))
	box.add_child(note)
	return box


func _build_abilities_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Abilities"
	box.add_theme_constant_override("separation", 6)

	box.add_child(_section("EQUIPPED  (keys 1 - 4)"))
	var slots := HBoxContainer.new()
	box.add_child(slots)
	for slot in PlayerData.SLOT_COUNT:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 0)
		var stripe := ColorRect.new()
		stripe.custom_minimum_size = Vector2(0, 4)
		column.add_child(stripe)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 52)
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 11)
		var s := slot
		btn.pressed.connect(func() -> void: _on_slot_pressed(s))
		column.add_child(btn)
		slots.add_child(column)
		slot_buttons.append(btn)
		slot_stripes.append(stripe)

	box.add_child(_section("UNLOCKED ABILITIES"))
	pool_grid = GridContainer.new()
	pool_grid.columns = 3
	box.add_child(pool_grid)

	notice_label = Label.new()
	notice_label.add_theme_font_size_override("font_size", 11)
	box.add_child(notice_label)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	info_label.add_theme_font_size_override("font_size", 11)
	box.add_child(info_label)
	return box


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#7fa2ff"))
	l.add_theme_font_size_override("font_size", 11)
	return l


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
