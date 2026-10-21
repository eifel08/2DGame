class_name HiddenWall
extends Node2D
## Illusion wall: a section of "stone" the player can walk straight through,
## no attack needed. Until found it is ONE-WAY:
##   - from the entry side (`pass_dir`) it lets the player in,
##   - from the other side it is solid, like any wall.
## Once the player has passed all the way through, it is found: with
## `opens_both_ways` it then stays passable from both sides. Finding it is
## saved (WorldState.secrets, key `secret_id`), so it never turns back into
## a mystery after a room change, a death or loading the save.
##
## Enemies never pass: they collide with it on their own physics layer.
## Projectiles and room queries ignore it (it is an illusion, not a tile).
## Rule D: finding it is silent - no sound, effect or text.
##
## Art: the Visual node is a placeholder drawn at 50% opacity so it is easy to
## spot while testing. Replace it with vines, darkness or a fake wall; the
## script only resizes a ColorRect named "Fill" if one exists.
## The node origin is at the floor; the wall extends `size` upward.
## No autoloads here (the generator instantiates it).

const PLAYER_LAYER := 5 ## Physics layer "hidden_wall_player" (in the player's mask).
const ENEMY_LAYER := 6 ## Physics layer "hidden_wall_enemy" (in every enemy's mask).
const PLACEHOLDER_ALPHA := 0.5

@export var secret_id := ""
@export var size := Vector2(32, 96)
@export_range(-1, 1, 2) var pass_dir := 1 ## Entry side: 1 = from the left (walking right), -1 = from the right.
@export var opens_both_ways := true ## Once found, passable from both sides.

var discovered := false
var player_blocked := false ## The player-side body is solid right now (tests, debug).
var _inside := false ## The player overlapped the wall last step.
var _player_body: StaticBody2D


func _ready() -> void:
	_player_body = _make_body(0)
	_make_body(1 << (ENEMY_LAYER - 1))
	var fill := get_node_or_null("Visual/Fill") as ColorRect
	if fill:
		fill.position = Vector2(-size.x / 2.0, -size.y)
		fill.size = size
	_apply_visual()


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


func get_rect() -> Rect2:
	return Rect2(global_position.x - size.x / 2.0, global_position.y - size.y, size.x, size.y)


## Called every step BEFORE the player moves. Makes the wall solid or
## passable for the player and returns true on the step it is found.
func update_for(player_rect: Rect2) -> bool:
	var overlapping := get_rect().intersects(player_rect)
	var on_entry_side := (player_rect.get_center().x - global_position.x) * pass_dir < 0.0
	var found_now := false
	if not discovered and _inside and not overlapping and not on_entry_side:
		reveal() # Walked all the way through from the entry side.
		found_now = true
	_inside = overlapping
	# Never solidify around a player standing inside it.
	_set_player_blocked(not overlapping and not on_entry_side and not (discovered and opens_both_ways))
	return found_now


## Marks the wall as found (also used when loading a save where it is).
func reveal() -> void:
	discovered = true
	_apply_visual()


func _set_player_blocked(on: bool) -> void:
	player_blocked = on
	_player_body.collision_layer = (1 << (PLAYER_LAYER - 1)) if on else 0


func _apply_visual() -> void:
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual:
		# Placeholder: always half transparent; found walls get a faint green tint.
		visual.modulate = Color(0.8, 1.0, 0.85, PLACEHOLDER_ALPHA) if discovered else Color(1, 1, 1, PLACEHOLDER_ALPHA)
