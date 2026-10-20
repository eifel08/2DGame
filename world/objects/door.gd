class_name Door
extends Node2D
## Room exit: an invisible trigger inside an open gap of the room's outer
## wall (side wall, ceiling or floor). Walking, jumping or falling into it
## moves the player to `target_room`, at the door named `target_door`, with
## the same offset along the opening and the same speed. Nothing is drawn:
## the opening itself is the only sign of an exit. While `locked` (an arena
## is active) it does nothing. No autoloads here (the generator instantiates it).
##
## Node origin:
##   side doors (vertical = 0)   - floor of the doorway, at the cell center
##   ceiling door (vertical = -1) - top edge of the room, center of the gap
##   floor door (vertical = 1)    - bottom edge of the room, center of the gap

@export var door_id := ""
@export var target_room := ""
@export var target_door := ""
@export var inward := -1 ## Side doors: direction into this room (+1 right, -1 left).
@export_range(-1, 1) var vertical := 0 ## 0 side, -1 opening in the ceiling, 1 opening in the floor.
@export var trigger_size := Vector2(24, 96)

const SIDE_ARRIVAL := 40.0 ## Just past the trigger, inside the room.
const RISE_SPEED := 900.0 ## Minimum upward speed when arriving through a floor gap.

var locked := false


func get_trigger_rect() -> Rect2:
	match vertical:
		-1:
			return Rect2(global_position.x - trigger_size.x / 2.0, global_position.y, trigger_size.x, trigger_size.y)
		1:
			return Rect2(global_position.x - trigger_size.x / 2.0, global_position.y - trigger_size.y, trigger_size.x, trigger_size.y)
	return Rect2(global_position.x - trigger_size.x / 2.0, global_position.y - trigger_size.y, trigger_size.x, trigger_size.y)


## Default arrival point (feet position) when nothing else is known.
func get_arrival_position() -> Vector2:
	return arrival_for(0.0)


## Arrival point for a player who left the other room `offset` px from the
## middle of that opening (along the opening: x for vertical doors, height
## above the floor for side doors).
func arrival_for(offset: float) -> Vector2:
	match vertical:
		-1: # Dropping in from above: just below the ceiling gap.
			return global_position + Vector2(_clamp_along(offset), trigger_size.y + 42.0)
		1: # Rising in from below: inside the floor gap, under the trigger line.
			return global_position + Vector2(_clamp_along(offset), -trigger_size.y - 2.0)
	return global_position + Vector2(inward * SIDE_ARRIVAL, clampf(offset, -trigger_size.y + 40.0, 0.0))


## The player's offset along this opening (see arrival_for).
func offset_of(player_feet: Vector2) -> float:
	if vertical != 0:
		return player_feet.x - global_position.x
	return player_feet.y - global_position.y


## Speed after arriving here: kept as is, but a player rising out of a floor
## gap always clears it.
func arrival_velocity(velocity: Vector2) -> Vector2:
	if vertical == 1:
		return Vector2(velocity.x, minf(velocity.y, -RISE_SPEED))
	return velocity


func _clamp_along(offset: float) -> float:
	var half := trigger_size.x / 2.0 - 14.0
	return clampf(offset, -half, half)
