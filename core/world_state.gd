class_name WorldState
extends RefCounted
## Playthrough progress that outlives room loads (kept in memory for the
## current session; new_game() starts over).
##
## Respawn hierarchy:
##   weak enemies   - revive when their room is entered again, or at a checkpoint save
##   strong enemies - revive only at a checkpoint save
##   bosses         - never revive in this playthrough
## Survivors are re-created on every room load, so an enemy that was damaged
## but not killed is back at full health when the player returns.
## Cleared arenas and collected placed shards also stay that way.

var dead_enemies := {} ## room_id -> {spawn_id: tier}
var defeated_bosses := {} ## boss_id -> true
var cleared_arenas := {} ## arena_id -> true
var collected_coins := {} ## room_id -> {coin_name: true}


func new_game() -> void:
	dead_enemies.clear()
	defeated_bosses.clear()
	cleared_arenas.clear()
	collected_coins.clear()


# ---------- Enemies ----------

func mark_dead(room_id: String, spawn_id: String, tier: String) -> void:
	if not dead_enemies.has(room_id):
		dead_enemies[room_id] = {}
	dead_enemies[room_id][spawn_id] = tier


func is_dead(room_id: String, spawn_id: String) -> bool:
	return dead_enemies.has(room_id) and dead_enemies[room_id].has(spawn_id)


## Entering a room revives its weak enemies.
func on_room_entered(room_id: String) -> void:
	_revive(room_id, ["weak"])


## A checkpoint save revives weak and strong enemies everywhere.
func on_checkpoint_rest() -> void:
	for room_id in dead_enemies.keys():
		_revive(room_id, ["weak", "strong"])


## Debug helper: revive every non-boss enemy in a room.
func revive_room(room_id: String) -> void:
	_revive(room_id, ["weak", "strong"])


func _revive(room_id: String, tiers: Array) -> void:
	if not dead_enemies.has(room_id):
		return
	var room: Dictionary = dead_enemies[room_id]
	for spawn_id in room.keys():
		if tiers.has(room[spawn_id]):
			room.erase(spawn_id)


# ---------- Bosses & arenas ----------

func defeat_boss(boss_id: String) -> void:
	defeated_bosses[boss_id] = true


func is_boss_defeated(boss_id: String) -> bool:
	return defeated_bosses.has(boss_id)


func clear_arena(arena_id: String) -> void:
	cleared_arenas[arena_id] = true


func is_arena_cleared(arena_id: String) -> bool:
	return cleared_arenas.has(arena_id)


# ---------- Placed shards ----------

func mark_coin(room_id: String, coin_name: String) -> void:
	if not collected_coins.has(room_id):
		collected_coins[room_id] = {}
	collected_coins[room_id][coin_name] = true


func is_coin_collected(room_id: String, coin_name: String) -> bool:
	return collected_coins.has(room_id) and collected_coins[room_id].has(coin_name)


func reset_room_coins(room_id: String) -> void:
	collected_coins.erase(room_id)
