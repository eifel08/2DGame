class_name GearTab
extends VBoxContainer
## The inventory's Gear tab, top to bottom:
##   POUCHES   every owned pouch
##   BELT      a belt with GearBelt.LOOPS loops. A worn pouch hangs in its
##             loop, drawn large, with its tool slots on it; a slotted tool
##             is drawn inside its slot. Loops past the pouch limit
##             (Config.gear.max_equipped_pouches) are locked.
##   TOOLS     every owned tool
## Same keyboard flow and visual states as the spell loadout (Abilities tab):
##   Confirm on a free pouch       choose a loop: the focus jumps to the first
##                                 free loop; confirm there to hang it (an
##                                 occupied loop has its pouch swapped out)
##   Confirm on a worn pouch       take it off (in the row or on the belt)
##   Confirm on a free tool        choose a slot: the focus jumps to the first
##                                 empty slot that can hold it; confirm there
##                                 (a slot holds its own tier or lower; an
##                                 occupied slot has its tool replaced)
##   Confirm on a slotted tool     take it out (in the row or in its slot)
##   Backspace                     cancel the choice, or empty the focused
##                                 slot / loop
## Items in use are half greyed in their row with a corner tag ("On", "In");
## the item waiting for a place is drawn pressed; focusing an item gives the
## card that shows it elsewhere (belt <-> row) a dim mirror frame.
## Arrows move between cards; Up from the pouch row returns to the tab bar.
## Changes only work at the saved checkpoint; elsewhere you can browse.
## Names, lore and curses show for the focused card only, never a number.

var game: Node
var tab_bar: TabBar
var pouch_row: HBoxContainer
var tool_row: HBoxContainer
var belt: GearBelt
var pouch_cards: Array[GearCard] = []
var tool_cards: Array[GearCard] = []
var belt_cards: Array[GearCard] = [] ## One per loop, always GearBelt.LOOPS.
var slot_cards: Array[GearCard] = []
var detail_name: Label
var detail_kind: Label
var detail_text: Label
var notice_label: Label
var pending_pouch_id := "" ## Pouch waiting for a loop.
var pending_tool_id := "" ## Tool waiting for a slot.
var _layout_key := ""


func setup(p_game: Node, p_tab_bar: TabBar) -> void:
	game = p_game
	tab_bar = p_tab_bar
	name = "Gear"
	_build()
	Events.gear_changed.connect(func() -> void:
		if is_visible_in_tree():
			rebuild())


func gear() -> GearManager:
	return game.gear


func can_change() -> bool:
	return game.player.at_checkpoint


## Called when the tab is shown (inventory opened or tab switched).
func open() -> void:
	pending_pouch_id = ""
	pending_tool_id = ""
	_layout_key = ""
	rebuild()


## The card Down from the tab bar enters: the first pouch, else the belt.
func first_focus() -> Control:
	return pouch_cards[0] if not pouch_cards.is_empty() else belt_cards[0]


# ---------- Actions ----------

func press_pouch(pouch_id: String) -> void:
	if not can_change():
		_flash_notice()
		return
	var g := gear()
	pending_tool_id = ""
	if g.is_equipped(pouch_id):
		pending_pouch_id = ""
		g.unequip_pouch(pouch_id) # Worn -> take it off.
		rebuild()
		return
	if pending_pouch_id == pouch_id:
		pending_pouch_id = "" # A second confirm cancels the choice.
		refresh()
		return
	# Free -> choose a loop: the first free one, else the first open one.
	var target := -1
	for card in belt_cards:
		if not card.locked and card.pouch == null:
			target = card.index
			break
	for card in belt_cards:
		if target == -1 and not card.locked:
			target = card.index
	if target == -1:
		_flash_notice()
		return
	pending_pouch_id = pouch_id
	refresh()
	belt_cards[target].grab_focus()


func press_belt(card: GearCard) -> void:
	if not can_change() or card.locked:
		_flash_notice() # Locked: the belt holds no more pouches.
		return
	var g := gear()
	if pending_pouch_id != "":
		var pouch_id := pending_pouch_id
		pending_pouch_id = ""
		if not g.equip_pouch_at(pouch_id, card.index):
			_flash_notice()
		rebuild()
		belt_cards[clampi(card.index, 0, maxi(0, g.active_pouches().size() - 1))].grab_focus()
		return
	if card.pouch != null:
		g.unequip_pouch(card.pouch.id) # Confirm on a worn pouch takes it off.
		rebuild()
	else:
		_flash_notice() # Empty: choose a pouch first.


