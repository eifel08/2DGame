class_name ToolData
extends Resource
## A tool: a small charm that goes into a pouch slot of its tier or higher
## (GearTier.can_hold). Its gameplay is a list of GearEffects, kept hidden
## from the player; `lore` is the only description they see and never
## states a number.
##
## Fusion (future): a fused tool is an ordinary ToolData whose effects are
## the effects of its parts, and whose `fused_from` names them. See ToolFusion.
## Tools can be made in code (GearRegistry) or as .tres files in the editor.

@export var id := ""
@export var display_name := ""
@export_multiline var lore := ""
@export var tier: GearTier.Tier = GearTier.Tier.WEAK
@export var effects: Array[GearEffect] = []
## Ids of the tools this one was fused from (empty for a base tool).
@export var fused_from: Array[String] = []


static func make(p_id: String, p_name: String, p_tier: GearTier.Tier, p_lore: String, p_effects: Array[GearEffect]) -> ToolData:
	var t := ToolData.new()
	t.id = p_id
	t.display_name = p_name
	t.tier = p_tier
	t.lore = p_lore
	t.effects = p_effects
	return t


func is_fused() -> bool:
	return not fused_from.is_empty()
