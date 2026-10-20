class_name EnergyGauge
extends Control
## Shows how much energy an ability needs: a small bar filled up to its
## threshold, in its tier color. Deliberately has no numbers.

var fill := 0.0
var color := Color.WHITE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(40, 6)


func set_requirement(cost: float, max_energy: float) -> void:
	fill = clampf(cost / maxf(1.0, max_energy), 0.0, 1.0)
	color = Config.energy_tier_color(cost)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.65))
	draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), color)
	for i in range(1, 4): # Quarter notches help reading the level.
		var x := r.size.x * i / 4.0
		draw_line(Vector2(x, 0), Vector2(x, r.size.y), Color(0, 0, 0, 0.5), 1.0)
	draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
