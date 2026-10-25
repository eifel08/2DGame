class_name MapReadState
extends PlayerState
## Quick view of the map: the player holds the Map key (Tab by default,
## rebindable) and reads the map (clip "map_read"). The map overlay
## (ui/map_overlay.gd) is shown in front of the player for as long as this
## state lasts.
##
## While reading:
##   - no movement: the player slows to a stop; gravity still applies
##   - no attacks, spells, dash, heal, grapple or interaction (they all need
##     the normal state)
##   - NOT protected: hits land as usual. A hit (any state change) ends the
##     quick view at once: the overlay closes and the clip stops. The player
##     must press the key again to reopen it.
## Releasing the key closes it and play goes on.

const BLOCKED: Array[StringName] = [&"jump", &"attack", &"dash", &"heal", &"grapple", &"spell", &"interact"]

var released := false
var health_at_start := 0.0


func enter(_params: Dictionary) -> void:
	released = false
	health_at_start = p.health.health
	p.is_jumping = false
	p.wall_sliding = false
	p.jump_buffer_timer = 0.0
	Events.map_opened.emit()


func step(delta: float) -> void:
	if not p.input.is_down(&"map"):
		released = true
		p.fsm.change("normal")
		return
	# Presses made while reading do nothing, now or after the map closes
	# (combat, spells and the hook read their presses after this step).
	for action in BLOCKED:
		p.input.consume(action)
	p.jump_buffer_timer = 0.0
	p.velocity.x = move_toward(p.velocity.x, 0.0, Config.map.quick_view_decel * delta)
	p.apply_gravity(delta, Config.movement.max_fall_speed)
	p.move(delta)


func exit() -> void:
	p.map_request = false
	var reason := "released"
	if not released:
		reason = "damage" if p.health.health < health_at_start else "interrupted"
	Events.map_closed.emit(reason)
