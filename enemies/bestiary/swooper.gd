class_name SwooperEnemy
extends BaseEnemy
## Small flying enemy. It floats and sways around its home point. When the
## player comes within `sight_range` (and in sight), it chirps (a short
## telegraph) and flies straight at them, steering all the way. It gives up
## and floats back home once the player leaves its leash.

@export var chase_speed := 210.0
@export var sway := 60.0


func _think(delta: float) -> void:
	match state:
		"idle":
			var dest := home + Vector2(sin(t * 0.9) * sway, -size.y / 2.0 + sin(t * 2.4) * 6.0) + Vector2(0, size.y / 2.0)
			move_fly(delta, (dest - global_position) * 3.0, 1200.0)
			if cooldown <= 0.0 and sees_target() and target_in_leash():
				face_target()
				telegraph("swoop")
				enter("alert")
		"alert": # A short shiver before the dive.
			move_fly(delta, Vector2.ZERO, 1500.0)
			if state_time >= 0.25:
				enter("chase")
		"chase":
			face_target()
			move_fly(delta, (target_center() - get_center()).normalized() * chase_speed, 900.0)
			if not target_in_leash() or target_distance() > sight_range * 1.8:
				enter("return")
		"return":
			move_fly(delta, (home - global_position).limit_length(1.0) * chase_speed * 0.6, 900.0)
			if home_distance() < 12.0:
				cooldown = 0.8
				enter("idle")
		_:
			enter("idle")
	if absf(velocity.x) > 10.0:
		facing = 1 if velocity.x > 0.0 else -1
