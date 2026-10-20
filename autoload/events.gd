extends Node
## Global signal hub (autoload "Events").
## Systems emit and listen here instead of holding references to each other.
## Example: CombatManager emits hit_landed; energy gain, hitstop, shake and
## particles each react on their own.

# Combat
@warning_ignore("unused_signal")
signal hit_landed(info: Dictionary) ## {target, damage, position, source, grants_energy, strength}
@warning_ignore("unused_signal")
signal pogo_bounced(position: Vector2, on_hazard: bool)
@warning_ignore("unused_signal")
signal attack_swung(direction: String)
@warning_ignore("unused_signal")
signal enemy_killed(enemy: Node)

# Player
@warning_ignore("unused_signal")
signal player_jumped(player: Node, kind: String)
@warning_ignore("unused_signal")
signal player_landed(player: Node, fall_speed: float)
@warning_ignore("unused_signal")
signal player_dashed(player: Node, direction: int)
@warning_ignore("unused_signal")
signal player_hurt(player: Node, damage: float)
@warning_ignore("unused_signal")
signal player_died(player: Node)
@warning_ignore("unused_signal")
signal heal_started(player: Node)
@warning_ignore("unused_signal")
signal heal_ended(player: Node)

# Vitals
@warning_ignore("unused_signal")
signal health_damaged(amount: float)
@warning_ignore("unused_signal")
signal health_healed(amount: float)
@warning_ignore("unused_signal")
signal energy_changed(value: float)

# Ultimates
@warning_ignore("unused_signal")
signal ultimate_changed(ability: RefCounted)
@warning_ignore("unused_signal")
signal ultimate_cast(ability: RefCounted)
@warning_ignore("unused_signal")
signal ultimate_denied(ability: RefCounted, reason: String)
@warning_ignore("unused_signal")
signal ultimate_impact(hitstop: float, shake: float)

# Animation (frame events from method tracks, e.g. "footstep", "swing")
@warning_ignore("unused_signal")
signal anim_event(owner: Node, event_name: String)
