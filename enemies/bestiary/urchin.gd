class_name UrchinEnemy
extends BaseEnemy
## Spike burst. It sits still. When the player gets too close it swells (a
## telegraph) and fires NON-DEFLECTABLE spikes in all directions (8 by
## default). Back off when it swells.

@export var trigger_range := 120.0
@export var spike_count := 8
@export var spike_speed := 260.0
@export var spike_damage := 15.0

var last_burst := 0 ## Spikes fired by the last burst (tests, debug).


func _think(delta: float) -> void:
	match state:
		"idle":
			move_ground(delta, 0.0)
			if cooldown <= 0.0 and target_distance() <= trigger_range and target_valid():
				telegraph("burst")
				enter("windup")
		"windup":
			move_ground(delta, 0.0)
			if state_time >= 0.55:
				for i in spike_count:
					var dir := Vector2.from_angle(TAU * i / spike_count - PI / 2.0)
					shoot(get_center() + dir * 14.0, dir, spike_speed, {
						"shape": "spike", "radius": 6.0, "damage": spike_damage, "life": 1.3, "color": Color("#c23a5a"),
					})
				last_burst = spike_count
				cooldown = 2.0
				enter("recover")
		"recover":
			move_ground(delta, 0.0)
			if state_time >= 0.35:
				enter("idle")
		_:
			enter("idle")
