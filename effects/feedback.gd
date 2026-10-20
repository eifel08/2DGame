class_name Feedback
extends Node
## "Game feel" layer. Listens to gameplay events and answers with hitstop,
## screen shake and particles. Gameplay code never calls these directly.

var camera: CameraRig
var effects: Effects
var hitstop_timer := 0.0
var _ghost_timer := 0.0
var _heal_sparkle := false


func setup(p_camera: CameraRig, p_effects: Effects) -> void:
	camera = p_camera
	effects = p_effects
	Events.hit_landed.connect(_on_hit)
	Events.pogo_bounced.connect(_on_pogo)
	Events.player_hurt.connect(_on_player_hurt)
	Events.player_hazard_respawn.connect(_on_hazard_respawn)
	Events.player_jumped.connect(_on_player_jumped)
	Events.player_landed.connect(_on_player_landed)
	Events.player_dashed.connect(_on_player_dashed)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.ultimate_impact.connect(_on_ultimate_impact)
	Events.currency_collected.connect(_on_currency_collected)
	Events.checkpoint_activated.connect(_on_checkpoint_activated)
	Events.player_rested.connect(_on_player_rested)
	Events.boss_telegraph.connect(_on_boss_telegraph)
	Events.boss_phase_changed.connect(_on_boss_phase_changed)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.arena_started.connect(func(_id: String) -> void: camera.add_trauma(0.35))
	Events.arena_cleared.connect(func(_id: String) -> void: camera.add_trauma(0.3))
	Events.health_healed.connect(func(_amount: float) -> void: _heal_sparkle = true)


# ---------- Hitstop ----------

func freeze(seconds: float) -> void:
	hitstop_timer = maxf(hitstop_timer, seconds)


## Returns true while the simulation should stay frozen.
func step_hitstop(delta: float) -> bool:
	if hitstop_timer <= 0.0:
		return false
	hitstop_timer -= delta
	return true


# ---------- Continuous visuals ----------

func step(delta: float, player: Player) -> void:
	camera.shake_enabled = Config.debug.screen_shake
	_ghost_timer -= delta
	var fast := player.state_name() == "dash" or player.state_name() == "ability"
	if fast and _ghost_timer <= 0.0:
		effects.ghost(player.get_rect())
		_ghost_timer = 0.025
	if (_heal_sparkle or player.is_channeling_heal) and randf() < 0.5:
		effects.burst(player.global_position + Vector2(randf_range(-12, 12), 0), {
			"count": 1, "color": Color("#8dffb0"), "speed": 60.0, "angle": -PI / 2.0,
			"spread": 0.6, "gravity": -200.0, "life": 0.5, "size": 3.0,
		})
	_heal_sparkle = false


# ---------- Event handlers ----------

func _on_hit(info: Dictionary) -> void:
	var c = Config.combat
	var s: float = info.strength
	freeze(c.hitstop_on_hit * s)
	camera.add_trauma(c.shake_on_hit * s)
	effects.burst(info.position, {"count": 8 + int(round(6 * s)), "color": Color("#fff3c4"), "speed": 320.0, "life": 0.3})
	# Exact damage numbers are debug data (see Config.stats_visible()).
	if Config.stats_visible():
		var col := Color.WHITE if info.source == "melee" else Color("#ffd36b")
		effects.float_text(info.position + Vector2(0, -18), "%.1f" % info.damage if fmod(info.damage, 1.0) != 0.0 else str(int(info.damage)), col)


func _on_pogo(pos: Vector2, on_hazard: bool) -> void:
	effects.burst(pos, {
		"count": 8, "color": Color("#ff9a9a") if on_hazard else Color("#bff6ff"), "speed": 200.0,
		"angle": PI / 2.0, "spread": PI * 0.9, "gravity": 300.0,
	})
	if on_hazard:
		freeze(Config.combat.hitstop_on_hit * 0.6)
		camera.add_trauma(Config.combat.shake_on_hit * 0.5)


