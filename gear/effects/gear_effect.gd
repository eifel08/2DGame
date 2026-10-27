class_name GearEffect
extends Resource
## One hidden effect of a tool, or one curse of a pouch. Effects are small,
## self-contained resources, so a tool is just a list of them and a fused
## tool is the lists of its parts put together (ToolFusion).
##
## Two kinds of contribution, both optional:
##   stat_mods()        multipliers merged into the player's "gear" modifier
##                      (Player.stat): e.g. {"attack_range_mul": 1.1}
##   on_* hooks         reactions to gameplay events, dispatched by GearManager
##
## Exact numbers live here only. Players see the lore of the tool or pouch,
## which never states a number.


func stat_mods() -> Dictionary:
	return {}


## The player lost `amount` health (any source).
func on_player_damaged(_ctx: UltimateContext, _amount: float) -> void:
	pass


## The player started a basic melee swing ("left", "right", "up", "down").
func on_attack_swung(_ctx: UltimateContext, _dir: String) -> void:
	pass


## Short technical text for the debug overlay (may show numbers).
func debug_text() -> String:
	return get_script().get_global_name()
