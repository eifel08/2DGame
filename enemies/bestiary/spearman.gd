class_name SpearmanEnemy
extends BaseEnemy
## Flying spearman. It hovers at its post. Once it notices the player it
## drifts toward them (keeping a little distance, a bit above) and, close
## enough, draws back and throws a spear straight at them. The spear can be
## DEFLECTED by a melee strike, but it does not fly back: the strike knocks it
## out of the air (on_deflect "destroy"), so it cannot hit the player.

@export var drift_speed := 75.0
@export var keep_distance := 170.0
@export var throw_range := 240.0
@export var spear_speed := 380.0
@export var spear_damage := 15.0
@export var throw_interval := 1.2

var throws := 0 ## Spears thrown (tests, debug).
var _lost := 0.0


func _on_spawn() -> void:
	throws = 0
	_lost = 0.0


func hand() -> Vector2:
	return get_center() + Vector2(facing * 8.0, -6.0)


func _think(delta: float) -> void:
	match state:
		"idle":
			var hover := home + Vector2(0, sin(t * 2.0) * 6.0)
			move_fly(delta, (hover - global_position) * 3.0, 800.0)
			if sees_target() and target_in_leash():
				enter("drift")
		"drift":
			face_target()
			var side := -facing
			var spot := target_center() + Vector2(side * keep_distance, -50.0) + Vector2(0, size.y / 2.0)
			move_fly(delta, (spot - global_position).limit_length(1.0) * drift_speed, 500.0)
			if sees_target(throw_range * 1.6):
				_lost = 0.0
				if cooldown <= 0.0 and target_distance() <= throw_range:
					telegraph("throw")
					enter("windup")
			else:
				_lost += delta
			if _lost > 1.5 or not target_in_leash():
				enter("return")
		"windup":
			face_target()
			move_fly(delta, Vector2.ZERO, 900.0)
			if state_time >= 0.35:
				shoot(hand(), target_center() - hand(), spear_speed, {
					"shape": "spear", "deflectable": true, "on_deflect": "destroy", "radius": 6.0,
					"damage": spear_damage, "life": 2.0, "color": Color("#ffc94d"),
				})
				throws += 1
				cooldown = throw_interval
				enter("drift")
		"return":
			move_fly(delta, (home - global_position).limit_length(1.0) * drift_speed * 1.5, 600.0)
			if home_distance() < 10.0:
				enter("idle")
		_:
			enter("idle")
