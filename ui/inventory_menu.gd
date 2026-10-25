class_name InventoryMenu
extends CanvasLayer
## Inventory window (I / Esc, gamepad Back) with two tabs:
##   Status    - shards (the only number), health and energy as bars
##   Abilities - the spell cross (left, a D-pad: SpellCross) and every
##               equippable spell the player knows (right)
##
## The cross: Center = Mana Discharge (fixed: it cannot be moved or removed),
## Up / Down = their slots, Left AND Right = the one Side slot (both cards
## always show the same spell). Focusing a side card frames it in gold and
## gives the other side card a dim mirror frame.
##
## Keyboard only, no mouse needed:
##   Left / Right on the tab row      switch tab (also Q / E, PgUp / PgDn)
##   Down / Up                        move between the tab row and the cards
##   Arrow keys                       move between cards
##   Enter / Space (confirm)
##     on an equipped spell (cross or pool)  unequip it
##     on a free spell (pool)                then choose a cross node; an
##                                           occupied slot is replaced
##     on the Center node                    nothing: Mana Discharge is fixed
##   Backspace / Delete               cancel the slot choice, or clear the focused node
## Loadout changes only work while standing at the saved checkpoint.
## Locked slots (padlock) take no spell until a Meditation Altar opens them.
## A new game knows no equippable spell: Spell Scrolls teach them.
## The game simulation is paused while the window is open.

const STATUS_TAB := 0
const ABILITIES_TAB := 1
## Corner tag of an equipped spell in the pool, per slot.
const SLOT_TAGS: Array[String] = ["Up", "Side", "Down"]

var game: Node
var panel: PanelContainer
var tabs: TabContainer
var tab_bar: TabBar
var shards_label: Label
var health_bar: StatBar
var energy_bar: StatBar
var cross: SpellCross
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
			_rebuild_pool() # The known pool may have changed (debug overlay).
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

## Confirm on a node of the spell cross ("Up", "Left", "Center", "Right", "Down").
func press_node(node_name: String) -> void:
	var manager: UltimateManager = game.ultimates
	var slot := SpellCross.slot_of(node_name)
	if slot == UltimateManager.NEUTRAL:
		_flash_notice() # Mana Discharge is fixed to the neutral Spell input.
		refresh()
		return
	if not manager.is_slot_open(slot):
		_flash_notice() # Locked: a Meditation Altar opens it.
		_show_details(null, true)
		return
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
	# Unequipped -> choose a node: focus the first empty open slot (or the
	# first open one). With every slot locked there is nothing to choose.
	var target := -1
	for slot_index in PlayerData.SLOT_COUNT:
		if manager.is_slot_open(slot_index) and game.player_data.equipped[slot_index] == "":
			target = slot_index
			break
	for slot_index in PlayerData.SLOT_COUNT:
		if target == -1 and manager.is_slot_open(slot_index):
			target = slot_index
	if target == -1:
		_flash_notice()
		return
	pending_ability_id = ability.id
	refresh()
	cross.card(node_for_slot(target)).grab_focus()


## The cross node that stands for a slot (the Side slot -> "Left").
static func node_for_slot(slot: int) -> String:
	match slot:
		PlayerData.SLOT_UP:
			return "Up"
		PlayerData.SLOT_SIDE:
			return "Left"
		PlayerData.SLOT_DOWN:
			return "Down"
	return "Center"


func _on_clear_pressed() -> void:
	if pending_ability_id != "":
		pending_ability_id = ""
		refresh()
		return
	var node_name := cross.node_name_of(get_viewport().gui_get_focus_owner())
	if node_name != "":
		press_node(node_name)


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
	health_bar.set_values(h.health, h.get_max_health(), h.base_max_health, Color("#ff5e6c"))
	energy_bar.set_values(h.energy, max_energy, h.base_max_energy, Color("#4fd1ff"))

	cross.refresh(max_energy)
	# Every known spell keeps a crisp icon; equipped ones show their direction.
	for card in pool_cards:
		var slot := manager.slot_of(card.ability.id)
		card.show_ability(card.ability, max_energy, SLOT_TAGS[slot] if slot >= 0 else "")
		card.button_pressed = card.ability.id == pending_ability_id

	if game.player_data.unlocked.is_empty() or game.player_data.open_slot_count() == 0:
		notice_label.text = "Spell Scrolls teach new spells. Meditate at an altar to open a spell slot. Mana Discharge (center) is always yours."
		notice_label.add_theme_color_override("font_color", Color("#c9b8ff"))
	elif not manager.can_change_loadout():
		notice_label.text = "Abilities can only be changed at your saved checkpoint."
		notice_label.add_theme_color_override("font_color", Color("#ffb3b3"))
	elif pending_ability_id != "":
		notice_label.text = "Choose Up, Side or Down for %s. An occupied slot is replaced. Backspace cancels." \
			% manager.get_ability(pending_ability_id).display_name
		notice_label.add_theme_color_override("font_color", Color("#ffd36b"))
	else:
		notice_label.text = "Mana Discharge (center) is fixed. Confirm an equipped spell to remove it; confirm a free one, then pick Up, Side or Down."
		notice_label.add_theme_color_override("font_color", Color("#8dffb0"))
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if focus is AbilityCard:
		_show_details(focus.ability, focus.locked)
	elif pending_ability_id != "":
		_show_details(manager.get_ability(pending_ability_id))
	else:
		_show_details(manager.neutral_spell())


## Name + description are only shown for the focused ability.
func _show_details(ability: UltimateAbility, locked := false) -> void:
	if locked:
		detail_icon.set_icon("locked", Color.WHITE)
		detail_name.text = "Locked slot"
		detail_desc.text = "Meditate at an altar to open this slot."
		detail_gauge.visible = false
		return
	if ability == null:
		detail_icon.set_icon("empty", Color.WHITE)
		detail_name.text = "Free slot"
		detail_desc.text = "Choose a spell on the right to place it here."
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
	panel.offset_left = -380.0 # Wide enough for eight cards in a row.
	panel.offset_right = 380.0
	panel.offset_top = -255.0
	panel.offset_bottom = 255.0
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
	tab_bar.focus_neighbor_bottom = tab_bar.get_path_to(cross.card("Up")) # Down from the tabs enters the cross.
	tabs.tab_changed.connect(_on_tab_changed) # After the tabs exist.

	var keys := Label.new()
	keys.text = "Left / Right  tab    Down / Up  move    Enter  confirm    Backspace  cancel    I / Esc  close"
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

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	box.add_child(top)

	var left := VBoxContainer.new()
	top.add_child(left)
	left.add_child(_section("SPELL + DIRECTION"))
	cross = SpellCross.new()
	cross.name = "SpellCross"
	left.add_child(cross)
	cross.build(game.ultimates, true, 76.0, 6.0) # Cards are 76 px (AbilityCard).
	for node_name in SpellCross.NODES:
		var card: AbilityCard = cross.card(node_name)
		var n: String = node_name
		card.pressed.connect(func() -> void: press_node(n))
		card.focus_entered.connect(func() -> void:
			if pending_ability_id == "":
				_show_details(game.ultimates.get_slot(SpellCross.slot_of(n)), not game.ultimates.is_slot_open(SpellCross.slot_of(n))))

	var right := VBoxContainer.new()
	top.add_child(right)
	right.add_child(_section("KNOWN SPELLS"))
	pool_grid = GridContainer.new()
	pool_grid.columns = 4
	pool_grid.add_theme_constant_override("h_separation", 8)
	pool_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(pool_grid)

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
