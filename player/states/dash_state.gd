class_name DashState
extends PlayerState
## Fixed-speed horizontal burst. Gravity off, invulnerable (i-frames).

var dir := 1
var timer := 0.0


func enter(_params: Dictionary) -> void:
	var ix := p.input.axis_x()
	if p.wall_sliding:
		dir = -p.wall_dir
	else:
		dir = ix if ix != 0 else p.facing
	timer = Config.movement.dash_duration
	p.air_dash_used = not p.grounded
	p.is_jumping = false
	p.facing = dir
	p.velocity.y = 0.0
	p.wall_sliding = false
	p.health.set_invulnerable("dash", true)
	Events.player_dashed.emit(p, dir)


func step(delta: float) -> void:
	var m = Config.movement
	p.velocity = Vector2(dir * m.dash_speed * p.stat("speed_mul"), 0.0)
	timer -= delta

	# Dash-jump: jumping out of a grounded dash keeps the momentum feel.
	if p.jump_buffer_timer > 0.0 and p.grounded:
		p.fsm.change("normal")
		p.jump(m.jump_velocity, "ground")
		return

	p.move(delta)
	if p.is_on_wall() or timer <= 0.0:
		p.fsm.change("normal")


func exit() -> void:
	var max_speed: float = Config.movement.max_run_speed * p.stat("speed_mul")
	p.velocity.x = clampf(p.velocity.x, -max_speed, max_speed)
	p.health.set_invulnerable("dash", false)
	p.dash_cooldown_timer = Config.movement.dash_cooldown
