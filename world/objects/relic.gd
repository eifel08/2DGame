class_name Relic
extends Collectible
## A permanent upgrade pickup (e.g. hidden in a secret room). Taking it (E)
## raises max health or max energy for the rest of the save. Collected relics
## never reappear (WorldState.relics). No autoloads here.
## Art: the Visual node and the AnimationPlayer "idle" clip are placeholders;
## replace them freely (the pickup area is get_rect()).

@export var relic_id := ""
@export_enum("max_health", "max_energy") var stat := "max_health"
@export var amount := 25.0


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(14, 40), Vector2(28, 40))
