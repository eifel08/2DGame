class_name Door
extends Node2D
## Room exit. Walking into the trigger moves the player to `target_room`,
## arriving next to the door named `target_door`. The node origin is at the
## floor of the doorway. While `locked` (e.g. an arena is active) it does
## nothing and draws bars. No autoloads here (the generator instantiates it).

@export var door_id := ""
@export var target_room := ""
@export var target_door := ""
@export var inward := -1 ## Direction pointing into this room from the doorway (+1 right, -1 left).
@export var trigger_size := Vector2(24, 96)

var locked := false:
	set(value):
		locked = value
		queue_redraw()


func get_trigger_rect() -> Rect2:
	return Rect2(global_position.x - trigger_size.x / 2.0, global_position.y - trigger_size.y, trigger_size.x, trigger_size.y)


## Where the player stands after arriving through this door.
func get_arrival_position() -> Vector2:
	return global_position + Vector2(inward * 56.0, 0.0)


func _draw() -> void:
	# Faint light spilling from the doorway so exits read as exits.
	var r := Rect2(-trigger_size.x / 2.0, -trigger_size.y, trigger_size.x, trigger_size.y)
	for i in 4:
		draw_rect(r.grow(-i * 3.0), Color(0.75, 0.85, 1.0, 0.05))
	var tip := Vector2(-inward * 6.0, -trigger_size.y * 0.5)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-inward * 6.0, -6), tip + Vector2(-inward * 6.0, 6), tip + Vector2(-inward * 14.0, 0)]),
		Color(0.85, 0.92, 1.0, 0.35))
