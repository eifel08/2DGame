class_name ChamberSign
extends Node2D
## A small plaque naming a Bestiary chamber's enemy (developer / tester aid).
## Pure decoration: no collision, no interaction. No autoloads here.

@export var title := ""


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	draw_rect(Rect2(-2, -30, 4, 30), Color("#5a6178")) # Post.
	var plate := Rect2(-w / 2.0, -48, w, 18)
	draw_rect(plate, Color("#2a3048"))
	draw_rect(plate, Color("#8b95b4"), false, 1.5)
	draw_string(font, plate.position + Vector2(0, 13), title, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color("#e3e8f5"))
