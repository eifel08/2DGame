class_name Player
extends CharacterBody2D
## Player entity: physics body, components and movement helpers.
## Behaviour lives in the state classes under player/states/:
##   normal  - ground / air / wall-slide locomotion
##   dash    - fixed-speed burst, gravity off, invulnerable
##   heal    - grounded channel that drains energy into health
##   cast    - ultimate wind-up, frozen in place, invulnerable
##   ability - movement handed to an ability (e.g. Comet Dash)
##   hurt    - short knockback stun after taking damage
##
## The node origin is at the feet (bottom-center). Game calls step() from
## its own fixed-step loop, so hitstop can freeze everything in one place.

const WIDTH := 22.0
const HEIGHT := 40.0
const ONE_WAY_LAYER := 3 ## Physics layer number used by one-way platforms.

@onready var health: HealthEnergy = $HealthEnergy
@onready var animator: PlayerAnimator = $Animator
@onready var flip: Node2D = $Flip

var input: InputState
var room: Room
var spawn_position := Vector2.ZERO
var safe_point := Vector2.ZERO ## Last safe ground position (hazard respawn target).
var fsm := StateMachine.new()

# Public state read by combat, animation, HUD and debug.
var facing := 1
var grounded := false
var wall_dir := 0
var at_checkpoint := false ## True while standing at the saved checkpoint (loadout swaps allowed).
var wall_sliding := false
var is_channeling_heal := false
var attack_dir := "" ## Written by CombatManager: "", "left", "right", "up", "down".
var facing_locked := false ## Written by CombatManager during attacks.
var modifiers := {} ## id -> {stat_name: multiplier}
## id -> Callable(damage: float, attacker: Node) -> bool. Asked before a hit
## lands; returning true negates it (e.g. a counter shield).
var hit_guards := {}

# Movement timers and resources.
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var dash_cooldown_timer := 0.0
var wall_jump_lock_timer := 0.0
var wall_coyote_timer := 0.0
var drop_through_timer := 0.0
var last_wall_dir := 0
var air_jumps_used := 0
var air_dash_used := false
var is_jumping := false ## True while the jump can still be cut short.


func _ready() -> void:
	set_physics_process(false)
	fsm.add("normal", NormalState.new(self))
	fsm.add("dash", DashState.new(self))
	fsm.add("heal", HealState.new(self))
	fsm.add("cast", CastState.new(self))
	fsm.add("ability", AbilityState.new(self))
	fsm.add("hurt", HurtState.new(self))
	fsm.add("trance", TranceState.new(self))
	fsm.add("dying", DyingState.new(self))
	health.energy_gain_source = func() -> float: return stat("energy_gain_mul")
	animator.setup(self)


func setup(p_input: InputState, p_room: Room, p_spawn: Vector2) -> void:
	input = p_input
	room = p_room
	spawn_position = p_spawn
	reset()


func reset() -> void:
	global_position = spawn_position
	safe_point = spawn_position
	velocity = Vector2.ZERO
	facing = 1
	grounded = false
	wall_dir = 0
	at_checkpoint = false
	wall_sliding = false
	is_channeling_heal = false
	attack_dir = ""
	facing_locked = false
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	dash_cooldown_timer = 0.0
	wall_jump_lock_timer = 0.0
	wall_coyote_timer = 0.0
	drop_through_timer = 0.0
	last_wall_dir = 0
	air_jumps_used = 0
	air_dash_used = false
	is_jumping = false
	set_collision_mask_value(ONE_WAY_LAYER, true)
	fsm.change("normal")
	modifiers.clear()
	hit_guards.clear()
	health.reset()
	animator.reset()


# ---------- Queries ----------

func state_name() -> String:
	return fsm.current_name


func get_rect() -> Rect2:
	return Rect2(global_position.x - WIDTH / 2.0, global_position.y - HEIGHT, WIDTH, HEIGHT)


func get_center() -> Vector2:
	return global_position + Vector2(0.0, -HEIGHT / 2.0)


## Product of all active modifiers for a stat (1.0 when none).
func stat(key: String) -> float:
	var value := 1.0
	for mod in modifiers.values():
		value *= mod.get(key, 1.0)
	return value


func add_modifier(id: String, mods: Dictionary) -> void:
	modifiers[id] = mods


func remove_modifier(id: String) -> void:
	modifiers.erase(id)


func add_hit_guard(id: String, guard: Callable) -> void:
	hit_guards[id] = guard


func remove_hit_guard(id: String) -> void:
	hit_guards.erase(id)


func can_attack() -> bool:
	return fsm.is_in("normal")


func can_cast() -> bool:
	return fsm.is_in("normal")


# ---------- Per-step update ----------

func step(delta: float) -> void:
	health.step(delta)
	if input.was_pressed(&"jump"):
		jump_buffer_timer = Config.movement.jump_buffer_time

	fsm.step(delta)

	jump_buffer_timer -= delta
	dash_cooldown_timer -= delta
	wall_jump_lock_timer -= delta
	wall_coyote_timer -= delta
	if drop_through_timer > 0.0:
		drop_through_timer -= delta
		if drop_through_timer <= 0.0:
			set_collision_mask_value(ONE_WAY_LAYER, true)

	flip.scale.x = facing
	# I-frame flicker.
	var flicker := health.has_iframes() and (Time.get_ticks_msec() / 60) % 2 == 0
	flip.modulate.a = 0.35 if flicker else 1.0
	animator.step(delta)


# ---------- Movement helpers used by states ----------

