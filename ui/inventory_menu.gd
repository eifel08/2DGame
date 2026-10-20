class_name InventoryMenu
extends CanvasLayer
## Inventory window (I / Tab / Esc, gamepad Back) with two tabs:
##   Status    - shards (the only number), health and energy as bars
##   Abilities - the 4 hotkey slots (top) and every unlocked ability (bottom)
##
## Keyboard only, no mouse needed:
##   Q / E (or PgUp / PgDn)  switch tab
##   Arrow keys              move between cards
##   Enter / Space           on a slot: select it, then pick an ability below
##                           on an ability: equip it into the selected slot
##                           on the empty card: clear the selected slot
##   Backspace / Delete      clear the selected slot
## Loadout changes only work while standing at a checkpoint.
## The game simulation is paused while the window is open.

const ABILITIES_TAB := 1

var game: Node
var panel: PanelContainer
var tabs: TabContainer
var shards_label: Label
var health_bar: StatBar
var energy_bar: StatBar
var slot_cards: Array[AbilityCard] = []
var pool_cards: Array[AbilityCard] = []
var empty_card: AbilityCard
var pool_grid: GridContainer
var detail_icon: AbilityIcon
var detail_name: Label
var detail_desc: Label
var detail_gauge: EnergyGauge
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
		_rebuild_pool()
		refresh()
		_focus_default()
	else:
		get_viewport().gui_release_focus()


# ---------- Keyboard handling ----------

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"menu_prev_tab"):
		switch_tab(-1)
	elif event.is_action_pressed(&"menu_next_tab"):
		switch_tab(1)
	elif event.is_action_pressed(&"menu_clear") and tabs.current_tab == ABILITIES_TAB:
		clear_selected_slot()
	else:
		return
	get_viewport().set_input_as_handled()


func switch_tab(step: int) -> void:
	tabs.current_tab = posmod(tabs.current_tab + step, tabs.get_tab_count())
	_focus_default()


func _focus_default() -> void:
	if tabs.current_tab == ABILITIES_TAB:
		slot_cards[selected_slot].grab_focus()
	else:
		get_viewport().gui_release_focus()


# ---------- Actions ----------

func select_slot(slot: int) -> void:
	selected_slot = slot
	refresh()
	if not game.ultimates.can_change_loadout():
		return
	# Jump to the ability currently in this slot (or the first card).
	var current: UltimateAbility = game.ultimates.get_slot(slot)
	for card in pool_cards:
		if card.ability == current:
			card.grab_focus()
			return
	(pool_cards[0] if not pool_cards.is_empty() else empty_card).grab_focus()


func equip_ability(ability_id: String) -> bool:
	if not game.ultimates.equip(selected_slot, ability_id):
		_flash_notice()
		return false
	refresh()
	slot_cards[selected_slot].grab_focus()
	return true


func clear_selected_slot() -> bool:
	if not game.ultimates.unequip(selected_slot):
		_flash_notice()
		return false
	refresh()
	slot_cards[selected_slot].grab_focus()
	return true


func _flash_notice() -> void:
	var tween := create_tween()
	notice_label.modulate = Color(1.6, 1.6, 1.6)
	tween.tween_property(notice_label, "modulate", Color.WHITE, 0.4)


# ---------- Refresh ----------

func refresh() -> void:
	var p: Player = game.player
	var h := p.health
	var manager: UltimateManager = game.ultimates
	var max_energy := h.get_max_energy()
	var can_swap := manager.can_change_loadout()

	shards_label.text = str(game.player_data.currency)
	health_bar.set_values(h.health, h.get_max_health(), Config.vitals.max_health, Color("#ff5e6c"))
	energy_bar.set_values(h.energy, max_energy, Config.vitals.max_energy, Color("#4fd1ff"))

	for slot in slot_cards.size():
		var card := slot_cards[slot]
		card.show_ability(manager.get_slot(slot), max_energy, slot + 1)
		card.button_pressed = slot == selected_slot
	for card in pool_cards:
		card.show_ability(card.ability, max_energy, 0, not can_swap)
	empty_card.show_ability(null, max_energy, 0, not can_swap)

	if can_swap:
		notice_label.text = "At a checkpoint: choose a slot, then an ability. The empty card clears the slot."
		notice_label.add_theme_color_override("font_color", Color("#8dffb0"))
	else:
		notice_label.text = "Abilities can only be changed at a checkpoint."
		notice_label.add_theme_color_override("font_color", Color("#ffb3b3"))
	_show_details(manager.get_slot(selected_slot))


