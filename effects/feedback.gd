class_name Feedback
extends Node
## "Game feel" layer. Listens to gameplay events and answers with hitstop,
## screen shake, effects (by name, see Effects.play) and sounds (by name,
## see the Sfx autoload). Gameplay code never calls these directly. The
## feedback is physical only: no text pop-ups for wins or discoveries.

var camera: CameraRig
var effects: Effects
var hitstop_timer := 0.0
var _trail_timer := 0.0
var _heal_sparkle := false


func setup(p_camera: CameraRig, p_effects: Effects) -> void:
	camera = p_camera
	effects = p_effects
	Events.hit_landed.connect(_on_hit)
	Events.pogo_bounced.connect(_on_pogo)
	Events.grapple_fired.connect(func(_origin: Vector2, _dir: Vector2) -> void: Sfx.play("grapple_fire"))
	Events.grapple_latched.connect(_on_grapple_latched)
	Events.grapple_deflected.connect(func(pos: Vector2) -> void:
		Sfx.play("grapple_latch", 1.6)
		effects.play("pogo_spike", pos))
	Events.grapple_bounced.connect(func(pos: Vector2) -> void:
		Sfx.play("pogo")
		effects.play("pogo_spark", pos))
	# Breakable platforms and pegs: a dry crumble, no flash (Rule F).
	Events.platform_crumbled.connect(func(_pos: Vector2) -> void: Sfx.play("break", 1.4))
	Events.peg_crumbled.connect(func(_pos: Vector2) -> void: Sfx.play("break", 1.8))
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
	Events.arena_started.connect(func(_id: String) -> void:
		Sfx.play("gate") # Gates slam shut.
		camera.add_trauma(0.35))
	Events.arena_cleared.connect(_on_arena_cleared)
	Events.enemy_spawning.connect(_on_enemy_spawning)
	Events.secret_found.connect(_on_secret_found)
	Events.relic_collected.connect(_on_relic_collected)
	# Deflect / parry / shields (BaseEnemy roster).
	Events.enemy_blocked.connect(func(enemy: Node, _dir: Vector2) -> void:
		Sfx.play("grapple_latch", 1.3) # A dull clank: the shield held.
		effects.play("pogo_spike", enemy.get_center()))
	Events.enemy_parried.connect(func(_enemy: Node, pos: Vector2) -> void:
		Sfx.play("hit", 1.5)
		freeze(0.08)
		effects.play("hit_spark", pos, {"scale": 1.3}))
	Events.projectile_deflected.connect(func(pos: Vector2) -> void:
		Sfx.play("pogo", 1.3)
		effects.play("pogo_spark", pos))
	Events.potion_collected.connect(_on_potion_collected)
	Events.scroll_collected.connect(_on_scroll_collected)
	Events.meditation_finished.connect(_on_meditation_finished)
	Events.player_dying.connect(func(_p: Node) -> void: Sfx.play("death"))
	Events.trance_broken.connect(func(p: Node) -> void: effects.play("trance_break", p.get_center()))
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
	_trail_timer -= delta
	var fast := player.state_name() == "dash" or player.state_name() == "ability"
	if fast and _trail_timer <= 0.0:
		effects.play("dash_trail", player.get_center())
		_trail_timer = 0.025
	if (_heal_sparkle or player.is_channeling_heal) and randf() < 0.5:
		effects.play("heal_sparkle", player.global_position + Vector2(randf_range(-12, 12), 0))
	_heal_sparkle = false
	if player.state_name() == "meditate" and randf() < 0.25:
		effects.play("meditate_glow", player.global_position + Vector2(randf_range(-14, 14), -4))


# ---------- Event handlers ----------

func _on_hit(info: Dictionary) -> void:
	var c = Config.combat
	var s: float = info.strength
	freeze(c.hitstop_on_hit * s)
	camera.add_trauma(c.shake_on_hit * s)
	effects.play("hit_spark", info.position, {"scale": 0.8 + 0.3 * s})
	Sfx.play("hit", randf_range(0.92, 1.08))
	# Exact damage numbers are debug data (see Config.stats_visible()).
	if Config.stats_visible():
		var col := Color.WHITE if info.source == "melee" else Color("#ffd36b")
		effects.float_text(info.position + Vector2(0, -18), "%.1f" % info.damage if fmod(info.damage, 1.0) != 0.0 else str(int(info.damage)), col)


func _on_pogo(pos: Vector2, on_hazard: bool) -> void:
	Sfx.play("pogo")
	effects.play("pogo_spike" if on_hazard else "pogo_spark", pos)
	if on_hazard:
		freeze(Config.combat.hitstop_on_hit * 0.6)
		camera.add_trauma(Config.combat.shake_on_hit * 0.5)


