class_name UltimateManager
extends Node2D
## Owns every known ultimate and the 4 hotkey slots (ult_1 .. ult_4).
## Checks the energy cost, starts the cast wind-up and updates running
## abilities. Loadout changes are only allowed at a checkpoint.
## Also draws ability visuals in world space.

const SLOT_ACTIONS: Array[StringName] = [&"ult_1", &"ult_2", &"ult_3", &"ult_4"]

var ctx: UltimateContext
var data: PlayerData
var abilities := {} ## id -> UltimateAbility


func setup(p_ctx: UltimateContext, p_data: PlayerData) -> void:
	ctx = p_ctx
	data = p_data


func register(ability: UltimateAbility) -> void:
	abilities[ability.id] = ability


func get_ability(ability_id: String) -> UltimateAbility:
	return abilities.get(ability_id)


## Ability in a hotkey slot, or null when the slot is empty.
func get_slot(slot: int) -> UltimateAbility:
	return abilities.get(data.equipped[slot])


func slot_of(ability_id: String) -> int:
	return data.equipped.find(ability_id)


func unlocked_abilities() -> Array[UltimateAbility]:
	var list: Array[UltimateAbility] = []
	for ability_id in data.unlocked:
		if abilities.has(ability_id):
			list.append(abilities[ability_id])
	return list


# ---------- Loadout ----------

func can_change_loadout() -> bool:
	return ctx.player.at_checkpoint


## Equips an unlocked ability into a slot. Refused away from checkpoints
## unless `force` is set (debug tools only).
func equip(slot: int, ability_id: String, force := false) -> bool:
	if not force and not can_change_loadout():
		return false
	if not data.is_unlocked(ability_id) or slot < 0 or slot >= SLOT_ACTIONS.size():
		return false
	data.equip(slot, ability_id)
	Events.loadout_changed.emit()
	return true


# ---------- Activation ----------

func step(delta: float) -> void:
	for slot in SLOT_ACTIONS.size():
		if ctx.input.was_pressed(SLOT_ACTIONS[slot]):
			try_activate(slot)
	for ability in abilities.values():
		ability.step(delta, ctx)
	queue_redraw()


func try_activate(slot: int) -> bool:
	var ability := get_slot(slot)
	var player := ctx.player
	if ability == null:
		Events.ultimate_denied.emit(null, "empty")
		return false
	if not player.can_cast() or not ability.can_activate(ctx):
		Events.ultimate_denied.emit(ability, "busy")
		return false
	if not player.health.spend_energy(ability.get_cost()):
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
