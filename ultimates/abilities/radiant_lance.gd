class_name RadiantLance
extends UltimateAbility
## BEAM: a long piercing beam fired forward, or straight up while Up is
## held. It stops at the first wall, lasts `duration` and hits each enemy
## along it once.

var t := 0.0
var dir := Vector2.RIGHT
var origin := Vector2.ZERO
var length := 0.0
var hit_set := {}


func _init() -> void:
	id = "radiant_lance"
	display_name = "Radiant Lance"
	kind = "Beam"
	color = Color("#f783ac")
	icon = "beam"
	description = "Fires a piercing beam of energy ahead, or straight up while aiming up. It stops at walls."


func _on_activate(ctx: UltimateContext) -> void:
	t = 0.0
	hit_set = {}
	dir = Vector2.UP if ctx.input.axis_y() < 0.0 else Vector2(ctx.player.facing, 0.0)
	_aim(ctx)
	ctx.effects.play("volley_muzzle", origin, {"tint": color, "scale": 1.6})
	Events.ultimate_impact.emit(0.05, 0.5)


func _on_step(delta: float, ctx: UltimateContext) -> void:
	t += delta
	_aim(ctx) # The beam stays anchored to the player.
	ctx.combat.damage_in_rect(beam_rect(), {
		"damage": cfg("damage"), "knockback": 300.0, "dir_y": -0.4 if dir.y < 0.0 else 0.0,
		"source": id, "strength": 0.8,
	}, hit_set)
	if t >= cfg("duration"):
		end(ctx)


## Origin at the player's chest; length clipped at the first solid tile.
func _aim(ctx: UltimateContext) -> void:
	origin = ctx.player.get_center() + dir * 8.0
	var room := ctx.combat.get_room()
	var max_len := cfg("length")
	length = 0.0
	while length < max_len and not room.is_solid_at(origin + dir * length):
		length += 8.0
	length = minf(length, max_len)


## World-space rectangle covered by the beam.
func beam_rect() -> Rect2:
	var w := cfg("width")
	var tip := origin + dir * length
	var r := Rect2(origin, Vector2.ZERO).expand(tip)
	return r.grow_individual(w / 2.0 if dir.y != 0.0 else 0.0, w / 2.0 if dir.x != 0.0 else 0.0,
		w / 2.0 if dir.y != 0.0 else 0.0, w / 2.0 if dir.x != 0.0 else 0.0)


func draw_world(canvas: CanvasItem, _ctx: UltimateContext) -> void:
	if not is_running:
		return
	var fade := 1.0 - t / cfg("duration")
	var r := beam_rect()
	canvas.draw_rect(r.grow(4.0), Color(color, 0.25 * fade))
	canvas.draw_rect(r, Color(color, 0.75 * fade))
	var core := r.grow_individual(-r.size.x * 0.3 if dir.y != 0.0 else 0.0, -r.size.y * 0.3 if dir.x != 0.0 else 0.0,
		-r.size.x * 0.3 if dir.y != 0.0 else 0.0, -r.size.y * 0.3 if dir.x != 0.0 else 0.0)
	canvas.draw_rect(core, Color(1, 1, 1, fade))
