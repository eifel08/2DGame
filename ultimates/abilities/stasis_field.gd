class_name StasisField
extends UltimateAbility
## EMERGENCY ESCAPE: a near-instant, short-range pulse that freezes every
## enemy and hostile projectile within `radius` (small) for `duration`
## (short). It is a last-second reaction to slip out of danger, not area
## control. Frozen enemies stop moving and thinking, deal no contact damage,
## and can still be hit. Frozen projectiles hang in the air, harmless, then
## fly on.

var t := 0.0
var origin := Vector2.ZERO
var frozen_enemies := 0 ## Counts from the last cast (tests, debug).
var frozen_projectiles := 0


func _init() -> void:
	id = "stasis_field"
	display_name = "Stasis Field"
	kind = "Emergency Escape"
	color = Color("#74c0fc")
	icon = "stasis"
	description = "A split-second cold pulse that freezes enemies and projectiles right next to you. Use it to escape at the last moment."


func _on_activate(ctx: UltimateContext) -> void:
	t = 0.0
	origin = ctx.player.get_center()
	var radius := cfg("radius")
	var duration := cfg("duration")
	frozen_enemies = 0
	for enemy in ctx.combat.get_enemies():
		if enemy.hitbox_active() and Geom.circle_overlaps_rect(origin, radius, enemy.get_rect()):
			enemy.freeze(duration)
			frozen_enemies += 1
	frozen_projectiles = ctx.combat.projectiles.freeze_in_circle(origin, radius, duration)
	ctx.effects.play("nova_burst", origin, {"tint": color})
	Events.ultimate_impact.emit(0.04, 0.35)


func _on_step(delta: float, ctx: UltimateContext) -> void:
	t += delta
	if t >= cfg("duration"):
		end(ctx)


func status_text() -> String:
	return "%.1fs" % maxf(0.0, cfg("duration") - t)


func draw_world(canvas: CanvasItem, _ctx: UltimateContext) -> void:
	if not is_running:
		return
	var radius := cfg("radius")
	var k := t / cfg("duration")
	var grow := minf(1.0, t / 0.15) # The pulse snaps open, then lingers.
	var fade := 1.0 - k
	canvas.draw_circle(origin, radius * grow, Color(color, 0.1 * fade))
	canvas.draw_arc(origin, radius * grow, 0.0, TAU, 64, Color(color, 0.6 * fade), 2.0, true)
	for i in 6: # Frost spokes.
		var dir := Vector2.from_angle(TAU * i / 6.0 + k * 0.6)
		canvas.draw_line(origin + dir * radius * 0.2 * grow, origin + dir * radius * 0.9 * grow, Color(color, 0.25 * fade), 1.5, true)
