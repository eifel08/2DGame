class_name InputState
extends RefCounted
## Buffers action edges (pressed / released) until a simulation step uses them.
## This way no press is lost while hitstop freezes the simulation.
## Actions are defined in Project Settings > Input Map.

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"jump", &"attack", &"dash", &"heal", &"grapple",
	&"ult_1", &"ult_2", &"ult_3", &"ult_4", &"ult_5", &"ult_6", &"ult_7", &"ult_8",
	&"interact", &"inventory", &"pause", &"toggle_debug", &"debug_navigate", &"reset_room",
]

var _pressed := {}
var _released := {}


## Call once per physics frame, before anything reads input.
func poll() -> void:
	for action in ACTIONS:
		if Input.is_action_just_pressed(action):
			_pressed[action] = true
		if Input.is_action_just_released(action):
			_released[action] = true


func is_down(action: StringName) -> bool:
	return Input.is_action_pressed(action)


func was_pressed(action: StringName) -> bool:
	return _pressed.get(action, false)


func was_released(action: StringName) -> bool:
	return _released.get(action, false)


## Clears a pressed edge so no other system reacts to it.
func consume(action: StringName) -> void:
	_pressed.erase(action)


## Call after each simulation step that actually ran.
func end_step() -> void:
	_pressed.clear()
	_released.clear()


## True if any gameplay action was freshly pressed this step (keys that were
## already held down do not count). Used to break the checkpoint trance.
func any_pressed() -> bool:
	for action in _pressed:
		if action not in [&"toggle_debug", &"debug_navigate", &"reset_room"]:
			return true
	return false


func axis_x() -> int:
	return int(is_down(&"move_right")) - int(is_down(&"move_left"))


func axis_y() -> int:
	return int(is_down(&"move_down")) - int(is_down(&"move_up"))
