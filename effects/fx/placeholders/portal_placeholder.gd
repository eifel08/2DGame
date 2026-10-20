class_name PortalPlaceholder
extends Node2D
## Placeholder art for the arena spawn portal: a pulsing ring and a floor
## rune that fade in and out. No countdown or timer is shown.

@export var radius := 34.0
@export var color := Color("#ff4dd2")
@export var life := 0.35

var time := 0.0


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	var k := clampf(time / life, 0.0, 1.0)
	var a := sin(k * PI) # Fades in, then out.
	var c := Vector2(0, -radius * 0.65)
	draw_arc(c, radius * (1.2 - 0.4 * k), 0.0, TAU, 32, Color(color, 0.8 * a), 3.0, true)
	draw_line(Vector2(-radius * 0.8, 0), Vector2(radius * 0.8, 0), Color(color, a), 3.0)
