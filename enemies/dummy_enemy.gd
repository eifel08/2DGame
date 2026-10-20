class_name DummyEnemy
extends CharacterBody2D
## Training dummy. The ground variant patrols and turns at walls and ledges.
## The flying variant hovers around its home point (ideal for pogo chains).
## It respawns at full health a few seconds after being destroyed.
## The node origin is at the feet (bottom-center).

const GRAVITY := 2000.0
const RESPAWN_DELAY := 2.5

@export var flying := false
@export var patrol := true
@export var max_health := 80.0
@export var patrol_range := 96.0
@export var patrol_speed := 55.0

@onready var flip: Node2D = $Flip
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var size: Vector2 = ($CollisionShape2D.shape as RectangleShape2D).size

var room: Room
var home := Vector2.ZERO
var health := 80.0
var alive := true
var facing := 1
var patrol_dir := 1
var flash_timer := 0.0
var stun_timer := 0.0
var respawn_timer := 0.0
var t := 0.0
var _anim_name := ""


func _ready() -> void:
	set_physics_process(false)


func setup(p_room: Room, home_position: Vector2) -> void:
	room = p_room
	home = home_position
	reset()


func reset() -> void:
	global_position = home
	velocity = Vector2.ZERO
	health = max_health
	alive = true
	patrol_dir = 1
	flash_timer = 0.0
	stun_timer = 0.0
	respawn_timer = 0.0
	t = randf() * 10.0
	_anim_name = ""


func get_rect() -> Rect2:
	return Rect2(global_position.x - size.x / 2.0, global_position.y - size.y, size.x, size.y)


func get_center() -> Vector2:
	return global_position + Vector2(0.0, -size.y / 2.0)


func deals_contact_damage() -> bool:
	return alive


## Returns damage actually applied (0 when already destroyed).
func take_hit(damage: float, direction: Vector2, knockback: float) -> float:
	if not alive:
		return 0.0
	health -= damage
	flash_timer = 0.12
	stun_timer = 0.25
	velocity.x = direction.x * knockback
	if flying:
		velocity.y = direction.y * knockback * 0.6
	else:
		velocity.y = direction.y * knockback * 0.6 - (120.0 if is_zero_approx(direction.y) else 0.0)
	if health <= 0.0:
		health = 0.0
		alive = false
		respawn_timer = RESPAWN_DELAY
	return damage


func step(delta: float) -> void:
	t += delta
	flash_timer -= delta
	stun_timer -= delta

	if not alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			reset()
	elif flying:
		_step_flying(delta)
	else:
		_step_ground(delta)

	if absf(velocity.x) > 5.0:
		facing = 1 if velocity.x > 0.0 else -1
	flip.scale.x = facing
	flip.modulate = Color(4, 4, 4) if flash_timer > 0.0 and alive else Color.WHITE
	_update_animation(delta)
	queue_redraw()


func _step_flying(delta: float) -> void:
	if stun_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
	else:
		var sway := sin(t * 0.8) * patrol_range * 0.7 if patrol else 0.0
		var target := home + Vector2(sway, sin(t * 2.2) * 8.0)
		velocity = (target - global_position) * 3.0
	move_and_slide()


func _step_ground(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, 800.0)
	if stun_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	elif patrol:
		if global_position.x > home.x + patrol_range:
			patrol_dir = -1
		if global_position.x < home.x - patrol_range:
			patrol_dir = 1
		velocity.x = patrol_dir * patrol_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)

	move_and_slide()
	if stun_timer > 0.0:
		return
	if is_on_wall():
		patrol_dir = 1 if get_wall_normal().x > 0.0 else -1
	# Turn around at ledges.
	if is_on_floor():
		var ahead_x := global_position.x + patrol_dir * (size.x / 2.0 + 2.0)
		if not room.is_ground_at(Vector2(ahead_x, global_position.y + 2.0)):
			patrol_dir *= -1


func _update_animation(delta: float) -> void:
	var next := "idle"
	if not alive:
		next = "dead"
	elif flash_timer > 0.0:
		next = "hurt"
	elif absf(velocity.x) > 5.0:
		next = "move"
	if next != _anim_name:
		_anim_name = next
		anim.play(next)
	anim.advance(delta)


func _draw() -> void:
	if not alive:
		return
	var w := size.x + 8.0
	var bar := Rect2(-w / 2.0, -size.y - 10.0, w, 4.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(w * health / max_health, 4.0)), Color("#ff6b6b"))
	if Config.stats_visible():
		draw_string(ThemeDB.fallback_font, bar.position + Vector2(-20, -3), "%d/%d" % [ceili(health), roundi(max_health)],
			HORIZONTAL_ALIGNMENT_CENTER, w + 40, 10, Color("#ffd0d0"))
