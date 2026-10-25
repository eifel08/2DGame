class_name BaseEnemy
extends Enemy
## Modular base for the bestiary enemies. A new enemy type is one small
## script that extends BaseEnemy and overrides _think(delta) (plus, when
## needed, blocks_hit, hitbox_active or _on_spawn), and one scene:
##   CharacterBody2D (this script) + CollisionShape2D + Flip/Rig (EnemyRig,
##   placeholder art picked by `look`) + AnimationPlayer (optional clips).
## Register the scene in Game.ENEMY_SCENES under a kind name; rooms place it
## with a marker whose meta "kind" is that name.
##
## What the base gives every enemy:
##   - a tiny state machine: state, state_time, enter(), cooldown
##   - senses: target_distance, sees_target (range + line of sight),
##     target_in_leash (the enemy never strays far from home)
##   - movement: move_ground (gravity, ledges), move_fly, ground_ahead
##   - attacks: shoot (hostile projectile, deflectable or not) and strike
##     (a short melee hitbox; a deflectable strike is PARRIED by a player
##     swing that touches it in time: no damage, the enemy staggers)
##   - telegraphs: telegraph() before every attack (Events.enemy_telegraph,
##     the rig shows the wind-up pose)
##   - noticing: while it has the player in sight (and a moment after) its
##     eyes glow red (is_alerted). There is no "!" sign.
## The deflect rule (see ProjectileSystem): deflectable = a standard melee
## swing sends it back; non-deflectable = only dodging helps. Magic never
## deflects.

const GRAVITY := 2000.0
const PARRY_STAGGER := 0.9 ## Seconds stunned after a parried strike.

@export var flying := false
@export var move_speed := 60.0
## How far it notices the player: about half the screen (the view is 960 px
## wide), and only with a clear line of sight.
@export var sight_range := 420.0
@export var leash_range := 520.0 ## Never chases further than this from home.
@export var start_cooldown := 0.6

var combat: CombatManager ## Set by Game when spawned.
var effects: Effects
var state := "idle"
var state_time := 0.0
var cooldown := 0.0
var t := 0.0 ## Free-running time (sways, bobs).
var visual_alpha := 1.0 ## Rig opacity (ghosts, vanishing).
var strike_info := {} ## {rect, damage, deflectable, time, hit} while a strike is live.
var parried := false ## Last strike was parried (tests, rig).
var alert_timer := 0.0 ## > 0: it has noticed the player (red eyes).
## States in which hits hurt but do not stun or push (committed attacks:
## a brute's smash cannot be cancelled by poking it).
var poise_states: Array[String] = []
var wander_dir := 0 ## wander(): -1, 0 (pause) or 1.
var _wander_time := 0.0


func _on_reset() -> void:
	state = "idle"
	state_time = 0.0
	cooldown = start_cooldown
	t = randf() * 10.0
	visual_alpha = 1.0
	strike_info = {}
	parried = false
	alert_timer = 0.0
	_on_spawn()


func _step_alive(delta: float) -> void:
	t += delta
	state_time += delta
	cooldown -= delta
	alert_timer -= delta
	if stun_timer > 0.0:
		strike_info = {}
		_step_stunned(delta)
	else:
		_think(delta)
	_step_strike(delta)


# ---------- Hooks ----------

## Called after every reset (spawn, revive).
func _on_spawn() -> void:
	pass


## The enemy's behavior, every step while alive and not stunned.
func _think(_delta: float) -> void:
	pass


## Knocked back or parried: drift to a stop.
func _step_stunned(delta: float) -> void:
	if flying:
		velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
		move_and_slide()
	else:
		move_ground(delta, move_toward(velocity.x, 0.0, 900.0 * delta))


func _on_hit(direction: Vector2, knockback: float) -> void:
	if state in poise_states:
		return
	stun_timer = maxf(stun_timer, 0.12 + 0.2 * knockback_mul)
	velocity.x = direction.x * knockback
	velocity.y = direction.y * knockback * 0.5 if flying else velocity.y


# ---------- State ----------

func enter(new_state: String) -> void:
	state = new_state
	state_time = 0.0


## Announces an attack: the rig shows its wind-up, feedback may react.
func telegraph(attack_name: String) -> void:
	Events.enemy_telegraph.emit(self, attack_name)


# ---------- Senses ----------

## Marks the player as noticed: the eyes glow red for a moment.
func notice(duration := 1.0) -> void:
	alert_timer = maxf(alert_timer, duration)


func is_alerted() -> bool:
	return alert_timer > 0.0


func target_valid() -> bool:
	return target != null and is_instance_valid(target)


func target_center() -> Vector2:
	return target.get_center() if target_valid() else get_center()


func target_distance() -> float:
	return get_center().distance_to(target_center()) if target_valid() else INF


func face_target() -> void:
	if target_valid() and absf(target.global_position.x - global_position.x) > 2.0:
		facing = 1 if target.global_position.x > global_position.x else -1


