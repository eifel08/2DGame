class_name RepulseAegis
extends UltimateAbility
## COUNTER (PARRY): consumes ALL current energy (at least `cost`) and opens a
## very short counter window (`window`, no wind-up). If an enemy touches the
## player inside that window, its contact damage is negated and it takes
## `reflect_mul` x the energy consumed. Timing is everything: cast it right
## before contact. A whiff wastes the energy.
##
## Enemy contact only (Damage.Source.ENEMY). Projectiles are never blocked or
## reflected: they hurt as usual. Range is tiny: the enemy must touch the
## player's body, or come within `counter_range` px of it.
## Built on Player.hit_guards, so combat code needs no special case.

const GUARD_ID := "repulse_aegis"

var consumed := 0.0 ## Energy taken by the last cast (the counter's fuel).
var stored := 0.0 ## Energy held by the open window.
var remaining := 0.0
var last_reflected := 0.0 ## Damage dealt by the last counter (tests, debug).
var countered := false ## The last cast landed its counter (tests, debug).
var _ctx: UltimateContext


func _init() -> void:
	id = "repulse_aegis"
	display_name = "Repulse Aegis"
	kind = "Counter"
	color = Color("#ffd166")
	icon = "aegis"
	description = "Pours all your energy into an instant parry. Time it just before an enemy touches you: the blow is negated and struck back at one and a half times the energy spent. Projectiles pass through."


## `cost` is only the minimum: the whole meter is consumed.
func pay_cost(health: HealthEnergy) -> bool:
	if not health.can_afford(get_cost()):
		return false
	consumed = health.energy
	health.set_energy(0.0)
	return true


func _on_activate(ctx: UltimateContext) -> void:
	_ctx = ctx
	stored = consumed
	remaining = cfg("window")
	countered = false
	ctx.player.add_hit_guard(GUARD_ID, _guard)
	Events.ultimate_impact.emit(0.0, 0.15)


func _on_step(delta: float, ctx: UltimateContext) -> void:
	# An enemy at the player's skin also triggers the counter, even if the
	# player still has i-frames and the contact hit itself never arrives.
	var reach := ctx.player.get_rect().grow(cfg("counter_range"))
	for enemy in ctx.combat.get_enemies():
		if enemy.deals_contact_damage() and reach.intersects(enemy.get_rect()):
			_counter(enemy)
			return
	remaining -= delta
	if remaining <= 0.0:
		end(ctx)


func _on_end(ctx: UltimateContext) -> void:
	ctx.player.remove_hit_guard(GUARD_ID)


## Hit guard: only enemy contact is countered; projectiles go through.
func _guard(_damage: float, attacker: Node, source: Damage.Source) -> bool:
	if source != Damage.Source.ENEMY or not attacker is Enemy:
		return false
	_counter(attacker)
	return true


func _counter(attacker: Enemy) -> void:
	var p := _ctx.player
	last_reflected = stored * cfg("reflect_mul")
	countered = true
	if attacker.hitbox_active():
		var dx := signf(attacker.get_center().x - p.get_center().x)
		_ctx.combat.apply_damage(attacker, {
			"damage": last_reflected,
			"direction": Vector2(dx if dx != 0.0 else float(p.facing), -0.3),
			"knockback": 520.0,
			"source": id,
			"strength": 1.0,
		})
	# Short grace so overlapping enemies cannot hit right after the counter.
	p.health.iframe_timer = maxf(p.health.iframe_timer, cfg("guard_iframes"))
	_ctx.effects.play("comet_impact", p.get_center(), {"tint": color, "scale": 0.9})
	Events.ultimate_impact.emit(0.08, 0.6)
	end(_ctx)


func status_text() -> String:
	return "%.2fs" % remaining


func draw_world(canvas: CanvasItem, ctx: UltimateContext) -> void:
	if not is_running:
		return
	var c := ctx.player.get_center()
	var k := remaining / cfg("window") # The hexagon closes in as the window runs out.
	var r := Player.HEIGHT * (0.55 + 0.35 * k)
	var points := PackedVector2Array()
	for i in 7: # Hexagon, closed.
		points.append(c + Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * r)
	canvas.draw_colored_polygon(points, Color(color, 0.25))
	canvas.draw_polyline(points, Color(color, 0.9), 3.0, true)
