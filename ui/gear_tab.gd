class_name GearTab
extends VBoxContainer
## The inventory's Gear tab: which pouches are worn and which tools sit in
## their slots. Same keyboard flow as the spell loadout (Abilities tab):
##   POUCHES row   every owned pouch. Confirm: wear it (up to
##                 Config.gear.max_equipped_pouches) or take it off.
##   TOOLS row     every owned tool. Confirm on a free tool: choose a slot
##                 (the focus jumps to the first empty slot that can hold it);
##                 confirm on a slotted tool: take it out.
##   SLOTS         one row per worn pouch, one card per slot (W / M / S).
##                 Confirm with a tool chosen: put it there (a slot holds its
##                 tier or lower; an occupied slot is replaced). Confirm on a
##                 filled slot: take its tool out.
##   Backspace     cancel the slot choice, or empty the focused slot.
## Arrows move between cards, Up from the top row returns to the tab bar.
## Changes only work at the saved checkpoint (like spells); elsewhere you can
## browse. Names, lore and curses show for the focused card only, never a number.

var game: Node
var tab_bar: TabBar
var pouch_row: HBoxContainer
var tool_row: HBoxContainer
var slots_box: VBoxContainer
var pouch_cards: Array[GearCard] = []
var tool_cards: Array[GearCard] = []
var slot_cards: Array[GearCard] = []
var detail_name: Label
var detail_kind: Label
var detail_text: Label
var notice_label: Label
var pending_tool_id := "" ## Tool waiting for a slot choice.
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
	pending_tool_id = ""
	_layout_key = ""
	rebuild()


## The card Down from the tab bar enters (first pouch, else first tool).
func first_focus() -> Control:
	if not pouch_cards.is_empty():
		return pouch_cards[0]
	return tool_cards[0] if not tool_cards.is_empty() else null


# ---------- Actions ----------

func press_pouch(pouch_id: String) -> void:
	if not can_change():
		_flash_notice()
		return
	pending_tool_id = ""
	var g := gear()
	if g.is_equipped(pouch_id):
		g.unequip_pouch(pouch_id)
	elif not g.equip_pouch(pouch_id):
		_flash_notice() # The pouch limit is reached.
	rebuild()


func press_tool(tool_id: String) -> void:
	if not can_change():
		_flash_notice()
		return
	var g := gear()
	if not g.find_tool(tool_id).is_empty():
		var at: Dictionary = g.find_tool(tool_id)
		g.clear_slot(at.pouch, at.slot) # Slotted -> take it out.
		pending_tool_id = ""
		rebuild()
		return
	if pending_tool_id == tool_id:
		pending_tool_id = "" # A second confirm cancels the choice.
		refresh()
		return
	# Free -> choose a slot: focus the first empty slot that can hold it, else
	# the first that can (its tool is replaced). No such slot: nothing to choose.
	var target: GearCard = null
	for card in slot_cards:
		if card.pouch.accepts(card.slot_index, g.get_tool(tool_id)) and card.tool == null:
			target = card
			break
	for card in slot_cards:
		if target == null and card.pouch.accepts(card.slot_index, g.get_tool(tool_id)):
			target = card
	if target == null:
		_flash_notice()
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
		if g.slot_tool(card.pouch.id, card.slot_index, tool_id):
			pending_tool_id = ""
			rebuild()
			_focus_tool(tool_id)
		else:
			_flash_notice() # Too strong for this slot.
		return
	if card.tool != null:
		g.clear_slot(card.pouch.id, card.slot_index)
		rebuild()
	else:
		_flash_notice() # Empty: choose a tool first.


## Backspace: cancel the slot choice, or empty the focused slot.
func clear_pressed() -> void:
	if pending_tool_id != "":
		pending_tool_id = ""
		refresh()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is GearCard and focus.kind == GearCard.Kind.SLOT and focus.tool != null:
		press_slot(focus)


# ---------- Refresh ----------

