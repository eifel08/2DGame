class_name ChargerEnemy
extends BaseEnemy
## Large grounded charger. It stands its ground. When the player is in front
## of it, on about the same level and within `sight_range`, it paws the ground
## (a telegraph) and then rushes forward at high speed until it hits a wall,
## a ledge or runs `charge_distance`. After the charge it is winded for a
## moment (the opening), then walks back to its post.
## Its back is armored with spikes: it is IMMUNE to damage from above. A down
## strike still POGOS off it (a foothold, no damage). Hit it from the side,
## best while it is winded. An elite: it does not come back when you re-enter
## the room, and keeps its wounds (strong tier, keeps_wounds).

@export var charge_speed := 520.0
@export var charge_distance := 420.0
@export var windup_time := 0.5
@export var recover_time := 0.55

var _charge_from := 0.0


func _on_spawn() -> void:
	poise_states = ["windup", "charge"]


## Spiked back: every blow coming down from above is refused...
func blocks_hit(direction: Vector2, _source: String) -> bool:
	return direction.y > 0.5


## ...but the player can still pogo off it.
func pogo_on_block() -> bool:
	return true


func _think(delta: float) -> void:
	match state:
		"idle":
			move_ground(delta, 0.0)
			if sees_target(): # Look first (red eyes), attack when ready.
				face_target()
			if cooldown <= 0.0 and is_alerted() and target_valid() and absf(target_center().y - get_center().y) < 60.0 \
					and target_distance() <= sight_range:
				telegraph("charge")
				enter("windup")
		"windup":
			move_ground(delta, 0.0)
			if state_time >= windup_time:
				_charge_from = global_position.x
				enter("charge")
		"charge":
			move_ground(delta, facing * charge_speed)
			if is_on_wall() or not ground_ahead(facing) or absf(global_position.x - _charge_from) >= charge_distance:
				enter("recover")
		"recover":
			move_ground(delta, move_toward(velocity.x, 0.0, 2400.0 * delta))
			if state_time >= recover_time:
				enter("return")
		"return":
			var dx := home.x - global_position.x
			if absf(dx) < 6.0:
				cooldown = 0.35
				face_target()
				enter("idle")
			else:
				facing = 1 if dx > 0.0 else -1
				move_ground(delta, facing * move_speed)
				if sees_target() and absf(target_center().y - get_center().y) < 60.0 and cooldown <= 0.0:
					face_target()
					telegraph("charge")
					enter("windup")
		_:
			enter("idle")
