class_name StatBar
extends Control
## Number-free status bar. The frame length shows the maximum (it grows when
## the maximum is upgraded); the fill shows the current value.

var value := 0.0
var max_value := 100.0
var base_max := 100.0 ## Maximum at the start; half the full width.
var color := Color.WHITE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 16)


func set_values(p_value: float, p_max: float, p_base: float, p_color: Color) -> void:
	value = p_value
	max_value = p_max
	base_max = p_base
	color = p_color
	queue_redraw()


func _draw() -> void:
	var frame_w := size.x * clampf(max_value / (base_max * 2.0), 0.05, 1.0)
	var frame := Rect2(0, 0, frame_w, size.y)
	draw_rect(Rect2(0, 0, size.x, size.y), Color(1, 1, 1, 0.05))
	draw_rect(frame, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(0, 0, frame_w * clampf(value / maxf(1.0, max_value), 0.0, 1.0), size.y), color)
	draw_rect(frame, Color(1, 1, 1, 0.35), false, 1.0)
