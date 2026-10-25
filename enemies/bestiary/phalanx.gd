class_name PhalanxEnemy
extends BaseEnemy
## BONUS - Shield-phalanx. A soldier behind a tall tower shield that always
## points the way it faces. Every hit from the FRONT (melee, projectiles,
## spells) bounces off the shield. From behind or from above it is open. It
## turns to face the player only after `turn_delay`: get behind it, or pogo
## off its helmet. When the player is in front and close, it thrusts its
## spear (a DEFLECTABLE strike: parry it with a swing).

@export var turn_delay := 0.5
@export var reach := 64.0
@export var thrust_damage := 15.0
@export var start_facing := -1 ## Shield toward the way in (the Bestiary is walked left to right).

var _behind_time := 0.0


func _on_spawn() -> void:
	facing = start_facing
	_behind_time = 0.0


## The shield covers the front: a blow travelling toward its face.
func blocks_hit(direction: Vector2, _source: String) -> bool:
	if direction.y > 0.5:
		return false # From above: over the shield.
	return direction.x != 0.0 and signf(direction.x) == -facing


func _think(delta: float) -> void:
	if not target_valid():
		move_ground(delta, 0.0)
		return
	var dx := target.global_position.x - global_position.x
	var behind := absf(dx) > 4.0 and signf(dx) != facing
	match state:
		"idle", "walk", "turn":
			var vx := 0.0
			if behind and sees_target(sight_range * 1.2):
				_behind_time += delta
				state = "turn"
				if _behind_time >= turn_delay:
					facing = -facing
					_behind_time = 0.0
			else:
				_behind_time = 0.0
				state = "idle"
				if sees_target() and target_in_leash():
					if absf(dx) <= reach and absf(target_center().y - get_center().y) < 50.0 and cooldown <= 0.0:
						telegraph("thrust")
						enter("windup")
					elif absf(dx) > reach * 0.8 and ground_ahead(facing):
						vx = facing * move_speed
						state = "walk"
			move_ground(delta, vx)
		"windup":
			move_ground(delta, 0.0)
			if state_time >= 0.3:
				strike(front_rect(reach + 10.0, 18.0, 18.0), thrust_damage, true, 0.12)
				enter("thrust")
		"thrust":
			move_ground(delta, 0.0)
			if state_time >= 0.15:
				enter("recover")
		"recover", "staggered":
			move_ground(delta, 0.0)
			if state_time >= 0.35:
				cooldown = 0.45
				enter("idle")
		_:
			enter("idle")


func _on_hit(direction: Vector2, knockback: float) -> void:
	stun_timer = 0.2
	velocity.x = direction.x * knockback * 0.4
