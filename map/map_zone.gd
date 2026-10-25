class_name MapZone
extends Resource
## One area map (a region of the world). Each zone has its own map grid, its
## own base map (acquired once, e.g. from a MapPickup) and its own rooms. A
## room belongs to exactly one zone; exits may lead into another zone, which
## is how the map switches zones as the player travels.
##
## A zone can be authored as a .tres resource in the editor, or as plain data
## (MapZone.from_dict, used by MapAtlas.create_default). The zone's map lies
## in the world as a MapPickup (layout letter 'M' in tools/build_assets.gd).

@export var zone_id := ""
@export var display_name := ""
@export var rooms: Array[MapRoom] = []


static func from_dict(id: String, data: Dictionary) -> MapZone:
	var z := MapZone.new()
	z.zone_id = id
	z.display_name = data.get("name", id)
	var room_defs: Dictionary = data.get("rooms", {})
	for room_id in room_defs:
		z.rooms.append(MapRoom.from_dict(room_id, room_defs[room_id]))
	return z


func get_room(room_id: String) -> MapRoom:
	for r in rooms:
		if r.room_id == room_id:
			return r
	return null


func has_room(room_id: String) -> bool:
	return get_room(room_id) != null


func room_ids() -> Array[String]:
	var ids: Array[String] = []
	for r in rooms:
		ids.append(r.room_id)
	return ids


## The bounding box of every room, in map cells (for centering the view).
func get_cell_bounds() -> Rect2i:
	var bounds := Rect2i()
	for r in rooms:
		bounds = r.rect if not bounds.has_area() else bounds.merge(r.rect)
	return bounds
