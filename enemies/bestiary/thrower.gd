class_name ThrowerEnemy
extends BaseEnemy
## Medium ranged enemy. It keeps its distance and LOBS deflectable
## projectiles at the player: a wind-up (arm back), then a gold orb thrown in
## an arc (a parabola) that comes down on the player. A melee swing that meets
## the orb knocks it away along the strike (ProjectileSystem.deflect_in_rect).
## It sees far (about half the screen). While the player is out of sight it
## wanders left and right at random. Up close, plain melee hurts it.

@export var throw_speed := 300.0
@export var throw_interval := 1.2
@export var lob_gravity := 900.0 ## Pull on the thrown orb (px/s^2): the arc.
@export var keep_away := 130.0
@export var projectile_damage := 15.0


func _think(delta: float) -> void:
	match state:
		"idle":
			if not sees_target():
				wander(delta, move_speed * 0.7)
				return
			var vx := 0.0
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
				var v := lob_velocity(hand, target_center())
				shoot(hand, v, v.length(), {
					"deflectable": true, "damage": projectile_damage, "radius": 8.0, "life": 3.0, "color": Color("#ffc94d"),
					"gravity": lob_gravity,
				})
				cooldown = throw_interval
				enter("recover")
		"recover":
			move_ground(delta, 0.0)
			if state_time >= 0.4:
				enter("idle")
		_:
			enter("idle")


## Launch velocity of a parabola from `from` that lands on `to`. The flight
## time grows with the distance, so near throws are flat and far ones high.
func lob_velocity(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	var time := clampf(absf(d.x) / throw_speed, 0.55, 1.2)
	return Vector2(d.x / time, d.y / time - 0.5 * lob_gravity * time)
