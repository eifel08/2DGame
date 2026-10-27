class_name GearTier
extends RefCounted
## Tool and pouch-slot tiers. A slot holds tools of its own tier or lower:
##   STRONG slot  Strong, Medium or Weak tools
##   MEDIUM slot  Medium or Weak tools
##   WEAK slot    Weak tools only

enum Tier { WEAK, MEDIUM, STRONG }

const NAMES: Array[String] = ["weak", "medium", "strong"]


## True when a slot of `slot_tier` can hold a tool of `tool_tier`.
static func can_hold(slot_tier: int, tool_tier: int) -> bool:
	return tool_tier <= slot_tier


static func name_of(tier: int) -> String:
	return NAMES[tier] if tier >= 0 and tier < NAMES.size() else "?"
