class_name PouchData
extends Resource
## A pouch: a few tool slots, each with a tier (`slots`), and a curse that
## is always active while the pouch is equipped, filled or not. The curse is
## a list of GearEffects like a tool's; the player only reads `curse_lore`,
## which never states a number.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_multiline var curse_lore := ""
## One entry per slot, its GearTier.Tier, e.g. [STRONG, MEDIUM, WEAK].
@export var slots: Array[GearTier.Tier] = []
@export var curse: Array[GearEffect] = []


static func make(p_id: String, p_name: String, p_slots: Array[GearTier.Tier], p_description: String,
		p_curse_lore: String, p_curse: Array[GearEffect]) -> PouchData:
	var p := PouchData.new()
	p.id = p_id
	p.display_name = p_name
	p.slots = p_slots
	p.description = p_description
	p.curse_lore = p_curse_lore
	p.curse = p_curse
	return p


func slot_count() -> int:
	return slots.size()


## True when slot `index` can take `tool` by tier.
func accepts(index: int, tool: ToolData) -> bool:
	return index >= 0 and index < slots.size() and tool != null and GearTier.can_hold(slots[index], tool.tier)
