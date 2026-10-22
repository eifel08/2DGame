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
## Three kinds, one scene each:
##   standard   grapple_peg.tscn            stays put (gold)
##   moving     grapple_peg_moving.tscn     back and forth along `travel`
##                                          (Mover, cyan); the rope follows,
##                                          so a hold or swing rides along
##   breakable  grapple_peg_breakable.tscn  latching starts a short timer
##                                          (`crumble_delay`, red, cracked);
##                                          then it crumbles, the hook lets go
##                                          and the peg is back after
##                                          `respawn_time`
## Game._update_movers steps every peg before the player moves.
## Art: replace Visual (Sprite2D); keep Shape (CollisionShape2D) small, the
## hook's forgiving rays already widen it. The moving path is drawn here.

const LAYER := 7
const MASK := 1 << (LAYER - 1)

@export_enum("standard", "moving", "breakable") var kind := "standard"
@export var travel := Vector2.ZERO ## Moving: offset of the far end.
@export var period := 4.0 ## Moving: seconds for there and back.
@export var phase := 0.0 ## Moving: start offset, 0..1 of a period.
@export var crumble_delay := 1.0 ## Breakable: seconds from latching to crumbling.
@export var respawn_time := 3.0 ## Breakable: seconds until it is back.
@export var draw_markings := true

var active := true ## False while crumbled: the hook cannot find it.
var crumbling := false
var crumble_left := 0.0
var respawn_left := 0.0
var mover: Mover


func _ready() -> void:
	collision_layer = MASK
	collision_mask = 0
	monitoring = false
	if kind == "moving":
		mover = Mover.new(position, travel, period, phase)
		position = mover.position_at(mover.t)


## Called by the hook when it latches here. A breakable peg starts to go.
func on_hooked() -> void:
	if kind == "breakable" and active and not crumbling:
		crumbling = true
		crumble_left = crumble_delay


## One game step: motion, the crumble timer and the respawn.
func step(delta: float) -> void:
	if mover:
		position = mover.step(delta)
		queue_redraw()
	if kind != "breakable":
		return
	if crumbling:
		crumble_left -= delta
		var visual := get_node_or_null("Visual") as Node2D
		if visual: # Shake while it is about to go.
			visual.position = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		if crumble_left <= 0.0:
			crumbling = false
			active = false
			collision_layer = 0
			visible = false
			respawn_left = respawn_time
			if visual:
				visual.position = Vector2.ZERO
			Events.peg_crumbled.emit(global_position)
	elif not active:
		respawn_left -= delta
		if respawn_left <= 0.0:
			active = true
			collision_layer = MASK
			visible = true


func _draw() -> void:
	if not draw_markings or mover == null:
		return
	draw_dashed_line(mover.start - position, mover.start + travel - position, Color(0.55, 1.0, 0.95, 0.35), 2.0, 6.0)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(0.55, 1.0, 0.95, 0.8), 1.5)
