class_name GrappleState
extends PlayerState
## Pulled by the grappling hook (combat/grapple_hook.gd) toward its anchor.
## Gravity is off. The speed eases up to Config.grapple.pull_speed, so the
## pull starts smoothly, and each step is clamped so the player never passes
## the hook's stop point. On an enemy that point keeps a safety gap to its
## contact hitbox.
## Ends (back to "normal") when the stop point is reached, the path is
## blocked, the hooked enemy is gone, the time runs out, or the player
## cancels: jump (the jump then happens as usual), dash, or grapple again.
## Not invulnerable: a hit switches to "hurt" like in any other state.

const STALL_FRAMES := 3 ## Steps in a row with almost no progress = blocked.

var hook: GrappleHook
var speed := 0.0
var time := 0.0
var stall := 0


func enter(params: Dictionary) -> void:
	hook = params["hook"]
	time = 0.0
	stall = 0
	var to := hook.stop_point(p) - p.get_center()
	speed = maxf(0.0, p.velocity.dot(to.normalized())) if to.length() > 0.001 else 0.0
	p.is_jumping = false
	p.wall_sliding = false
	p.jump_buffer_timer = 0.0 # A jump pressed before the latch does not cancel it.


func step(delta: float) -> void:
	var g = Config.grapple
	time += delta

	# Player cancels.
	if p.input.was_pressed(&"grapple"):
		p.input.consume(&"grapple") # Lets go; does not fire a new hook this step.
		_finish(false)
		return
	if p.jump_buffer_timer > 0.0:
		_finish(false) # The normal state uses the buffered jump next step.
		return
	if Config.upgrades.dash and p.input.was_pressed(&"dash") and p.dash_cooldown_timer <= 0.0 and not p.air_dash_used:
		_settle()
		p.fsm.change("dash")
		return

	if not hook.is_pulling() or time >= g.pull_max_time:
		_finish(false)
		return
	var to := hook.stop_point(p) - p.get_center()
	var dist := to.length()
	if dist <= g.arrive_distance:
		_finish(true)
		return
	var dir := to / dist
	if absf(dir.x) > 0.01:
		p.facing = int(signf(dir.x))
	speed = move_toward(speed, g.pull_speed, g.pull_accel * delta)
	var want := minf(speed * delta, dist) # Never overshoot the stop point.
	p.velocity = dir * want / delta
	var before := p.global_position
	p.move(delta)
	stall = stall + 1 if p.global_position.distance_to(before) < want * 0.25 else 0
	if stall >= STALL_FRAMES:
		_finish(false)


## Back to normal movement. `arrived`: the pull reached its stop point.
func _finish(arrived: bool) -> void:
	_settle()
	if arrived and not hook.on_enemy():
		p.velocity = p.velocity.normalized() * speed * Config.grapple.exit_speed_mul
	p.fsm.change("normal")


## A pull toward an enemy never leaves momentum toward it, so the player
## does not drift into its contact hitbox after the pull.
func _settle() -> void:
	if hook.on_enemy():
		p.velocity = Vector2.ZERO


func exit() -> void:
	var finished := hook
	hook = null
	if finished:
		finished.on_pull_ended()
