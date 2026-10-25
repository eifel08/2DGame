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


## True when any corner or the middle of `r` is inside solid rock.
func rect_blocked(r: Rect2) -> bool:
	for p in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end, r.get_center()]:
		if is_solid_at(p):
			return true
	return false


## The nearest point to `pos` where a box `size` (bottom-centered on the
## point, like the objects' feet) is free of solid rock. Searches rings
## outward in `step` px up to `max_dist`; returns `pos` if nothing is found.
func free_spot(pos: Vector2, size: Vector2, step := 4.0, max_dist := 128.0) -> Vector2:
	var box := func(at: Vector2) -> Rect2: return Rect2(at - Vector2(size.x / 2.0, size.y), size)
	if not rect_blocked(box.call(pos)):
		return pos
	var r := step
	while r <= max_dist:
		var n := maxi(8, int(TAU * r / step))
		for i in n:
			var at := pos + Vector2.from_angle(TAU * i / n) * r
			if not rect_blocked(box.call(at)):
				return at
		r += step
	return pos


## The way out into open air from `pos`: away from the rock found within
## `reach` px around it (zero in the middle of open space).
func open_direction(pos: Vector2, reach := 24.0) -> Vector2:
	var away := Vector2.ZERO
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0)
		if is_solid_at(pos + d * reach):
			away -= d
	return away.normalized() if away.length() > 0.01 else Vector2.ZERO


## Free space straight above `pos` (px), up to `limit`.
func headroom(pos: Vector2, limit := 400.0) -> float:
	var d := 0.0
	while d < limit:
		if is_solid_at(pos + Vector2(0, -d)):
			return d
		d += 4.0
	return limit


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


## Spikes only occupy the part of their tile that points into open space.
## The cell's transform flags (set by tools/build_assets.gd) give the side:
##   none                  floor spikes, pointing up    (lower 60%)
##   FLIP_V                ceiling spikes, pointing down (upper 60%)
##   TRANSPOSE             wall spikes, pointing left  (right 60%, wall on the right)
##   TRANSPOSE | FLIP_H    wall spikes, pointing right (left 60%, wall on the left)
func hazard_rect_for_cell(cell: Vector2i) -> Rect2:
	var ts := Vector2(tiles.tile_set.tile_size)
	var origin := tiles.to_global(Vector2(cell) * ts)
	var alt := tiles.get_cell_alternative_tile(cell)
	if alt & TileSetAtlasSource.TRANSFORM_TRANSPOSE:
		var x := origin.x if alt & TileSetAtlasSource.TRANSFORM_FLIP_H else origin.x + ts.x * 0.4
		return Rect2(x, origin.y + 3.0, ts.x * 0.6, ts.y - 6.0)
	if alt & TileSetAtlasSource.TRANSFORM_FLIP_V:
		return Rect2(origin.x + 3.0, origin.y, ts.x - 6.0, ts.y * 0.6)
	return Rect2(origin.x + 3.0, origin.y + ts.y * 0.4, ts.x - 6.0, ts.y * 0.6)


## Returns the first hazard rect overlapping `rect`, or an empty Rect2.
## `include_lava` false: spikes only (the pogo check: lava is never pogoed).
func find_hazard(rect: Rect2, include_lava := true) -> Rect2:
	var hits := hazards_in(rect, include_lava)
	return hits[0] if not hits.is_empty() else Rect2()


## Every hazard rect overlapping `rect`: spike tiles, and Lava nodes unless
## `include_lava` is false.
func hazards_in(rect: Rect2, include_lava := true) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if include_lava:
		for node in get_objects():
			if node is Lava and node.get_rect().intersects(rect):
				result.append(node.get_rect())
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
				result.append(h)
	return result


## The tile cell under a world point, as a world-space rect.
func cell_rect_at(world_pos: Vector2) -> Rect2:
	var ts := Vector2(tiles.tile_set.tile_size)
	var cell := tiles.local_to_map(tiles.to_local(world_pos))
	return Rect2(tiles.to_global(Vector2(cell) * ts), ts)


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


const EDGE_TOP := 1
const EDGE_RIGHT := 2
const EDGE_BOTTOM := 4
const EDGE_LEFT := 8
const WALL_VARIANTS := 16 ## Atlas columns 0..15: solid wall, lit by edge mask (tools/build_assets.gd).


## Fills `cells` with solid wall (e.g. a sealed doorway, Game.seal_door) and
## re-lights the faces around them the way the generator does: a wall tile
## lights every face that borders open space.
func seal_cells(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	for cell in cells:
		tiles.set_cell(cell, 0, Vector2i(0, 0))
	for cell in cells:
		for n in [cell, cell + Vector2i.UP, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.LEFT]:
			_relight(n)
	tiles.update_internals() # Collision is there on the very next physics step.


func _relight(cell: Vector2i) -> void:
	var coords := tiles.get_cell_atlas_coords(cell)
	if tiles.get_cell_source_id(cell) != 0 or coords.y != 0 or coords.x >= WALL_VARIANTS:
		return
	var mask := 0
	if not _wall_or_outside(cell + Vector2i.UP):
		mask |= EDGE_TOP
	if not _wall_or_outside(cell + Vector2i.RIGHT):
		mask |= EDGE_RIGHT
	if not _wall_or_outside(cell + Vector2i.DOWN):
		mask |= EDGE_BOTTOM
	if not _wall_or_outside(cell + Vector2i.LEFT):
		mask |= EDGE_LEFT
	tiles.set_cell(cell, 0, Vector2i(mask, 0))


func _wall_or_outside(cell: Vector2i) -> bool:
	return not tiles.get_used_rect().has_point(cell) or is_solid_at(cell_center(cell))


func cell_center(cell: Vector2i) -> Vector2:
	return tiles.to_global(tiles.map_to_local(cell))
