class_name CameraRig
extends Camera2D
## Smooth follow camera with trauma-based screen shake.
## Shake offset = max_shake * trauma^2, so small hits feel subtle and big hits
## feel strong. Trauma decays continuously, including during hitstop.

@export var max_shake := 14.0
@export var trauma_decay := 1.7
@export var look_ahead := 48.0

var trauma := 0.0
var shake_enabled := true
var bounds := Rect2()


func setup(room_bounds: Rect2) -> void:
	bounds = room_bounds
	position_smoothing_enabled = false


func _target_for(player: Player) -> Vector2:
	var view := get_viewport_rect().size
	var target := player.get_center() + Vector2(player.facing * look_ahead, -view.y * 0.05)
	var half := view / 2.0
	target.x = clampf(target.x, bounds.position.x + half.x, maxf(bounds.position.x + half.x, bounds.end.x - half.x))
	target.y = clampf(target.y, bounds.position.y + half.y, maxf(bounds.position.y + half.y, bounds.end.y - half.y))
	return target


func follow(player: Player, delta: float) -> void:
	var target := _target_for(player)
	global_position.x = lerpf(global_position.x, target.x, Geom.damp(7.0, delta))
	global_position.y = lerpf(global_position.y, target.y, Geom.damp(5.0, delta))


func snap_to(player: Player) -> void:
	global_position = _target_for(player)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func step_shake(delta: float) -> void:
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	var power := trauma * trauma * max_shake if shake_enabled else 0.0
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * power
