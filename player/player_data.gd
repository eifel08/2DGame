class_name PlayerData
extends RefCounted
## Persistent player progression: currency, unlocked abilities and the four
## equipped ultimate slots. It survives deaths and room resets.
## Gameplay rules (e.g. "swap only at a checkpoint") live in UltimateManager.

const SLOT_COUNT := 4

var currency := 0
var unlocked: Array[String] = [] ## Every ability the player has discovered.
var equipped: Array[String] = ["", "", "", ""] ## Ability id per hotkey slot ("" = empty).


func add_currency(amount: int) -> void:
	currency = maxi(0, currency + amount)


func spend_currency(amount: int) -> bool:
	if amount > currency:
		return false
	currency -= amount
	return true


func unlock(ability_id: String) -> void:
	if not unlocked.has(ability_id):
		unlocked.append(ability_id)


func is_unlocked(ability_id: String) -> bool:
	return unlocked.has(ability_id)


func unequip(slot: int) -> void:
	equipped[slot] = ""


func equipped_count() -> int:
	return equipped.filter(func(id: String) -> bool: return id != "").size()


## Puts an ability into a slot. If it is already in another slot, the two
## slots swap so an ability is never equipped twice.
func equip(slot: int, ability_id: String) -> void:
	var other := equipped.find(ability_id)
	if other != -1 and other != slot:
		equipped[other] = equipped[slot]
	equipped[slot] = ability_id
