class_name Relic
extends Node2D
## A permanent upgrade pickup (e.g. hidden in a secret room). Touching it
## raises max health or max energy for the rest of the save. Collected relics
## never reappear (WorldState.relics). No autoloads here.

@export var relic_id := ""
@export_enum("max_health", "max_energy") var stat := "max_health"
@export var amount := 25.0

var collected := false
var _t := 0.0


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(14, 40), Vector2(28, 40))


func collect() -> void:
	collected = true
	visible = false


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(0, -22 + sin(_t * 2.0) * 3.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_circle(c, 16.0 + pulse * 3.0, Color(1.0, 0.4, 0.5, 0.18))
	var r := 9.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.4), c + Vector2(r, -r * 0.2), c + Vector2(0, r * 1.2), c + Vector2(-r, -r * 0.2)]), Color("#ff5e7a"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.4), c + Vector2(r * 0.4, -r * 0.4), c + Vector2(0, -r * 0.1), c + Vector2(-r * 0.4, -r * 0.4)]), Color(1, 1, 1, 0.7))