## The enemy-hit side of a hook is already covered by hit_landed.
func _on_grapple_latched(anchor: Vector2, on_enemy: bool) -> void:
	Sfx.play("grapple_latch")
	if not on_enemy:
		effects.play("grapple_latch", anchor)


func _on_player_hurt(player: Node, _damage: float) -> void:
	freeze(Config.combat.hitstop_on_hurt)
	camera.add_trauma(Config.combat.shake_on_hurt)
	effects.play("player_hurt", player.get_center())
	Sfx.play("hurt")


func _on_hazard_respawn(_player: Node, from_position: Vector2, to_position: Vector2) -> void:
	freeze(Config.combat.hitstop_on_hurt)
	camera.add_trauma(Config.combat.shake_on_hurt)
	effects.play("hazard_poof", from_position + Vector2(0, -20))
	effects.play("safe_return", to_position + Vector2(0, -20))


func _on_player_jumped(player: Node, kind: String) -> void:
	effects.play("double_jump" if kind == "double" else "jump_dust", player.global_position)


func _on_player_landed(player: Node, fall_speed: float) -> void:
	if fall_speed >= 450.0:
		effects.play("land_dust", player.global_position)


func _on_player_dashed(player: Node, dir: int) -> void:
	# The effect points left (away from a rightward dash); flip it for a left dash.
	effects.play("dash_burst", player.get_center() - Vector2(dir * 10, 0), {"rotation": 0.0 if dir > 0 else PI})


func _on_enemy_spawning(enemy: Node) -> void:
	Sfx.play("spawn")
	effects.play("spawn_portal", enemy.global_position, {"scale": enemy.size.y / 44.0})


func _on_enemy_killed(enemy: Node) -> void:
	camera.add_trauma(0.25)
	effects.play("enemy_death", enemy.get_center())


func _on_currency_collected(amount: int, pos: Vector2) -> void:
	effects.play("coin_pickup", pos + Vector2(0, -11))
	effects.float_text(pos + Vector2(0, -26), "+%d" % amount, Coin.COLOR)


func _on_checkpoint_activated(checkpoint: Node) -> void:
	effects.play("checkpoint_light", checkpoint.global_position + Vector2(0, -50))


func _on_player_rested(checkpoint: Node) -> void:
	Sfx.play("save")
	effects.play("save_glow", checkpoint.global_position + Vector2(0, -20))


func _on_boss_telegraph(boss: Node, _attack: String) -> void:
	effects.play("boss_telegraph", boss.get_center() + Vector2(0, -20))


func _on_boss_phase_changed(boss: Node, _phase: int) -> void:
	camera.add_trauma(0.6)
	effects.play("boss_phase", boss.get_center())


## NO CELEBRATIONS (GUIDELINES.md, Rule F): bosses, arenas, secrets and
## relics never get fanfares, jingles, flashes, flares or text. Feedback is
## environmental only: the boss roars and dissolves, arena gates move with a
## mechanical clunk, a broken wall crumbles, a picked-up relic is just gone.
func _on_boss_defeated(_boss: Node) -> void:
	camera.add_trauma(0.3)


## Arena cleared: the gates open with a mechanical sound. Nothing else.
func _on_arena_cleared(_arena_id: String) -> void:
	Sfx.play("gate")


## A secret wall breaks: stone crumbles (debris + a crash). No jingle or flash.
func _on_secret_found(_secret_id: String, pos: Vector2) -> void:
	Sfx.play("break")
	camera.add_trauma(0.25)
	effects.play("wall_break", pos)


## A relic is taken: a soft pickup sound and a small puff. No jingle or flare.
func _on_relic_collected(_relic_id: String, pos: Vector2) -> void:
	Sfx.play("pickup")
	effects.play("relic_pickup", pos + Vector2(0, -22))


## Potions and scrolls: the same soft pickup as a relic (Rule F spirit: no
## jingle or flare). The puff takes the potion's color.
func _on_potion_collected(_potion_id: String, stat: String, pos: Vector2) -> void:
	Sfx.play("pickup", 0.9)
	effects.play("potion_pickup", pos + Vector2(0, -20), {"tint": Color("#4f8dff") if stat == "max_energy" else Color("#ff5e6c")})


func _on_scroll_collected(_spell_id: String, pos: Vector2) -> void:
	Sfx.play("pickup", 1.15)
	effects.play("scroll_pickup", pos + Vector2(0, -18))


## A meditation completed: one low, calm tone. Nothing on an interruption.
func _on_meditation_finished(_altar: Node, slot: int) -> void:
	if slot >= 0:
		Sfx.play("save", 0.7)


func _on_ultimate_impact(hitstop: float, shake: float) -> void:
	freeze(hitstop)
	camera.add_trauma(shake)
