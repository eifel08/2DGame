class_name SpellScroll
extends Node2D
## A collectible Spell Scroll. Touching it teaches `spell_id` for good: the
## spell joins the known pool and can be put on an open Up / Side / Down slot
## at the saved checkpoint. No autoloads here (see Interactable).
## A scroll is gone once its spell is known, so nothing extra is saved: the
## known spells (PlayerData.unlocked) are the record.
## Art: the Visual node and the AnimationPlayer "idle" clip are placeholders.

@export var spell_id := ""

var collected := false


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(14, 36), Vector2(28, 36))


func collect() -> void:
	collected = true
	visible = false
