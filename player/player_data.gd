class_name PlayerData
extends RefCounted
## Persistent player progression: currency, unlocked spells and the spell
## loadout. It survives deaths and room resets.
## Gameplay rules (e.g. "swap only at a checkpoint") live in UltimateManager.
##
## The loadout follows the Spell button + direction:
##   neutral (no direction)  NEUTRAL_SPELL, Mana Discharge. Fixed for good:
##                           it is never stored here, never equipped or removed.
##   SLOT_UP                 Spell + Up
##   SLOT_SIDE               Spell + Left / Right (one slot for both sides)
##   SLOT_DOWN               Spell + Down
## Each directional slot holds one spell id or "" (empty).

const SLOT_UP := 0
const SLOT_SIDE := 1
const SLOT_DOWN := 2
const SLOT_COUNT := 3
const SLOT_NAMES: Array[String] = ["up", "side", "down"]
const NEUTRAL_SPELL := "mana_discharge"

var currency := 0
var unlocked: Array[String] = [] ## Every equippable spell the player has discovered.
var equipped: Array[String] = empty_slots() ## Spell id per directional slot ("" = empty).


static func empty_slots() -> Array[String]:
	var slots: Array[String] = []
	slots.resize(SLOT_COUNT)
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
	if ability_id != NEUTRAL_SPELL and not unlocked.has(ability_id):
		unlocked.append(ability_id)


func is_unlocked(ability_id: String) -> bool:
	return ability_id == NEUTRAL_SPELL or unlocked.has(ability_id)


## Forgets a spell (debug): it leaves the pool and its slot. The neutral
## spell can never be forgotten.
func lock(ability_id: String) -> void:
	unlocked.erase(ability_id)
	var slot := equipped.find(ability_id)
	if slot != -1:
		equipped[slot] = ""


func unequip(slot: int) -> void:
	equipped[slot] = ""


func equipped_count() -> int:
	return equipped.filter(func(id: String) -> bool: return id != "").size()


## Puts a spell into a slot. If it is already in another slot, the two
## slots swap so a spell is never equipped twice. The neutral spell is
## refused: it is fixed to the neutral input.
func equip(slot: int, ability_id: String) -> bool:
	if ability_id == NEUTRAL_SPELL or slot < 0 or slot >= SLOT_COUNT:
		return false
	var other := equipped.find(ability_id)
	if other != -1 and other != slot:
		equipped[other] = equipped[slot]
	equipped[slot] = ability_id
	return true