## Rebuilds the cards when owned or worn gear changed, then refreshes.
func rebuild() -> void:
	var g := gear()
	var data: PlayerData = game.player_data
	var active: Array = g.active_pouches().map(func(p: PouchData) -> String: return p.id)
	var key := "%s|%s|%s" % [data.owned_pouches, data.owned_tools, active]
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
	for card in tool_cards:
		card.show_tool(card.tool, not g.find_tool(card.tool.id).is_empty())
		card.set_pressed_no_signal(card.tool.id == pending_tool_id)
	for card in slot_cards:
		card.show_slot(card.pouch, card.slot_index, g.tool_in(card.pouch.id, card.slot_index))

	var data: PlayerData = game.player_data
	if data.owned_pouches.is_empty() and data.owned_tools.is_empty():
		_notice("Pouches and tools are found in the world. Take them, then rest at your checkpoint to wear them.", Color("#c9b8ff"))
	elif not can_change():
		_notice("Gear can only be changed at your saved checkpoint.", Color("#ffb3b3"))
	elif pending_tool_id != "":
		_notice("Choose a slot for %s. A slot holds its own tier or lower. Backspace cancels." % g.get_tool(pending_tool_id).display_name, Color("#ffd36b"))
	elif g.active_pouches().is_empty():
		_notice("Confirm a pouch to wear it. Its tools only work while it is worn, and its curse always does.", Color("#8dffb0"))
	else:
		_notice("Confirm a pouch to wear or remove it; confirm a tool, then pick a slot. Confirm a filled slot to empty it.", Color("#8dffb0"))
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	_show_details(focus if focus is GearCard else null)


func _show_details(card: GearCard) -> void:
	if card == null:
		detail_name.text = "Gear"
		detail_kind.text = ""
		detail_text.text = "Pouches hold tools. Strong slots hold any tool, medium slots medium or weak ones, weak slots only weak ones."
		return
	var tool: ToolData = card.tool if card.kind != GearCard.Kind.POUCH else null
	if card.kind == GearCard.Kind.SLOT and tool == null:
		var tier_name := GearTier.name_of(card.slot_tier).capitalize()
		detail_name.text = "Empty %s slot" % tier_name.to_lower()
		detail_kind.text = "%s · %s" % [card.pouch.display_name, ["Holds weak tools only", "Holds medium or weak tools", "Holds any tool"][card.slot_tier]]
		detail_text.text = "Choose a tool above to place it here."
		return
	if tool:
		detail_name.text = tool.display_name
		detail_kind.text = "%s tool" % GearTier.name_of(tool.tier).capitalize()
		detail_text.text = tool.lore
		return
	var p := card.pouch
	var tiers := PackedStringArray()
	for t in p.slots:
		tiers.append(GearTier.name_of(t))
	detail_name.text = p.display_name
	detail_kind.text = "Pouch · slots: %s%s" % [", ".join(tiers), "  · worn" if gear().is_equipped(p.id) else ""]
	detail_text.text = "%s\nCurse: %s" % [p.description, p.curse_lore]


func _notice(text: String, color: Color) -> void:
	notice_label.text = text
	notice_label.add_theme_color_override("font_color", color)


func _flash_notice() -> void:
	refresh()
	var tween := create_tween()
	notice_label.modulate = Color(1.6, 1.6, 1.6)
	tween.tween_property(notice_label, "modulate", Color.WHITE, 0.4)


# ---------- Cards ----------

