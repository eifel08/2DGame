class_name AscendantForm
extends UltimateAbility
## TRANSFORMATION / BUFF STATE: for a duration the player deals more damage,
## moves faster and swings wider. Built purely on stat modifiers, so movement
## and combat code need no special cases.

const MODIFIER_ID := "ascendant_form"

var remaining := 0.0
var spark_timer := 0.0


func _init() -> void:
	id = "ascendant_form"
	display_name = "Ascendant Form"
	kind = "Transformation"
	color = Color("#d6a8ff")
	icon = "ascend"
	description = "Temporary empowered state: more damage, speed and reach."


func _on_activate(ctx: UltimateContext) -> void:
	remaining = cfg("duration")
	spark_timer = 0.0
	ctx.player.add_modifier(MODIFIER_ID, {
		"damage_mul": cfg("damage_mul"),
		"speed_mul": cfg("speed_mul"),
		"attack_range_mul": cfg("range_mul"),
		"energy_gain_mul": 0.5, # Balance: slower meter gain while empowered.
	})
	Events.ultimate_impact.emit(0.1, 0.6)
	ctx.effects.play("ascendant_ring", ctx.player.get_center(), {"tint": color})


func _on_step(delta: float, ctx: UltimateContext) -> void:
	var p := ctx.player
	remaining -= delta
	spark_timer -= delta
	if spark_timer <= 0.0:
		spark_timer = 0.04
		ctx.effects.play("ascendant_spark", p.global_position + Vector2(randf_range(-11, 11), 0), {"tint": color})
	if remaining <= 0.0:
		end(ctx)


func _on_end(ctx: UltimateContext) -> void:
	ctx.player.remove_modifier(MODIFIER_ID)


func status_text() -> String:
	return "%.1fs" % remaining


func draw_world(canvas: CanvasItem, ctx: UltimateContext) -> void:
	if not is_running:
		return
	var p := ctx.player
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
	var c := p.get_center()
	var rx := Player.WIDTH * 1.1 + pulse * 3.0
	var ry := Player.HEIGHT * 0.75 + pulse * 3.0
	var points := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		points.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	canvas.draw_polyline(points, Color(color, 0.25 + pulse * 0.2), 3.0, true)
