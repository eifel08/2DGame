class_name PlayerState
extends RefCounted
## Base class for player states. Each state reads Config and input, then
## writes velocity through the Player's movement helpers.

var p: Player


func _init(player: Player) -> void:
	p = player


func enter(_params: Dictionary) -> void:
	pass


func step(_delta: float) -> void:
	pass


func exit() -> void:
	pass
