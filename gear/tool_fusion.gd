class_name ToolFusion
extends RefCounted
## Combines tools into one fused tool. Nothing in the game fuses yet; this
## is the single place a future fusion feature (an NPC, an altar, a recipe
## list) calls. Because a tool's whole gameplay is its list of GearEffects,
## fusing needs no special cases:
##   - effects: every part's effects, duplicated so parts stay untouched.
##     Stat effects on the same key simply multiply (Player.stat), event
##     effects all run.
##   - tier: the highest part tier unless one is given, so a fused tool
##     still needs a slot that could hold its strongest part.
##   - fused_from: the part ids, for saves, UI and un-fusing.
## Register the result with GearRegistry / GearManager.add_tool like any tool.


static func fuse(id: String, display_name: String, lore: String, parts: Array[ToolData], tier := -1) -> ToolData:
	var effects: Array[GearEffect] = []
	var top := 0
	var ids: Array[String] = []
	for part in parts:
		top = maxi(top, part.tier)
		ids.append(part.id)
		for effect in part.effects:
			effects.append(effect.duplicate(true))
	var fused := ToolData.make(id, display_name, (top if tier < 0 else tier) as GearTier.Tier, lore, effects)
	fused.fused_from = ids
	return fused
