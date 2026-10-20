class_name Interactable
extends Node2D
## Base for anything the player can interact with (E / gamepad B).
## Subclasses override interact(game). Visuals are plain child nodes, so art
## can be swapped freely. The node origin is at the feet (bottom-center).
## Note: object scripts must not use autoloads (Config/Events), because the
## asset generator instantiates these scenes outside the running game.

@export var prompt := "Read"
@export var interact_size := Vector2(56, 56)

var highlighted := false:
	set(value):
		if highlighted != value:
			highlighted = value
			queue_redraw()


func get_interact_rect() -> Rect2:
	return Rect2(global_position.x - interact_size.x / 2.0, global_position.y - interact_size.y,
		interact_size.x, interact_size.y)


func can_interact() -> bool:
	return true


func interact(_game: Node) -> void:
	pass


## Small "E  Read" prompt above the object while the player is in range.
func _draw() -> void:
	if not highlighted:
		return
	var font := ThemeDB.fallback_font
	var text := "E  " + prompt
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
	var box := Rect2(-width / 2.0, -interact_size.y - 22.0, width, 17.0)
	draw_rect(box, Color(0.04, 0.05, 0.1, 0.85))
	draw_rect(box, Color(1, 1, 1, 0.35), false, 1.0)
	draw_string(font, box.position + Vector2(0, 13), text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, Color.WHITE)
