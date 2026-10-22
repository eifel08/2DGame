class_name GrappleState
extends PlayerState
## The grappling hook (combat/grapple_hook.gd) is out. Three parts:
##
##   hold   while the hook flies: the player hangs still in the air (no
##          gravity, horizontal speed fades), so they never drop and snag on
##          a wall first. On the ground they simply stand. A miss or a
##          deflection off a hazard ends the hold.
##   pull   the hook latched in pull mode: gravity stays off, the speed eases
##          up to Config.grapple.pull_speed, and each step is clamped so the
##          player never passes the hook's stop point. On an enemy that point
##          keeps a safety gap to its contact hitbox; arriving there rebounds
##          the player upward (nearly a pogo) and only then strikes the enemy.
##   swing  the hook latched in swing mode (Down in the air): a pendulum.
##          The rope keeps its length from the latch; gravity alone drives the
##          arc (no damping). It lets go at once on: jump (a fresh jump that
##          keeps the swing's speed), grapple, dash, damage (any state change),
##          touching terrain, or the rope crossing an enemy or a hazard.
##          Letting go keeps the swing's momentum.
##   peg hold  a pull that reached a grapple peg (GrapplePeg): the hook stays
##          attached and the player hangs still under the peg (no gravity,
##          zero velocity; a moving peg carries the player along). Left / Right only turn the player. Any other
##          action pressed lets go at once and still does its job: Jump jumps
##          (with the double jump back), Dash dashes, Attack / Spell fire
##          from normal movement, Grapple only lets go. A swing throw at a
##          peg swings around it instead (the swing part above).
##
## Back to "normal" afterwards. A pull ends when the stop point is reached,
## the path is blocked, the hooked enemy is gone, the time runs out, or the
## player cancels: grapple again (lets go), dash, or jump (a fresh jump).
## Any latched hook refreshes the double jump when it ends, however it ends.
## Not invulnerable: a hit switches to "hurt" like in any other state.

const STALL_FRAMES := 3 ## Steps in a row with almost no progress = blocked.
const MIN_ROPE := 8.0 ## Shortest swing rope.
## Actions that do NOT end a peg hold: Left / Right turn the player; the rest
## open menus or debug tools and leave the player alone.
const HOLD_KEEP: Array[StringName] = [
	&"move_left", &"move_right", &"pause", &"inventory", &"toggle_debug", &"debug_navigate",
]

var hook: GrappleHook
var latched := false ## The hook held, so the pull or swing has started.
var speed := 0.0
var time := 0.0
var stall := 0
# Pendulum: angle from straight down (positive = right of the anchor),
# angular speed, and rope length (anchor to the player's center).
var angle := 0.0
var omega := 0.0
var rope_length := 0.0
var swing_end_reason := "" ## Why the last swing let go (tests, debug).


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
	if hook.is_holding():
		_step_peg_hold(delta)
	elif hook.is_pulling():
		if not latched:
			_begin_pull()
		_step_pull(delta)
	elif hook.is_swinging():
		if not latched:
			_begin_swing()
		_step_swing(delta)
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


# ---------- Pull (hook latched, pull mode) ----------

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
		_jump_off()
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
## A pull that reaches a peg does not end: it becomes a peg hold.
func _finish(arrived: bool) -> void:
	var g = Config.grapple
	if arrived and hook.on_peg():
		p.global_position += hook.hang_point() - p.get_center() # Exactly under the peg.
		p.velocity = Vector2.ZERO
		hook.begin_hold()
		return
	if hook.on_enemy():
		_settle()
		if arrived and hook.enemy_alive():
			_rebound()
			hook.strike_enemy(p) # The delayed hit: only now, after the bounce.
	elif arrived:
		if hook.anchor_one_way:
			p.velocity = Vector2.ZERO # Standing on the platform: land right away.
		else:
			p.velocity = p.velocity.normalized() * speed * g.exit_speed_mul
	p.fsm.change("normal")


## Reached the enemy's safe distance: bounce up (nearly a full pogo) and a
## little away from it.
func _rebound() -> void:
	var g = Config.grapple
	var enemy := hook.target_enemy
	var away := -signf(enemy.get_center().x - p.get_center().x)
	if away == 0.0:
		away = -p.facing
	p.velocity = Vector2(away * g.enemy_bounce_recoil, -Config.combat.pogo_velocity * g.enemy_bounce_mul)
	p.grounded = false
	p.is_jumping = false # Fixed height, like the pogo.
	Events.grapple_bounced.emit(p.global_position + Vector2(0, -Player.HEIGHT))


