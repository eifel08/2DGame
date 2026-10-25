class_name HopperEnemy
extends BaseEnemy
## Bouncing pest that clings to ANY surface: floor, walls and ceilings. Its
## own "gravity" always points into the surface it sits on, so it crouches
## and hops on a wall or upside down on a ceiling just as on the floor. Made
## for enclosed rooms with low ceilings and many walls. It never looks for
## the player. Again and again it picks a nearby point on some surface:
##   same surface   a hop in a parabola along it (its gravity pulls it back)
##   other surface  a straight dart across the open space; whatever it hits
##                  first (wall, ceiling, floor) it sticks to
## It drifts back toward home when it strays too far.

@export var reach := 170.0 ## How far its target points lie.
@export var hop_time := 0.45 ## Flight time of a parabola hop (s).
@export var hop_gravity := 1600.0 ## Its pull toward the surface during a hop.
@export var dart_speed := 300.0
@export var dart_time := 1.0 ## A dart that hits nothing falls after this long.
@export var wait_time := Vector2(0.3, 0.8) ## min, max pause on a surface.

var normal := Vector2.UP ## Points away from the surface it clings to.
var goal := Vector2.ZERO ## The point it is heading for.
var hops := 0 ## Parabola hops so far (tests, debug).
var darts := 0 ## Straight darts so far.
var surfaces_seen := {} ## normal -> true: floor UP, walls LEFT / RIGHT, ceiling DOWN.
var _wait := 0.5


func _on_spawn() -> void:
	normal = Vector2.UP
	goal = home
	hops = 0
	darts = 0
	surfaces_seen = {Vector2.UP: true}
	_wait = randf_range(wait_time.x, wait_time.y)


func tangent() -> Vector2:
	return Vector2(-normal.y, normal.x)


func _think(delta: float) -> void:
	match state:
		"idle", "stick":
			state = "stick"
			velocity = Vector2.ZERO
			if state_time >= _wait:
				enter("crouch")
		"crouch":
			velocity = Vector2.ZERO
			if state_time >= 0.12:
				_launch()
		"hop":
			velocity -= normal * hop_gravity * delta
			_fly(delta)
			if state == "hop" and state_time > hop_time * 2.0:
				enter("fall")
		"dart":
			_fly(delta)
			if state == "dart" and state_time > dart_time:
				enter("fall")
		"fall":
			velocity.y = minf(velocity.y + GRAVITY * delta, 800.0)
			_fly(delta)
		_:
			enter("stick")


func _launch() -> void:
	var pick := pick_goal()
	goal = pick[0]
	var from := get_center()
	if pick[1]:
		# Same surface: a parabola along it, pulled back by its own gravity.
		var along := (goal - from).dot(tangent())
		velocity = tangent() * (along / hop_time) + normal * (0.5 * hop_gravity * hop_time)
		hops += 1
		enter("hop")
	else:
		velocity = (goal - from).normalized() * dart_speed
		darts += 1
		enter("dart")


## Moves; touching any surface makes it stick there.
func _fly(delta: float) -> void:
	var hit := move_and_collide(velocity * delta)
	if hit:
		_attach(hit.get_normal())


func _attach(n: Vector2) -> void:
	normal = Vector2(signf(n.x), 0.0) if absf(n.x) > absf(n.y) else Vector2(0.0, signf(n.y))
	velocity = Vector2.ZERO
	surfaces_seen[normal] = true
	_wait = randf_range(wait_time.x, wait_time.y)
	enter("stick")


## A point next to a surface within reach, found by casting a few random rays
## from its middle. Returns [point, same_surface].
func pick_goal() -> Array:
	var from := get_center()
	var toward_home := home + Vector2(0, -size.y / 2.0) - from
	for i in 20:
		var dir := Vector2.from_angle(randf() * TAU)
		if toward_home.length() > leash_range * 0.5:
			dir = toward_home.normalized().rotated(randf_range(-0.7, 0.7))
		if dir.dot(normal) < -0.3:
			continue # Not into its own surface.
		var prev := from
		var hit_normal := Vector2.ZERO
		var d := 8.0
		while d <= reach:
			var q := from + dir * d
			if room.is_solid_at(q):
				var a := room.tiles.local_to_map(room.tiles.to_local(prev))
				var b := room.tiles.local_to_map(room.tiles.to_local(q))
				hit_normal = Vector2(-signf(dir.x), 0.0) if a.x != b.x else Vector2(0.0, -signf(dir.y))
				break
			prev = q
			d += 6.0
		if hit_normal == Vector2.ZERO or prev.distance_to(from) < 36.0:
			continue
		var same := hit_normal == normal and absf((prev - from).dot(normal)) < 10.0
		return [prev, same]
	return [from + normal * 60.0, false] # Nothing found: jump off the surface.


func _step_stunned(delta: float) -> void:
	if state in ["hop", "dart", "fall"]:
		_fly(delta) # Hits flash it but do not knock it off its path.


func _on_hit(_direction: Vector2, _knockback: float) -> void:
	stun_timer = 0.08
