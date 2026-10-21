class_name SecretWall
extends Node2D
## Base class of the two kinds of secret wall (GUIDELINES.md, "Secret walls").
## Both are disguised as ordinary wall, but they behave very differently:
##
##   Type 1 - HiddenPocketWall: hides a pocket or alcove of THIS room.
##            One-way until the player walks through it, then revealed for
##            good (saved). Everything inside the pocket is covered until then.
##   Type 2 - SecretDoorway:    a disguised room transition to ANOTHER room.
##            Never consumed; usable back and forth. Semi-transparent from the
##            entry side; from the exit side an ordinary open doorway (Rule E).
## Rule D applies to both: every pocket and room is closed by solid wall
## wherever there is no transition.
##
## Each type has its own scene and its own visual nodes, so final art and
## animations plug in per type. This base only knows the size and how to
## draw placeholder wall tiles. The node origin is at the floor; the wall
## extends `size` upward. No autoloads here (the generator instantiates it).

const TILES_PNG := "res://world/tiles/tiles.png"
const TILE := 32.0
## Tile atlas edge bits (tools/build_assets.gd): a lit face per exposed side.
const EDGE_RIGHT := 2
const EDGE_LEFT := 8

@export var size := Vector2(32, 96)


func get_rect() -> Rect2:
	return Rect2(global_position.x - size.x / 2.0, global_position.y - size.y, size.x, size.y)


## Placeholder art: fills `target` (if it has no art of its own yet) with
## wall tiles covering `rect` (global), so the disguise matches the room's
## walls. `edge_mask` lights the faces that border open space.
func fill_with_wall_tiles(target: Node2D, rect: Rect2, edge_mask: int) -> void:
	if target == null or target.get_child_count() > 0:
		return # Custom art is already there.
	var texture := load(TILES_PNG) as Texture2D
	if texture == null:
		return
	var cols := int(roundf(rect.size.x / TILE))
	var rows := int(roundf(rect.size.y / TILE))
	for cy in rows:
		for cx in cols:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(edge_mask * TILE, 0.0, TILE, TILE)
			target.add_child(sprite)
			sprite.global_position = rect.position + Vector2(cx, cy) * TILE