## A pull toward an enemy never leaves momentum toward it, so the player
## does not drift into its contact hitbox after the pull.
func _settle() -> void:
	if latched and hook.on_enemy():
		p.velocity = Vector2.ZERO


# ---------- Swing (hook latched, swing mode) ----------

func _begin_swing() -> void:
	latched = true
	var offset := p.get_center() - hook.anchor
	rope_length = maxf(offset.length(), MIN_ROPE)
	angle = atan2(offset.x, offset.y)
	omega = p.velocity.dot(_tangent()) / rope_length
	swing_end_reason = ""


## Direction of motion for a positive angular speed.
func _tangent() -> Vector2:
	return Vector2(cos(angle), -sin(angle))


func _step_swing(delta: float) -> void:
	if p.input.was_pressed(&"grapple") or p.input.was_pressed(&"dash") or p.jump_buffer_timer > 0.0:
		_release_swing("input")
		return
	# Pendulum: gravity is the only force (no air resistance).
	omega += -(Config.movement.gravity / rope_length) * sin(angle) * delta
	angle += omega * delta
	var target := hook.anchor + Vector2(sin(angle), cos(angle)) * rope_length
	p.velocity = (target - p.get_center()) / delta
	if absf(p.velocity.x) > 1.0:
		p.facing = int(signf(p.velocity.x))
	p.move(delta)
	if p.get_slide_collision_count() > 0:
		_release_swing("terrain")
	elif hook.rope_obstructed(hook.rope_origin(p), hook.anchor):
		_release_swing("obstructed")


## Lets go of the swing, keeping its momentum. Jump: a fresh jump on top.
## Grapple lets go; dash lets go into a dash.
func _release_swing(reason: String) -> void:
	swing_end_reason = reason
	Events.grapple_swing_ended.emit(reason)
	p.velocity = _tangent() * omega * rope_length
	if reason == "input":
		if p.input.was_pressed(&"grapple"):
			p.input.consume(&"grapple") # Lets go; does not fire a new hook this step.
		elif p.jump_buffer_timer > 0.0:
			_jump_off()
			return
		elif Config.upgrades.dash and p.input.was_pressed(&"dash") and p.dash_cooldown_timer <= 0.0 and not p.air_dash_used:
			p.fsm.change("dash")
			return
	p.fsm.change("normal")


# ---------- Peg hold (hook latched on a peg after a pull) ----------

func _step_peg_hold(delta: float) -> void:
	# Hangs still under the peg: no gravity, no drift. A moving peg carries
	# the player along (with collisions).
	var to := hook.hang_point() - p.get_center()
	if to.length() > 0.01:
		p.velocity = to / delta
		p.move(delta)
	p.velocity = Vector2.ZERO
	var ix := p.input.axis_x()
	if ix != 0:
		p.facing = ix
	for action in InputState.ACTIONS:
		if action in HOLD_KEEP or not p.input.was_pressed(action):
			continue
		if action == &"grapple":
			p.input.consume(&"grapple") # Lets go; does not fire a new hook this step.
		if action == &"jump":
			_jump_off()
		elif action == &"dash" and Config.upgrades.dash and p.dash_cooldown_timer <= 0.0 and not p.air_dash_used:
			p.fsm.change("dash")
		else:
			p.fsm.change("normal") # Attack, Spell, Up / Down, ...: from normal movement.
		return


# ---------- Shared ----------

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


## Leaves a latched hook with a fresh jump. exit() refreshes the double jump
## first, so this jump is a free one.
func _jump_off() -> void:
	p.fsm.change("normal")
	p.jump(Config.movement.jump_velocity, "grapple")


func exit() -> void:
	if hook and hook.is_swinging() and swing_end_reason == "":
		swing_end_reason = "interrupted" # Damage, a hazard, a reset: any other state change.
		Events.grapple_swing_ended.emit(swing_end_reason)
	if latched:
		p.air_jumps_used = 0 # Using the hook refreshes the double jump.
	var finished := hook
	hook = null
	latched = false
	if finished:
		finished.on_state_ended()
