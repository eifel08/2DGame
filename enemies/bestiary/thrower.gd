class_name ThrowerEnemy
extends BaseEnemy
## Medium ranged enemy. It keeps its distance and throws DEFLECTABLE
## projectiles at the player: a wind-up (arm back), then a gold orb aimed at
## the player. A melee swing that meets the orb sends it straight back.

@export var throw_speed := 300.0
@export var throw_interval := 1.8
@export var keep_away := 130.0
@export var projectile_damage := 15.0


func _think(delta: float) -> void:
	match state:
		"idle":
			var vx := 0.0
			if sees_target():
				face_target()
				var dx := target.global_position.x - global_position.x
				if absf(dx) < keep_away and ground_ahead(-facing) and not wall_ahead(-facing):
					vx = -facing * move_speed # Back off, still facing the player.
				if cooldown <= 0.0:
					telegraph("throw")
					enter("windup")
			move_ground(delta, vx)
		"windup":
			face_target()
			move_ground(delta, 0.0)
			if state_time >= 0.45:
				var hand := get_center() + Vector2(facing * 10.0, -10.0)
				shoot(hand, target_center() - hand, throw_speed, {
					"deflectable": true, "damage": projectile_damage, "radius": 8.0, "life": 3.0, "color": Color("#ffc94d"),
				})
				cooldown = throw_interval
				enter("recover")
		"recover":
			move_ground(delta, 0.0)
			if state_time >= 0.4:
				enter("idle")
		_:
			enter("idle")
