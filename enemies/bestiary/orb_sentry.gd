class_name OrbSentryEnemy
extends BaseEnemy
## Floating 4-way turret. It floats in place and, at random intervals, glows
## and fires NON-DEFLECTABLE energy orbs in the four cardinal directions
## (Up, Down, Left, Right) at once. It only fires while the player is near.

@export var orb_speed := 200.0
@export var orb_damage := 15.0
@export var active_range := 520.0
@export var interval_min := 1.0
@export var interval_max := 2.2

const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]


func _think(delta: float) -> void:
	var hover := home + Vector2(0, sin(t * 2.0) * 6.0)
	move_fly(delta, (hover - global_position) * 4.0, 1200.0)
	match state:
		"idle":
			if cooldown <= 0.0 and target_distance() <= active_range:
				telegraph("burst")
				enter("windup")
		"windup":
			if state_time >= 0.4:
				for dir in DIRECTIONS:
					shoot(get_center() + dir * 18.0, dir, orb_speed, {"radius": 9.0, "damage": orb_damage, "life": 2.6, "color": Color("#8a3df0")})
				cooldown = randf_range(interval_min, interval_max)
				enter("idle")
		_:
			enter("idle")


func _on_hit(direction: Vector2, knockback: float) -> void:
	stun_timer = 0.1
	velocity = direction * knockback * 0.3
