class_name GearCard
extends Button
## Icon-only button for the inventory's Gear tab. Names and lore appear in
## the tab's detail area on focus, like the ability cards. Fully keyboard
## operable: arrows move focus, Enter / Space presses.
##   POUCH  an owned pouch (top row)
##   TOOL   an owned tool (bottom row)
##   BELT   one of the belt's loops: the worn pouch drawn large, an empty
##          loop, or a locked one (past the pouch limit)
##   SLOT   one tool slot of a worn pouch, drawn on that pouch on the belt
## Visual states follow the spell loadout (AbilityCard):
##   normal       an owned item that is free to use
##   half greyed  an owned item that is in use elsewhere (worn pouch, slotted
##                tool), with a corner tag ("On", "In")
##   pressed      the item waiting for a place (Button pressed style)
##   gold frame   keyboard focus; `mirror` draws a dim, thinner gold frame on
##                the card that shows the same item elsewhere (belt <-> row)

enum Kind { POUCH, TOOL, BELT, SLOT }

var kind: Kind = Kind.TOOL
var pouch: PouchData ## POUCH, BELT (null = empty loop), and the pouch of a SLOT.
var tool: ToolData ## TOOL, or the tool in a SLOT (null = empty).
var index := -1 ## BELT: loop index. SLOT: slot index in its pouch.
var tier := 0 ## POUCH / BELT: the pouch's strongest slot. SLOT: the slot's tier.
var tag := "" ## Corner text: "On", "In", or the slot's tier ("W", "M", "S").
var dim := false ## Half greyed: in use elsewhere.
var locked := false ## BELT: past the pouch limit.
var mirror := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func() -> void:
		if is_visible_in_tree():
			grab_focus())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func show_pouch(p: PouchData, worn: bool, p_tier: int) -> void:
	kind = Kind.POUCH
	pouch = p
	tier = p_tier
	dim = worn
	tag = "On" if worn else ""
	queue_redraw()


func show_tool(t: ToolData, slotted: bool) -> void:
	kind = Kind.TOOL
	tool = t
	dim = slotted
	tag = "In" if slotted else ""
	queue_redraw()


func show_belt(loop: int, p: PouchData, p_tier: int, p_locked: bool) -> void:
	kind = Kind.BELT
	index = loop
	pouch = p
	tier = p_tier
	locked = p_locked
	dim = false
	tag = ""
	queue_redraw()


func show_slot(p: PouchData, slot: int, t: ToolData) -> void:
	kind = Kind.SLOT
	pouch = p
	index = slot
	tier = p.slots[slot]
	tool = t
	dim = false
	tag = GearArt.TIER_TAGS[tier]
	queue_redraw()


func set_mirror(on: bool) -> void:
	if mirror != on:
		mirror = on
		queue_redraw()


## A stable id for finding this card again after a rebuild.
func card_id() -> String:
	match kind:
		Kind.POUCH:
			return "pouch:" + pouch.id
		Kind.TOOL:
			return "tool:" + tool.id
		Kind.BELT:
			return "belt:%d" % index
	return "slot:%s:%d" % [pouch.id, index]


func _draw() -> void:
	var center := size / 2.0
	var r := minf(size.x, size.y) * 0.3
	match kind:
		Kind.POUCH:
			GearArt.pouch(self, center + Vector2(0, 2), r, GearArt.tier_color(tier), dim, pouch.id)
		Kind.TOOL:
			GearArt.tool(self, center, r, GearArt.tier_color(tool.tier), dim, tool.id)
		Kind.BELT:
			if locked:
				AbilityIcon.draw_symbol(self, "locked", center, r * 0.9, Color(1, 1, 1, 0.35))
			elif pouch:
				GearArt.pouch(self, center + Vector2(0, 2), minf(size.x * 0.34, 34.0), GearArt.tier_color(tier), false, pouch.id)
			else:
				GearArt.belt_loop(self, center, r, Color.WHITE)
		Kind.SLOT:
			var frame := GearArt.tier_color(tier)
			draw_circle(center, r * 1.15, Color(GearArt.INK, 0.85))
			if tool:
				GearArt.tool(self, center, r * 1.1, GearArt.tier_color(tool.tier), false, tool.id)
			else:
				GearArt.empty_slot(self, center, r * 1.05, frame)
	if tag != "":
		draw_string(ThemeDB.fallback_font, Vector2(4, 11), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.65))
	if has_focus(): # Primary selection: full gold frame.
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.5), AbilityCard.FOCUS_COLOR, false, 3.0)
	elif mirror: # The same item, shown elsewhere.
		draw_rect(Rect2(Vector2.ZERO, size).grow(-3.0), AbilityCard.MIRROR_COLOR, false, 1.5)
