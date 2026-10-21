class_name PlayerData
extends RefCounted
## Persistent player progression: currency, unlocked abilities and the
## equipped ultimate slots. It survives deaths and room resets.
## Gameplay rules (e.g. "swap only at a checkpoint") live in UltimateManager.
##
## There are MAX_SLOTS hotkeys (ult_1 .. ult_8). Only the first
## `slot_capacity` of them can hold an ability; the rest stay empty.

const MAX_SLOTS := 8
const DEFAULT_CAPACITY := 4

var currency := 0
var unlocked: Array[String] = [] ## Every ability the player has discovered.
var equipped: Array[String] = empty_slots() ## Ability id per hotkey slot ("" = empty).
var slot_capacity := DEFAULT_CAPACITY ## How many slots may hold an ability (1..MAX_SLOTS).


static func empty_slots() -> Array[String]:
	var slots: Array[String] = []
	slots.resize(MAX_SLOTS)
	slots.fill("")
	return slots


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


## Forgets an ability (debug): it leaves the pool and its slot.
func lock(ability_id: String) -> void:
	unlocked.erase(ability_id)
	var slot := equipped.find(ability_id)
	if slot != -1:
		equipped[slot] = ""


## Sets how many slots are usable. Abilities beyond the new limit are unequipped.
func set_capacity(count: int) -> void:
	slot_capacity = clampi(count, 1, MAX_SLOTS)
	for slot in range(slot_capacity, MAX_SLOTS):
		equipped[slot] = ""


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
