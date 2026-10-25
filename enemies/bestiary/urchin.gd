class_name UrchinEnemy
extends BaseEnemy
## Spike burst. It wanders left and right at random (turning at walls and
## ledges). When the player gets too close it stops, swells (a telegraph)
## and fires NON-DEFLECTABLE spikes in all directions (8 by default). Back
## off when it swells.

@export var trigger_range := 120.0
@export var spike_count := 8
@export var spike_speed := 260.0
@export var spike_damage := 15.0

var last_burst := 0 ## Spikes fired by the last burst (tests, debug).
var wander_dir := 1
var _wander_time := 0.0


func _on_spawn() -> void:
	wander_dir = -1 if randf() < 0.5 else 1
	_wander_time = randf_range(1.0, 2.2)


func _think(delta: float) -> void:
	match state:
		"idle":
			# Random wander: pick a side, walk a while, sometimes pause.
			_wander_time -= delta
			if _wander_time <= 0.0:
				wander_dir = [-1, 0, 1, 1, -1].pick_random()
				_wander_time = randf_range(0.8, 2.0)
			if wander_dir != 0 and is_on_floor() and (not ground_ahead(wander_dir) or wall_ahead(wander_dir)):
				wander_dir = -wander_dir
			if wander_dir != 0:
				facing = wander_dir
			move_ground(delta, wander_dir * move_speed)
			if cooldown <= 0.0 and target_distance() <= trigger_range and target_valid():
				notice()
				telegraph("burst")
				enter("windup")
		"windup":
			move_ground(delta, 0.0)
			if state_time >= 0.4:
				for i in spike_count:
					var dir := Vector2.from_angle(TAU * i / spike_count - PI / 2.0)
					shoot(get_center() + dir * 14.0, dir, spike_speed, {
						"shape": "spike", "radius": 6.0, "damage": spike_damage, "life": 1.3, "color": Color("#c23a5a"),
					})
				last_burst = spike_count
				cooldown = 1.0
				enter("recover")
		"recover":
			move_ground(delta, 0.0)
			if state_time >= 0.2:
				enter("idle")
		_:
			enter("idle")
