class_name EjectState
extends PlayerState
## Upward room transition (Rule B, GUIDELINES.md). The player arrives at the
## threshold of the floor gap, inside the opening, and is physically carried
## out of it:
##   rise - straight up out of the gap until the feet clear the floor surface
##          (no sideways motion, so the gap's edges are never clipped)
##   arc  - a ballistic launch up and to ONE side, landing on the floor beside
##          the gap. Real gravity and real collisions (move_and_slide).
## Input is ignored until the player lands, so the arc never drifts back over
## the gap. The player is NOT invulnerable during the ejection.

const RISE_SPEED := 620.0 ## Speed while climbing out of the gap.
const CLEARANCE := 6.0 ## Feet this far above the floor surface end the rise.
const APEX_HEIGHT := 72.0 ## Arc apex above the floor surface.
const TIMEOUT := 2.0 ## Safety net: hand control back if the arc never lands.

var phase := "rise"
var target := Vector2.ZERO ## Landing point (feet) beside the gap.
var surface_y := 0.0 ## Top of the floor next to the gap.
var elapsed := 0.0
var flight_time := 0.0 ## Planned duration of the arc (tests, debug).


func enter(params: Dictionary) -> void:
	target = params["target"]
	surface_y = target.y
	phase = "rise"
	elapsed = 0.0
	flight_time = 0.0
	p.is_jumping = false
	p.wall_sliding = false
	p.grounded = false
	p.velocity = Vector2(0.0, -RISE_SPEED)


func step(delta: float) -> void:
	elapsed += delta
	if phase == "rise":
		p.velocity = Vector2(0.0, -RISE_SPEED)
		p.move(delta)
		if p.global_position.y <= surface_y - CLEARANCE or p.is_on_ceiling():
			_launch()
	else:
		p.velocity.y += Config.movement.gravity * delta
		p.move(delta)
		if p.grounded and p.velocity.y >= 0.0:
			p.fsm.change("normal")
			return
	if elapsed >= TIMEOUT:
		p.fsm.change("normal")


## Ballistic launch from here to `target` with its apex APEX_HEIGHT above the
## floor: vy from the rise to the apex, vx from the total flight time.
func _launch() -> void:
	phase = "arc"
	var g: float = Config.movement.gravity
	var apex_y := minf(p.global_position.y, surface_y) - APEX_HEIGHT
	var vy := -sqrt(2.0 * g * (p.global_position.y - apex_y))
	flight_time = -vy / g + sqrt(2.0 * (target.y - apex_y) / g)
	p.velocity = Vector2((target.x - p.global_position.x) / flight_time, vy)
	p.facing = 1 if target.x >= p.global_position.x else -1
