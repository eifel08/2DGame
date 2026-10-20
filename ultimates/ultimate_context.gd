class_name UltimateContext
extends RefCounted
## Everything an ultimate may touch, passed to each ability hook.

var player: Player
var combat: CombatManager
var effects: Effects
var input: InputState


func _init(p_player: Player, p_combat: CombatManager, p_effects: Effects, p_input: InputState) -> void:
	player = p_player
	combat = p_combat
	effects = p_effects
	input = p_input
