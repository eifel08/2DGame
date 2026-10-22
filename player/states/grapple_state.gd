class_name GrappleState
extends PlayerState
## The grappling hook (combat/grapple_hook.gd) is out. Two parts:
##
##   hold  while the hook flies: the player hangs still in the air (no
##         gravity, horizontal speed fades), so they never drop and snag on a
##         wall before the pull. On the ground they simply stand. A miss or a
##         deflection off a hazard ends the hold.
##   pull  once the hook latches: gravity stays off, the speed eases up to
##         Config.grapple.pull_speed, and each step is clamped so the player
##         never passes the hook's stop point. On an enemy that point keeps a
##         safety gap to its contact hitbox; arriving there rebounds the
##         player upward and a little away, like a pogo.
##
## Back to "normal" when the stop point is reached, the path is blocked, the
## hooked enemy is gone, the time runs out, or the player cancels: grapple
## again (lets go), dash, or jump (a fresh jump during a pull).
## A latched pull refreshes the double jump when it ends, however it ends.
## Not invulnerable: a hit switches to "hurt" like in any other state.

const STALL_FRAMES := 3 ## Steps in a row with almost no progress = blocked.

var hook: GrappleHook
var latched := false ## The hook held, so the pull has started.
var speed := 0.0
var time := 0.0
var stall := 0


func enter(params: Dictionary) -> void:
	hook = params["hook"]
	latched = false
	speed = 0.0
	time = 0.0
	stall = 0
	p.is_jumping = false
	p.wall_sliding = false
	p.jump_buffer_timer = 0.0 # A jump pressed just before the throw does not cancel it.


func step(delta: float) -> void:
	if hook.is_pulling():
		if not latched:
			_begin_pull()
		_step_pull(delta)
	elif hook.is_flying():
		_step_hold(delta)
	else:
		p.fsm.change("normal") # Missed or deflected: the hook flies back on its own.


# ---------- Hold (hook in flight) ----------

func _step_hold(delta: float) -> void:
	if _cancelled():
		return
	if p.jump_buffer_timer > 0.0:
		p.fsm.change("normal") # Not latched: the normal state jumps by its usual rules.
		return
	var m = Config.movement
	p.velocity.x = move_toward(p.velocity.x, 0.0, (m.ground_decel if p.grounded else m.air_decel) * delta)
	if p.grounded:
		p.apply_gravity(delta, m.max_fall_speed) # Stay settled on the floor.
	else:
		p.velocity.y = 0.0 # Air suspension: no fall while the hook flies.
	p.move(delta)


# ---------- Pull (hook latched) ----------

func _begin_pull() -> void:
	latched = true
	time = 0.0
	stall = 0
	var to := hook.stop_point(p) - p.get_center()
	speed = maxf(0.0, p.velocity.dot(to.normalized())) if to.length() > 0.001 else 0.0


func _step_pull(delta: float) -> void:
	var g = Config.grapple
	time += delta
	if _cancelled():
		return
	if p.jump_buffer_timer > 0.0:
		_settle()
		p.fsm.change("normal") # exit() refreshes the double jump ...
		p.jump(Config.movement.jump_velocity, "grapple") # ... so this jump is a free one.
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


## Grapple again (lets go) or dash. Returns true when the state was left.
func _cancelled() -> bool:
	if p.input.was_pressed(&"grapple"):
		p.input.consume(&"grapple") # Lets go; does not fire a new hook this step.
		_settle()
		p.fsm.change("normal")
		return true
	if Config.upgrades.dash and p.input.was_pressed(&"dash") and p.dash_cooldown_timer <= 0.0 and not p.air_dash_used:
		_settle()
		p.fsm.change("dash")
		return true
	return false


## Back to normal movement. `arrived`: the pull reached its stop point.
func _finish(arrived: bool) -> void:
	var g = Config.grapple
	if hook.on_enemy():
		_settle()
		if arrived:
			_rebound()
	elif arrived:
		if hook.anchor_one_way:
			p.velocity = Vector2.ZERO # Standing on the platform: land right away.
		else:
			p.velocity = p.velocity.normalized() * speed * g.exit_speed_mul
	p.fsm.change("normal")


## Reached the enemy's safe distance: bounce up and a little away, like a pogo.
func _rebound() -> void:
	var g = Config.grapple
	var enemy := hook.target_enemy
	var away := -1.0
	if is_instance_valid(enemy):
		away = -signf(enemy.get_center().x - p.get_center().x)
	if away == 0.0:
		away = -p.facing
	p.velocity = Vector2(away * g.enemy_bounce_recoil, -g.enemy_bounce_velocity)
	p.grounded = false
	p.is_jumping = false # Fixed height, like the pogo.
	Events.grapple_bounced.emit(p.global_position + Vector2(0, -Player.HEIGHT))


## A pull toward an enemy never leaves momentum toward it, so the player
## does not drift into its contact hitbox after the pull.
func _settle() -> void:
	if latched and hook.on_enemy():
		p.velocity = Vector2.ZERO


func exit() -> void:
	if latched:
		p.air_jumps_used = 0 # Using the hook refreshes the double jump.
	var finished := hook
	hook = null
	latched = false
	if finished:
		finished.on_state_ended()
