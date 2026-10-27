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
## and right sides in a way a flat map cannot show. The case in this world
## was the Hidden Vault: west of the Upper Galleries (secret doorway on its
## east side), yet its west door led to the Ember Crossing, EAST of the
## Galleries. That doorway is now walled up in both layouts
## (tools/build_assets.gd), so only the secret entrance remains.
## The resolver stays as a check and a safety net. For such a room, every
## side exit whose neighbour does not touch it on the map is a conflict. The
## secret exit (or the room's intended_entrance) is kept; every other
## conflicting exit is suppressed on both ends: the map draws no connector
## for it, and with Config.map.seal_anomaly_entrances the game seals that
## doorway with wall tiles at load time (Game.seal_door). The smoke test
## fails while the default world has any suppressed exit, so a new anomaly
## gets walled up in its layout as well.

## The default world: two zones.
const WORLD := {
	"halls": {
		"name": "Testing Halls",
		"origin": [0, 0],
		"color": "#5b7bd5", # Slate blue.
		"rooms": {
			"test_room": {"name": "Testing Halls", "rect": [0, 0, 5, 2], "exits": [
				{"door": "east", "side": "right", "at": 1, "to": "boss_room", "to_door": "west"},
				{"door": "ceiling", "side": "top", "at": 2, "to": "upper_room", "to_door": "floor"},
				{"door": "floor", "side": "bottom", "at": 2, "to": "bestiary", "to_door": "ceiling"},
				{"door": "ceiling_west", "side": "top", "at": 0, "to": "gear_room", "to_door": "floor"},
			]},
			# Tinker's Loft: up and to the left of the Halls, its floor gap over their west end.
			"gear_room": {"name": "Tinker's Loft", "rect": [-2, -1, 3, 1], "exits": [
				{"door": "floor", "side": "bottom", "at": 2, "to": "test_room", "to_door": "ceiling_west"},
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
	# Above the Halls: the Galleries' floor gap meets the Halls' ceiling gap.
	"reaches": {
		"name": "Upper Reaches",
		"origin": [0, -2],
		"color": "#d0843f", # Ember orange.
		"rooms": {
			"upper_room": {"name": "Upper Galleries", "rect": [2, 1, 3, 1], "exits": [
				{"door": "floor", "side": "bottom", "at": 0, "to": "test_room", "to_door": "ceiling"},
				{"door": "west", "side": "left", "to": "hidden_vault", "to_door": "east", "secret": true},
				{"door": "east", "side": "right", "to": "lava_room", "to_door": "west"},
			]},
			# Was a spatial anomaly (linked to the Ember Crossing on its west
			# side too); that doorway is walled up in both layouts. The secret
			# doorway is its only entrance.
			# One cell wide, so it never overlaps the Tinker's Loft below-left of it on the world grid.
			"hidden_vault": {"name": "Hidden Vault", "rect": [1, 1, 1, 1], "hidden": true, "exits": [
				{"door": "east", "side": "right", "to": "upper_room", "to_door": "west", "secret": true},
			]},
			"lava_room": {"name": "Ember Crossing", "rect": [5, 1, 4, 1], "exits": [
				{"door": "west", "side": "left", "to": "upper_room", "to_door": "east"},
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

## A room's rect on the world grid (its zone's world_origin applied).
func world_rect(r: MapRoom) -> Rect2i:
	var zone := zone_of(r.room_id)
	return zone.world_rect(r) if zone else r.rect


## True when `e` (an exit of `r`) leads to a room that touches `r` on that
## side, on the world grid (so exits into another zone are checked too).
func exit_is_adjacent(r: MapRoom, e: MapExit) -> bool:
	var t := get_room(e.target_room)
	if t == null:
		return true
	var a := world_rect(r)
	var b := world_rect(t)
	var rows_overlap := b.position.y < a.end.y and a.position.y < b.end.y
	var cols_overlap := b.position.x < a.end.x and a.position.x < b.end.x
	match e.side:
		"left":
			return rows_overlap and b.end.x == a.position.x
		"right":
			return rows_overlap and b.position.x == a.end.x
		"top":
			return cols_overlap and b.end.y == a.position.y
	return cols_overlap and b.position.y == a.end.y


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
