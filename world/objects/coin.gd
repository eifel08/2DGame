class_name Coin
extends Node2D
## Currency pickup ("shards"). Placed coins come back when the room resets.
## Dropped coins (from enemies) burst out, settle on the floor and are freed
## once collected. The node origin is at the feet (bottom-center).
## A dropped coin collides with its whole box: it bounces off walls and
## ceilings, lands only from above, and is pushed back into open air if it
## ever ends up inside rock. It never gets embedded in the level.

const GRAVITY := 1400.0
const SIZE := Vector2(16, 18) ## The pickup box (see get_rect), feet at the bottom center.
const COLOR := Color("#ffd36b")

@export var value := 5

var dropped := false
var collected := false
var velocity := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	_t = randf() * TAU


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(8, 20), SIZE)


func _box_at(feet: Vector2) -> Rect2:
	return Rect2(feet - Vector2(SIZE.x / 2.0, SIZE.y + 2.0), SIZE)


func step(delta: float, room: Node) -> void:
	_t += delta
	if collected:
		return
	if dropped and velocity != Vector2.ZERO:
		velocity.y += GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0.0, 120.0 * delta)
		var next := global_position + velocity * delta
		# Walls: the whole box, not one point. Bounce back softly.
		if room.rect_blocked(_box_at(Vector2(next.x, global_position.y))):
			next.x = global_position.x
			velocity.x = -velocity.x * 0.4
		# Ceilings: stop rising and fall back down.
		if velocity.y < 0.0 and room.rect_blocked(_box_at(next)):
			next.y = global_position.y
			velocity.y = -velocity.y * 0.25
		# Floors: land only from above, on the tile top it reached.
		if velocity.y > 0.0 and room.is_ground_at(next):
			var ts: float = room.tiles.tile_set.tile_size.y
			var top := floorf(next.y / ts) * ts
			if top >= global_position.y - 1.0:
				next.y = top
				velocity = Vector2.ZERO
		global_position = next
		# Safety net: never rest inside rock.
		if room.rect_blocked(get_rect()):
			global_position = room.free_spot(global_position, SIZE + Vector2(0, 2))
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
