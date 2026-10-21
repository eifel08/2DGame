class_name AbilityState
extends PlayerState
## Movement is handed to an external controller (a mobility ultimate).
## Controller contract: control_start(player), control_step(delta, player) -> bool
## (true = finished), control_finish(player), and an `invulnerable` property.
## `invulnerable` is read every step, so a controller may switch it mid-move
## (Meteor Slam: a vulnerable hop, then an invulnerable dive).

var controller: Object


func enter(params: Dictionary) -> void:
	controller = params["controller"]
	p.is_jumping = false
	p.wall_sliding = false
	controller.control_start(p)
	_sync_invulnerable()


func step(delta: float) -> void:
	var done: bool = controller.control_step(delta, p)
	_sync_invulnerable()
	if done:
		p.fsm.change("normal")


func _sync_invulnerable() -> void:
	p.health.set_invulnerable("ability", bool(controller.get("invulnerable")))


func exit() -> void:
	p.health.set_invulnerable("ability", false)
	var finished := controller
	controller = null
	if finished:
		finished.control_finish(p)
