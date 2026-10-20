class_name HurtState
extends PlayerState
## Short knockback stun after taking damage. I-frames are handled by HealthEnergy.

var timer := 0.0


func enter(params: Dictionary) -> void:
	var dir: int = params.get("dir", 1)
	var knock_up: bool = params.get("knock_up", false)
	p.velocity = Vector2(dir * 300.0, -640.0 if knock_up else -320.0)
	p.is_jumping = false
	p.wall_sliding = false
	timer = 0.22


func step(delta: float) -> void:
	p.velocity.x = move_toward(p.velocity.x, 0.0, 900.0 * delta)
	p.apply_gravity(delta, Config.movement.max_fall_speed)
	p.move(delta)
	timer -= delta
	if timer <= 0.0:
		p.fsm.change("normal")
