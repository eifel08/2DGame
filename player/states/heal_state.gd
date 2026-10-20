class_name HealState
extends PlayerState
## Chunk-based (risk-reward) healing. Hold the heal button on the ground:
##   1. short wind-up,
##   2. a chunk channels for Config.vitals.heal_chunk_time: energy drains and
##      the health it will give shows as a WHITE pending segment,
##   3. on completion the pending health turns into real (red) health,
##   4. a short pause follows, so releasing the button now is safe,
##   5. if the button is still held and there is enough energy, the next
##      chunk starts.
## Releasing early, jumping, leaving the ground or taking damage during a
## chunk loses the drained energy and restores nothing.

var windup := 0.0
var chunk_time := 0.0
var pause_time := 0.0
var channeling := false ## A chunk is in progress (energy at risk).


func enter(_params: Dictionary) -> void:
	windup = Config.vitals.heal_windup
	pause_time = 0.0
	channeling = false
	p.is_channeling_heal = false
	Events.heal_started.emit(p)


func step(delta: float) -> void:
	var v = Config.vitals
	p.velocity.x = move_toward(p.velocity.x, 0.0, Config.movement.ground_decel * delta)
	p.apply_gravity(delta, Config.movement.max_fall_speed)
	p.move(delta)

	if not p.input.is_down(&"heal") or not p.grounded or p.jump_buffer_timer > 0.0:
		p.fsm.change("normal") # exit() cancels an unfinished chunk.
		return
	if windup > 0.0:
		windup -= delta
		if windup <= 0.0:
			_start_chunk()
		return
	if pause_time > 0.0:
		pause_time -= delta
		if pause_time <= 0.0:
			if p.health.can_start_heal_chunk():
				_start_chunk()
			else:
				p.fsm.change("normal")
		return
	if channeling:
		chunk_time += delta
		var progress: float = chunk_time / maxf(0.01, v.heal_chunk_time)
		p.health.channel_heal_chunk(progress)
		if progress >= 1.0:
			p.health.complete_heal_chunk()
			channeling = false
			p.is_channeling_heal = false
			pause_time = maxf(0.001, v.heal_chunk_pause)


func _start_chunk() -> void:
	if not p.health.can_start_heal_chunk():
		p.fsm.change("normal")
		return
	p.health.start_heal_chunk()
	chunk_time = 0.0
	channeling = true
	p.is_channeling_heal = true


func exit() -> void:
	if channeling:
		p.health.cancel_heal_chunk() # Interrupted: energy lost, no health.
	channeling = false
	p.is_channeling_heal = false
	Events.heal_ended.emit(p)
