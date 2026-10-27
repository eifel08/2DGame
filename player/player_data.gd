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
##
## Progression: a new game knows NO equippable spell and every directional
## slot is LOCKED. Spell Scrolls teach spells (unlock), Meditation Altars
## open slots (open_slot). A locked slot holds nothing and casts nothing.
##
## Movement abilities (MOVEMENT) are found in the world too (AbilityPickup):
## a new game has none. Seen tutorials are kept so each popup shows once.

const SLOT_UP := 0
const SLOT_SIDE := 1
const SLOT_DOWN := 2
const SLOT_COUNT := 3
const SLOT_NAMES: Array[String] = ["up", "side", "down"]
const NEUTRAL_SPELL := "mana_discharge"
## Movement abilities found as items: double jump, dash, wall climb / slide
## (incl. wall jumps), grappling hook.
const MOVEMENT: Array[String] = ["double_jump", "dash", "wall_climb", "grapple"]

var currency := 0
var unlocked: Array[String] = [] ## Every equippable spell the player has discovered.
var equipped: Array[String] = empty_slots() ## Spell id per directional slot ("" = empty).
var open_slots: Array[bool] = locked_slots() ## Per directional slot: true once a Meditation Altar opened it.
var movement: Array[String] = [] ## Movement abilities collected (MOVEMENT ids).
var seen_tutorials: Array[String] = [] ## Tutorial popups already shown (TutorialPopup ids).
## Pouches and tools (rules in GearManager). A tool sits in at most one slot.
var owned_tools: Array[String] = []
var owned_pouches: Array[String] = []
var equipped_pouches: Array[String] = [] ## Equip order; only the first Config.gear.max_equipped_pouches are active.
var pouch_contents := {} ## pouch id -> Array[String], one tool id per slot ("" = empty). Kept while unequipped.


static func empty_slots() -> Array[String]:
	var slots: Array[String] = []
	slots.resize(SLOT_COUNT)
	slots.fill("")
	return slots


static func locked_slots() -> Array[bool]:
	var slots: Array[bool] = []
	slots.resize(SLOT_COUNT)
	slots.fill(false)
	return slots


func is_slot_open(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT and open_slots[slot]


## Opens a directional slot for good. Returns false if it was already open.
func open_slot(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT or open_slots[slot]:
		return false
	open_slots[slot] = true
	return true


func open_slot_count() -> int:
	return open_slots.count(true)


func has_movement(ability_id: String) -> bool:
	return movement.has(ability_id)


## Learns a movement ability for good. Returns false if unknown or known.
func learn_movement(ability_id: String) -> bool:
	if not MOVEMENT.has(ability_id) or movement.has(ability_id):
		return false
	movement.append(ability_id)
	return true


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
## refused: it is fixed to the neutral input. A locked slot is refused too.
func equip(slot: int, ability_id: String) -> bool:
	if ability_id == NEUTRAL_SPELL or not is_slot_open(slot):
		return false
	var other := equipped.find(ability_id)
	if other != -1 and other != slot:
		equipped[other] = equipped[slot]
	equipped[slot] = ability_id
	return true


# ---------- Gear (pouches and tools) ----------

func gear_to_dict() -> Dictionary:
	return {
		"tools": owned_tools.duplicate(),
		"pouches": owned_pouches.duplicate(),
		"equipped": equipped_pouches.duplicate(),
		"contents": pouch_contents.duplicate(true),
	}


## A save from before gear stores none: no tools, no pouches.
func gear_from_dict(d: Dictionary) -> void:
	owned_tools = _strings(d.get("tools", []))
	owned_pouches = _strings(d.get("pouches", []))
	equipped_pouches = _strings(d.get("equipped", []))
	pouch_contents = {}
	var contents: Dictionary = d.get("contents", {})
	for pouch_id in contents:
		pouch_contents[String(pouch_id)] = _strings(contents[pouch_id])


static func _strings(list: Array) -> Array[String]:
	var out: Array[String] = []
	for v in list:
		out.append(String(v))
	return out
