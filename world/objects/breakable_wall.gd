class_name BreakableWall
extends Node2D
## Hidden passage: a section of wall that looks like the surrounding stone
## (with faint cracks) and breaks after a few hits. Once broken it stays open
## for the save (WorldState.secrets). The node origin is at the floor, the
## wall extends `size` upward. No autoloads here (the generator instantiates it).
## Art: the Visual node is a placeholder. The AnimationPlayer plays "idle",
## then "hit_1", "hit_2", ... per hit (missing clips are skipped). Breaking
## removes the wall at once; the crumble is the "wall_break" effect.

@export var secret_id := ""
@export var size := Vector2(32, 96)
@export var hits_required := 3

var hits := 0
var intact := true
var _body: StaticBody2D


func _ready() -> void:
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = Vector2(0, -size.y / 2.0)
	_body.add_child(shape)
	add_child(_body)


func get_rect() -> Rect2:
	return Rect2(global_position.x - size.x / 2.0, global_position.y - size.y, size.x, size.y)


## Returns true when this hit breaks the wall.
func hit() -> bool:
	if not intact:
		return false
	hits += 1
	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation("hit_%d" % hits):
		anim.play("hit_%d" % hits)
	if hits >= hits_required:
		open()
		return true
	return false


## Removes the wall (also used when loading a save where it is already broken).
func open() -> void:
	intact = false
	if _body:
		_body.queue_free()
		_body = null
	visible = false
