extends Node
## Save slots (autoload "Saves"): 5 independent profiles, each a JSON file in
## user://saves/slot_N.json. A slot stores the saved checkpoint (room +
## position), shards, unlocked/equipped abilities, health/energy growth and
## world progress (defeated bosses, cleared arenas, collected shards, opened
## secrets, relics). Respawnable enemies are not stored: loading always
## resets them, and the player starts with 0 energy.

const SLOT_COUNT := 5
const VERSION := 1
const ROOM_NAMES := {
	"test_room": "Testing Halls",
	"boss_room": "Sentinel's Arena",
	"arena_room": "Proving Grounds",
	"secret_room": "Hidden Shrine",
	"upper_room": "Upper Galleries",
	"bestiary": "Bestiary",
	"hidden_vault": "Hidden Vault",
	"lava_room": "Ember Crossing",
	"gear_room": "Tinker's Loft",
}

var save_dir := "user://saves"
var active_slot := -1 ## -1 = not saving (tests, or running scenes/game.tscn directly).
var pending_data := {} ## Loaded when the game scene starts; {} = new game.


func slot_path(slot: int) -> String:
	return save_dir.path_join("slot_%d.json" % (slot + 1))


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func read_slot(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}


func write_slot(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	data["version"] = VERSION
	data["slot"] = slot
	data["saved_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func delete_slot(slot: int) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


## One-line description for the slot menu.
func summary(slot: int) -> String:
	var data := read_slot(slot)
	if data.is_empty():
		return "New Game"
	var minutes := int(data.get("playtime", 0.0)) / 60
	return "%s  ·  ◆ %d  ·  %d:%02d" % [ROOM_NAMES.get(data.get("room", ""), "?"),
		int(data.get("currency", 0)), minutes / 60, minutes % 60]


## Selects a slot for the next game scene: loads it, or starts a new game.
func start_slot(slot: int) -> void:
	active_slot = slot
	pending_data = read_slot(slot)
