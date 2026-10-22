class_name Lava
extends Node2D
## Lava: a floor-only hazard (GUIDELINES.md, Hazards). One node covers a run
## of 'L' cells in a layout; tools/build_assets.gd refuses lava that is not
## sitting on a solid floor. No collision: like spikes, touching its hazard
## rect (get_rect) deals hazard damage and sends the player back to safe ground.
## Unlike spikes it can NEVER be pogoed: CombatManager's down-attack ignores
## lava (Room.find_hazard(rect, false)), so a pogo attempt falls in.
## The node origin is the top-left of the run. Art: replace Visual; the
## surface glow and bubbles are drawn by this script (draw_bubbles).

const SURFACE := 8.0 ## The lava surface sits this far below the top of its cells.

@export var size := Vector2(32, 32)
@export var draw_bubbles := true

var _t := 0.0


func _ready() -> void:
	var body := get_node_or_null("Visual/Body") as Polygon2D
	if body:
		body.polygon = PackedVector2Array([Vector2(0, SURFACE), Vector2(size.x, SURFACE), size, Vector2(0, size.y)])
	var crust := get_node_or_null("Visual/Surface") as Polygon2D
	if crust:
		crust.polygon = PackedVector2Array([Vector2(0, SURFACE - 2), Vector2(size.x, SURFACE - 2),
			Vector2(size.x, SURFACE + 3), Vector2(0, SURFACE + 3)])


## The hazard area (world space): everything below the surface.
func get_rect() -> Rect2:
	return Rect2(global_position + Vector2(0, SURFACE), Vector2(size.x, size.y - SURFACE))


func _process(delta: float) -> void:
	if draw_bubbles:
		_t += delta
		queue_redraw()


func _draw() -> void:
	if not draw_bubbles:
		return
	var n := int(size.x / 24.0)
	for i in n:
		var k := float(i) * 1.618
		var phase := fmod(_t * 0.6 + k, 1.0)
		var x := fmod(k * 37.0, size.x - 8.0) + 4.0
		var y := SURFACE + 4.0 + (size.y - SURFACE - 8.0) * (1.0 - phase)
		draw_circle(Vector2(x, y), 1.5 + 2.0 * phase, Color(1.0, 0.85, 0.35, 0.8 * (1.0 - phase)))
