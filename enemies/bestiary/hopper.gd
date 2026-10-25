class_name HopperEnemy
extends BaseEnemy
## Jumping pest. It waits a random moment, crouches, then hops a short random
## distance, so it bounces from platform to platform. It hops back toward home
## when it has strayed too far.

@export var hop_speed_x := Vector2(110.0, 210.0) ## min, max
@export var hop_speed_y := Vector2(520.0, 680.0) ## min, max
@export var wait_time := Vector2(0.4, 1.2) ## min, max

var _wait := 0.6
var hops := 0 ## Hops so far (tests, debug).


func _on_spawn() -> void:
	_wait = randf_range(wait_time.x, wait_time.y)
	hops = 0


func _think(delta: float) -> void:
	match state:
		"idle":
			move_ground(delta, move_toward(velocity.x, 0.0, 1200.0 * delta))
			if is_on_floor() and state_time >= _wait:
				enter("crouch")
		"crouch":
			move_ground(delta, 0.0)
			if state_time >= 0.15:
				var dir := -1 if randf() < 0.5 else 1
				if home_distance() > leash_range * 0.5:
					dir = 1 if home.x > global_position.x else -1
				facing = dir
				velocity.y = -randf_range(hop_speed_y.x, hop_speed_y.y)
				hops += 1
				enter("hop")
				move_ground(delta, dir * randf_range(hop_speed_x.x, hop_speed_x.y))
		"hop":
			move_ground(delta, velocity.x)
			if is_on_wall():
				velocity.x = -velocity.x * 0.5
			if is_on_floor() and state_time > 0.1:
				_wait = randf_range(wait_time.x, wait_time.y)
				enter("idle")
		_:
			enter("idle")
