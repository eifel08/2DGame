class_name MapState
extends RefCounted
## Fog of war: what the player knows of each zone map. Saved with the slot
## (to_dict / from_dict), like WorldState.
##
## Every room is in one of three states:
##   UNKNOWN   not drawn at all
##   OUTLINED  drawn as a wireframe: the zone's base map shows it, but the
##             player has not been there (or has not marked it yet)
##   FILLED    drawn filled in: explored
##
## Rules:
##   - Acquiring a zone's map (acquire_map) outlines every room of that zone
##     that is in its base map (MapRoom.outlined_by_base_map: no hidden rooms,
##     and not necessarily every room).
##   - Entering a room (enter_room) fills it in. An outlined room is filled; a
##     room that was not on the map at all is added and filled.
##   - Config.map.auto_mark_rooms = false switches to manual marking: entering
##     a room only remembers it as `pending`; nothing changes on the map until
##     mark_pending() (Game calls it at a checkpoint save when
##     Config.map.mark_on_rest) or mark_room() fills it.
## Rooms that are on no zone map (MapAtlas.get_room == null) are ignored.

enum Reveal { UNKNOWN, OUTLINED, FILLED }

var atlas: MapAtlas
var acquired := {} ## zone_id -> true: the zone's base map is owned.
var rooms := {} ## room_id -> Reveal (UNKNOWN rooms are not stored).
var pending := {} ## room_id -> true: entered, waiting to be marked (manual marking).
var current_room := "" ## Where the player is (the map's player marker).


func _init(p_atlas: MapAtlas = null) -> void:
	atlas = p_atlas


func new_game() -> void:
	acquired.clear()
	rooms.clear()
	pending.clear()


# ---------- Queries ----------

func reveal_of(room_id: String) -> Reveal:
	return rooms.get(room_id, Reveal.UNKNOWN)


func is_filled(room_id: String) -> bool:
	return reveal_of(room_id) == Reveal.FILLED


func has_map(zone_id: String) -> bool:
	return acquired.has(zone_id)


## The zone of the room the player is in (null for a room on no map).
func current_zone() -> MapZone:
	return atlas.zone_of(current_room)


## A zone the player can look at: its map is owned or a room of it is known.
func is_zone_known(zone_id: String) -> bool:
	if has_map(zone_id):
		return true
	var zone := atlas.get_zone(zone_id)
	if zone:
		for r in zone.rooms:
			if reveal_of(r.room_id) != Reveal.UNKNOWN:
				return true
	return false


## Every zone the map screen can switch to, in atlas order.
func known_zones() -> Array[String]:
	var ids: Array[String] = []
	for zone_id in atlas.zone_ids():
		if is_zone_known(zone_id):
			ids.append(zone_id)
	return ids


# ---------- Changes ----------

## The zone's base map: outlines its base-map rooms. Returns how many rooms
## were newly outlined (0 when the map was owned already).
func acquire_map(zone_id: String) -> int:
	var zone := atlas.get_zone(zone_id)
	if zone == null or has_map(zone_id):
		return 0
	acquired[zone_id] = true
	var count := 0
	for r in zone.rooms:
		if r.outlined_by_base_map() and reveal_of(r.room_id) == Reveal.UNKNOWN:
			rooms[r.room_id] = Reveal.OUTLINED
			count += 1
			Events.map_room_revealed.emit(r.room_id, Reveal.OUTLINED)
	Events.map_acquired.emit(zone_id)
	return count


## The player walked into `room_id` (Game calls this on every room load).
func enter_room(room_id: String) -> void:
	current_room = room_id
	if atlas.get_room(room_id) == null or is_filled(room_id):
		return
	if Config.map.auto_mark_rooms:
		mark_room(room_id)
	else:
		pending[room_id] = true


## Fills `room_id` in (adding it to the map if it was not there). Returns
## true when the map changed.
func mark_room(room_id: String) -> bool:
	pending.erase(room_id)
	if atlas.get_room(room_id) == null or is_filled(room_id):
		return false
	rooms[room_id] = Reveal.FILLED
	Events.map_room_revealed.emit(room_id, Reveal.FILLED)
	return true


## Manual marking: fills every room entered since the last marking. Returns
## the rooms that changed.
func mark_pending() -> Array[String]:
	var changed: Array[String] = []
	for room_id in pending.keys():
		if mark_room(room_id):
			changed.append(room_id)
	pending.clear()
	return changed


# ---------- Saving ----------

func to_dict() -> Dictionary:
	var filled := []
	var outlined := []
	for room_id in rooms:
		if rooms[room_id] == Reveal.FILLED:
			filled.append(room_id)
		elif rooms[room_id] == Reveal.OUTLINED:
			outlined.append(room_id)
	return {
		"maps": acquired.keys(),
		"filled": filled,
		"outlined": outlined,
		"pending": pending.keys(),
	}


## A save from before the map system has no "map" entry: an empty map.
func from_dict(data: Dictionary) -> void:
	new_game()
	for zone_id in data.get("maps", []):
		acquired[String(zone_id)] = true
	for room_id in data.get("outlined", []):
		rooms[String(room_id)] = Reveal.OUTLINED
	for room_id in data.get("filled", []):
		rooms[String(room_id)] = Reveal.FILLED
	for room_id in data.get("pending", []):
		pending[String(room_id)] = true
