class_name TranceState
extends PlayerState
## Loading into a checkpoint (save load, death respawn, new game): the player
## floats in a trance at the checkpoint, invulnerable and without control.
## Any freshly pressed button (not one that was already held) breaks it.

var time := 0.0


func enter(_params: Dictionary) -> void:
	time = 0.0
	p.velocity = Vector2.ZERO
	p.is_jumping = false
	p.wall_sliding = false
	p.health.set_invulnerable("trance", true)


func step(delta: float) -> void:
	time += delta
	p.velocity = Vector2.ZERO
	p.move(delta) # Stay settled on the floor; the rig floats visually.
	if time > 0.15 and p.input.any_pressed():
		p.fsm.change("normal")
		Events.trance_broken.emit(p)


func exit() -> void:
	p.health.set_invulnerable("trance", false)
