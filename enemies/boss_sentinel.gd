class_name BossSentinel
extends Enemy
## Intro boss: the Hollow Sentinel. It always tracks the player: it faces
## them, walks toward them, and aims every attack at where the player is
## standing when the attack launches. Attacks are picked by distance:
##   charge - telegraphed lunge that runs past the player's position
##   leap   - jumps to land on the player, slams, sends shockwaves both ways
##   volley - aimed shards at the player (spread)
## Below half health it enters phase 2: shorter telegraphs, faster moves and
## extra shards. Every attack is preceded by a clear telegraph (white eyes).

const GRAVITY := 2200.0

@export var boss_id := "hollow_sentinel"
@export var display_name := "Hollow Sentinel"
@export var walk_speed := 85.0
@export var charge_speed := 560.0
@export var leap_time := 0.75
@export var shard_damage := 15.0
@export var shockwave_damage := 15.0

var combat: CombatManager
var phase := 1
var state := "intro"
var state_time := 0.0
var cooldown := 1.0
var pending_attack := ""
var last_attack := ""
var last_target_position := Vector2.ZERO ## Where the current attack is aimed.
var attack_history: Array[String] = []
var recover_time := 0.5
var _charge_dir := 1
var _charge_target_x := 0.0
var _shots_left := 0
var _shot_index := 0
var _shot_timer := 0.0


func _on_reset() -> void:
	phase = 1
	cooldown = 1.0
	pending_attack = ""
	last_attack = ""
	attack_history.clear()
	_enter("intro")


func speed_mul() -> float:
	return 1.3 if phase == 2 else 1.0


func telegraph_time() -> float:
	return 0.5 if phase == 1 else 0.34


func _enter(new_state: String) -> void:
	state = new_state
	state_time = 0.0


func _face_target() -> void:
	if target:
		facing = 1 if target.global_position.x >= global_position.x else -1


func _on_hit(direction: Vector2, knockback: float) -> void:
	velocity.x += direction.x * knockback * 0.3 # Heavy: hits barely move it.
	if phase == 1 and health <= max_health * 0.5 and health > 0.0:
		phase = 2
		_enter("roar")
		Events.boss_phase_changed.emit(self, 2)


func _step_alive(delta: float) -> void:
	state_time += delta
	velocity.y = minf(velocity.y + GRAVITY * delta, 900.0)
	match state:
		"intro":
			velocity.x = 0.0
			_face_target()
			if state_time > 0.8:
				_enter("stalk")
		"roar":
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			if state_time > 0.6:
				cooldown = 0.3
				_enter("stalk")
		"stalk":
			_face_target()
			cooldown -= delta
			var dx := target.global_position.x - global_position.x
			var want := signf(dx) * walk_speed * speed_mul() if absf(dx) > 70.0 else 0.0
			velocity.x = move_toward(velocity.x, want, 1200.0 * delta)
			if cooldown <= 0.0:
				_choose_attack(absf(dx))
		"telegraph":
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_face_target()
			last_target_position = target.global_position # Keep tracking while winding up.
			if state_time >= telegraph_time():
				_launch(pending_attack)
		"charge":
			velocity.x = _charge_dir * charge_speed * speed_mul()
			var passed := (_charge_dir > 0 and global_position.x > _charge_target_x + 90.0) \
				or (_charge_dir < 0 and global_position.x < _charge_target_x - 90.0)
			if is_on_wall() or passed or state_time > 1.1:
				_recover(0.55)
		"leap":
			if state_time > 0.1 and is_on_floor():
				_slam()
		"volley":
			velocity.x = 0.0
			_face_target()
			_shot_timer -= delta
			if _shots_left > 0 and _shot_timer <= 0.0:
				_fire_shard()
			if _shots_left == 0 and state_time > 0.5:
				_recover(0.45)
		"recover":
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			if state_time > recover_time:
				cooldown = randf_range(0.45, 0.85) / speed_mul()
				_enter("stalk")
	move_and_slide()


## Picks an attack by distance to the player; never the same one twice in a row.
func _choose_attack(distance: float) -> void:
	var options: Array[String] = []
	if distance > 300.0:
		options = ["leap", "volley"]
	elif distance < 140.0:
		options = ["charge", "leap"]
	else:
		options = ["charge", "volley", "leap"]
	if options.size() > 1:
		options.erase(last_attack)
	pending_attack = options[randi() % options.size()]
	last_target_position = target.global_position
	_enter("telegraph")
	Events.boss_telegraph.emit(self, pending_attack)


func _launch(kind: String) -> void:
	last_attack = kind
	attack_history.append(kind)
	last_target_position = target.global_position
	match kind:
		"charge":
			_charge_dir = 1 if last_target_position.x >= global_position.x else -1
			_charge_target_x = last_target_position.x
			facing = _charge_dir
			_enter("charge")
		"leap":
			var t := leap_time / speed_mul()
			var dx := clampf(last_target_position.x - global_position.x, -560.0, 560.0)
			velocity = Vector2(dx / t, -GRAVITY * t * 0.5)
			_face_target()
			_enter("leap")
		"volley":
			_shots_left = 3 if phase == 1 else 5
			_shot_index = 0
			_shot_timer = 0.0
			_enter("volley")


func _slam() -> void:
	velocity.x = 0.0
	if combat:
		for dir in [-1, 1]:
			combat.projectiles.spawn({
				"position": global_position + Vector2(dir * size.x * 0.5, -12.0),
				"velocity": Vector2(dir * 360.0 * speed_mul(), 0.0),
				"radius": 12.0, "damage": shockwave_damage, "life": 1.6, "hostile": true,
				"color": Color("#ffb347"), "shape": "wave",
			})
	Events.ultimate_impact.emit(0.03, 0.45)
	_recover(0.6)


func _fire_shard() -> void:
	var from := get_center() + Vector2(facing * 10.0, -size.y * 0.3)
	var aim_point: Vector2 = target.get_center() if target.has_method("get_center") else target.global_position
	var aim := (aim_point - from).angle()
	var count := 3 if phase == 1 else 5
	var spread := (float(_shot_index) - (count - 1) / 2.0) * 0.16
	if combat:
		combat.projectiles.spawn({
			"position": from, "velocity": Vector2.from_angle(aim + spread) * 380.0 * speed_mul(),
			"radius": 8.0, "damage": shard_damage, "life": 3.0, "hostile": true, "color": Color("#ff7a9a"),
		})
	_shot_index += 1
	_shots_left -= 1
	_shot_timer = 0.12


func _recover(duration: float) -> void:
	recover_time = duration
	_enter("recover")


func _choose_animation() -> String:
	if not alive:
		return "dead"
	if flash_timer > 0.0 and state in ["stalk", "recover"]:
		return "hurt"
	match state:
		"telegraph": return "telegraph"
		"charge": return "charge"
		"leap": return "leap"
		"volley": return "volley"
		"recover": return "recover"
		"roar": return "roar"
		"stalk": return "walk" if absf(velocity.x) > 10.0 else "idle"
	return "idle"
