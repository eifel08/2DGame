class_name Checkpoint
extends Interactable
## Respawn point. It never saves passively: the player saves by interacting
## (E, or Down on the ground). Saving centers the player on the checkpoint,
## restores full health and makes it the respawn point after death. While
## standing at the saved checkpoint the ultimate loadout can be changed.
##
## Art is modular: put any visuals under "Visual" and give the optional
## AnimationPlayer animations named "inactive", "activate" and "active".

@export var is_start := false ## The checkpoint used at game start.

var lit := false

@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")


func _ready() -> void:
	_play("inactive")


func get_respawn_position() -> Vector2:
	return global_position


func set_lit(on: bool, animate := true) -> void:
	if lit == on:
		return
	lit = on
	if not on:
		_play("inactive")
	elif animate and _has("activate"):
		_play("activate")
		anim.queue("active")
	else:
		_play("active")


func interact(game: Node) -> void:
	game.save_at_checkpoint(self)


func _has(anim_name: String) -> bool:
	return anim != null and anim.has_animation(anim_name)


func _play(anim_name: String) -> void:
	if _has(anim_name):
		anim.play(anim_name)