## Integrates velocity with collision and refreshes ground state.
func move(delta: float) -> void:
	var fall_speed := velocity.y
	var was_grounded := grounded
	move_and_slide()
	grounded = is_on_floor()
	if grounded:
		coyote_timer = Config.movement.coyote_time
		air_jumps_used = 0
		air_dash_used = false
		if not was_grounded:
			Events.player_landed.emit(self, fall_speed)
		if room.is_safe_ground(get_rect()):
			safe_point = global_position
	else:
		coyote_timer -= delta


func apply_gravity(delta: float, max_fall: float) -> void:
	var m = Config.movement
	var g: float = m.gravity
	if velocity.y > 0.0:
		g *= m.fall_gravity_mul
	elif is_jumping and absf(velocity.y) < m.apex_threshold:
		g *= m.apex_gravity_mul
	velocity.y = minf(velocity.y + g * delta, max_fall)


func touching_wall(dir: int) -> bool:
	return test_move(global_transform, Vector2(dir * 2.0, 0.0))


func jump(jump_velocity: float, kind: String) -> void:
	velocity.y = -jump_velocity
	grounded = false
	is_jumping = true
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	Events.player_jumped.emit(self, kind)


## Wall jumps have a fixed height (a quick tap is not cut short), so walls
## feel crisp. Holding toward the wall gives a "climb jump": a smaller push
## and a shorter control lock, so the player can steer straight back into
## the same wall and climb it with consecutive wall jumps.
func wall_jump(from_wall_dir: int) -> void:
	var m = Config.movement
	var climbing := input.axis_x() == from_wall_dir
	var push: float = m.wall_climb_jump_vel_x if climbing else m.wall_jump_vel_x
	velocity = Vector2(-from_wall_dir * push, -m.wall_jump_vel_y)
	facing = -from_wall_dir
	wall_sliding = false
	is_jumping = false
	air_jumps_used = 0 # A wall jump refreshes air resources.
	air_dash_used = false
	jump_buffer_timer = 0.0
	wall_coyote_timer = 0.0
	wall_jump_lock_timer = m.wall_climb_lock_time if climbing else m.wall_jump_lock_time
	Events.player_jumped.emit(self, "wall")


func start_drop_through() -> void:
	set_collision_mask_value(ONE_WAY_LAYER, false)
	drop_through_timer = 0.22
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	grounded = false


# ---------- Facade used by other systems ----------

## Down-attack connected: bounce and refresh air resources.
func pogo(pogo_velocity: float) -> void:
	if not fsm.is_in("normal"):
		return
	velocity.y = -pogo_velocity
	grounded = false
	is_jumping = false # Pogo height is fixed, never cut short.
	air_jumps_used = 0
	air_dash_used = false


func start_cast(duration: float, on_release: Callable) -> void:
	fsm.change("cast", {"duration": duration, "on_release": on_release})


## Hands movement to `controller`, an object with
## control_start(player), control_step(delta, player) -> bool (true = done),
## control_finish(player) and an `invulnerable` property.
func begin_ability_control(controller: Object) -> void:
	fsm.change("ability", {"controller": controller})


## Applies a hit unless invulnerable or negated by a hit guard. `force`
## bypasses both (debug "Take Damage" button). `attacker` is the enemy behind
## the hit, when known. Returns true when the hit landed.
func receive_hit(damage: float, source_x: float, knock_up := false, force := false, attacker: Node = null) -> bool:
	if not force and health.is_invulnerable():
		return false
	if not force:
		for guard: Callable in hit_guards.values():
			if guard.call(damage, attacker):
				return false
	health.take_damage(damage)
	var dir := 1 if global_position.x >= source_x else -1
	Events.player_hurt.emit(self, damage)
	if health.health <= 0.0:
		die(dir)
	else:
		fsm.change("hurt", {"dir": dir, "knock_up": knock_up})
	return true


## Starts the death animation; the game respawns the player once it is done.
func die(dir := 0) -> void:
	if fsm.is_in("dying"):
		return
	fsm.change("dying", {"dir": dir})
	Events.player_died.emit(self)


func is_dying() -> bool:
	return fsm.is_in("dying")


func death_finished() -> bool:
	return fsm.is_in("dying") and (fsm.current as DyingState).finished


## Floating trance after loading into a checkpoint; any fresh press breaks it.
func enter_trance() -> void:
	fsm.change("trance")


## Touching a hazard: take damage (unless invulnerable) and teleport back to
## the last safe ground (or the checkpoint, see Config.combat). If the damage
## is lethal there is no teleport: the death respawns the player at the
## active checkpoint instead. Teleporting even when invulnerable (dash, god
## mode, i-frames) guarantees the player can never get stuck in a hazard.
func hazard_respawn(damage: float) -> void:
	if is_dying():
		return # Already collapsing; the death respawn takes over.
	var from := global_position
	var took_damage := not health.is_invulnerable()
	if took_damage:
		health.take_damage(damage)
		if health.health <= 0.0:
			Events.player_hurt.emit(self, damage)
			die()
			return
	else:
		health.iframe_timer = maxf(health.iframe_timer, 0.4)
	var target := safe_point if Config.combat.hazard_to_safe_ground else spawn_position
	global_position = target
	velocity = Vector2.ZERO
	grounded = false
	is_jumping = false
	set_collision_mask_value(ONE_WAY_LAYER, true)
	drop_through_timer = 0.0
	fsm.change("normal")
	Events.player_hazard_respawn.emit(self, from, target)
	if took_damage:
		Events.player_hurt.emit(self, damage)


## Called by method tracks in the AnimationPlayer (e.g. "footstep", "swing").
func _on_anim_event(event_name: String) -> void:
	Events.anim_event.emit(self, event_name)
