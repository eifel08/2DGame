class_name Mover
extends RefCounted
## Back-and-forth motion for moving platforms and pegs: from `start` to
## `start + travel` and back, every `period` seconds, eased at both ends.
## Stepped by the game loop (Game._update_movers), so hitstop freezes it.

var start := Vector2.ZERO
var travel := Vector2.ZERO
var period := 4.0
var t := 0.0


func _init(p_start: Vector2, p_travel: Vector2, p_period: float, p_phase := 0.0) -> void:
	start = p_start
	travel = p_travel
	period = maxf(p_period, 0.1)
	t = p_phase * period


## Advances the clock; returns the new position.
func step(delta: float) -> Vector2:
	t += delta
	return position_at(t)


func position_at(time: float) -> Vector2:
	return start + travel * (0.5 - 0.5 * cos(TAU * time / period))