func press_tool(tool_id: String) -> void:
	if not can_change():
		_flash_notice()
		return
	var g := gear()
	pending_pouch_id = ""
	var at: Dictionary = g.find_tool(tool_id)
	if not at.is_empty():
		pending_tool_id = ""
		g.clear_slot(at.pouch, at.slot) # Slotted -> take it out.
		rebuild()
		return
	if pending_tool_id == tool_id:
		pending_tool_id = "" # A second confirm cancels the choice.
		refresh()
		return
	var tool := g.get_tool(tool_id)
	var target: GearCard = null
	for card in slot_cards:
		if card.pouch.accepts(card.index, tool) and card.tool == null:
			target = card
			break
	for card in slot_cards:
		if target == null and card.pouch.accepts(card.index, tool):
			target = card
	if target == null:
		_flash_notice() # No worn pouch has a slot that can hold it.
		return
	pending_tool_id = tool_id
	refresh()
	target.grab_focus()


func press_slot(card: GearCard) -> void:
	if not can_change():
		_flash_notice()
		return
	var g := gear()
	if pending_tool_id != "":
		var tool_id := pending_tool_id
		if g.slot_tool(card.pouch.id, card.index, tool_id):
			pending_tool_id = ""
			rebuild()
			_focus_card("tool:" + tool_id)
		else:
			_flash_notice() # Too strong for this slot.
		return
	if card.tool != null:
		g.clear_slot(card.pouch.id, card.index)
		rebuild()
	else:
		_flash_notice() # Empty: choose a tool first.


## Backspace: cancel the choice, or empty the focused slot or loop.
func clear_pressed() -> void:
	if pending_pouch_id != "" or pending_tool_id != "":
		pending_pouch_id = ""
		pending_tool_id = ""
		refresh()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is GearCard and (focus.kind == GearCard.Kind.SLOT and focus.tool != null
			or focus.kind == GearCard.Kind.BELT and focus.pouch != null):
		if focus.kind == GearCard.Kind.SLOT:
			press_slot(focus)
		else:
			press_belt(focus)


# ---------- Refresh ----------

## Rebuilds the cards when owned or worn gear changed, then refreshes.
func rebuild() -> void:
	var g := gear()
	var data: PlayerData = game.player_data
	var key := "%s|%s|%s|%d" % [data.owned_pouches, data.owned_tools, data.equipped_pouches, g.max_pouches()]
	if key != _layout_key:
		_layout_key = key
		var focus_id := _focus_id()
		_rebuild_cards()
		_restore_focus(focus_id)
	refresh()


func refresh() -> void:
	var g := gear()
	for card in pouch_cards:
		card.show_pouch(card.pouch, g.is_equipped(card.pouch.id), g.tier_of("pouch", card.pouch.id))
		card.set_pressed_no_signal(card.pouch.id == pending_pouch_id)
	for card in tool_cards:
		card.show_tool(card.tool, not g.find_tool(card.tool.id).is_empty())
		card.set_pressed_no_signal(card.tool.id == pending_tool_id)
	var worn := g.active_pouches()
	for card in belt_cards:
		var p: PouchData = worn[card.index] if card.index < worn.size() else null
		card.show_belt(card.index, p, g.tier_of("pouch", p.id) if p else 0, card.index >= g.max_pouches())
		var loop: GearBelt.Loop = belt.loops[card.index]
		loop.has_pouch = p != null
		loop.slot_count = p.slot_count() if p else 0
		loop.tier_color = GearArt.tier_color(card.tier)
		loop.queue_redraw()
	for card in slot_cards:
		card.show_slot(card.pouch, card.index, g.tool_in(card.pouch.id, card.index))
	_update_mirrors()

	var data: PlayerData = game.player_data
	if data.owned_pouches.is_empty() and data.owned_tools.is_empty():
		_notice("Pouches and tools are found in the world. Take them, then rest at your checkpoint to wear them.", Color("#c9b8ff"))
	elif not can_change():
		_notice("Gear can only be changed at your saved checkpoint.", Color("#ffb3b3"))
	elif pending_pouch_id != "":
		_notice("Choose a belt loop for %s. A worn pouch there is swapped out. Backspace cancels." % g.get_pouch(pending_pouch_id).display_name, Color("#ffd36b"))
	elif pending_tool_id != "":
		_notice("Choose a slot for %s. A slot holds its own tier or lower. Backspace cancels." % g.get_tool(pending_tool_id).display_name, Color("#ffd36b"))
	elif worn.is_empty():
		_notice("Confirm a pouch, then a belt loop, to wear it. Its tools only work while it is worn, and its curse always does.", Color("#8dffb0"))
	else:
		_notice("Confirm a free pouch or tool, then where it goes. Confirm a worn pouch or slotted tool to take it off.", Color("#8dffb0"))
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	_show_details(focus if focus is GearCard else null)


