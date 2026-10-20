class_name RingPlaceholder
extends Node2D
## Placeholder art: an expanding, fading ring. Replace with a sprite or a
## particle system in the effect scene that uses it.

@export var radius := 60.0
@export var color := Color.WHITE
@export var width := 4.0
@export var life := 0.35
@export var delay := 0.0

var time := 0.0


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	var k := (time - delay) / life
	if k < 0.0 or k >= 1.0:
		return
	draw_arc(Vector2.ZERO, radius * (0.2 + 0.8 * k), 0.0, TAU, 48, Color(color, color.a * (1.0 - k)), width * (1.0 - k) + 1.0, true)
