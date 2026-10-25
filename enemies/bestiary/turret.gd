class_name TurretEnemy
extends BaseEnemy
## Turret. Bolted down. When it sees the player it aims (a red sight line
## that tracks, then locks for a beat) and fires a NON-DEFLECTABLE bolt
## straight at where it aimed. Cannot be knocked back.

@export var bolt_speed := 380.0
@export var aim_time := 0.6
@export var lock_time := 0.15 ## The last part of the aim no longer tracks: jump then.
@export var fire_interval := 1.5
@export var bolt_damage := 15.0

var aim_dir := Vector2.RIGHT


func muzzle() -> Vector2:
	return get_center() + Vector2(0, -6)


func _think(delta: float) -> void:
	match state:
		"idle":
			move_ground(delta, 0.0)
			if sees_target():
				face_target()
				aim_dir = (target_center() - muzzle()).normalized()
				if cooldown <= 0.0:
					telegraph("aim")
					enter("aim")
		"aim":
			move_ground(delta, 0.0)
			if state_time < aim_time - lock_time and target_valid():
				face_target()
				aim_dir = (target_center() - muzzle()).normalized()
			if state_time >= aim_time:
				shoot(muzzle() + aim_dir * 16.0, aim_dir, bolt_speed, {"radius": 7.0, "damage": bolt_damage, "life": 3.0, "color": Color("#d1365e")})
				cooldown = fire_interval
				enter("recover")
		"recover":
			move_ground(delta, 0.0)
			if state_time >= 0.3:
				enter("idle")
		_:
			enter("idle")


func _on_hit(_direction: Vector2, _knockback: float) -> void:
	stun_timer = 0.05 # Bolted down: no knockback.