func _on_player_hurt(player: Node, _damage: float) -> void:
	freeze(Config.combat.hitstop_on_hurt)
	camera.add_trauma(Config.combat.shake_on_hurt)
	effects.burst(player.get_center(), {"count": 16, "color": Color("#ff6b6b"), "speed": 300.0, "size": 5.0})


func _on_hazard_respawn(_player: Node, from_position: Vector2, to_position: Vector2) -> void:
	freeze(Config.combat.hitstop_on_hurt)
	camera.add_trauma(Config.combat.shake_on_hurt)
	effects.burst(from_position + Vector2(0, -20), {"count": 18, "color": Color("#ff6b6b"), "speed": 280.0, "size": 5.0})
	effects.ring(to_position + Vector2(0, -20), {"radius": 40.0, "color": Color("#bff6ff"), "width": 4.0, "life": 0.4})


func _on_player_jumped(player: Node, kind: String) -> void:
	if kind == "double":
		effects.ring(player.global_position, {"radius": 26.0, "color": Color("#bff6ff"), "width": 3.0, "life": 0.25})
	else:
		effects.burst(player.global_position, {"count": 5, "color": Color("#9aa7c7"), "speed": 90.0, "gravity": 100.0, "life": 0.25, "size": 3.0})


func _on_player_landed(player: Node, fall_speed: float) -> void:
	if fall_speed < 450.0:
		return
	effects.burst(player.global_position, {
		"count": 8, "color": Color("#9aa7c7"), "speed": 140.0, "angle": -PI / 2.0,
		"spread": PI, "gravity": 400.0, "life": 0.3, "size": 3.0,
	})


func _on_player_dashed(player: Node, dir: int) -> void:
	effects.burst(player.get_center() - Vector2(dir * 10, 0), {
		"count": 10, "color": Color("#d9f6ff"), "speed": 200.0, "angle": PI if dir > 0 else 0.0,
		"spread": 0.8, "gravity": 0.0, "life": 0.25, "size": 3.0,
	})


func _on_enemy_killed(enemy: Node) -> void:
	camera.add_trauma(0.25)
	effects.burst(enemy.get_center(), {"count": 24, "color": Color("#ffb36b"), "speed": 380.0, "size": 5.0, "life": 0.5})


func _on_currency_collected(amount: int, pos: Vector2) -> void:
	effects.burst(pos + Vector2(0, -11), {"count": 6, "color": Coin.COLOR, "speed": 140.0, "gravity": 200.0, "life": 0.3, "size": 3.0})
	effects.float_text(pos + Vector2(0, -26), "+%d" % amount, Coin.COLOR)


func _on_checkpoint_activated(checkpoint: Node) -> void:
	effects.ring(checkpoint.global_position + Vector2(0, -50), {"radius": 50.0, "color": Color("#ffb347"), "width": 4.0, "life": 0.45})


func _on_player_rested(checkpoint: Node) -> void:
	effects.burst(checkpoint.global_position + Vector2(0, -20), {
		"count": 20, "color": Color("#8dffb0"), "speed": 120.0, "angle": -PI / 2.0,
		"spread": 1.4, "gravity": -150.0, "life": 0.7, "size": 3.0,
	})


func _on_boss_telegraph(boss: Node, _attack: String) -> void:
	effects.ring(boss.get_center() + Vector2(0, -20), {"radius": 46.0, "color": Color.WHITE, "width": 3.0, "life": 0.3})


func _on_boss_phase_changed(boss: Node, _phase: int) -> void:
	camera.add_trauma(0.6)
	effects.ring(boss.get_center(), {"radius": 140.0, "color": Color("#b06cff"), "width": 8.0, "life": 0.6})


func _on_boss_defeated(boss: Node) -> void:
	freeze(0.25)
	camera.add_trauma(0.9)
	effects.burst(boss.get_center(), {"count": 60, "color": Color("#b06cff"), "speed": 480.0, "size": 6.0, "life": 0.8})
	effects.ring(boss.get_center(), {"radius": 200.0, "color": Color.WHITE, "width": 8.0, "life": 0.7})


func _on_ultimate_impact(hitstop: float, shake: float) -> void:
	freeze(hitstop)
	camera.add_trauma(shake)
