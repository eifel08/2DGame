class_name Enemy
extends CharacterBody2D
## Shared enemy contract used by combat, the HUD and the room/world logic.
## Tiers drive persistence (see core/world_state.gd):
##   "weak"   - revives on a room transition or at a checkpoint
##   "strong" - revives only at a checkpoint (saving, dying, loading)
##   "boss"   - never revives in the playthrough
## Dead enemies stay dead; there is no timed respawn.
##
## Hitboxes: hitbox_active() is the single switch for being hit AND for
## dealing contact damage. It is false while spawning (telegraph) and from
## the very moment an enemy dies; the body collision is disabled too.
## The node origin is at the feet (bottom-center).
##
## Visuals are pure placeholders: the rig under Flip/Rig is animated by the
## AnimationPlayer ("idle", "move", "hurt", "dead", "spawn", ...). Swap the
## rig and the clips for real art; this script only picks clip names.

const SPAWN_TELEGRAPH := 0.35 ## Arena wave spawns: seconds harmless (the "spawn" clip).

@export_enum("weak", "strong", "boss") var tier := "weak"
@export var max_health := 80.0
@export var currency_drop := 6 ## Shards dropped when destroyed.
@export var contact_damage_mul := 1.0
@export var knockback_mul := 1.0 ## Lower = heavier.

@onready var flip: Node2D = $Flip
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var size: Vector2 = (shape.shape as RectangleShape2D).size

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
var spawn_timer := 0.0 ## > 0 while the spawn telegraph runs.
var freeze_timer := 0.0 ## > 0 while held by a stasis effect: no movement, no AI, no contact damage.
var _anim_name := ""


func _ready() -> void:
	set_physics_process(false)


## `telegraph`: appear through a portal (translucent, harmless, untouchable)
## before becoming active. Used only for arena wave spawns.
func setup(p_room: Room, home_position: Vector2, p_target: Node2D = null, telegraph := false) -> void:
	room = p_room
	home = home_position
	target = p_target
	reset()
	if telegraph:
		spawn_timer = SPAWN_TELEGRAPH
		Events.enemy_spawning.emit(self)


func reset() -> void:
	global_position = home
	velocity = Vector2.ZERO
	health = max_health
	alive = true
	visible = true
	flash_timer = 0.0
	stun_timer = 0.0
	dead_time = 0.0
	spawn_timer = 0.0
	freeze_timer = 0.0
	_anim_name = ""
	shape.set_deferred("disabled", false)
	_on_reset()


func get_rect() -> Rect2:
	return Rect2(global_position.x - size.x / 2.0, global_position.y - size.y, size.x, size.y)


func get_center() -> Vector2:
	return global_position + Vector2(0.0, -size.y / 2.0)


func is_spawning() -> bool:
	return spawn_timer > 0.0


## Can be hit and can hurt the player.
func hitbox_active() -> bool:
	return alive and spawn_timer <= 0.0


func deals_contact_damage() -> bool:
	return hitbox_active() and not is_frozen()


func is_frozen() -> bool:
	return freeze_timer > 0.0


## Holds the enemy in place for `duration`. It can still be hit.
func freeze(duration: float) -> void:
	if not hitbox_active():
		return
	freeze_timer = maxf(freeze_timer, duration)
	velocity = Vector2.ZERO


func restore_full_health() -> void:
	if alive:
		health = max_health


## Returns damage actually applied (0 when dead or still spawning).
func take_hit(damage: float, direction: Vector2, knockback: float) -> float:
	if not hitbox_active():
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
	freeze_timer = 0.0
	velocity = Vector2.ZERO
	shape.set_deferred("disabled", true) # No more collision of any kind.


func step(delta: float) -> void:
	flash_timer -= delta
	stun_timer -= delta
	if not alive:
		dead_time += delta
		_step_dead(delta)
	elif spawn_timer > 0.0:
		spawn_timer -= delta
		facing = 1 if target == null or target.global_position.x >= global_position.x else -1
	elif freeze_timer > 0.0:
		freeze_timer -= delta # Frozen: the AI and physics simply do not run.
		velocity = Vector2.ZERO
	else:
		_step_alive(delta)
	flip.scale.x = facing
	if alive and flash_timer > 0.0:
		flip.modulate = Color(4, 4, 4) # Hit flash tint.
	elif alive and is_frozen():
		flip.modulate = Color(0.55, 0.85, 1.6) # Frozen tint.
	else:
		flip.modulate = Color.WHITE
	var next := _choose_animation()
	if next != _anim_name and anim.has_animation(next):
		_anim_name = next
		anim.play(next)
	if not is_frozen():
		anim.advance(delta) # A frozen enemy holds its pose.
	queue_redraw()


# ----- Hooks for subclasses -----

func _on_reset() -> void:
	pass


func _on_hit(_direction: Vector2, _knockback: float) -> void:
	pass


func _step_alive(_delta: float) -> void:
	pass


## Death visual. Default: the "dead" clip, then hidden after 0.6 s.
func _step_dead(_delta: float) -> void:
	if dead_time > 0.6:
		visible = false # Stays dead until its tier allows a revive.


func _choose_animation() -> String:
	if not alive:
		return "dead"
	if spawn_timer > 0.0:
		return "spawn"
	if flash_timer > 0.0:
		return "hurt"
	return "move" if absf(velocity.x) > 5.0 else "idle"


## Health bar above the head (HUD element; bosses use the HUD bar instead).
func _draw() -> void:
	if not alive or spawn_timer > 0.0 or tier == "boss":
		return
	# Health bar above the head (bosses use the HUD bar instead).
	var w := size.x + 8.0
	var bar := Rect2(-w / 2.0, -size.y - 10.0, w, 4.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(w * health / max_health, 4.0)), Color("#ff6b6b") if tier == "weak" else Color("#ffb347"))
	if Config.stats_visible():
		draw_string(ThemeDB.fallback_font, bar.position + Vector2(-20, -3), "%d/%d" % [ceili(health), roundi(max_health)],
			HORIZONTAL_ALIGNMENT_CENTER, w + 40, 10, Color("#ffd0d0"))

