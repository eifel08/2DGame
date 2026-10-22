class_name ManaDischarge
extends UltimateAbility
## THE NEUTRAL SPELL: the Spell button with no direction held. Fixed for
## good (never equipped, moved or removed; see PlayerData.NEUTRAL_SPELL).
##
## Always drains ALL current energy. With at least `cost` energy it releases
## a wave that grows to a radius scaled by the player's MAX energy
## (`radius_per_energy` x max energy, so energy upgrades widen it) and deals
## minimal damage (`damage`) to every enemy it passes, once each.
## With less than `cost` it still casts and still drains what is left, but
## FAILS: a small ring flickers and vanishes almost at once (`fizzle_time`),
## dealing no damage.

var t := 0.0
var radius := 0.0
var max_radius := 0.0
var origin := Vector2.ZERO
var hit_set := {}
var consumed := 0.0 ## Energy drained by the last cast.
var failed := false ## The last cast fizzled (not enough energy).


func _init() -> void:
	id = "mana_discharge"
	display_name = "Mana Discharge"
	kind = "Neutral"
	color = Color("#8fd6ff")
	icon = "discharge"
	fixed = true
	description = "Releases all your stored energy in a wave. The more energy you can hold, the wider it spreads. It barely hurts, and with too little energy it fizzles out."


## Never refused: drains everything. Below `cost` the cast fails.
func pay_cost(health: HealthEnergy) -> bool:
	consumed = health.energy
	failed = consumed < get_cost() - 0.0001
	health.set_energy(0.0)
	return true


## Full wave radius for a given maximum energy.
func wave_radius(max_energy: float) -> float:
	return cfg("radius_per_energy") * max_energy


func _on_activate(ctx: UltimateContext) -> void:
	t = 0.0
	radius = 0.0
	hit_set = {}
	origin = ctx.player.get_center()
	max_radius = cfg("fizzle_radius") if failed else wave_radius(ctx.player.health.get_max_energy())
	if not failed:
		Events.ultimate_impact.emit(0.03, 0.3)


func _duration() -> float:
	return cfg("fizzle_time") if failed else cfg("expand_time") + 0.15


func _on_step(delta: float, ctx: UltimateContext) -> void:
	t += delta
	var expand := cfg("fizzle_time") if failed else cfg("expand_time")
	var k := minf(1.0, t / expand)
	radius = (1.0 - pow(1.0 - k, 3.0)) * max_radius # Ease-out.
	if not failed:
		ctx.combat.damage_in_circle(origin, radius, {
			"damage": cfg("damage"), "knockback": 140.0, "source": id, "strength": 0.3,
		}, hit_set)
	if t >= _duration():
		end(ctx)


func draw_world(canvas: CanvasItem, _ctx: UltimateContext) -> void:
	if not is_running or radius <= 0.0:
		return
	var fade := maxf(0.0, 1.0 - t / _duration())
	if failed: # A thin, broken ring that is gone almost at once.
		for i in 6:
			var a := TAU * i / 6.0
			canvas.draw_arc(origin, radius, a, a + 0.6, 6, Color(color, fade * 0.6), 1.5, true)
		return
	canvas.draw_circle(origin, radius, Color(color, fade * 0.15))
	canvas.draw_arc(origin, radius, 0.0, TAU, 64, Color(Color("#e6f7ff"), fade), 3.0, true)
