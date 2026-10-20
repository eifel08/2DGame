class_name CometDash
extends UltimateAbility
## MOBILITY-COMBAT HYBRID: an 8-directional invulnerable charge that damages
## everything on its path and ends with a small explosion. It takes over the
## player's movement through Player.begin_ability_control(self).

var invulnerable := true ## Read by the player's ability state.
var dir := Vector2.RIGHT
var time_left := 0.0
var hit_set := {}
var cancelled := false
var _ctx: UltimateContext


func _init() -> void:
	id = "comet_dash"
	display_name = "Comet Dash"
	kind = "Mobility Strike"
	color = Color("#ff7a59")
	icon = "comet"
	description = "Aimable invulnerable charge that pierces enemies, then detonates."


func _on_activate(ctx: UltimateContext) -> void:
	_ctx = ctx
	var aim := Vector2(ctx.input.axis_x(), ctx.input.axis_y())
	if aim == Vector2.ZERO:
		aim = Vector2(ctx.player.facing, 0)
	dir = aim.normalized()
	if aim.x != 0.0:
		ctx.player.facing = int(signf(aim.x))
	hit_set = {}
	cancelled = false
	ctx.player.begin_ability_control(self)


# ----- Ability-control contract (called by the player's AbilityState) -----

func control_start(_player: Player) -> void:
	time_left = cfg("duration")


func control_step(delta: float, player: Player) -> bool:
	player.velocity = dir * cfg("speed")
	player.move(delta)
	_ctx.combat.damage_in_rect(player.get_rect().grow(10.0), {
		"damage": cfg("damage"), "knockback": 380.0, "dir_y": -0.3, "source": id, "strength": 0.7,
	}, hit_set)
	time_left -= delta
	var blocked := player.is_on_wall() \
		or (dir.y < 0.0 and player.is_on_ceiling()) \
		or (dir.y > 0.0 and player.is_on_floor())
	return time_left <= 0.0 or blocked


func control_finish(player: Player) -> void:
	if cancelled:
		return
	_detonate(player)
	# Exit with controllable momentum instead of full ability speed.
	player.velocity = Vector2(dir.x * Config.movement.max_run_speed, -320.0 if dir.y < 0.0 else 0.0)
	end(_ctx)


func _detonate(player: Player) -> void:
	var c := player.get_center()
	_ctx.combat.damage_in_circle(c, cfg("burst_radius"), {
		"damage": cfg("burst_damage"), "knockback": 300.0, "source": id, "strength": 0.6,
	})
	_ctx.effects.ring(c, {"radius": cfg("burst_radius"), "color": color, "width": 6.0, "life": 0.3})
	_ctx.effects.burst(c, {"count": 22, "color": color, "speed": 360.0, "gravity": 200.0, "life": 0.35, "size": 4.0})
	Events.ultimate_impact.emit(0.05, 0.45)


func cancel(_ctx_unused: UltimateContext) -> void:
	# A reset exits the ability state, which calls control_finish(): skip the blast.
	cancelled = true
	is_running = false
