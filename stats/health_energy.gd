class_name HealthEnergy
extends Node
## Owns health, the single shared energy meter and invulnerability.
## It knows nothing about combat or input: other systems call its methods
## (gain_energy_from_hit, spend_energy, channel_heal...) and listen to Events.

var health := 100.0
var energy := 0.0
var iframe_timer := 0.0
## Named invulnerability sources, e.g. "dash", "cast", "ability".
var invuln_flags := {}
## Growth hooks for later upgrades (e.g. max-health items). Added to Config base values.
var max_health_bonus := 0.0
var max_energy_bonus := 0.0
## Extra multiplier for energy gain (wired to the owner's stat modifiers).
var energy_gain_source: Callable = func() -> float: return 1.0


func get_max_health() -> float:
	return Config.vitals.max_health + max_health_bonus


func get_max_energy() -> float:
	return Config.vitals.max_energy + max_energy_bonus


func reset() -> void:
	health = get_max_health()
	energy = 0.0
	iframe_timer = 0.0
	invuln_flags.clear()
	Events.energy_changed.emit(energy)


func step(delta: float) -> void:
	if iframe_timer > 0.0:
		iframe_timer -= delta
	# Keep values valid if max values are tweaked in the debug overlay.
	health = minf(health, get_max_health())
	energy = minf(energy, get_max_energy())


# ---------- Invulnerability ----------

func has_iframes() -> bool:
	return iframe_timer > 0.0


func is_invulnerable() -> bool:
	return iframe_timer > 0.0 or not invuln_flags.is_empty() or Config.upgrades.god_mode


func set_invulnerable(key: String, on: bool) -> void:
	if on:
		invuln_flags[key] = true
	else:
		invuln_flags.erase(key)


# ---------- Health ----------

func take_damage(amount: float) -> float:
	var applied := minf(amount, health)
	health -= applied
	iframe_timer = Config.vitals.iframe_duration
	Events.health_damaged.emit(applied)
	return applied


func heal(amount: float) -> float:
	var before := health
	health = clampf(health + amount, 0.0, get_max_health())
	var healed := health - before
	if healed > 0.0:
		Events.health_healed.emit(healed)
	return healed


func full_heal() -> void:
	heal(get_max_health())


func can_heal() -> bool:
	return health < get_max_health() and energy > 0.0


## Converts energy into health for one frame of channeling.
## Returns false when channeling must stop (full health or empty meter).
func channel_heal(delta: float) -> bool:
	if not can_heal():
		return false
	var spent := minf(energy, Config.vitals.heal_energy_per_second * delta)
	set_energy(energy - spent)
	heal(spent * Config.vitals.health_per_energy)
	return can_heal()


# ---------- Energy ----------

func set_energy(value: float) -> void:
	energy = clampf(value, 0.0, get_max_energy())
	Events.energy_changed.emit(energy)


func add_energy(amount: float) -> void:
	set_energy(energy + amount)


func gain_energy_from_hit(strength := 1.0) -> void:
	var v = Config.vitals
	add_energy(v.energy_per_hit * v.energy_gain_mul * energy_gain_source.call() * strength)


func can_afford(cost: float) -> bool:
	return energy >= cost - 0.0001


func spend_energy(cost: float) -> bool:
	if not can_afford(cost):
		return false
	set_energy(energy - cost)
	return true