## Dim mirror frame on the card that shows the focused item elsewhere.
func _update_mirrors() -> void:
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	var partner := ""
	if focus is GearCard:
		match focus.kind:
			GearCard.Kind.POUCH:
				var loop := gear().data.equipped_pouches.find(focus.pouch.id)
				partner = "belt:%d" % loop if loop != -1 and loop < gear().max_pouches() else ""
			GearCard.Kind.BELT:
				partner = "pouch:" + focus.pouch.id if focus.pouch else ""
			GearCard.Kind.TOOL:
				var at: Dictionary = gear().find_tool(focus.tool.id)
				partner = "slot:%s:%d" % [at.pouch, at.slot] if not at.is_empty() else ""
			GearCard.Kind.SLOT:
				partner = "tool:" + focus.tool.id if focus.tool else ""
	for card in _all_cards():
		card.set_mirror(partner != "" and card.card_id() == partner)


func _show_details(card: GearCard) -> void:
	var g := gear()
	if card == null:
		_detail("Gear", "", "Pouches hang on your belt and hold tools. Strong slots hold any tool, medium slots medium or weak ones, weak slots only weak ones.")
		return
	match card.kind:
		GearCard.Kind.BELT:
			if card.locked:
				_detail("Locked belt loop", "", "Your belt holds no more pouches for now.")
				return
			if card.pouch == null:
				_detail("Empty belt loop", "", "Choose a pouch above to hang it here.")
				return
		GearCard.Kind.SLOT:
			if card.tool == null:
				_detail("Empty %s slot" % GearTier.name_of(card.tier), card.pouch.display_name,
					["Holds weak tools only.", "Holds medium or weak tools.", "Holds any tool."][card.tier])
				return
	if card.tool and card.kind != GearCard.Kind.BELT:
		var where: Dictionary = g.find_tool(card.tool.id)
		_detail(card.tool.display_name, "%s tool%s" % [GearTier.name_of(card.tool.tier).capitalize(),
			"  · in the %s" % g.get_pouch(where.pouch).display_name if not where.is_empty() else ""], card.tool.lore)
		return
	var p := card.pouch
	var tiers := PackedStringArray()
	for t in p.slots:
		tiers.append(GearTier.name_of(t))
	_detail(p.display_name, "Pouch · slots: %s%s" % [", ".join(tiers), "  · worn" if g.is_equipped(p.id) else ""],
		"%s\nCurse: %s" % [p.description, p.curse_lore])


func _detail(title: String, kind: String, text: String) -> void:
	detail_name.text = title
	detail_kind.text = kind
	detail_text.text = text


func _notice(text: String, color: Color) -> void:
	notice_label.text = text
	notice_label.add_theme_color_override("font_color", color)


func _flash_notice() -> void:
	refresh()
	var tween := create_tween()
	notice_label.modulate = Color(1.6, 1.6, 1.6)
	tween.tween_property(notice_label, "modulate", Color.WHITE, 0.4)


# ---------- Cards ----------

func _all_cards() -> Array[GearCard]:
	var cards: Array[GearCard] = []
	cards.append_array(pouch_cards)
	cards.append_array(belt_cards)
	cards.append_array(slot_cards)
	cards.append_array(tool_cards)
	return cards


