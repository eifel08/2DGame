class_name LoreObject
extends Interactable
## A sign, tablet or NPC that opens a dialogue. Assign a DialogueData resource
## in the Inspector; the visuals are free-form child nodes.

@export var dialogue: DialogueData


func can_interact() -> bool:
	return dialogue != null


func interact(game: Node) -> void:
	game.open_dialogue(dialogue)
