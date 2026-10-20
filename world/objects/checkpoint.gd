class_name Checkpoint
extends Interactable
## Respawn point. Touching it activates it: after death or a hazard hit the
## player returns to the last activated checkpoint. Interacting ("Rest")
## fully restores health. While standing at the active checkpoint the
## ultimate loadout can be changed in the inventory.
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
	game.rest_at_checkpoint(self)


func _has(anim_name: String) -> bool:
	return anim != null and anim.has_animation(anim_name)


func _play(anim_name: String) -> void:
	if _has(anim_name):
		anim.play(anim_name)
