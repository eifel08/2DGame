class_name CrawlerEnemy
extends BaseEnemy
## BONUS - Wall-crawler. It clings to solid surfaces and creeps along them,
## around convex corners and up into concave ones: floor, wall, ceiling,
## wall... So it circles a block of rock forever. When it hangs upside down
## and the player passes right below it, it lets go and drops on them, then
## crawls on from wherever it lands. Knockback does not move it.
##
## It moves by surface geometry, not physics: `contact` is the point on the
## surface under its middle, `normal` points away from the surface and `dir`
## is the crawl direction (all cardinal). Surfaces lie on tile edges.

@export var crawl_speed := 70.0
@export var drop_window := 18.0 ## |dx| to the player that triggers a drop.

const TILE := 32.0

var contact := Vector2.ZERO
var normal := Vector2.UP
var dir := Vector2.RIGHT
var fall_speed := 0.0
var turns := 0 ## Corners taken (tests, debug).


func _on_spawn() -> void:
	contact = home
	normal = Vector2.UP
	dir = Vector2.RIGHT
	fall_speed = 0.0
	turns = 0
	_place()


## Body center sits half a body away from the surface.
func _place() -> void:
	var center := contact + normal * (size.y / 2.0)
	global_position = center + Vector2(0, size.y / 2.0)


func _think(delta: float) -> void:
	match state:
		"idle", "crawl":
			state = "crawl"
			_crawl(delta)
			if normal == Vector2.DOWN and target_valid() and absf(target.global_position.x - contact.x) <= drop_window \
					and target.global_position.y > contact.y and line_clear(get_center(), target_center()):
				telegraph("drop")
				enter("fall")
				fall_speed = 0.0
				contact.y += size.y # Let go: the body hangs below the rock.
				normal = Vector2.UP
		"fall":
			fall_speed = minf(fall_speed + GRAVITY * delta, 900.0)
			var next := contact + Vector2(0, fall_speed * delta)
			if room.is_solid_at(next + Vector2(0, 1)):
				next.y = floorf((next.y + 1.0) / TILE) * TILE
				contact = next
				normal = Vector2.UP
				dir = Vector2.RIGHT if not target_valid() or target.global_position.x >= contact.x else Vector2.LEFT
				enter("crawl")
			else:
				contact = next
			_place()
		_:
			enter("crawl")


func _crawl(delta: float) -> void:
	contact += dir * crawl_speed * delta
	if room.is_solid_at(contact + dir * 2.0 + normal * 4.0):
		# Concave corner: a wall ahead. Turn to climb it.
		var old_normal := normal
		normal = -dir
		dir = old_normal
		_snap()
		turns += 1
	elif not room.is_solid_at(contact - normal * 2.0):
		# Convex corner: the surface ended. Wrap around the edge.
		var old_normal := normal
		normal = dir
		dir = -old_normal
		_snap()
		turns += 1
	_place() # Facing stays 1: the rig turns with `normal` instead of flipping.


## Puts the contact point exactly on the tile edge of the new surface.
func _snap() -> void:
	if normal.x != 0.0:
		contact.x = roundf(contact.x / TILE) * TILE
	else:
		contact.y = roundf(contact.y / TILE) * TILE


func _step_stunned(_delta: float) -> void:
	_place() # Stuck to its surface: hits flash it but never move it.


func _on_hit(_direction: Vector2, _knockback: float) -> void:
	stun_timer = 0.08
