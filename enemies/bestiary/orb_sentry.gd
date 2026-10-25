class_name OrbSentryEnemy
extends BaseEnemy
## Floating 4-way turret, a wanderer. It drifts around its part of the room
## at random, whether it has seen the player or not, and keeps firing its
## pattern: a short glow, then energy orbs in the four cardinal directions
## (Up, Down, Left, Right) at once, at random short intervals.
## Its orbs are DEFLECTABLE: a melee swing knocks one away along the strike.

@export var orb_speed := 200.0
@export var orb_damage := 15.0
@export var interval_min := 0.6
@export var interval_max := 1.2
@export var wander_area := Vector2(260.0, 110.0) ## Half-size of the box around home it roams.
@export var drift_speed := 70.0

const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

var wander_to := Vector2.ZERO
var _wander_time := 0.0
var volleys := 0 ## Volleys fired (tests, debug).


func _on_spawn() -> void:
	_pick_wander_point()
	volleys = 0


func _pick_wander_point() -> void:
	for i in 8:
		var p := home + Vector2(randf_range(-wander_area.x, wander_area.x), randf_range(-wander_area.y, wander_area.y * 0.3))
		if not room.is_solid_at(p + Vector2(0, -size.y / 2.0)) and line_clear(get_center(), p + Vector2(0, -size.y / 2.0)):
			wander_to = p
			break
	_wander_time = randf_range(1.5, 3.0)


func _think(delta: float) -> void:
	_wander_time -= delta
	if global_position.distance_to(wander_to) < 10.0 or _wander_time <= 0.0 or is_on_wall() or is_on_ceiling():
		_pick_wander_point()
	var bob := Vector2(0, sin(t * 2.0) * 20.0)
	move_fly(delta, (wander_to - global_position).limit_length(1.0) * drift_speed + bob, 500.0)
	if sees_target(): # Only for the red eyes: it fires either way.
		face_target()
	match state:
		"idle":
			if cooldown <= 0.0:
				telegraph("burst")
				enter("windup")
		"windup":
			if state_time >= 0.3:
				for dir in DIRECTIONS:
					shoot(get_center() + dir * 18.0, dir, orb_speed, {"radius": 9.0, "damage": orb_damage, "life": 2.6,
						"color": Color("#ffc94d"), "deflectable": true})
				volleys += 1
				cooldown = randf_range(interval_min, interval_max)
				enter("idle")
		_:
			enter("idle")


func _on_hit(direction: Vector2, knockback: float) -> void:
	stun_timer = 0.1
	velocity = direction * knockback * 0.3
