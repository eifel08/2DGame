class_name GrapplePeg
extends Area2D
## Grapple peg: an anchor point only the grappling hook interacts with.
## It sits alone on physics layer 7 "grapple_peg" with an empty mask, and no
## body has layer 7 in its mask, so the player and enemies pass through it.
## The hook finds it with its own rays on that layer (GrappleHook._cast_pegs).
##   swing throw (Down in the air)  a pendulum around the peg
##   any other throw                a pull to the peg, then a static hold:
##                                  the player hangs still under it
##                                  (GrappleState, "Peg hold")
## Art: replace Visual (Sprite2D); keep Shape (CollisionShape2D) small, the
## hook's forgiving rays already widen it.

const LAYER := 7
const MASK := 1 << (LAYER - 1)


func _ready() -> void:
	collision_layer = MASK
	collision_mask = 0
	monitoring = false
