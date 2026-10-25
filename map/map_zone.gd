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
##
## World placement: room rects are in the zone's own cells; `world_origin`
## places cell (0, 0) on the world grid, so the zones fit together (the
## inventory's world view, panning between zones). Cross-zone exits must meet
## in world cells (checked by the smoke test).

@export var zone_id := ""
@export var display_name := ""
@export var world_origin := Vector2i.ZERO
## The zone's own colour on the map (MapView derives fill, edge and outline
## from it). Every zone has a different one.
@export var color := Color("#5b7bd5")
@export var rooms: Array[MapRoom] = []


static func from_dict(id: String, data: Dictionary) -> MapZone:
	var z := MapZone.new()
	z.zone_id = id
	z.display_name = data.get("name", id)
	var origin: Array = data.get("origin", [0, 0])
	z.world_origin = Vector2i(origin[0], origin[1])
	z.color = Color(data.get("color", "#5b7bd5"))
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


## A room's rect on the world grid.
func world_rect(r: MapRoom) -> Rect2i:
	return Rect2i(r.rect.position + world_origin, r.rect.size)


## The bounding box of every room on the world grid.
func get_world_bounds() -> Rect2i:
	var bounds := get_cell_bounds()
	return Rect2i(bounds.position + world_origin, bounds.size)


## The bounding box of every room, in the zone's own map cells.
func get_cell_bounds() -> Rect2i:
	var bounds := Rect2i()
	for r in rooms:
		bounds = r.rect if not bounds.has_area() else bounds.merge(r.rect)
	return bounds
