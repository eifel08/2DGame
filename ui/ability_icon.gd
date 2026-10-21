class_name AbilityIcon
extends Control
## Ability symbol drawn from basic shapes. Replace with textures later by
## swapping this control; the inventory and HUD only call set_icon().

var shape := ""
var color := Color.WHITE
var dim := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(p_shape: String, p_color: Color, p_dim := false) -> void:
	shape = p_shape
	color = p_color
	dim = p_dim
	queue_redraw()


func _draw() -> void:
	draw_symbol(self, shape, size / 2.0, minf(size.x, size.y) * 0.42, Color(color, 0.4 if dim else 1.0))


## Shared by inventory cards and the HUD slot strip.
static func draw_symbol(c: CanvasItem, symbol: String, center: Vector2, r: float, col: Color) -> void:
	match symbol:
		"nova": # Shockwave: rings around a core.
			c.draw_arc(center, r, 0.0, TAU, 32, col, maxf(1.5, r * 0.12), true)
			c.draw_arc(center, r * 0.58, 0.0, TAU, 24, col, maxf(1.0, r * 0.1), true)
			c.draw_circle(center, r * 0.2, col)
		"volley": # Fan of bolts.
			for i in 3:
				var a := -PI / 2.0 + (i - 1) * 0.62
				var tip := center + Vector2(0, r * 0.75) + Vector2.from_angle(a) * r * 1.3
				c.draw_line(center + Vector2(0, r * 0.75), tip, Color(col, 0.55), maxf(1.0, r * 0.08), true)
				c.draw_circle(tip, r * 0.22, col)
		"ascend": # Rising chevrons.
			for i in 2:
				var y := center.y + r * 0.45 - i * r * 0.6
				c.draw_polyline(PackedVector2Array([Vector2(center.x - r * 0.7, y + r * 0.35), Vector2(center.x, y - r * 0.35), Vector2(center.x + r * 0.7, y + r * 0.35)]),
					col, maxf(1.5, r * 0.16), true)
			c.draw_circle(Vector2(center.x, center.y - r * 0.85), r * 0.14, col)
		"comet": # Head with a trail.
			var head := center + Vector2(r * 0.4, -r * 0.4)
			for i in 3:
				var off := Vector2(-r, r).normalized().orthogonal() * (i - 1) * r * 0.28
				c.draw_line(head + off, head + off + Vector2(-r, r) * 1.1, Color(col, 0.5), maxf(1.0, r * 0.1), true)
			c.draw_circle(head, r * 0.34, col)
		"aegis": # Hexagonal shield with a core.
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(center + Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * r * 0.9)
			c.draw_polyline(pts, col, maxf(1.5, r * 0.14), true)
			c.draw_circle(center, r * 0.25, col)
		"stasis": # Snowflake: three crossed bars with tips.
			for i in 3:
				var d := Vector2.from_angle(PI / 2.0 + i * PI / 3.0) * r * 0.9
				c.draw_line(center - d, center + d, col, maxf(1.5, r * 0.12), true)
				c.draw_circle(center + d, r * 0.12, col)
				c.draw_circle(center - d, r * 0.12, col)
		"beam": # Emitter with a long beam.
			c.draw_rect(Rect2(center.x - r * 0.9, center.y - r * 0.14, r * 1.8, r * 0.28), col)
			c.draw_rect(Rect2(center.x - r * 0.9, center.y - r * 0.3, r * 1.8, r * 0.6), Color(col, 0.35))
			c.draw_circle(Vector2(center.x - r * 0.75, center.y), r * 0.3, col)
		"slam": # Downward arrow onto a ground line.
			c.draw_line(center + Vector2(0, -r * 0.9), center + Vector2(0, r * 0.35), col, maxf(1.5, r * 0.16), true)
			c.draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.45, r * 0.15), center + Vector2(r * 0.45, r * 0.15), center + Vector2(0, r * 0.6)]), col)
			c.draw_line(center + Vector2(-r * 0.95, r * 0.8), center + Vector2(r * 0.95, r * 0.8), col, maxf(1.5, r * 0.12), true)
		"empty": # Empty slot.
			c.draw_arc(center, r * 0.7, 0.0, TAU, 24, Color(col, 0.45), 1.5, true)
			c.draw_line(center + Vector2(-r * 0.45, r * 0.45), center + Vector2(r * 0.45, -r * 0.45), Color(col, 0.45), 1.5, true)
		_:
			c.draw_rect(Rect2(center - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), col, false, 2.0)