## Name + description are only shown for the focused/selected ability.
func _show_details(ability: UltimateAbility) -> void:
	if ability == null:
		detail_icon.set_icon("empty", Color.WHITE)
		detail_name.text = "Empty slot"
		detail_desc.text = "No ability is assigned to this key."
		detail_gauge.visible = false
		return
	detail_icon.set_icon(ability.icon, ability.color)
	detail_name.text = ability.display_name
	detail_desc.text = ability.description
	detail_gauge.visible = true
	detail_gauge.set_requirement(ability.get_cost(), game.player.health.get_max_energy())


func _rebuild_pool() -> void:
	var abilities: Array[UltimateAbility] = game.ultimates.unlocked_abilities()
	if pool_cards.size() == abilities.size():
		for i in abilities.size():
			pool_cards[i].ability = abilities[i]
		return
	for card in pool_cards:
		card.queue_free()
	pool_cards.clear()
	for ability in abilities:
		var card := AbilityCard.new()
		card.ability = ability
		card.pressed.connect(func() -> void: equip_ability(card.ability.id))
		card.focus_entered.connect(func() -> void: _show_details(card.ability))
		pool_grid.add_child(card)
		pool_cards.append(card)
	pool_grid.move_child(empty_card, -1)


# ---------- Construction ----------

func _build() -> void:
	panel = PanelContainer.new()
	panel.layout_direction = Control.LAYOUT_DIRECTION_LTR
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -230.0
	panel.offset_bottom = 230.0
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
	title.text = "INVENTORY"
	title.add_theme_color_override("font_color", Color("#ffd43b"))
	root.add_child(title)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	root.add_child(tabs)
	tabs.add_child(_build_status_tab())
	tabs.add_child(_build_abilities_tab())

	var keys := Label.new()
	keys.text = "Q / E  tab    Arrows  move    Enter  select    Backspace  clear slot    I / Tab / Esc  close"
	keys.add_theme_font_size_override("font_size", 10)
	keys.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	root.add_child(keys)


func _build_status_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Status"
	box.add_theme_constant_override("separation", 14)
	box.add_child(_spacer(6))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 16)
	box.add_child(grid)

	grid.add_child(_name_label("Shards", Coin.COLOR))
	shards_label = Label.new()
	shards_label.add_theme_font_size_override("font_size", 18)
	grid.add_child(shards_label)
	grid.add_child(_name_label("Health", Color("#ff5e6c")))
	health_bar = StatBar.new()
	grid.add_child(health_bar)
	grid.add_child(_name_label("Energy", Color("#4fd1ff")))
	energy_bar = StatBar.new()
	grid.add_child(energy_bar)

	var note := Label.new()
	note.text = "The bar frames grow when your maximum health or energy increases."
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	note.add_theme_font_size_override("font_size", 11)
	box.add_child(note)
	return box


func _build_abilities_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Abilities"
	box.add_theme_constant_override("separation", 6)

	box.add_child(_section("EQUIPPED"))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	box.add_child(slots)
	for slot in PlayerData.SLOT_COUNT: # Left to right: keys 1, 2, 3, 4.
		var card := AbilityCard.new()
		card.toggle_mode = true
		var s := slot
		card.pressed.connect(func() -> void: select_slot(s))
		card.focus_entered.connect(func() -> void: _show_details(game.ultimates.get_slot(s)))
		slots.add_child(card)
		slot_cards.append(card)

	box.add_child(_section("UNLOCKED"))
	pool_grid = GridContainer.new()
	pool_grid.columns = 6
	pool_grid.add_theme_constant_override("h_separation", 8)
	box.add_child(pool_grid)
	empty_card = AbilityCard.new()
	empty_card.pressed.connect(func() -> void: clear_selected_slot())
	empty_card.focus_entered.connect(func() -> void: _show_details(null))
	pool_grid.add_child(empty_card)

	# Detail area: enough fixed height that the last line is never clipped.
	var detail := HBoxContainer.new()
	detail.custom_minimum_size = Vector2(0, 86)
	detail.add_theme_constant_override("separation", 12)
	box.add_child(detail)
	detail_icon = AbilityIcon.new()
	detail_icon.custom_minimum_size = Vector2(56, 56)
	detail_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail.add_child(detail_icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(text_box)
	detail_name = Label.new()
	detail_name.add_theme_font_size_override("font_size", 15)
	text_box.add_child(detail_name)
	detail_gauge = EnergyGauge.new()
	detail_gauge.custom_minimum_size = Vector2(160, 8)
	detail_gauge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	text_box.add_child(detail_gauge)
	detail_desc = Label.new()
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.custom_minimum_size = Vector2(0, 40)
	detail_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	text_box.add_child(detail_desc)

	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_font_size_override("font_size", 11)
	box.add_child(notice_label)
	return box


func _name_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 17)
	return l


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
