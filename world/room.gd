class_name Room
extends Node2D
## A playable room: a TileMapLayer plus spawn markers.
## Gameplay code asks the room about the world (solid? hazard? ground?)
## instead of reading tiles directly.
##
## TileSet custom data layers: "one_way" (bool), "hazard" (bool).
## Any painted tile that is neither one-way nor hazard counts as solid.

@onready var tiles: TileMapLayer = $Tiles


func get_bounds() -> Rect2:
	var used := tiles.get_used_rect()
	var size := Vector2(tiles.tile_set.tile_size)
	return Rect2(Vector2(used.position) * size, Vector2(used.size) * size)


func get_player_spawn() -> Vector2:
	return ($PlayerSpawn as Marker2D).global_position


## Returns [{position: Vector2, flying: bool}, ...] from the EnemySpawns markers.
func get_enemy_spawns() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker in $EnemySpawns.get_children():
		result.append({"position": marker.global_position, "flying": marker.get_meta("flying", false)})
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
