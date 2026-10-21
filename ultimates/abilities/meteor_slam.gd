class_name MeteorSlam
extends UltimateAbility
## DIVE STRIKE: the player plunges straight down, invulnerable, hitting
## anything on the way, then slams the ground in a wide shockwave. Brief
## i-frames follow the landing. Takes over movement through
## Player.begin_ability_control(self), like Comet Dash.
##
## Cast on the ground, the player first makes a small hop upward (`hop`
## phase). The hop is a VULNERABLE wind-up: a hit interrupts it and no slam
## follows. At the top of the hop the invulnerable dive starts. Cast in the
## air, the dive starts at once.

var invulnerable := true ## Read every step by the player's ability state: false while hopping.
var phase := "dive" ## "hop" (ground wind-up) or "dive".
var hop_left := 0.0
var time_left := 0.0
var hit_set := {}
var cancelled := false
var slam_count := 0 ## Completed slams (tests, debug).
var _ctx: UltimateContext


func _init() -> void:
	id = "meteor_slam"
	display_name = "Meteor Slam"
	kind = "Dive Strike"
	color = Color("#8ce99a")
	icon = "slam"
	description = "Plunge straight down, untouchable, and smash the ground in a wide shockwave. From the ground you hop up first, and the hop leaves you open."


func _on_activate(ctx: UltimateContext) -> void:
	_ctx = ctx
	hit_set = {}
	cancelled = false
	ctx.player.begin_ability_control(self)


# ----- Ability-control contract (called by the player's AbilityState) -----

func control_start(player: Player) -> void:
	if player.grounded:
		phase = "hop"
		invulnerable = false
		hop_left = cfg("hop_time")
		player.velocity = Vector2(0.0, -cfg("hop_velocity"))
		player.grounded = false
		Events.player_jumped.emit(player, "slam_hop")
	else:
		_start_dive()


func _start_dive() -> void:
	phase = "dive"
	invulnerable = true
	time_left = cfg("max_time")


func control_step(delta: float, player: Player) -> bool:
	if phase == "hop":
		# Rise and slow down under gravity; dive at the top (or on a ceiling).
		player.velocity.x = 0.0
		player.velocity.y += Config.movement.gravity * delta
		player.move(delta)
		hop_left -= delta
		if player.velocity.y >= 0.0 or hop_left <= 0.0 or player.is_on_ceiling():
			_start_dive()
		return false
	player.velocity = Vector2(0.0, cfg("speed"))
	player.move(delta)
	_ctx.combat.damage_in_rect(player.get_rect().grow(8.0), {
		"damage": cfg("dive_damage"), "knockback": 200.0, "dir_y": 1.0, "source": id, "strength": 0.5,
	}, hit_set)
	time_left -= delta
	return player.is_on_floor() or time_left <= 0.0


func control_finish(player: Player) -> void:
	# A reset, a hit during the hop or a hazard teleport ends it early: no slam then.
	if cancelled or phase == "hop" or (time_left > 0.0 and not player.is_on_floor()):
		end(_ctx)
		return
	_slam(player)
	player.velocity = Vector2.ZERO
	player.health.iframe_timer = maxf(player.health.iframe_timer, cfg("land_iframes"))
	end(_ctx)


func _slam(player: Player) -> void:
	var feet := player.global_position
	var r := cfg("slam_radius")
	_ctx.combat.damage_in_rect(Rect2(feet.x - r, feet.y - r * 0.5, r * 2.0, r * 0.5 + 6.0), {
		"damage": cfg("slam_damage"), "knockback": 460.0, "dir_y": -0.7, "source": id, "strength": 0.9,
	})
	_ctx.effects.play("comet_impact", feet, {"tint": color, "scale": r / 100.0})
	_ctx.effects.play("land_dust", feet, {"scale": 2.0})
	Events.ultimate_impact.emit(0.07, 0.8)
	slam_count += 1


func cancel(_ctx_unused: UltimateContext) -> void:
	# A reset exits the ability state, which calls control_finish(): skip the slam.
	cancelled = true
	is_running = false


func draw_world(canvas: CanvasItem, ctx: UltimateContext) -> void:
	if not is_running:
		return
	var r := ctx.player.get_rect()
	for i in 3: # Speed streaks above the player.
		var x := r.position.x + r.size.x * (0.2 + 0.3 * i)
		canvas.draw_line(Vector2(x, r.position.y - 6.0), Vector2(x, r.position.y - 34.0 - i * 6.0), Color(color, 0.6), 2.0, true)
	canvas.draw_rect(r.grow(3.0), Color(color, 0.35), false, 2.0)
