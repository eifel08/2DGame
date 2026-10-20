class_name CastState
extends PlayerState
## Ultimate wind-up: the player hovers in place, invulnerable, then the
## ability is released through the `on_release` callback.

var timer := 0.0
var on_release := Callable()


func enter(params: Dictionary) -> void:
	timer = params.get("duration", 0.0)
	on_release = params.get("on_release", Callable())
	p.is_jumping = false
	p.velocity.y = 0.0
	p.health.set_invulnerable("cast", true)


func step(delta: float) -> void:
	p.velocity.x = move_toward(p.velocity.x, 0.0, 4000.0 * delta)
	p.velocity.y = 0.0 # Hover while casting, even in the air.
	timer -= delta
	if timer <= 0.0:
		var release := on_release
		on_release = Callable()
		p.fsm.change("normal")
		if release.is_valid():
			release.call() # May switch to the "ability" state.


func exit() -> void:
	on_release = Callable()
	p.health.set_invulnerable("cast", false)
