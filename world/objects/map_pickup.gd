class_name MapPickup
extends Collectible
## A zone's map, lying in the world. Taking it (E) gives the zone's base map
## (MapState.acquire_map): every room of the zone's base map appears as an
## outline. No autoloads here.
## Game places one where MapZone.map_pickup says, until the map is owned
## (MapState.acquired is the record; nothing else is saved). Feedback is a
## soft pickup sound and a small puff, nothing more (Rule F).
## Art: the Visual node and the AnimationPlayer "idle" clip are placeholders.

@export var zone_id := ""


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(14, 32), Vector2(28, 32))
