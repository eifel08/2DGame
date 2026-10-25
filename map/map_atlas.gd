class_name MapAtlas
extends RefCounted
## Every zone map of the world, and the room -> zone lookup. Game owns one
## (Game.atlas); MapState and the map views read it.
##
## Adding a zone: add an entry to WORLD below (or build a MapZone resource
## and call add_zone). Each room of the zone gets a rect in map cells and one
## exit per Door of its scene. The smoke test checks that the exits match the
## doors.
##
## Spatial anomaly (resolve_anomalies). A room can be linked on BOTH its left
## and right sides in a way a flat map cannot show: e.g. the Hidden Vault
## lies west of the Upper Galleries (secret doorway on its east side), yet its
## west door leads to the Ember Crossing, which lies EAST of the Galleries.
## For such a room, every side exit whose neighbour does not touch it on the
## map is a conflict. The secret exit (or the room's intended_entrance) is
## kept; every other conflicting exit is suppressed on both ends: the map
## draws no connector for it, and with Config.map.seal_anomaly_entrances the
## game seals that doorway with wall tiles in both rooms (Game._seal_door),
## so it can't be used either. Only the intended (or secret) way in remains.

## The default world: two zones.
const WORLD := {
	"halls": {
		"name": "Testing Halls",
		"map_pickup": {"room": "test_room", "position": Vector2(1456, 704)}, # Floor, right of the middle block.
		"rooms": {
			"test_room": {"name": "Testing Halls", "rect": [0, 0, 5, 2], "exits": [
				{"door": "east", "side": "right", "at": 1, "to": "boss_room", "to_door": "west"},
				{"door": "ceiling", "side": "top", "at": 2, "to": "upper_room", "to_door": "floor"},
				{"door": "floor", "side": "bottom", "at": 2, "to": "bestiary", "to_door": "ceiling"},
			]},
			"boss_room": {"name": "Sentinel's Arena", "rect": [5, 1, 3, 1], "exits": [
				{"door": "west", "side": "left", "to": "test_room", "to_door": "east"},
				{"door": "east", "side": "right", "to": "arena_room", "to_door": "west"},
			]},
			"arena_room": {"name": "Proving Grounds", "rect": [8, 1, 3, 1], "exits": [
				{"door": "west", "side": "left", "to": "boss_room", "to_door": "east"},
				{"door": "east", "side": "right", "to": "secret_room", "to_door": "west", "secret": true},
			]},
			"secret_room": {"name": "Hidden Shrine", "rect": [11, 1, 2, 1], "hidden": true, "exits": [
				{"door": "west", "side": "left", "to": "arena_room", "to_door": "east", "secret": true},
			]},
			# Not on the base map: the map does not show the whole zone.
			"bestiary": {"name": "Bestiary", "rect": [0, 2, 13, 1], "base": false, "exits": [
				{"door": "ceiling", "side": "top", "at": 2, "to": "test_room", "to_door": "floor"},
			]},
		},
	},
	"reaches": {
		"name": "Upper Reaches",
		"map_pickup": {"room": "upper_room", "position": Vector2(592, 512)}, # Floor, right of the altar.
		"rooms": {
			"upper_room": {"name": "Upper Galleries", "rect": [2, 1, 3, 1], "exits": [
				{"door": "floor", "side": "bottom", "at": 0, "to": "test_room", "to_door": "ceiling"},
				{"door": "west", "side": "left", "to": "hidden_vault", "to_door": "east", "secret": true},
				{"door": "east", "side": "right", "to": "lava_room", "to_door": "west"},
			]},
			# The spatial anomaly: linked left (Ember Crossing) and right (Upper
			# Galleries). The secret doorway is its intended entrance.
			"hidden_vault": {"name": "Hidden Vault", "rect": [0, 1, 2, 1], "hidden": true, "exits": [
				{"door": "east", "side": "right", "to": "upper_room", "to_door": "west", "secret": true},
				{"door": "west", "side": "left", "to": "lava_room", "to_door": "east"},
			]},
			"lava_room": {"name": "Ember Crossing", "rect": [5, 1, 4, 1], "exits": [
				{"door": "west", "side": "left", "to": "upper_room", "to_door": "east"},
				{"door": "east", "side": "right", "to": "hidden_vault", "to_door": "west"},
			]},
		},
	},
}

