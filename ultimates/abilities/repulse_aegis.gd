class_name RepulseAegis
extends UltimateAbility
## COUNTER SHIELD: consumes ALL current energy (at least `cost`). While the
## shield holds, the next enemy hit (contact or projectile) is negated and
## the attacker takes `reflect_mul` x the energy consumed. One counter per
## cast; the shield fades after `duration` if nothing strikes.
## Built on Player.hit_guards, so combat code needs no special case.

const GUARD_ID := "repulse_aegis"

var consumed := 0.0 ## Energy taken by the last cast (the counter's fuel).
var stored := 0.0 ## Energy held by the running shield.
var remaining := 0.0
var last_reflected := 0.0 ## Damage dealt by the last counter (tests, debug).
var _ctx: UltimateContext


func _init() -> void:
	id = "repulse_aegis"
	display_name = "Repulse Aegis"
	kind = "Counter Shield"
	color = Color("#ffd166")
	icon = "aegis"
	description = "Pours all your energy into a shield. The next blow is negated and struck back at one and a half times the energy spent."


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
	remaining = cfg("duration")
	ctx.player.add_hit_guard(GUARD_ID, _guard)
	ctx.effects.play("ascendant_ring", ctx.player.get_center(), {"tint": color})
	Events.ultimate_impact.emit(0.03, 0.3)


func _on_step(delta: float, ctx: UltimateContext) -> void:
	remaining -= delta
	if remaining <= 0.0:
		end(ctx)


func _on_end(ctx: UltimateContext) -> void:
	ctx.player.remove_hit_guard(GUARD_ID)


## Hit guard: negate the hit and strike the attacker back.
func _guard(_damage: float, attacker: Node) -> bool:
	var p := _ctx.player
	last_reflected = stored * cfg("reflect_mul")
	if attacker is Enemy and attacker.hitbox_active():
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
	return true


func status_text() -> String:
	return "%.1fs" % remaining


func draw_world(canvas: CanvasItem, ctx: UltimateContext) -> void:
	if not is_running:
		return
	var c := ctx.player.get_center()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 110.0)
	var r := Player.HEIGHT * 0.85 + pulse * 2.0
	var points := PackedVector2Array()
	for i in 7: # Hexagon, closed.
		points.append(c + Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * r)
	canvas.draw_colored_polygon(points, Color(color, 0.12 + pulse * 0.06))
	canvas.draw_polyline(points, Color(color, 0.7), 2.5, true)
