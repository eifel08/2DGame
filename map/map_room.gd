class_name MapRoom
extends Resource
## One room on a zone map: where it sits (in map cells), how it is revealed
## and its openings. The layout is schematic: a cell is roughly one screen,
## it does not have to match the room's tiles exactly.
##
## Reveal rules (MapState):
##   in_base_map  true: drawn as an outline as soon as the zone's map is
##                acquired. false: left out of the base map (a map does not
##                have to show 100 % of the zone); found by entering it.
##   hidden       a secret room. Never in the base map, whatever in_base_map
##                says, and its secret connectors stay hidden until found.

@export var room_id := "" ## The Room scene's id (Game.ROOM_SCENES).
@export var display_name := ""
@export var rect := Rect2i(0, 0, 1, 1) ## Position and size in map cells.
@export var in_base_map := true
@export var hidden := false
## Spatial anomaly override: the door_id of the side exit to keep when this
## room is linked on both its left and right sides in a way the flat map
## cannot show. Empty: keep the secret exit, else the one that touches its
## neighbour on the map (MapAtlas.resolve_anomalies).
@export var intended_entrance := ""
@export var exits: Array[MapExit] = []


static func from_dict(id: String, data: Dictionary) -> MapRoom:
	var r := MapRoom.new()
	r.room_id = id
	r.display_name = data.get("name", id)
	var cells: Array = data.get("rect", [0, 0, 1, 1])
	r.rect = Rect2i(cells[0], cells[1], cells[2], cells[3])
	r.hidden = bool(data.get("hidden", false))
	r.in_base_map = bool(data.get("base", true)) and not r.hidden
	r.intended_entrance = data.get("intended_entrance", "")
	for exit_data in data.get("exits", []):
		r.exits.append(MapExit.from_dict(exit_data))
	return r


func get_exit(door_id: String) -> MapExit:
	for e in exits:
		if e.door_id == door_id:
			return e
	return null


## True when the base map (a map pickup) outlines this room.
func outlined_by_base_map() -> bool:
	return in_base_map and not hidden


## The map cell of the connector stub of `e`: the cell inside the rect, next
## to the side it opens on.
func exit_cell(e: MapExit) -> Vector2i:
	match e.side:
		"left":
			return Vector2i(rect.position.x, rect.position.y + clampi(e.at, 0, rect.size.y - 1))
		"right":
			return Vector2i(rect.end.x - 1, rect.position.y + clampi(e.at, 0, rect.size.y - 1))
		"top":
			return Vector2i(rect.position.x + clampi(e.at, 0, rect.size.x - 1), rect.position.y)
	return Vector2i(rect.position.x + clampi(e.at, 0, rect.size.x - 1), rect.end.y - 1)
