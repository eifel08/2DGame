class_name AmbusherEnemy
extends BaseEnemy
## Teleporting ambush enemy. While the player is out of range it wanders left
## and right. The INSTANT the player comes into range it vanishes: there is no
## free moment to hit it first. It waits unseen for a short beat, then a
## semi-transparent GHOST flickers BEHIND the player (the warning), and it
## materializes there for a quick strike. The strike is deflectable: a swing
## toward the ghost in time parries it. While vanished, hidden or a ghost it
## cannot be hit and cannot hurt; after the strike it is open for a moment.

@export var vanish_time := 0.15 ## Fade-out (already untouchable).
@export var hidden_time := 0.45 ## The short cooldown before the ambush.
@export var ghost_time := 0.4
@export var strike_damage := 15.0
@export var behind := 46.0 ## Distance behind the player.

var ghost_at := Vector2.ZERO


func _on_spawn() -> void:
	poise_states = ["appear", "strike"] # Committed: the blade comes, parry it.


func hitbox_active() -> bool:
	return super() and not state in ["vanish", "hidden", "ghost"]


func _think(delta: float) -> void:
	match state:
		"idle":
			visual_alpha = 1.0
			if sees_target() and target_in_leash():
				telegraph("vanish")
				enter("vanish") # At once: no window to hit it first.
				velocity = Vector2.ZERO
				return
			if home_distance() > leash_range:
				global_position = home # Lost: blink home.
			wander(delta, move_speed * 0.8)
		"vanish":
			visual_alpha = 1.0 - state_time / vanish_time
			velocity = Vector2.ZERO
			if state_time >= vanish_time:
				visual_alpha = 0.0
				enter("hidden")
		"hidden": # Gone. A short cooldown before the ambush.
			visual_alpha = 0.0
			velocity = Vector2.ZERO
			if state_time >= hidden_time:
				if not target_valid() or not target_in_leash():
					global_position = home
					enter("idle")
					return
				ghost_at = _spot_behind_target()
				global_position = ghost_at
				face_target()
				enter("ghost")
		"ghost": # The warning: a flickering, see-through copy behind the player.
			velocity = Vector2.ZERO
			visual_alpha = 0.3 + 0.15 * sin(state_time * 40.0)
			face_target()
			if state_time >= ghost_time:
				visual_alpha = 1.0
				enter("appear")
		"appear":
			move_ground(delta, 0.0)
			if state_time >= 0.12:
				strike(front_rect(44.0, 40.0, 2.0), strike_damage, true, 0.1)
				enter("strike")
		"strike":
			move_ground(delta, 0.0)
			if state_time >= 0.12:
				enter("recover")
		"recover", "staggered":
			move_ground(delta, 0.0)
			if state_time >= 0.5:
				enter("idle")
		_:
			enter("idle")


## Feet position just behind the player (the side they are not facing), on
## the ground. Falls back to the other side if that spot is inside a wall.
func _spot_behind_target() -> Vector2:
	var p := target as Player
	var back := -p.facing if p else -1
	for side in [back, -back]:
		var spot := Vector2(target.global_position.x + side * behind, target.global_position.y)
		if not room.is_solid_at(spot + Vector2(0, -size.y / 2.0)):
			for dy in range(0, 200, 8): # Settle onto the ground below.
				if room.is_ground_at(spot + Vector2(0, dy + 1)):
					return spot + Vector2(0, dy)
			return spot
	return target.global_position
