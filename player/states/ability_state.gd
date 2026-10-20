class_name AbilityState
extends PlayerState
## Movement is handed to an external controller (a mobility ultimate).
## Controller contract: control_start(player), control_step(delta, player) -> bool
## (true = finished), control_finish(player), and an `invulnerable` property.

var controller: Object


func enter(params: Dictionary) -> void:
	controller = params["controller"]
	p.is_jumping = false
	p.wall_sliding = false
	if controller.get("invulnerable"):
		p.health.set_invulnerable("ability", true)
	controller.control_start(p)


func step(delta: float) -> void:
	if controller.control_step(delta, p):
		p.fsm.change("normal")


func exit() -> void:
	p.health.set_invulnerable("ability", false)
	var finished := controller
	controller = null
	if finished:
		finished.control_finish(p)
