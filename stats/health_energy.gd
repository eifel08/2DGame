class_name HealthEnergy
extends Node
## Owns health, the single shared energy meter and invulnerability.
## It knows nothing about combat or input: other systems call its methods
## (gain_energy_from_hit, spend_energy, channel_heal_chunk...) and listen to Events.

## Maximum stats. Set them in the Inspector (player.tscn > HealthEnergy)
## or in code; upgrades add on top through the bonus fields below.
## The player starts LOW (STARTING_MAX_*): Health Potions, Mana Potions and
## relics raise the maximums for good (max_health_bonus / max_energy_bonus).
const STARTING_MAX_HEALTH := 50.0
const STARTING_MAX_ENERGY := 50.0
@export_group("Max stats")
@export_range(1.0, 1000.0, 1.0) var base_max_health := STARTING_MAX_HEALTH
@export_range(1.0, 1000.0, 1.0) var base_max_energy := STARTING_MAX_ENERGY
@export_group("")

var health := STARTING_MAX_HEALTH
var energy := 0.0
var iframe_timer := 0.0
## Named invulnerability sources, e.g. "dash", "cast", "ability".
var invuln_flags := {}
## Growth from upgrades (potions, relics). Added to the base values and saved.
var max_health_bonus := 0.0
var max_energy_bonus := 0.0
## Extra multiplier for energy gain (wired to the owner's stat modifiers).
var energy_gain_source: Callable = func() -> float: return 1.0
## The owner's stat lookup (Player.stat): "energy_cost_mul" scales the heal
## chunk cost, "energy_leak_mul" the passive leak. Gear (pouch curses) sets them.
var stat_source: Callable = func(_key: String) -> float: return 1.0


func get_max_health() -> float:
	return base_max_health + max_health_bonus


func get_max_energy() -> float:
	return base_max_energy + max_energy_bonus


## Changes a maximum for good (future upgrades). Current values are kept
## within the new limits.
func set_base_max_health(value: float) -> void:
	base_max_health = maxf(1.0, value)
	health = minf(health, get_max_health())


func set_base_max_energy(value: float) -> void:
	base_max_energy = maxf(1.0, value)
	set_energy(minf(energy, get_max_energy()))


func reset() -> void:
	health = get_max_health()
	energy = 0.0
	iframe_timer = 0.0
	invuln_flags.clear()
	pending_heal = 0.0
	Events.energy_changed.emit(energy)


func step(delta: float) -> void:
	if iframe_timer > 0.0:
		iframe_timer -= delta
	# Passive leak (Config.vitals.energy_leak_rate, 0 = none), scaled by gear.
	var leak: float = Config.vitals.energy_leak_rate * stat_source.call("energy_leak_mul")
	if leak > 0.0 and energy > 0.0:
		set_energy(energy - leak * delta)
	# Keep values valid if max values are tweaked in the debug overlay.
	health = minf(health, get_max_health())
	energy = minf(energy, get_max_energy())


# ---------- Invulnerability ----------

func has_iframes() -> bool:
	return iframe_timer > 0.0


func is_invulnerable() -> bool:
	return iframe_timer > 0.0 or not invuln_flags.is_empty() or Config.upgrades.god_mode


## True when damage from `source` (Damage.Source) is prevented right now.
## Enemies and projectiles respect i-frames and invulnerability; hazards
## (spikes, lava, acid) ignore them all. Only the debug God Mode stops those.
func blocks(source: Damage.Source) -> bool:
	if source == Damage.Source.HAZARD:
		return Config.upgrades.god_mode
	return is_invulnerable()


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


# ---------- Chunk healing ----------
# Healing comes in whole chunks. While a chunk channels, energy drains and the
# health it will give shows as `pending_heal` (the white segment on the bar).
# Only a completed chunk turns pending health into real health; an
# interrupted chunk loses the drained energy and restores nothing.

var pending_heal := 0.0 ## Health shown in white while a chunk is channeling.
var _chunk_drained := 0.0


## Energy one heal chunk drains (Config.vitals.heal_chunk_energy, scaled by gear).
func heal_chunk_cost() -> float:
	return Config.vitals.heal_chunk_energy * stat_source.call("energy_cost_mul")


func can_start_heal_chunk() -> bool:
	return health < get_max_health() and energy >= heal_chunk_cost() - 0.0001


func start_heal_chunk() -> void:
	pending_heal = 0.0
	_chunk_drained = 0.0


## Advances the current chunk to `progress` (0..1), draining energy in step.
func channel_heal_chunk(progress: float) -> void:
	var v = Config.vitals
	var target_drain: float = heal_chunk_cost() * clampf(progress, 0.0, 1.0)
	var drain := minf(target_drain - _chunk_drained, energy)
	if drain > 0.0:
		_chunk_drained += drain
		set_energy(energy - drain)
	pending_heal = minf(v.heal_chunk_health * clampf(progress, 0.0, 1.0), get_max_health() - health)


## The chunk finished: pending health becomes real health.
func complete_heal_chunk() -> float:
	var amount := heal(Config.vitals.heal_chunk_health)
	pending_heal = 0.0
	_chunk_drained = 0.0
	return amount


## The chunk was interrupted: the energy is gone and nothing is restored.
func cancel_heal_chunk() -> void:
	pending_heal = 0.0
	_chunk_drained = 0.0


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
