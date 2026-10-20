class_name SpiritVolley
extends UltimateAbility
## PROJECTILE BURST: fires a fan of homing spirit bolts in quick succession.

var fired := 0
var timer := 0.0
var facing := 1


func _init() -> void:
	id = "spirit_volley"
	display_name = "Spirit Volley"
	kind = "Projectile Burst"
	color = Color("#7cf3ff")
	icon = "volley"
	description = "Releases a fan of homing bolts that seek the nearest enemies."


func _on_activate(ctx: UltimateContext) -> void:
	fired = 0
	timer = 0.0
	facing = ctx.player.facing
	Events.ultimate_impact.emit(0.03, 0.25)


func _on_step(delta: float, ctx: UltimateContext) -> void:
	var count := int(cfg("count"))
	var origin := ctx.player.get_center() + Vector2(0, -6)
	timer -= delta
	while timer <= 0.0 and fired < count:
		# Fan from "up and slightly back" to "forward".
		var k := float(fired) / (count - 1) if count > 1 else 0.5
		var local := lerpf(-2.0, 0.2, k)
		var angle := local if facing > 0 else PI - local
		ctx.combat.projectiles.spawn({
			"position": origin,
			"velocity": Vector2.from_angle(angle) * cfg("speed"),
			"damage": cfg("damage"),
			"homing": cfg("homing"),
			"delay": 0.12,
			"color": color,
			"source": id,
		})
		ctx.effects.burst(origin, {"count": 3, "color": color, "speed": 120.0, "gravity": 0.0, "life": 0.2, "size": 3.0})
		fired += 1
		timer += cfg("interval")
	if fired >= count:
		end(ctx)
