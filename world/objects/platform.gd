class_name Platform
extends AnimatableBody2D
## A one-way platform object (layer 3 "one_way", like '=' tiles): the player
## lands on it from above and jumps up through it. Three kinds, one scene each:
##   standard   platform.tscn            stays put
##   moving     platform_moving.tscn     back and forth along `travel` (Mover);
##                                      a player standing on it rides along
##   breakable  platform_breakable.tscn  standing on it starts a short timer
##                                      (`crumble_delay`), then it crumbles
##                                      and drops the player; it comes back
##                                      after `respawn_time` (not while the
##                                      player overlaps its spot)
## Game._update_movers steps every platform before the player moves and
## carries the player standing on it. The grappling hook latches on it (one-
## way layer) and follows it (GrappleHook.follow_anchor); a hook on a
## crumbled platform lets go.
## The node origin is the top-center. Art: replace Visual; Visual/Body and
## Visual/Top (Polygon2D) are sized to `size` by this script. The kind's
## markings (chevrons, cracks, path) are drawn here (draw_markings).

const LAYER := 3

@export_enum("standard", "moving", "breakable") var kind := "standard"
@export var size := Vector2(96, 12)
@export var travel := Vector2.ZERO ## Moving: offset of the far end.
@export var period := 4.0 ## Moving: seconds for there and back.
@export var phase := 0.0 ## Moving: start offset, 0..1 of a period.
@export var crumble_delay := 1.0 ## Breakable: seconds from first contact to crumbling.
@export var respawn_time := 3.0 ## Breakable: seconds until it is back.
@export var draw_markings := true

var solid := true ## False while crumbled.
var crumbling := false
var crumble_left := 0.0
var respawn_left := 0.0
var last_delta := Vector2.ZERO ## Movement in the last step (carries riders).
var mover: Mover
var _shape: CollisionShape2D
var _home := Vector2.ZERO


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1 << (LAYER - 1)
	collision_mask = 0
	_home = position
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	_shape.position = Vector2(0, size.y / 2.0)
	_shape.one_way_collision = true
	add_child(_shape)
	if kind == "moving":
		mover = Mover.new(position, travel, period, phase)
		position = mover.position_at(mover.t)
	var h := size / 2.0
	var body := get_node_or_null("Visual/Body") as Polygon2D
	if body:
		body.polygon = PackedVector2Array([Vector2(-h.x, 0), Vector2(h.x, 0), Vector2(h.x, size.y), Vector2(-h.x, size.y)])
	var top := get_node_or_null("Visual/Top") as Polygon2D
	if top:
		top.polygon = PackedVector2Array([Vector2(-h.x, 0), Vector2(h.x, 0), Vector2(h.x, 3), Vector2(-h.x, 3)])


func top_y() -> float:
	return global_position.y


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(size.x / 2.0, 0), size)


## True when the player stands on top of it.
func supports(p: Player) -> bool:
	if not solid or not p.grounded:
		return false
	var feet := p.global_position
	return absf(feet.y - top_y()) <= 3.0 and absf(feet.x - global_position.x) <= size.x / 2.0 + Player.WIDTH / 2.0


## One game step: motion, the crumble timer and the respawn.
func step(delta: float, p: Player) -> void:
	var before := position
	if mover:
		position = mover.step(delta)
	last_delta = position - before
	if kind == "moving":
		queue_redraw() # The path marking stays put while the platform moves.
	if kind != "breakable":
		return
	if crumbling:
		crumble_left -= delta
		if crumble_left <= 0.0:
			_crumble()
	elif not solid:
		respawn_left -= delta
		if respawn_left <= 0.0 and not get_rect().grow(4.0).intersects(p.get_rect()):
			_restore()
	if solid and not crumbling and supports(p):
		crumbling = true
		crumble_left = crumble_delay
	if visible:
		var visual := get_node_or_null("Visual") as Node2D
		if visual: # Shake while it is about to go.
			visual.position = Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0)) if crumbling else Vector2.ZERO
		queue_redraw()


func _crumble() -> void:
	crumbling = false
	solid = false
	respawn_left = respawn_time
	_shape.set_deferred("disabled", true)
	visible = false
	Events.platform_crumbled.emit(get_rect().get_center())


func _restore() -> void:
	solid = true
	_shape.set_deferred("disabled", false)
	visible = true
	position = _home


func _draw() -> void:
	if not draw_markings:
		return
	var h := size.x / 2.0
	match kind:
		"moving":
			var a := mover.start - position if mover else Vector2.ZERO
			var b := mover.start + travel - position if mover else travel
			draw_dashed_line(a + Vector2(0, size.y / 2.0), b + Vector2(0, size.y / 2.0), Color(0.55, 1.0, 0.95, 0.35), 2.0, 6.0)
			for i in int(size.x / 24.0):
				var x := -h + 12.0 + i * 24.0
				var d := signf(travel.x) if travel.x != 0.0 else 1.0
				draw_polyline(PackedVector2Array([Vector2(x - 3 * d, 4), Vector2(x + 2 * d, 7), Vector2(x - 3 * d, 10)]), Color(0.85, 1.0, 1.0, 0.9), 1.5)
		"breakable":
			var c := Color(0.2, 0.1, 0.04, 0.95 if crumbling else 0.75)
			for i in int(size.x / 32.0):
				var x := -h + 10.0 + i * 32.0
				draw_polyline(PackedVector2Array([Vector2(x, 1), Vector2(x + 5, 6), Vector2(x + 2, 11)]), c, 1.5)
				draw_line(Vector2(x + 5, 6), Vector2(x + 12, 4), c, 1.0)
