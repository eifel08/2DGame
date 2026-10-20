class_name DyingState
extends PlayerState
## Health reached zero: a short collapse animation plays (no control,
## invulnerable), then `finished` turns true and the game starts the respawn.

const DURATION := 1.0

var time := 0.0
var finished := false


func enter(params: Dictionary) -> void:
	time = 0.0
	finished = false
	p.is_jumping = false
	p.wall_sliding = false
	p.velocity = Vector2(params.get("dir", 0) * 160.0, -260.0)
	p.health.set_invulnerable("dying", true)
	Events.player_dying.emit(p)


func step(delta: float) -> void:
	time += delta
	p.velocity.x = move_toward(p.velocity.x, 0.0, 600.0 * delta)
	p.apply_gravity(delta, Config.movement.max_fall_speed)
	p.move(delta)
	if time >= DURATION:
		finished = true


func exit() -> void:
	p.health.set_invulnerable("dying", false)
