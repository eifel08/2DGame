class_name NovaBurst
extends UltimateAbility
## AREA-OF-EFFECT BLAST: an expanding shockwave centered on the player.
## Each enemy is hit once as the ring passes over it.

var t := 0.0
var radius := 0.0
var origin := Vector2.ZERO
var hit_set := {}


func _init() -> void:
	id = "nova_burst"
	display_name = "Nova Burst"
	kind = "AoE Blast"
	color = Color("#ffb347")
	description = "Expanding shockwave that damages and repels everything nearby."


func _on_activate(ctx: UltimateContext) -> void:
	t = 0.0
	radius = 0.0
	origin = ctx.player.get_center()
	hit_set = {}
	Events.ultimate_impact.emit(0.06, 0.7)
	ctx.effects.burst(origin, {"count": 40, "color": color, "speed": 520.0, "size": 5.0, "gravity": 0.0, "life": 0.45})


func _on_step(delta: float, ctx: UltimateContext) -> void:
	t += delta
	var k := minf(1.0, t / cfg("expand_time"))
	radius = (1.0 - pow(1.0 - k, 3.0)) * cfg("radius") # Ease-out.
	ctx.combat.damage_in_circle(origin, radius, {
		"damage": cfg("damage"), "knockback": 420.0, "source": id, "strength": 0.9,
	}, hit_set)
	if t >= cfg("expand_time") + 0.2:
		end(ctx)


func draw_world(canvas: CanvasItem, _ctx: UltimateContext) -> void:
	if not is_running or radius <= 0.0:
		return
	var fade := maxf(0.0, 1.0 - t / (cfg("expand_time") + 0.2))
	canvas.draw_circle(origin, radius, Color(color, fade * 0.25))
	canvas.draw_arc(origin, radius, 0.0, TAU, 64, Color(Color("#fff1d0"), fade), 6.0, true)
