class_name DamageToEnergyEffect
extends GearEffect
## Part of every wound comes back as energy.

@export var fraction := 0.15 ## Share of the health lost that is added as energy.


static func make(p_fraction: float) -> DamageToEnergyEffect:
	var e := DamageToEnergyEffect.new()
	e.fraction = p_fraction
	return e


func on_player_damaged(ctx: UltimateContext, amount: float) -> void:
	if amount > 0.0 and not ctx.player.is_dying():
		ctx.player.health.add_energy(amount * fraction)


func debug_text() -> String:
	return "damage -> energy %d%%" % roundi(fraction * 100.0)
