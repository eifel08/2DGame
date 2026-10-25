class_name BruteEnemy
extends BaseEnemy
## Large club-wielding brute. It lumbers toward the player and, in reach,
## raises its club (a long, clear wind-up) and smashes it down. The smash is
## NON-DEFLECTABLE (a swing cannot parry it) and deals DOUBLE damage
## (2 x Config.combat.contact_damage). Dodge, then punish the recovery.

@export var reach := 74.0
@export var windup_time := 0.65
@export var recover_time := 0.8


func _on_spawn() -> void:
	poise_states = ["windup", "smash"]


func smash_damage() -> float:
	return Config.combat.contact_damage * 2.0


func _think(delta: float) -> void:
	match state:
		"idle", "walk":
			var vx := 0.0
			if sees_target() and target_in_leash():
				face_target()
				var dx := absf(target.global_position.x - global_position.x)
				if dx <= reach and absf(target_center().y - get_center().y) < 70.0 and cooldown <= 0.0:
					telegraph("smash")
					enter("windup")
					move_ground(delta, 0.0)
					return
				if dx > reach * 0.7 and ground_ahead(facing):
					vx = facing * move_speed
			elif home_distance() > 8.0:
				facing = 1 if home.x > global_position.x else -1
				vx = facing * move_speed * 0.7
			state = "walk" if vx != 0.0 else "idle"
			move_ground(delta, vx)
		"windup":
			move_ground(delta, 0.0)
			if state_time >= windup_time:
				strike(front_rect(reach + 6.0, 64.0), smash_damage(), false, 0.12)
				enter("smash")
		"smash":
			move_ground(delta, 0.0)
			if state_time >= 0.15:
				enter("recover")
		"recover":
			move_ground(delta, 0.0)
			if state_time >= recover_time:
				cooldown = 0.9
				enter("idle")
		_:
			enter("idle")
