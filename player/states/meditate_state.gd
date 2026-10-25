class_name MeditateState
extends PlayerState
## Meditation at a MeditationAltar ("Concentrate"). The player kneels at the
## altar (clip "meditate") for `duration` seconds without control. When the
## time is up, `on_complete` runs (the altar's slot opens) and play goes on.
## The player is NOT protected: a hit (any state change) interrupts it, and
## `on_cancel` runs instead. Nothing is unlocked then.

var time := 0.0
var duration := 1.0
var on_complete: Callable
var on_cancel: Callable
var finished := false


func enter(params: Dictionary) -> void:
	time = 0.0
	finished = false
	duration = maxf(0.05, params.get("duration", 1.0))
	on_complete = params.get("on_complete", Callable())
	on_cancel = params.get("on_cancel", Callable())
	p.velocity = Vector2.ZERO
	p.is_jumping = false
	p.wall_sliding = false


func step(delta: float) -> void:
	time += delta
	p.velocity.x = 0.0
	p.apply_gravity(delta, Config.movement.max_fall_speed)
	p.move(delta)
	if time >= duration:
		finished = true
		p.fsm.change("normal")
		if on_complete.is_valid():
			on_complete.call()


func progress() -> float:
	return clampf(time / duration, 0.0, 1.0)


func exit() -> void:
	if not finished and on_cancel.is_valid():
		on_cancel.call()
