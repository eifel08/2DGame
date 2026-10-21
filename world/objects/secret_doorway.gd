class_name SecretDoorway
extends SecretWall
## TYPE 2 secret wall: a disguised room transition (GUIDELINES.md, "Secret
## walls"). It covers the gap of an ordinary side door (the Door node next to
## it does the transition) and has no collision: the player simply walks
## into the "wall" and arrives in another room.
##
##   - Never consumed: it works back and forth, as often as you like, and is
##     not saved. It never disappears.
##   - Visual asymmetry: `side = "entry"` (the room you discover it from) is
##     drawn semi-transparent; `side = "exit"` (inside the secret room) looks
##     exactly like the surrounding wall.
##   - `inward` is the direction into this room (+1 right, -1 left); it
##     decides which face of the disguise is lit.
##
## Art and animation (replace freely, keep the node names):
##   EntryVisual     shown on the entry side. Placeholder: wall tiles at 50% opacity.
##   ExitVisual      shown on the exit side. Placeholder: solid wall tiles.
##   AnimationPlayer optional; a "pass" clip plays whenever the player walks through.

const ENTRY_ALPHA := 0.5

@export_enum("entry", "exit") var side := "entry"
@export_range(-1, 1, 2) var inward := 1

var _was_inside := false


func _ready() -> void:
	var mask := EDGE_RIGHT if inward > 0 else EDGE_LEFT
	var entry := get_node_or_null("EntryVisual") as Node2D
	var exit := get_node_or_null("ExitVisual") as Node2D
	fill_with_wall_tiles(entry if is_entry() else exit, get_rect(), mask)
	if entry:
		entry.visible = is_entry()
		entry.modulate.a = ENTRY_ALPHA
	if exit:
		exit.visible = not is_entry()


func is_entry() -> bool:
	return side == "entry"


## The disguise currently shown (tests, debug).
func shown_visual() -> CanvasItem:
	return get_node_or_null("EntryVisual" if is_entry() else "ExitVisual") as CanvasItem


## Called every step: plays the optional "pass" clip as the player enters.
func update_for(player_rect: Rect2) -> void:
	var inside := get_rect().intersects(player_rect)
	if inside and not _was_inside:
		var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim and anim.has_animation("pass"):
			anim.play("pass")
	_was_inside = inside
