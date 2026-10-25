class_name MeditationAltar
extends Interactable
## A Meditation / Concentration altar. Interact (E) on the ground: the player
## kneels in a meditation (player state "meditate", clip "meditate") for
## Config.progression.meditation_time. When it completes, the altar's spell
## slot (Up, Side or Down) is unlocked for good. Taking a hit interrupts the
## meditation and nothing is unlocked.
## An altar is spent once its slot is open, so nothing extra is saved: the
## open slots (PlayerData.open_slots) are the record.
## Art: replace Visual; optional AnimationPlayer clips "idle" (ready) and
## "spent" (its slot is open).

const SLOT_IDS: Array[String] = ["up", "side", "down"] ## Same order as PlayerData.SLOT_*.

@export_enum("up", "side", "down") var slot_name := "up"

var spent := false
var busy := false ## True while the player meditates here (no prompt).

@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")


func _ready() -> void:
	_play("idle")


## PlayerData.SLOT_UP / SLOT_SIDE / SLOT_DOWN.
func get_slot() -> int:
	return SLOT_IDS.find(slot_name)


func can_interact() -> bool:
	return not spent and not busy


func interact(game: Node) -> void:
	game.meditate_at(self)


## Where the player kneels: the altar's center, on the floor.
func get_meditation_position() -> Vector2:
	return global_position


func set_spent(on: bool) -> void:
	if spent == on:
		return
	spent = on
	highlighted = false
	_play("spent" if on else "idle")


func _play(anim_name: String) -> void:
	if anim != null and anim.has_animation(anim_name):
		anim.play(anim_name)