func _rebuild_cards() -> void:
	for card in pouch_cards + tool_cards + slot_cards:
		card.get_parent().remove_child(card)
		card.queue_free()
	pouch_cards.clear()
	tool_cards.clear()
	slot_cards.clear()
	var g := gear()
	var data: PlayerData = game.player_data
	for pouch_id in g.pouches:
		if data.owned_pouches.has(pouch_id):
			var card := _card(pouch_row)
			card.toggle_mode = true
			card.show_pouch(g.get_pouch(pouch_id), false, 0)
			card.pressed.connect(func() -> void: press_pouch(card.pouch.id))
			pouch_cards.append(card)
	for tool_id in g.tools:
		if data.owned_tools.has(tool_id):
			var card := _card(tool_row)
			card.toggle_mode = true
			card.show_tool(g.get_tool(tool_id), false)
			card.pressed.connect(func() -> void: press_tool(card.tool.id))
			tool_cards.append(card)
	var worn := g.active_pouches()
	for i in GearBelt.LOOPS:
		var loop: GearBelt.Loop = belt.loops[i]
		if i < worn.size():
			for s in worn[i].slot_count():
				var card := GearCard.new()
				card.custom_minimum_size = Vector2(30, 30)
				loop.slot_row.add_child(card)
				card.focus_entered.connect(func() -> void: _on_card_focus(card))
				card.show_slot(worn[i], s, g.tool_in(worn[i].id, s))
				card.pressed.connect(func() -> void: press_slot(card))
				slot_cards.append(card)
	for card in pouch_cards:
		card.focus_neighbor_top = card.get_path_to(tab_bar) # Up from the top row: the tabs.
	if pouch_cards.is_empty():
		for card in belt_cards:
			card.focus_neighbor_top = card.get_path_to(tab_bar)


func _card(parent: Control) -> GearCard:
	var card := GearCard.new()
	card.custom_minimum_size = Vector2(50, 50)
	parent.add_child(card)
	card.focus_entered.connect(func() -> void: _on_card_focus(card))
	return card


func _on_card_focus(card: GearCard) -> void:
	_update_mirrors()
	_show_details(card)


func _focus_id() -> String:
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	return focus.card_id() if focus is GearCard and is_instance_valid(focus) else ""


func _restore_focus(focus_id: String) -> void:
	if focus_id != "" and not _focus_card(focus_id):
		first_focus().grab_focus()


func _focus_card(card_id: String) -> bool:
	for card in _all_cards():
		if card.card_id() == card_id:
			card.grab_focus()
			return true
	return false


# ---------- Construction ----------

func _build() -> void:
	add_theme_constant_override("separation", 4)
	add_child(_section("POUCHES"))
	pouch_row = HBoxContainer.new()
	pouch_row.add_theme_constant_override("separation", 6)
	pouch_row.custom_minimum_size = Vector2(0, 50)
	add_child(pouch_row)

	add_child(_section("BELT"))
	belt = GearBelt.new()
	add_child(belt)
	for loop in belt.loops:
		var card := loop.belt_card
		card.index = belt_cards.size()
		card.kind = GearCard.Kind.BELT
		card.focus_entered.connect(func() -> void: _on_card_focus(card))
		card.pressed.connect(func() -> void: press_belt(card))
		belt_cards.append(card)

	add_child(_section("TOOLS"))
	tool_row = HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	tool_row.custom_minimum_size = Vector2(0, 50)
	add_child(tool_row)

	# Detail area: enough fixed height that the lore is never clipped.
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(0, 66)
	detail.add_theme_constant_override("separation", 0)
	add_child(detail)
	detail_name = Label.new()
	detail_name.add_theme_font_size_override("font_size", 14)
	detail.add_child(detail_name)
	detail_kind = Label.new()
	detail_kind.add_theme_font_size_override("font_size", 10)
	detail_kind.add_theme_color_override("font_color", Color("#7fa2ff"))
	detail.add_child(detail_kind)
	detail_text = Label.new()
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	detail_text.add_theme_font_size_override("font_size", 11)
	detail.add_child(detail_text)

	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_font_size_override("font_size", 10)
	add_child(notice_label)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#7fa2ff"))
	l.add_theme_font_size_override("font_size", 10)
	return l
