class_name NormalState
extends PlayerState
## Ground, air and wall locomotion share one state because the player moves
## between them every few frames and the rules overlap. Pressing into a wall
## while falling slides slowly (wall friction); jumping off it is a wall jump.


func step(delta: float) -> void:
	var m = Config.movement
	var wall_climb := p.can_use("wall_climb") # Collected items (AbilityPickup) + debug switches.
	var input := p.input
	var ix := input.axis_x()

	# --- Horizontal: crisp accel/decel with a turnaround boost ---
	var max_speed: float = m.max_run_speed * p.stat("speed_mul")
	var accel: float
	if p.grounded:
		accel = m.ground_accel if ix != 0 else m.ground_decel
	else:
		accel = m.air_accel if ix != 0 else m.air_decel
	if ix != 0 and p.velocity.x != 0.0 and signf(p.velocity.x) != ix:
		accel *= m.turn_boost
	if p.wall_jump_lock_timer > 0.0:
		accel *= 0.2
	p.velocity.x = move_toward(p.velocity.x, ix * max_speed, accel * delta)
	if ix != 0 and not p.facing_locked:
		p.facing = ix

	# --- Walls ---
	p.wall_dir = 1 if p.touching_wall(1) else (-1 if p.touching_wall(-1) else 0)
	if wall_climb and not p.grounded and p.wall_dir != 0:
		p.last_wall_dir = p.wall_dir
		p.wall_coyote_timer = m.wall_coyote_time
	p.wall_sliding = wall_climb and not p.grounded and p.wall_dir != 0 \
		and ix == p.wall_dir and p.velocity.y > 0.0
	if p.wall_sliding:
		p.air_jumps_used = 0
		p.air_dash_used = false
		if not p.facing_locked:
			p.facing = -p.wall_dir # Face away from the wall.

	# --- Drop through one-way platforms (down + jump) ---
	if p.jump_buffer_timer > 0.0 and p.grounded and input.is_down(&"move_down") \
			and p.room.standing_on_one_way_only(p.get_rect()):
		p.start_drop_through()

	# --- Jumps: ground/coyote > wall > double ---
	if p.jump_buffer_timer > 0.0:
		if p.grounded or p.coyote_timer > 0.0:
			p.jump(m.jump_velocity, "ground")
		elif wall_climb and (p.wall_dir != 0 or p.wall_coyote_timer > 0.0):
			p.wall_jump(p.wall_dir if p.wall_dir != 0 else p.last_wall_dir)
		elif p.can_use("double_jump") and p.air_jumps_used < 1:
			p.air_jumps_used += 1
			p.jump(m.double_jump_velocity, "double")

	# --- Variable jump height: releasing early cuts upward speed ---
	if p.is_jumping and not input.is_down(&"jump"):
		if p.velocity.y < 0.0:
			p.velocity.y *= m.jump_cut_mul
		p.is_jumping = false
	if p.velocity.y >= 0.0:
		p.is_jumping = false

	p.apply_gravity(delta, m.wall_slide_speed if p.wall_sliding else m.max_fall_speed)

	# --- Transitions ---
	if p.can_use("dash") and input.was_pressed(&"dash") and p.dash_cooldown_timer <= 0.0 and not p.air_dash_used:
		p.fsm.change("dash")
		return
	if p.grounded and input.is_down(&"heal") and p.health.can_start_heal_chunk():
		p.fsm.change("heal")
		return
	if p.map_request and input.is_down(&"map") and p.can_read_map():
		p.fsm.change("map_read") # Map quick view: held key, see MapReadState.
		return

	p.move(delta)
