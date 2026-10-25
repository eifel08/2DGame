class_name HopperEnemy
extends BaseEnemy
## Bouncing pest, made for cramped spaces (low ceilings, many walls). It
## never looks for the player. Again and again it picks a nearby point, at
## any height, and goes there:
##   same level      a hop in a parabola that lands on the point
##   other height    a straight dart at the point; it bounces off walls and
##                   low ceilings on the way, then drops when it arrives
## It drifts back toward home when it strays too far.

@export var reach := Vector2(150.0, 140.0) ## How far its target points lie (x, y); high darts meet low ceilings.
@export var hop_time := 0.5 ## Flight time of a parabola hop (s).
@export var dart_speed := 280.0
@export var dart_time := 0.9 ## A dart gives up after this long.
@export var wait_time := Vector2(0.3, 0.9) ## min, max pause between moves.

var goal := Vector2.ZERO ## Feet position it is heading for.
var hops := 0 ## Parabola hops so far (tests, debug).
var darts := 0 ## Straight darts so far.
var bounces := 0 ## Wall / ceiling bounces during darts.
var _wait := 0.5


func _on_spawn() -> void:
	_wait = randf_range(wait_time.x, wait_time.y)
	hops = 0
	darts = 0
	bounces = 0
	goal = home


## A free point near it: same level (on ground) or another height (open air).
## Returns [point, same_level].
func pick_goal() -> Array:
	var bias := 0.0
	if home_distance() > leash_range * 0.5:
		bias = signf(home.x - global_position.x)
	for i in 12:
		var dx := randf_range(50.0, reach.x) * (bias if bias != 0.0 else (-1.0 if randf() < 0.5 else 1.0))
		if randf() < 0.5: # Same level: a spot on the ground beside it.
			var p := global_position + Vector2(dx, 0.0)
			if room.is_ground_at(p + Vector2(0, 2)) and not room.is_solid_at(p + Vector2(0, -size.y / 2.0)) \
					and line_clear(get_center(), p + Vector2(0, -size.y / 2.0)):
				return [p, true]
		else: # Another height: any open spot up or down.
			var p := global_position + Vector2(dx * 0.7, randf_range(-reach.y, reach.y * 0.5))
			if absf(p.y - global_position.y) >= 24.0 and not room.is_solid_at(p + Vector2(0, -size.y / 2.0)):
				return [p, false]
	return [global_position + Vector2(-facing * 60.0, 0.0), true]


func _think(delta: float) -> void:
	match state:
		"idle":
			move_ground(delta, move_toward(velocity.x, 0.0, 1200.0 * delta))
			if is_on_floor() and state_time >= _wait:
				enter("crouch")
		"crouch":
			move_ground(delta, 0.0)
			if state_time >= 0.12:
				var pick := pick_goal()
				goal = pick[0]
				facing = 1 if goal.x >= global_position.x else -1
				if pick[1]:
					# Parabola: lands on the goal after hop_time.
					velocity = Vector2((goal.x - global_position.x) / hop_time, -0.5 * GRAVITY * hop_time)
					hops += 1
					enter("hop")
				else:
					velocity = (goal - global_position).normalized() * dart_speed
					darts += 1
					enter("dart")
		"hop":
			move_ground(delta, velocity.x)
			if is_on_wall():
				velocity.x = -velocity.x * 0.6
				bounces += 1
			if is_on_floor() and state_time > 0.08:
				_land()
		"dart": # A straight line, bouncing off whatever it hits.
			var hit := move_and_collide(velocity * delta)
			if hit:
				velocity = velocity.bounce(hit.get_normal()) * 0.85
				bounces += 1
			if global_position.distance_to(goal) < 12.0 or state_time >= dart_time:
				enter("fall")
		"fall":
			move_ground(delta, move_toward(velocity.x, 0.0, 400.0 * delta))
			if is_on_floor():
				_land()
		_:
			enter("idle")


func _land() -> void:
	_wait = randf_range(wait_time.x, wait_time.y)
	enter("idle")
