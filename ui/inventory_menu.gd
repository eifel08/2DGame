class_name InventoryMenu
extends CanvasLayer
## Inventory window (I / Tab / Esc, gamepad Back) with two tabs:
##   Status    - shards (the only number), health and energy as bars
##   Abilities - the 4 hotkey slots (top) and every unlocked ability (bottom)
##
## Keyboard only, no mouse needed:
##   Left / Right on the tab row      switch tab (also Q / E, PgUp / PgDn)
##   Down / Up                        move between the tab row and the cards
##   Arrow keys                       move between cards
##   Z / Enter / Space (confirm)
##     on an equipped ability (slot or grid)  unequip it
##     on an unequipped ability (grid)        then choose slot 1-4; an occupied
##                                            slot is replaced
##   Backspace / Delete               cancel the slot choice, or clear the focused slot
## Loadout changes only work while standing at the saved checkpoint.
## The game simulation is paused while the window is open.

const STATUS_TAB := 0
const ABILITIES_TAB := 1

var game: Node
var panel: PanelContainer
var tabs: TabContainer
var tab_bar: TabBar
var shards_label: Label
var health_bar: StatBar
var energy_bar: StatBar
var slot_cards: Array[AbilityCard] = []
var pool_cards: Array[AbilityCard] = []
var pool_grid: GridContainer
var detail_icon: AbilityIcon
var detail_name: Label
var detail_desc: Label
var detail_gauge: EnergyGauge
var notice_label: Label
var pending_ability_id := "" ## Ability waiting for a slot choice.


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
	pending_ability_id = ""
	if panel.visible:
		_rebuild_pool()
		refresh()
		tab_bar.grab_focus() # Left / Right switches tabs right away.
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
		_on_clear_pressed()
	else:
		return
	get_viewport().set_input_as_handled()


func switch_tab(step: int) -> void:
	tabs.current_tab = posmod(tabs.current_tab + step, tabs.get_tab_count())
	tab_bar.grab_focus()


func _on_tab_changed(_tab: int) -> void:
	pending_ability_id = ""
	if is_open():
		refresh()


# ---------- Loadout actions ----------

## Confirm on a top slot.
func press_slot(slot: int) -> void:
	var manager: UltimateManager = game.ultimates
	if pending_ability_id != "":
		# Assign the chosen ability here (an occupied slot is replaced).
		if manager.equip(slot, pending_ability_id):
			pending_ability_id = ""
		else:
			_flash_notice()
	elif manager.get_slot(slot) != null:
		if not manager.unequip(slot): # Confirm on an equipped slot unequips it.
			_flash_notice()
	refresh()


## Confirm on an ability in the lower grid.
func press_pool(ability: UltimateAbility) -> void:
	var manager: UltimateManager = game.ultimates
	if not manager.can_change_loadout():
		_flash_notice()
		return
	var slot := manager.slot_of(ability.id)
	if slot >= 0:
		manager.unequip(slot) # Equipped -> unequip.
		pending_ability_id = ""
		refresh()
		return
	# Unequipped -> choose a slot: focus the first empty slot (or slot 1).
	pending_ability_id = ability.id
	refresh()
	var target: int = game.player_data.equipped.find("")
	slot_cards[target if target >= 0 else 0].grab_focus()


func _on_clear_pressed() -> void:
	if pending_ability_id != "":
		pending_ability_id = ""
		refresh()
		return
	var focus := get_viewport().gui_get_focus_owner()
	var slot := slot_cards.find(focus)
	if slot >= 0:
		press_slot(slot)


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

	shards_label.text = str(game.player_data.currency)
	health_bar.set_values(h.health, h.get_max_health(), Config.vitals.max_health, Color("#ff5e6c"))
	energy_bar.set_values(h.energy, max_energy, Config.vitals.max_energy, Color("#4fd1ff"))

	for slot in slot_cards.size():
		slot_cards[slot].show_ability(manager.get_slot(slot), max_energy, slot + 1)
	# Every unlocked ability keeps a crisp icon; equipped ones show their key.
	for card in pool_cards:
		var slot := manager.slot_of(card.ability.id)
		card.show_ability(card.ability, max_energy, slot + 1 if slot >= 0 else 0)
		card.button_pressed = card.ability.id == pending_ability_id

	if not manager.can_change_loadout():
		notice_label.text = "Abilities can only be changed at your saved checkpoint."
		notice_label.add_theme_color_override("font_color", Color("#ffb3b3"))
	elif pending_ability_id != "":
		notice_label.text = "Choose a key slot for %s. An occupied slot is replaced. Backspace cancels." \
			% manager.get_ability(pending_ability_id).display_name
		notice_label.add_theme_color_override("font_color", Color("#ffd36b"))
	else:
		notice_label.text = "Confirm an equipped ability to remove it. Confirm a free one, then pick its slot."
		notice_label.add_theme_color_override("font_color", Color("#8dffb0"))
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if focus is AbilityCard:
		_show_details(focus.ability)
	elif pending_ability_id != "":
		_show_details(manager.get_ability(pending_ability_id))
	else:
		_show_details(manager.get_slot(0))


## Name + description are only shown for the focused ability.
func _show_details(ability: UltimateAbility) -> void:
	if ability == null:
		detail_icon.set_icon("empty", Color.WHITE)
		detail_name.text = "Free slot"
		detail_desc.text = "Choose an ability below to place it on this key."
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
		card.toggle_mode = true
		card.pressed.connect(func() -> void: press_pool(card.ability))
		card.focus_entered.connect(func() -> void: _show_details(card.ability))
		pool_grid.add_child(card)
		pool_cards.append(card)


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
	tab_bar = tabs.get_tab_bar()
	tab_bar.focus_mode = Control.FOCUS_ALL # Left / Right on the tab row switches tabs.
	root.add_child(tabs)
	tabs.add_child(_build_status_tab())
	tabs.add_child(_build_abilities_tab())
	tabs.tab_changed.connect(_on_tab_changed) # After the tabs exist.

	var keys := Label.new()
	keys.text = "Left / Right  tab    Down / Up  move    Z / Enter  confirm    Backspace  cancel    I / Tab / Esc  close"
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
		var s := slot
		card.pressed.connect(func() -> void: press_slot(s))
		card.focus_entered.connect(func() -> void:
			if pending_ability_id == "":
				_show_details(game.ultimates.get_slot(s)))
		slots.add_child(card)
		slot_cards.append(card)

	box.add_child(_section("UNLOCKED"))
	pool_grid = GridContainer.new()
	pool_grid.columns = 6
	pool_grid.add_theme_constant_override("h_separation", 8)
	box.add_child(pool_grid)

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
