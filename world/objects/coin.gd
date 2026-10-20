class_name Coin
extends Node2D
## Currency pickup ("shards"). Placed coins come back when the room resets.
## Dropped coins (from enemies) burst out, settle on the floor and are freed
## once collected. The node origin is at the feet (bottom-center).

const GRAVITY := 1400.0
const COLOR := Color("#ffd36b")

@export var value := 5

var dropped := false
var collected := false
var velocity := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	_t = randf() * TAU


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(8, 20), Vector2(16, 18))


func step(delta: float, room: Node) -> void:
	_t += delta
	if collected:
		return
	if dropped and velocity != Vector2.ZERO:
		velocity.y += GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0.0, 120.0 * delta)
		var next := global_position + velocity * delta
		if room.is_solid_at(Vector2(next.x, global_position.y - 4.0)):
			next.x = global_position.x
			velocity.x = -velocity.x * 0.4
		if velocity.y > 0.0 and room.is_ground_at(next):
			var ts: float = room.tiles.tile_set.tile_size.y
			next.y = floorf(next.y / ts) * ts
			velocity = Vector2.ZERO
		global_position = next
	queue_redraw()


func collect() -> void:
	collected = true
	visible = false


func restore() -> void:
	collected = false
	visible = true


func _draw() -> void:
	var c := Vector2(0, -11 + sin(_t * 3.0) * 2.0)
	var r := 6.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.3), c + Vector2(r, 0), c + Vector2(0, r * 1.3), c + Vector2(-r, 0)]), COLOR)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.3), c + Vector2(r * 0.4, -r * 0.2), c + Vector2(0, 0), c + Vector2(-r * 0.4, -r * 0.2)]), Color(1, 1, 1, 0.7))
