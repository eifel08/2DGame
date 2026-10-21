class_name HiddenPocketWall
extends SecretWall
## TYPE 1 secret wall: hides a pocket / alcove INSIDE the current room
## (GUIDELINES.md, "Secret walls"). Walk straight through it - no attack.
##
## Until found:
##   - ONE-WAY: passable from the entry side (`pass_dir`), solid from the
##     pocket side, like any wall;
##   - the whole pocket (`pocket_rect`: its items, shards, enemies, doors) is
##     covered by the `Cover` node, so nothing inside can be seen;
##   - a pocket outside the room's normal area stays outside the camera
##     limits (Game._refresh_camera_bounds).
## Walking all the way through FINDS it, once and for good: the wall and the
## cover are gone (passable both ways), the camera may show the pocket, and
## the find is saved (WorldState.secrets, key `secret_id`). It never hides
## again after a room change, a death or loading the save. Finding it is
## silent (Rule D).
##
## Enemies never pass it: they collide on their own physics layer.
## Projectiles and room queries ignore it (it is not a tile).
##
## Art and animation (replace freely, keep the node names):
##   Visual          the disguised wall. Placeholder: wall tiles at 50% opacity.
##   Cover           hides the pocket. Placeholder: solid wall tiles.
##   AnimationPlayer optional; a "reveal" clip plays when it is found
##                   (it should hide Visual and Cover). Without it both just hide.

const PLAYER_LAYER := 5 ## Physics layer "hidden_wall_player" (in the player's mask).
const ENEMY_LAYER := 6 ## Physics layer "hidden_wall_enemy" (in every enemy's mask).
const PLACEHOLDER_ALPHA := 0.5

@export var secret_id := ""
@export_range(-1, 1, 2) var pass_dir := 1 ## Entry side: 1 = from the left (walking right), -1 = from the right.
@export var pocket_rect := Rect2() ## The hidden pocket in global coordinates (set by the generator).

var discovered := false
var player_blocked := false ## The player-side body is solid right now (tests, debug).
var _inside := false ## The player overlapped the wall last step.
var _player_body: StaticBody2D


func _ready() -> void:
	_player_body = _make_body(0)
	_make_body(1 << (ENEMY_LAYER - 1))
	# The face toward the entry side is lit, like a wall bordering the room.
	fill_with_wall_tiles(get_node_or_null("Visual"), get_rect(), EDGE_LEFT if pass_dir > 0 else EDGE_RIGHT)
	fill_with_wall_tiles(get_node_or_null("Cover"), pocket_rect, 0)
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual:
		visual.modulate.a = PLACEHOLDER_ALPHA
	_apply_revealed(false)


func _make_body(layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = Vector2(0, -size.y / 2.0)
	body.add_child(shape)
	add_child(body)
	return body


## The area the camera may show once found: the pocket and the opening.
func camera_rect() -> Rect2:
	return pocket_rect.merge(get_rect()) if pocket_rect.has_area() else get_rect()


## Called every step BEFORE the player moves. Makes the wall solid or
## passable for the player and returns true on the step it is found.
func update_for(player_rect: Rect2) -> bool:
	var overlapping := get_rect().intersects(player_rect)
	var on_entry_side := (player_rect.get_center().x - global_position.x) * pass_dir < 0.0
	var found_now := false
	if not discovered and _inside and not overlapping and not on_entry_side:
		reveal(true) # Walked all the way through from the entry side.
		found_now = true
	_inside = overlapping
	# Never solidify around a player standing inside it.
	_set_player_blocked(not discovered and not overlapping and not on_entry_side)
	return found_now


## Found: permanently un-hidden. `animate` plays the "reveal" clip if there
## is one (a save load reveals instantly).
func reveal(animate := false) -> void:
	discovered = true
	_set_player_blocked(false)
	_apply_revealed(animate)


func is_covered() -> bool:
	var cover := get_node_or_null("Cover") as CanvasItem
	return cover != null and cover.visible


func _set_player_blocked(on: bool) -> void:
	player_blocked = on
	if _player_body:
		_player_body.collision_layer = (1 << (PLAYER_LAYER - 1)) if on else 0


func _apply_revealed(animate: bool) -> void:
	if not discovered:
		return
	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animate and anim and anim.has_animation("reveal"):
		anim.play("reveal")
		return
	for node_name in ["Visual", "Cover"]:
		var item := get_node_or_null(node_name) as CanvasItem
		if item:
			item.visible = false