func _rebuild_cards() -> void:
	for card in pouch_cards + tool_cards + slot_cards:
		card.get_parent().remove_child(card)
		card.queue_free()
	pouch_cards.clear()
	tool_cards.clear()
	slot_cards.clear()
	for row in slots_box.get_children():
		slots_box.remove_child(row)
		row.queue_free()
	var g := gear()
	var data: PlayerData = game.player_data
	for pouch_id in g.pouches:
		if data.owned_pouches.has(pouch_id):
			var card := _card(pouch_row)
			card.pouch = g.get_pouch(pouch_id)
			card.kind = GearCard.Kind.POUCH
			card.toggle_mode = false
			card.pressed.connect(func() -> void: press_pouch(card.pouch.id))
			pouch_cards.append(card)
	for tool_id in g.tools:
		if data.owned_tools.has(tool_id):
			var card := _card(tool_row)
			card.tool = g.get_tool(tool_id)
			card.kind = GearCard.Kind.TOOL
			card.pressed.connect(func() -> void: press_tool(card.tool.id))
			tool_cards.append(card)
	for pouch in g.active_pouches():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		slots_box.add_child(row)
		var label := Label.new()
		label.text = pouch.display_name
		label.custom_minimum_size = Vector2(150, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", GearArt.tier_color(g.tier_of("pouch", pouch.id)))
		row.add_child(label)
		for i in pouch.slot_count():
			var card := _card(row)
			card.toggle_mode = false
			card.show_slot(pouch, i, g.tool_in(pouch.id, i))
			card.pressed.connect(func() -> void: press_slot(card))
			slot_cards.append(card)
	for card in pouch_cards + tool_cards:
		card.focus_neighbor_top = card.get_path_to(tab_bar) # Up from the top row: the tabs.


func _card(parent: Control) -> GearCard:
	var card := GearCard.new()
	parent.add_child(card)
	card.focus_entered.connect(func() -> void: _show_details(card))
	return card


## Identity of the focused card, to find it again after a rebuild.
func _focus_id() -> String:
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if not focus is GearCard:
		return ""
	match focus.kind:
		GearCard.Kind.POUCH:
			return "pouch:" + focus.pouch.id
		GearCard.Kind.TOOL:
			return "tool:" + focus.tool.id
	return "slot:%s:%d" % [focus.pouch.id, focus.slot_index]


func _restore_focus(focus_id: String) -> void:
	if focus_id == "":
		return
	for card in pouch_cards + tool_cards + slot_cards:
		if _id_of(card) == focus_id:
			card.grab_focus()
			return
	var first := first_focus()
	if first:
		first.grab_focus()


func _id_of(card: GearCard) -> String:
	match card.kind:
		GearCard.Kind.POUCH:
			return "pouch:" + card.pouch.id
		GearCard.Kind.TOOL:
			return "tool:" + card.tool.id
	return "slot:%s:%d" % [card.pouch.id, card.slot_index]


func _focus_tool(tool_id: String) -> void:
	for card in tool_cards:
		if card.tool.id == tool_id:
			card.grab_focus()


# ---------- Construction ----------

func _build() -> void:
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	add_child(top)
	var left := VBoxContainer.new()
	top.add_child(left)
	left.add_child(_section("POUCHES"))
	pouch_row = HBoxContainer.new()
	pouch_row.add_theme_constant_override("separation", 6)
	pouch_row.custom_minimum_size = Vector2(0, 56)
	left.add_child(pouch_row)
	var right := VBoxContainer.new()
	top.add_child(right)
	right.add_child(_section("TOOLS"))
	tool_row = HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	tool_row.custom_minimum_size = Vector2(0, 56)
	right.add_child(tool_row)

	add_child(_section("WORN POUCHES AND THEIR SLOTS"))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 130)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	slots_box = VBoxContainer.new()
	slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_box.add_theme_constant_override("separation", 6)
	scroll.add_child(slots_box)

	# Detail area: enough fixed height that the lore is never clipped.
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(0, 92)
	add_child(detail)
	detail_name = Label.new()
	detail_name.add_theme_font_size_override("font_size", 15)
	detail.add_child(detail_name)
	detail_kind = Label.new()
	detail_kind.add_theme_font_size_override("font_size", 11)
	detail_kind.add_theme_color_override("font_color", Color("#7fa2ff"))
	detail.add_child(detail_kind)
	detail_text = Label.new()
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	detail_text.add_theme_font_size_override("font_size", 12)
	detail.add_child(detail_text)

	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_font_size_override("font_size", 11)
	add_child(notice_label)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#7fa2ff"))
	l.add_theme_font_size_override("font_size", 11)
	return l
