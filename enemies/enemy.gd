class_name Enemy
extends CharacterBody2D
## Shared enemy contract used by combat, the HUD and the room/world logic.
## Tiers drive persistence (see core/world_state.gd):
##   "weak"   - revives on a room transition or a checkpoint save
##   "strong" - revives only on a checkpoint save
##   "boss"   - never revives in the playthrough
## Dead enemies stay dead; there is no timed respawn.
## The node origin is at the feet (bottom-center).

@export_enum("weak", "strong", "boss") var tier := "weak"
@export var max_health := 80.0
@export var currency_drop := 6 ## Shards dropped when destroyed.
@export var contact_damage_mul := 1.0
@export var knockback_mul := 1.0 ## Lower = heavier.

@onready var flip: Node2D = $Flip
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var size: Vector2 = ($CollisionShape2D.shape as RectangleShape2D).size

var room: Room
var target: Node2D ## Usually the player.
var spawn_id := "" ## Persistence key; "" = not persisted (e.g. arena waves).
var home := Vector2.ZERO
var health := 80.0
var alive := true
var facing := 1
var flash_timer := 0.0
var stun_timer := 0.0
var dead_time := 0.0
var _anim_name := ""


func _ready() -> void:
	set_physics_process(false)


func setup(p_room: Room, home_position: Vector2, p_target: Node2D = null) -> void:
	room = p_room
	home = home_position
	target = p_target
	reset()


func reset() -> void:
	global_position = home
	velocity = Vector2.ZERO
	health = max_health
	alive = true
	visible = true
	flash_timer = 0.0
	stun_timer = 0.0
	dead_time = 0.0
	_anim_name = ""
	_on_reset()


func get_rect() -> Rect2:
	return Rect2(global_position.x - size.x / 2.0, global_position.y - size.y, size.x, size.y)


func get_center() -> Vector2:
	return global_position + Vector2(0.0, -size.y / 2.0)


func deals_contact_damage() -> bool:
	return alive


func restore_full_health() -> void:
	if alive:
		health = max_health


## Returns damage actually applied (0 when already destroyed).
func take_hit(damage: float, direction: Vector2, knockback: float) -> float:
	if not alive:
		return 0.0
	health -= damage
	flash_timer = 0.12
	_on_hit(direction, knockback * knockback_mul)
	if health <= 0.0:
		health = 0.0
		_die()
	return damage


## Instant death (e.g. touching spikes). Returns true if it was alive.
func kill() -> bool:
	if not alive:
		return false
	health = 0.0
	_die()
	return true


func _die() -> void:
	alive = false
	dead_time = 0.0


func step(delta: float) -> void:
	flash_timer -= delta
	stun_timer -= delta
	if alive:
		_step_alive(delta)
	else:
		dead_time += delta
		if dead_time > 0.6:
			visible = false # Stays dead until its tier allows a revive.
	flip.scale.x = facing
	flip.modulate = Color(4, 4, 4) if flash_timer > 0.0 and alive else Color.WHITE
	var next := _choose_animation()
	if next != _anim_name and anim.has_animation(next):
		_anim_name = next
		anim.play(next)
	anim.advance(delta)
	queue_redraw()


# ----- Hooks for subclasses -----

func _on_reset() -> void:
	pass


func _on_hit(_direction: Vector2, _knockback: float) -> void:
	pass


func _step_alive(_delta: float) -> void:
	pass


func _choose_animation() -> String:
	if not alive:
		return "dead"
	if flash_timer > 0.0:
		return "hurt"
	return "move" if absf(velocity.x) > 5.0 else "idle"


## Health bar above the head (bosses use the HUD bar instead).
func _draw() -> void:
	if not alive or tier == "boss":
		return
	var w := size.x + 8.0
	var bar := Rect2(-w / 2.0, -size.y - 10.0, w, 4.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(w * health / max_health, 4.0)), Color("#ff6b6b") if tier == "weak" else Color("#ffb347"))
	if Config.stats_visible():
		draw_string(ThemeDB.fallback_font, bar.position + Vector2(-20, -3), "%d/%d" % [ceili(health), roundi(max_health)],
			HORIZONTAL_ALIGNMENT_CENTER, w + 40, 10, Color("#ffd0d0"))
