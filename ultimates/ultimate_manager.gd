class_name UltimateManager
extends Node2D
## Owns every registered spell and the spell loadout. One Spell button
## (action "spell") plus the held direction picks what is cast:
##   no direction        Mana Discharge (PlayerData.NEUTRAL_SPELL), fixed for good
##   Up                  the Up slot
##   Down                the Down slot
##   Left / Right        the Side slot, cast toward that side (the player turns)
## Up wins over Down, and both win over Left / Right. An empty slot casts
## nothing (it never falls back to the neutral spell). So does a LOCKED
## slot: a new game starts with every directional slot locked and no
## equippable spell known. Spell Scrolls teach spells (learn), Meditation
## Altars open slots (open_slot).
## Checks the energy cost, starts the cast wind-up and updates running
## spells. Loadout changes are only allowed at a checkpoint.
## Also draws spell visuals in world space.

const SPELL_ACTION := &"spell"
const NEUTRAL := -1 ## Slot index used for the neutral spell.

var ctx: UltimateContext
var data: PlayerData
var abilities := {} ## id -> UltimateAbility


func setup(p_ctx: UltimateContext, p_data: PlayerData) -> void:
	ctx = p_ctx
	data = p_data


func register(ability: UltimateAbility) -> void:
	abilities[ability.id] = ability
	ability.cost_scale = func() -> float: return ctx.player.stat("energy_cost_mul") if ctx else 1.0


func get_ability(ability_id: String) -> UltimateAbility:
	return abilities.get(ability_id)


## Number of directional slots (Up, Side, Down).
func slot_count() -> int:
	return PlayerData.SLOT_COUNT


## Spell in a slot: NEUTRAL gives Mana Discharge; a directional slot gives
## its spell, or null when it is empty.
func get_slot(slot: int) -> UltimateAbility:
	if slot == NEUTRAL:
		return abilities.get(PlayerData.NEUTRAL_SPELL)
	if not data.is_slot_open(slot):
		return null
	return abilities.get(data.equipped[slot])


func neutral_spell() -> UltimateAbility:
	return get_slot(NEUTRAL)


## Slot of a spell: NEUTRAL for the fixed spell, -2 when not equipped.
func slot_of(ability_id: String) -> int:
	if ability_id == PlayerData.NEUTRAL_SPELL:
		return NEUTRAL
	var slot := data.equipped.find(ability_id)
	return slot if slot != -1 else -2


## The equippable spells the player knows (the fixed neutral spell is not
## in this pool: it can never be moved).
func unlocked_abilities() -> Array[UltimateAbility]:
	var list: Array[UltimateAbility] = []
	for ability_id in data.unlocked:
		if abilities.has(ability_id) and not abilities[ability_id].fixed:
			list.append(abilities[ability_id])
	return list


## The slot the held direction selects (see the class comment).
static func slot_for_input(axis_x: int, axis_y: int) -> int:
	if axis_y < 0:
		return PlayerData.SLOT_UP
	if axis_y > 0:
		return PlayerData.SLOT_DOWN
	if axis_x != 0:
		return PlayerData.SLOT_SIDE
	return NEUTRAL


# ---------- Loadout ----------

func can_change_loadout() -> bool:
	return ctx.player.at_checkpoint


## Equips an unlocked spell into a directional slot. Refused away from
## checkpoints unless `force` is set (debug tools only), and always refused
## for the fixed neutral spell.
func equip(slot: int, ability_id: String, force := false) -> bool:
	if not force and not can_change_loadout():
		return false
	var ability := get_ability(ability_id)
	if ability == null or ability.fixed or not data.is_unlocked(ability_id):
		return false
	if not data.equip(slot, ability_id):
		return false
	Events.loadout_changed.emit()
	return true


func is_slot_open(slot: int) -> bool:
	return slot == NEUTRAL or data.is_slot_open(slot)


## Opens a locked directional slot for good (Meditation Altars). Works
## anywhere: it is progression, not a loadout change.
func open_slot(slot: int) -> bool:
	if not data.open_slot(slot):
		return false
	Events.spell_slot_opened.emit(slot)
	Events.loadout_changed.emit()
	return true


## Teaches an equippable spell for good (Spell Scrolls). Returns false if it
## was already known or cannot be learned (unknown id, the fixed spell).
func learn(ability_id: String) -> bool:
	if not abilities.has(ability_id) or abilities[ability_id].fixed or data.is_unlocked(ability_id):
		return false
	data.unlock(ability_id)
	Events.spell_learned.emit(ability_id)
	Events.loadout_changed.emit()
	return true


## Empties a directional slot. Same checkpoint rule. The neutral slot
## (Mana Discharge) can never be emptied.
func unequip(slot: int, force := false) -> bool:
	if not force and not can_change_loadout():
		return false
	if slot < 0 or slot >= PlayerData.SLOT_COUNT:
		return false
	data.unequip(slot)
	Events.loadout_changed.emit()
	return true


# ---------- Spell pool (debug tools, future progression) ----------

## Adds a spell to the known pool, or removes it (and empties its slot).
## The fixed neutral spell is always known.
func set_known(ability_id: String, known: bool) -> void:
	if not abilities.has(ability_id) or abilities[ability_id].fixed:
		return
	if known:
		data.unlock(ability_id)
	else:
		data.lock(ability_id)
	Events.loadout_changed.emit()


## Debug: fills the empty open slots with known, unequipped spells.
func auto_equip() -> void:
	for ability in unlocked_abilities():
		if slot_of(ability.id) >= 0:
			continue
		var free := -1
		for slot in PlayerData.SLOT_COUNT:
			if data.is_slot_open(slot) and data.equipped[slot] == "":
				free = slot
				break
		if free == -1:
			break
		data.equip(free, ability.id)
	Events.loadout_changed.emit()


# ---------- Activation ----------

func step(delta: float) -> void:
	if ctx.input.was_pressed(SPELL_ACTION):
		var ix := ctx.input.axis_x()
		var slot := slot_for_input(ix, ctx.input.axis_y())
		if slot == PlayerData.SLOT_SIDE and ctx.player.can_cast():
			ctx.player.facing = ix # Side spells go toward the held side.
		try_activate(slot)
	for ability in abilities.values():
		ability.step(delta, ctx)
	queue_redraw()


func try_activate(slot: int) -> bool:
	var ability := get_slot(slot)
	var player := ctx.player
	if ability == null:
		Events.ultimate_denied.emit(null, "empty" if is_slot_open(slot) else "locked")
		return false
	if not player.can_cast() or not ability.can_activate(ctx):
		Events.ultimate_denied.emit(ability, "busy")
		return false
	if not ability.pay_cost(player.health):
		Events.ultimate_denied.emit(ability, "energy")
		return false
	Events.ultimate_cast.emit(ability)
	player.start_cast(ability.get_cast_time(), func() -> void: ability.activate(ctx))
	return true


func cancel_all() -> void:
	for ability in abilities.values():
		if ability.is_running:
			ability.cancel(ctx)


func _draw() -> void:
	for ability in abilities.values():
		ability.draw_world(self, ctx)
