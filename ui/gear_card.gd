class_name GearCard
extends Button
## Icon-only button for the inventory's Gear tab: a pouch, a tool, or one
## tool slot of an equipped pouch. Names and lore appear in the tab's detail
## area on focus, like the ability cards. Fully keyboard operable: arrows
## move focus, Enter / Space presses. Focus frame: full gold (AbilityCard).

enum Kind { POUCH, TOOL, SLOT }

var kind: Kind = Kind.TOOL
var pouch: PouchData ## POUCH, and the owning pouch of a SLOT.
var tool: ToolData ## TOOL, or the tool in a SLOT (null = empty).
var slot_index := -1 ## SLOT: index in its pouch.
var slot_tier := 0 ## SLOT: the slot's GearTier.Tier.
var tag := "" ## Corner text: "On" (equipped pouch), "In" (slotted tool), "W" / "M" / "S" (slot tier).
var dim := false ## Unequipped pouch or unusable tool.


func _init() -> void:
	custom_minimum_size = Vector2(56, 56)
	focus_mode = Control.FOCUS_ALL
	toggle_mode = true
	mouse_entered.connect(func() -> void:
		if is_visible_in_tree():
			grab_focus())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func show_pouch(p: PouchData, equipped: bool, tier: int) -> void:
	kind = Kind.POUCH
	pouch = p
	slot_tier = tier
	tag = "On" if equipped else ""
	dim = not equipped
	queue_redraw()


func show_tool(t: ToolData, slotted: bool) -> void:
	kind = Kind.TOOL
	tool = t
	tag = "In" if slotted else ""
	dim = false
	queue_redraw()


func show_slot(p: PouchData, index: int, t: ToolData) -> void:
	kind = Kind.SLOT
	pouch = p
	slot_index = index
	slot_tier = p.slots[index]
	tool = t
	tag = GearArt.TIER_TAGS[slot_tier]
	dim = false
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0 + Vector2(0, 2)
	var r := minf(size.x, size.y) * 0.24
	match kind:
		Kind.POUCH:
			GearArt.pouch(self, center, r, GearArt.tier_color(slot_tier), dim)
		Kind.TOOL:
			GearArt.tool(self, center, r, GearArt.tier_color(tool.tier) if tool else Color.WHITE, dim)
		Kind.SLOT:
			var frame := GearArt.tier_color(slot_tier)
			draw_rect(Rect2(Vector2.ZERO, size).grow(-4.0), Color(frame, 0.55), false, 1.5)
			if tool:
				GearArt.tool(self, center, r, GearArt.tier_color(tool.tier))
			else:
				GearArt.empty_slot(self, center, r, frame)
	if tag != "":
		draw_string(ThemeDB.fallback_font, Vector2(6, 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.65))
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.5), AbilityCard.FOCUS_COLOR, false, 3.0)
