class_name CameraRig
extends Camera2D
## Smooth follow camera with trauma-based screen shake, plus look up / down:
## holding Up or Down while standing still pans the view vertically after a
## short delay (Config.camera). The view never leaves the room bounds.
## Shake offset = max_shake * trauma^2, so small hits feel subtle and big hits
## feel strong. Trauma decays continuously, including during hitstop.

@export var max_shake := 14.0
@export var trauma_decay := 1.7
@export var look_ahead := 48.0

var trauma := 0.0
var shake_enabled := true
var bounds := Rect2()
var look_offset := 0.0 ## Current vertical look pan in px (negative = up).
var _look_hold := 0.0 ## How long the current look direction has been held.
var _look_dir := 0


func setup(room_bounds: Rect2) -> void:
	bounds = room_bounds
	position_smoothing_enabled = false


func _target_for(player: Player) -> Vector2:
	var view := get_viewport_rect().size
	var target := _clamp_center(player.get_center() + Vector2(player.facing * look_ahead, -view.y * 0.05))
	# The look pans from the view actually on screen (after the room clamp),
	# so it works even where the follow target is pinned against a room edge.
	return _clamp_center(target + Vector2(0.0, look_offset))


func follow(player: Player, delta: float) -> void:
	_step_look(player, delta)
	var target := _target_for(player)
	global_position.x = lerpf(global_position.x, target.x, Geom.damp(7.0, delta))
	global_position.y = lerpf(global_position.y, target.y, Geom.damp(5.0, delta))


func snap_to(player: Player) -> void:
	look_offset = 0.0
	_look_hold = 0.0
	_look_dir = 0
	global_position = _target_for(player)


## Pans toward the held look direction once it was held for look_delay;
## eases back as soon as the player lets go or moves.
func _step_look(player: Player, delta: float) -> void:
	var c = Config.camera
	var dir := player.look_request()
	if dir != _look_dir:
		_look_dir = dir
		_look_hold = 0.0
	_look_hold += delta
	var want: float = dir * c.look_distance if dir != 0 and _look_hold >= c.look_delay else 0.0
	# Returning is twice as fast: once the player moves, the view is needed ahead.
	var rate: float = c.look_speed * (2.0 if want == 0.0 else 1.0)
	look_offset = lerpf(look_offset, want, Geom.damp(rate, delta))


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Shake is clamped so the view never shows anything outside the room:
## no glimpses of empty space beyond the walls.
func step_shake(delta: float) -> void:
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	var power := trauma * trauma * max_shake if shake_enabled else 0.0
	var wanted := global_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * power
	offset = _clamp_center(wanted) - global_position


## Visible world rect (camera center + offset), for checks and tests.
func view_rect() -> Rect2:
	var view := get_viewport_rect().size
	return Rect2(global_position + offset - view / 2.0, view)


func _clamp_center(center: Vector2) -> Vector2:
	var half := get_viewport_rect().size / 2.0
	return Vector2(
		clampf(center.x, bounds.position.x + half.x, maxf(bounds.position.x + half.x, bounds.end.x - half.x)),
		clampf(center.y, bounds.position.y + half.y, maxf(bounds.position.y + half.y, bounds.end.y - half.y)))
