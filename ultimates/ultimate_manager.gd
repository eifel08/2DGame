class_name UltimateManager
extends Node2D
## Holds the registered ultimates, tracks which one is equipped, checks the
## energy cost, starts the cast wind-up and updates running abilities.
## Also draws ability visuals in world space.

var ctx: UltimateContext
var abilities: Array[UltimateAbility] = []
var active_index := 0


func setup(p_ctx: UltimateContext) -> void:
	ctx = p_ctx


func register(ability: UltimateAbility) -> void:
	abilities.append(ability)


func get_active() -> UltimateAbility:
	return abilities[active_index]


func cycle(step_by := 1) -> void:
	set_active_index(posmod(active_index + step_by, abilities.size()))


func set_active_by_id(ability_id: String) -> void:
	for i in abilities.size():
		if abilities[i].id == ability_id:
			set_active_index(i)
			return


func set_active_index(i: int) -> void:
	active_index = i
	Events.ultimate_changed.emit(get_active())


func step(delta: float) -> void:
	if ctx.input.was_pressed(&"ultimate"):
		try_activate()
	for ability in abilities:
		ability.step(delta, ctx)
	queue_redraw()


func try_activate() -> bool:
	var ability := get_active()
	var player := ctx.player
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
	for ability in abilities:
		if ability.is_running:
			ability.cancel(ctx)


func _draw() -> void:
	for ability in abilities:
		ability.draw_world(self, ctx)
