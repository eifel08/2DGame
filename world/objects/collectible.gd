class_name Collectible
extends Node2D
## Base for every item lying in the world that the player takes: relics and
## potions, Spell Scrolls, movement items, zone maps, pouches and tools.
## Walking over one does nothing. Standing at it and pressing Interact (E)
## takes it, like saving at a checkpoint: Game._update_interaction picks the
## nearest interactable or collectible and shows its "E  Take" prompt.
## Shards (Coin) are currency, not items: they are still taken on touch.
## No autoloads here (see Interactable).

const PROMPT := "Take"

var collected := false
var highlighted := false:
	set(value):
		if highlighted != value:
			highlighted = value
			queue_redraw()


## The item's body (global). Subclasses size it to their art.
func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(14, 36), Vector2(28, 36))


## Where the player must stand to take it: a little wider than the item.
func get_interact_rect() -> Rect2:
	return get_rect().grow_individual(14.0, 8.0, 14.0, 0.0)


func can_interact() -> bool:
	return not collected


func collect() -> void:
	collected = true
	highlighted = false
	visible = false


## Back in the world (debug: a forgotten spell, item or piece of gear).
func restore() -> void:
	collected = false
	visible = true


func _draw() -> void:
	draw_prompt()


## The "E  Take" prompt above the item while it is the focused one.
func draw_prompt() -> void:
	if highlighted:
		Interactable.draw_prompt(self, "E  " + PROMPT, get_rect().position.y - global_position.y)
