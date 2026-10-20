class_name HealState
extends PlayerState
## Hold the heal button on the ground: after a short wind-up, energy drains
## continuously into health. Releasing, jumping, leaving the ground, taking
## damage, full health or an empty meter all end the channel.

var windup := 0.0


func enter(_params: Dictionary) -> void:
	windup = Config.vitals.heal_windup
	p.is_channeling_heal = false
	Events.heal_started.emit(p)


func step(delta: float) -> void:
	p.velocity.x = move_toward(p.velocity.x, 0.0, Config.movement.ground_decel * delta)
	p.apply_gravity(delta, Config.movement.max_fall_speed)
	p.move(delta)

	if not p.input.is_down(&"heal") or not p.grounded or p.jump_buffer_timer > 0.0:
		p.fsm.change("normal")
		return
	if windup > 0.0:
		windup -= delta
		return
	p.is_channeling_heal = true
	if not p.health.channel_heal(delta):
		p.fsm.change("normal")


func exit() -> void:
	p.is_channeling_heal = false
	Events.heal_ended.emit(p)
