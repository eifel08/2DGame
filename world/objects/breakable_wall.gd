class_name BreakableWall
extends Node2D
## Hidden passage: a section of wall that looks like the surrounding stone
## (with faint cracks) and breaks after a few hits. Once broken it stays open
## for the save (WorldState.secrets). The node origin is at the floor, the
## wall extends `size` upward. No autoloads here (the generator instantiates it).

@export var secret_id := ""
@export var size := Vector2(32, 96)
@export var hits_required := 3

var hits := 0
var intact := true
var _flash := 0.0
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
	_flash = 0.1
	queue_redraw()
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


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()


func _draw() -> void:
	if not intact:
		return
	var r := Rect2(-size.x / 2.0, -size.y, size.x, size.y)
	var ts := 32.0
	var y := r.position.y
	while y < r.end.y: # Same look as solid tiles, so it blends into the wall.
		draw_rect(Rect2(r.position.x, y, r.size.x, ts), Color("#2a3150"))
		draw_rect(Rect2(r.position.x + 2, y + 2, r.size.x - 4, ts - 4), Color("#323a5e"))
		y += ts
	# Hairline cracks: barely visible at first, clearer with every hit.
	var a := 0.12 + 0.3 * hits
	var crack := Color(0.06, 0.07, 0.12, a)
	draw_polyline(PackedVector2Array([Vector2(-6, r.position.y + 10), Vector2(2, r.position.y + 34), Vector2(-4, r.position.y + 58), Vector2(5, r.end.y - 12)]), crack, 1.5)
	if hits > 0:
		draw_polyline(PackedVector2Array([Vector2(2, r.position.y + 34), Vector2(12, r.position.y + 44)]), crack, 1.5)
	if _flash > 0.0:
		draw_rect(r, Color(1, 1, 1, 0.35))
