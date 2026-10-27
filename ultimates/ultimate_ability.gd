class_name UltimateAbility
extends RefCounted
## Base class for every ultimate. A new ultimate only needs to:
##   1. extend this class and override the _on_* hooks it needs,
##   2. add a config block to Config.ultimates (at least "cost" and "cast_time"),
##   3. register it in ultimate_registry.gd.
## Optional hooks: pay_cost() for special energy rules (e.g. "consume all"),
## and the ability-control contract (see Player.begin_ability_control) for
## abilities that take over movement.
##
## Lifecycle (driven by UltimateManager):
##   energy check -> player cast wind-up (cast_time) -> activate() -> step() each frame
##   -> the ability calls end(ctx) when it is finished.

var id := ""
var display_name := ""
var kind := "" ## Short label shown in the HUD and debug overlay.
var color := Color.WHITE
var icon := "" ## Symbol drawn by ui/ability_icon.gd ("nova", "volley", "ascend", "comet", "aegis", "stasis", "beam", "slam", "discharge").
var description := ""
## Fixed spells (Mana Discharge) belong to the neutral Spell input for good:
## they never appear in the equippable pool and cannot be unequipped.
var fixed := false
var is_running := false
## Multiplier on the energy cost, set by UltimateManager.register (gear:
## Player.stat("energy_cost_mul")).
var cost_scale: Callable = func() -> float: return 1.0


## Reads a live value from Config.ultimates[id].
func cfg(key: String) -> float:
	return float(Config.ultimates[id][key])


func get_cost() -> float:
	return cfg("cost") * cost_scale.call()


func get_cast_time() -> float:
	return cfg("cast_time")


## Takes the energy for one cast. `get_cost()` is the threshold shown on the
## HUD; the default spends exactly that. Return false (spending nothing) when
## the player cannot afford it. Override for special rules (RepulseAegis).
func pay_cost(health: HealthEnergy) -> bool:
	return health.spend_energy(get_cost())


## Override to add extra activation rules.
func can_activate(_ctx: UltimateContext) -> bool:
	return not is_running


func activate(ctx: UltimateContext) -> void:
	is_running = true
	_on_activate(ctx)


func step(delta: float, ctx: UltimateContext) -> void:
	if is_running:
		_on_step(delta, ctx)


func end(ctx: UltimateContext) -> void:
	if not is_running:
		return
	is_running = false
	_on_end(ctx)


## Called when the room or player resets. Default: end quietly.
func cancel(ctx: UltimateContext) -> void:
	end(ctx)


## Optional HUD text while running (e.g. remaining duration).
func status_text() -> String:
	return ""


func draw_world(_canvas: CanvasItem, _ctx: UltimateContext) -> void:
	pass


# ----- Hooks -----

func _on_activate(_ctx: UltimateContext) -> void:
	pass


func _on_step(_delta: float, _ctx: UltimateContext) -> void:
	pass


func _on_end(_ctx: UltimateContext) -> void:
	pass
