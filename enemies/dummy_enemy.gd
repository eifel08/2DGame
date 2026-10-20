class_name DummyEnemy
extends Enemy
## Training dummy (weak or strong tier). The ground variant patrols and turns
## at walls and ledges; the flying variant hovers around its home point
## (ideal for pogo chains). It never respawns by itself.

const GRAVITY := 2000.0

@export var flying := false
@export var patrol := true
@export var patrol_range := 96.0
@export var patrol_speed := 55.0

var patrol_dir := 1
var t := 0.0


func _on_reset() -> void:
	patrol_dir = 1
	t = randf() * 10.0


func _on_hit(direction: Vector2, knockback: float) -> void:
	stun_timer = 0.25 * knockback_mul + 0.05
	velocity.x = direction.x * knockback
	if flying:
		velocity.y = direction.y * knockback * 0.6
	else:
		velocity.y = direction.y * knockback * 0.6 - (120.0 * knockback_mul if is_zero_approx(direction.y) else 0.0)


func _step_alive(delta: float) -> void:
	t += delta
	if flying:
		_step_flying(delta)
	else:
		_step_ground(delta)
	if absf(velocity.x) > 5.0:
		facing = 1 if velocity.x > 0.0 else -1


func _step_flying(delta: float) -> void:
	if stun_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
	else:
		var sway := sin(t * 0.8) * patrol_range * 0.7 if patrol else 0.0
		var dest := home + Vector2(sway, sin(t * 2.2) * 8.0)
		velocity = (dest - global_position) * 3.0
	move_and_slide()


func _step_ground(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, 800.0)
	if stun_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	elif patrol:
		if global_position.x > home.x + patrol_range:
			patrol_dir = -1
		if global_position.x < home.x - patrol_range:
			patrol_dir = 1
		velocity.x = patrol_dir * patrol_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)

	move_and_slide()
	if stun_timer > 0.0:
		return
	if is_on_wall():
		patrol_dir = 1 if get_wall_normal().x > 0.0 else -1
	# Turn around at ledges.
	if is_on_floor():
		var ahead_x := global_position.x + patrol_dir * (size.x / 2.0 + 2.0)
		if not room.is_ground_at(Vector2(ahead_x, global_position.y + 2.0)):
			patrol_dir *= -1
