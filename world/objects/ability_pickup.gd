class_name AbilityPickup
extends Node2D
## A movement ability lying in the world: Double Jump, Dash, Wall Climb (wall
## slide + wall jumps) or the Grappling Hook. Touching it learns the ability
## for good (PlayerData.movement); the first time, a tutorial popup explains it.
## A pickup is gone once its ability is known, so nothing extra is saved.
## No autoloads here (see Interactable).
## Art: the placeholder (a glowing orb with the ability's symbol) is drawn
## only while the Visual node is empty; put your own art into Visual.

@export_enum("double_jump", "dash", "wall_climb", "grapple") var ability := "double_jump"

var collected := false
var _t := 0.0

@onready var visual: Node2D = get_node_or_null("Visual")


func _process(delta: float) -> void:
	_t += delta
	if visual:
		visual.position.y = -24.0 + sin(_t * 3.0) * 3.0
	queue_redraw()


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(16, 44), Vector2(32, 44))


func collect() -> void:
	collected = true
	visible = false


func restore() -> void:
	collected = false
	visible = true


func _draw() -> void:
	if visual and visual.get_child_count() > 0:
		return
	var col: Color = AbilityArt.COLORS.get(ability, Color.WHITE)
	var center := Vector2(0, -24.0 + sin(_t * 3.0) * 3.0)
	var pulse := 1.0 + sin(_t * 4.0) * 0.08
	draw_circle(center, 19.0 * pulse, Color(col, 0.16))
	draw_circle(center, 13.0, Color("#1b2238"))
	draw_arc(center, 13.0, 0.0, TAU, 24, col, 2.0, true)
	AbilityArt.movement_symbol(self, ability, center, 9.0, col)
