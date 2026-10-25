class_name ShellbackEnemy
extends BaseEnemy
## Shielded sides: a low crawler with a hard shell plate on its left and its
## right. Hits from either side (melee, projectiles, spells) bounce off. Only
## a blow coming DOWN from above (a down strike / pogo) hurts it.

@export var patrol_range := 80.0

var patrol_dir := 1


func _on_spawn() -> void:
	patrol_dir = 1


## Blocked unless the blow travels downward (from above).
func blocks_hit(direction: Vector2, _source: String) -> bool:
	return direction.y <= 0.5


func _think(delta: float) -> void:
	if global_position.x > home.x + patrol_range:
		patrol_dir = -1
	elif global_position.x < home.x - patrol_range:
		patrol_dir = 1
	if is_on_floor() and (not ground_ahead(patrol_dir) or wall_ahead(patrol_dir)):
		patrol_dir *= -1
	facing = patrol_dir
	state = "walk"
	move_ground(delta, patrol_dir * move_speed)


func _on_hit(direction: Vector2, knockback: float) -> void:
	stun_timer = 0.15
	velocity.x = direction.x * knockback * 0.3
