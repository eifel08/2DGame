class_name StateMachine
extends RefCounted
## Generic finite state machine. A state is any object with
## enter(params: Dictionary), step(delta: float) and exit().
## A state that calls change() inside step() should return right after.

var states := {}
var current: Object
var current_name := ""
var time_in_state := 0.0


func add(state_name: String, state: Object) -> void:
	states[state_name] = state


func change(state_name: String, params := {}) -> void:
	assert(states.has(state_name), "StateMachine: unknown state '%s'" % state_name)
	if current:
		current.exit()
	current = states[state_name]
	current_name = state_name
	time_in_state = 0.0
	current.enter(params)


func step(delta: float) -> void:
	time_in_state += delta
	if current:
		current.step(delta)


func is_in(state_name: String) -> bool:
	return current_name == state_name
