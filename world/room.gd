class_name Room
extends Node2D
## A playable room: a TileMapLayer plus spawn markers.
## Gameplay code asks the room about the world (solid? hazard? ground?)
## instead of reading tiles directly.
##
## TileSet custom data layers: "one_way" (bool), "hazard" (bool).
## Any painted tile that is neither one-way nor hazard counts as solid.

@export var room_id := "" ## Key used by WorldState and doors.
## The room's normal area, when the tiles reach further (e.g. a hidden pocket
## built outside it). Empty = all tiles. The camera stays inside it until a
## hidden pocket out there is found (see Game._refresh_camera_bounds).
@export var main_rect := Rect2()

@onready var tiles: TileMapLayer = $Tiles


## The normal room area: the camera's limits and the layout checks.
func get_bounds() -> Rect2:
	return main_rect if main_rect.has_area() else get_full_bounds()


## Every tile, including hidden pockets beyond the normal area.
func get_full_bounds() -> Rect2:
	var used := tiles.get_used_rect()
	var size := Vector2(tiles.tile_set.tile_size)
	return Rect2(tiles.to_global(Vector2(used.position) * size), Vector2(used.size) * size)


## Player spawn marker, or the first door's arrival point, or the room center.
func get_player_spawn() -> Vector2:
	var marker := get_node_or_null("PlayerSpawn") as Marker2D
	if marker:
		return marker.global_position
	var doors := get_doors()
	return doors[0].get_arrival_position() if not doors.is_empty() else get_bounds().get_center()


## Returns [{id, position, kind}, ...] from the EnemySpawns markers.
## kind: "weak", "flyer" or "strong". The marker name is the persistence id.
func get_enemy_spawns() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker in $EnemySpawns.get_children():
		var flying: bool = marker.get_meta("flying", false)
		var kind: String = marker.get_meta("kind", "flyer" if flying else "weak")
		result.append({"id": String(marker.name), "position": marker.global_position, "kind": kind})
	return result


func _data_at(world_pos: Vector2) -> TileData:
	return tiles.get_cell_tile_data(tiles.local_to_map(tiles.to_local(world_pos)))


func is_solid_at(world_pos: Vector2) -> bool:
	var d := _data_at(world_pos)
	return d != null and not d.get_custom_data("one_way") and not d.get_custom_data("hazard")


func is_one_way_at(world_pos: Vector2) -> bool:
	var d := _data_at(world_pos)
	return d != null and d.get_custom_data("one_way")


## Floor an enemy can walk on (solid or one-way).
func is_ground_at(world_pos: Vector2) -> bool:
	var d := _data_at(world_pos)
	return d != null and not d.get_custom_data("hazard")


## True when the feet rest only on one-way tiles (drop-through allowed).
func standing_on_one_way_only(rect: Rect2) -> bool:
	var y := rect.end.y + 2.0
	var any_one_way := false
	for x in [rect.position.x + 1.0, rect.get_center().x, rect.end.x - 1.0]:
		var p := Vector2(x, y)
		if is_solid_at(p):
			return false
		if is_one_way_at(p):
			any_one_way = true
	return any_one_way


## Safe ground for hazard respawns: both feet supported by real floor and no
## hazard within ~1.5 tiles to either side or just below.
func is_safe_ground(rect: Rect2) -> bool:
	var y := rect.end.y + 2.0
	if not is_ground_at(Vector2(rect.position.x + 1.0, y)) or not is_ground_at(Vector2(rect.end.x - 1.0, y)):
		return false
	var margin := float(tiles.tile_set.tile_size.x) * 1.5
	var probe := Rect2(rect.position.x - margin, rect.end.y - 4.0, rect.size.x + margin * 2.0, 40.0)
	return not find_hazard(probe).has_area()


## Spikes only occupy the lower part of their tile.
func hazard_rect_for_cell(cell: Vector2i) -> Rect2:
	var ts := Vector2(tiles.tile_set.tile_size)
	var origin := tiles.to_global(Vector2(cell) * ts)
	return Rect2(origin.x + 3.0, origin.y + ts.y * 0.4, ts.x - 6.0, ts.y * 0.6)


## Returns the first hazard rect overlapping `rect`, or an empty Rect2.
func find_hazard(rect: Rect2) -> Rect2:
	var first := tiles.local_to_map(tiles.to_local(rect.position))
	var last := tiles.local_to_map(tiles.to_local(rect.end))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			var d := tiles.get_cell_tile_data(cell)
			if d == null or not d.get_custom_data("hazard"):
				continue
			var h := hazard_rect_for_cell(cell)
			if h.intersects(rect):
				return h
	return Rect2()


## Interactables, checkpoints and pickups placed in the room.
func get_objects() -> Array[Node]:
	var node := get_node_or_null("Objects")
	return node.get_children() if node else []


func get_doors() -> Array[Door]:
	var list: Array[Door] = []
	for node in get_objects():
		if node is Door:
			list.append(node)
	return list


func get_arena() -> ArenaEncounter:
	for node in get_objects():
		if node is ArenaEncounter:
			return node
	return null


## Non-solid cells on the room border. Every one must be covered by a door
## (see the layout test), so the player can never walk into empty space.
func border_openings() -> Array[Vector2i]:
	var used := tiles.get_used_rect()
	var gaps: Array[Vector2i] = []
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var on_border := x == used.position.x or x == used.end.x - 1 or y == used.position.y or y == used.end.y - 1
			if on_border and not is_solid_at(cell_center(Vector2i(x, y))):
				gaps.append(Vector2i(x, y))
	return gaps


func cell_center(cell: Vector2i) -> Vector2:
	return tiles.to_global(tiles.map_to_local(cell))
