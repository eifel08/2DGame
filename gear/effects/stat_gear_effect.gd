class_name StatGearEffect
extends GearEffect
## Multiplies one player stat (read through Player.stat). Keys in use:
##   attack_range_mul   melee hitbox size (CombatManager.get_attack_hitbox)
##   run_speed_mul      top running speed only; never jumps or dash speed
##   cooldown_mul       dash and grappling hook recovery
##   energy_cost_mul    spell costs and heal chunk energy
##   energy_leak_mul    passive energy leak (Config.vitals.energy_leak_rate)
##   damage_taken_mul   damage from enemies and projectiles (not hazards)

@export var stat := ""
@export var multiplier := 1.0


static func make(p_stat: String, p_multiplier: float) -> StatGearEffect:
	var e := StatGearEffect.new()
	e.stat = p_stat
	e.multiplier = p_multiplier
	return e


func stat_mods() -> Dictionary:
	return {stat: multiplier}


func debug_text() -> String:
	return "%s x%.2f" % [stat, multiplier]