var zones: Array[MapZone] = []
var _zone_of := {} ## room_id -> MapZone


static func create_default() -> MapAtlas:
	var atlas := MapAtlas.new()
	for zone_id in WORLD:
		atlas.zones.append(MapZone.from_dict(zone_id, WORLD[zone_id]))
	atlas.rebuild()
	return atlas


## Adds (or replaces) a zone, e.g. one authored as a .tres resource.
func add_zone(zone: MapZone) -> void:
	for i in zones.size():
		if zones[i].zone_id == zone.zone_id:
			zones[i] = zone
			rebuild()
			return
	zones.append(zone)
	rebuild()


## Re-indexes the rooms and re-resolves the anomalies. Call after editing zones.
func rebuild() -> void:
	_zone_of.clear()
	for zone in zones:
		for r in zone.rooms:
			assert(not _zone_of.has(r.room_id), "MapAtlas: room '%s' is in two zones" % r.room_id)
			_zone_of[r.room_id] = zone
	resolve_anomalies()


func get_zone(zone_id: String) -> MapZone:
	for zone in zones:
		if zone.zone_id == zone_id:
			return zone
	return null


## The zone a room belongs to, or null for a room that is on no map.
func zone_of(room_id: String) -> MapZone:
	return _zone_of.get(room_id)


func get_room(room_id: String) -> MapRoom:
	var zone := zone_of(room_id)
	return zone.get_room(room_id) if zone else null


func zone_ids() -> Array[String]:
	var ids: Array[String] = []
	for zone in zones:
		ids.append(zone.zone_id)
	return ids


# ---------- Spatial anomalies ----------

## True when `e` (a left / right exit of `r`) leads to a room that touches `r`
## on that side of the map. Exits into another zone always count as touching:
## they are drawn as a stub that leaves the map.
func exit_is_adjacent(r: MapRoom, e: MapExit) -> bool:
	var t := get_room(e.target_room)
	if t == null or zone_of(t.room_id) != zone_of(r.room_id):
		return true
	var rows_overlap := t.rect.position.y < r.rect.end.y and r.rect.position.y < t.rect.end.y
	var cols_overlap := t.rect.position.x < r.rect.end.x and r.rect.position.x < t.rect.end.x
	match e.side:
		"left":
			return rows_overlap and t.rect.end.x == r.rect.position.x
		"right":
			return rows_overlap and t.rect.position.x == r.rect.end.x
		"top":
			return cols_overlap and t.rect.end.y == r.rect.position.y
	return cols_overlap and t.rect.position.y == r.rect.end.y


## A room linked on both its left and right sides, where at least one of those
## links does not touch its neighbour on the map.
func is_anomaly_room(r: MapRoom) -> bool:
	var left := false
	var right := false
	var conflict := false
	for e in r.exits:
		if e.side == "left":
			left = true
		elif e.side == "right":
			right = true
		else:
			continue
		if not exit_is_adjacent(r, e):
			conflict = true
	return left and right and conflict


## Marks the conflicting, unintended side exits of every anomaly room (and
## the door on the other end) as suppressed. See the class description.
func resolve_anomalies() -> void:
	for zone in zones:
		for r in zone.rooms:
			for e in r.exits:
				e.suppressed = false
	for zone in zones:
		for r in zone.rooms:
			if not is_anomaly_room(r):
				continue
			for e in r.exits:
				if not e.is_horizontal() or exit_is_adjacent(r, e):
					continue
				if e.secret or e.door_id == r.intended_entrance:
					continue # The intended (or secret) way in stays.
				var t := get_room(e.target_room)
				var back := t.get_exit(e.target_door) if t else null
				if back and (back.secret or t.intended_entrance == back.door_id):
					continue
				e.suppressed = true
				if back:
					back.suppressed = true


## door_ids of `room_id` whose connection is suppressed (sealed in the world).
func suppressed_doors(room_id: String) -> Array[String]:
	var ids: Array[String] = []
	var r := get_room(room_id)
	if r:
		for e in r.exits:
			if e.suppressed:
				ids.append(e.door_id)
	return ids