## Within `range` and nothing solid in between.
func sees_target(range := -1.0) -> bool:
	if not target_valid() or (target is Player and (target as Player).is_dying()):
		return false
	var r := sight_range if range < 0.0 else range
	if target_distance() <= r and line_clear(get_center(), target_center()):
		notice()
		return true
	return false


## The player is close enough to home to be chased.
func target_in_leash() -> bool:
	return target_valid() and target_center().distance_to(home + Vector2(0, -size.y / 2.0)) <= leash_range


func home_distance() -> float:
	return global_position.distance_to(home)


## No solid tile on the straight line from `a` to `b`.
func line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / 12.0) + 1
	for i in range(1, steps):
		if room.is_solid_at(a.lerp(b, float(i) / steps)):
			return false
	return true


# ---------- Movement ----------

## Gravity + horizontal speed `vx`, then move_and_slide.
func move_ground(delta: float, vx: float) -> void:
	velocity.x = vx
	velocity.y = minf(velocity.y + GRAVITY * delta, 800.0)
	move_and_slide()


## Random idle stroll for walkers: walk left or right for a while, pause now
## and then, turn at walls and ledges. Call it from _think while idle.
func wander(delta: float, speed := -1.0) -> void:
	_wander_time -= delta
	if _wander_time <= 0.0:
		wander_dir = [-1, 0, 1, 1, -1].pick_random()
		if home_distance() > leash_range * 0.4:
			wander_dir = 1 if home.x > global_position.x else -1 # Drift back home.
		_wander_time = randf_range(0.8, 2.0)
	if wander_dir != 0 and is_on_floor() and (not ground_ahead(wander_dir) or wall_ahead(wander_dir)):
		wander_dir = -wander_dir
	if wander_dir != 0:
		facing = wander_dir
	move_ground(delta, wander_dir * (move_speed if speed < 0.0 else speed))


## Steers toward `desired` velocity (flyers).
func move_fly(delta: float, desired: Vector2, accel := 900.0) -> void:
	velocity = velocity.move_toward(desired, accel * delta)
	move_and_slide()


## Ground continues one step ahead in `dir` (no ledge).
func ground_ahead(dir: int) -> bool:
	return room.is_ground_at(Vector2(global_position.x + dir * (size.x / 2.0 + 4.0), global_position.y + 2.0))


func wall_ahead(dir: int) -> bool:
	return room.is_solid_at(Vector2(global_position.x + dir * (size.x / 2.0 + 4.0), global_position.y - size.y / 2.0))


# ---------- Attacks ----------

## Fires a hostile projectile from `from` along `dir`. Deflectable shots are
## the only ones a melee swing can send back.
func shoot(from: Vector2, dir: Vector2, speed: float, opts := {}) -> void:
	if combat == null:
		return
	var o := {
		"position": from,
		"velocity": dir.normalized() * speed,
		"radius": 7.0,
		"damage": Config.combat.contact_damage,
		"life": 2.5,
		"hostile": true,
		"owner": self,
		"deflectable": false,
		"color": Color("#b0306a"),
	}
	o.merge(opts, true)
	combat.projectiles.spawn(o)


## A melee strike: `rect` is live for `duration`. It hits the player once.
## A deflectable strike that meets an active player swing is PARRIED instead:
## no damage, and this enemy staggers (Events.enemy_parried).
func strike(rect: Rect2, damage: float, deflectable: bool, duration := 0.1) -> void:
	strike_info = {"rect": rect, "damage": damage, "deflectable": deflectable, "time": duration, "hit": false}
	parried = false
	_step_strike(0.0)


func _step_strike(delta: float) -> void:
	if strike_info.is_empty():
		return
	var rect: Rect2 = strike_info.rect
	if strike_info.deflectable and combat != null:
		var swing := combat.deflect_box() # Forgiving window and box (see CombatManager).
		if swing.has_area() and swing.intersects(rect.grow(6.0)):
			strike_info = {}
			parried = true
			stun_timer = PARRY_STAGGER
			velocity.x = -facing * 160.0
			enter("staggered")
			Events.enemy_parried.emit(self, rect.get_center())
			return
	if not strike_info.hit and target is Player and rect.intersects((target as Player).get_rect()):
		strike_info.hit = true
		(target as Player).receive_hit(strike_info.damage, get_center().x, false, false, self, Damage.Source.ENEMY)
	strike_info.time -= delta
	if strike_info.time <= 0.0:
		strike_info = {}


## A rect in front of the enemy: `reach` wide, `height` tall, `lift` above the feet.
func front_rect(reach: float, height: float, lift := 0.0) -> Rect2:
	var x := global_position.x + (size.x / 2.0 - 6.0) * facing
	if facing < 0:
		x -= reach
	return Rect2(x, global_position.y - lift - height, reach, height)


func _choose_animation() -> String:
	if not alive:
		return "dead"
	if spawn_timer > 0.0:
		return "spawn"
	if flash_timer > 0.0:
		return "hurt"
	return state
