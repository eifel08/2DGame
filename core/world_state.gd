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
## but not killed is back at full health when the player returns. Except
## elites (Enemy.keeps_wounds): their damage is kept in `wounds` until a
## checkpoint rest.
## Cleared arenas, collected placed shards, opened secrets and relics also
## stay that way. to_dict()/from_dict() feed the save slots; respawnable
## enemy deaths are deliberately not saved (loading resets them).

var dead_enemies := {} ## room_id -> {spawn_id: tier}
var defeated_bosses := {} ## boss_id -> true
var cleared_arenas := {} ## arena_id -> true
var collected_coins := {} ## room_id -> {coin_name: true}
var secrets := {} ## secret_id -> true (broken walls, found Type 1 hidden pockets)
var relics := {} ## relic_id -> true
var wounds := {} ## room_id -> {spawn_id: health}: damaged elites (not saved).


func new_game() -> void:
	dead_enemies.clear()
	defeated_bosses.clear()
	cleared_arenas.clear()
	collected_coins.clear()
	secrets.clear()
	relics.clear()
	wounds.clear()


func to_dict() -> Dictionary:
	var coins := {}
	for room_id in collected_coins:
		coins[room_id] = collected_coins[room_id].keys()
	return {
		"defeated_bosses": defeated_bosses.keys(),
		"cleared_arenas": cleared_arenas.keys(),
		"collected_coins": coins,
		"secrets": secrets.keys(),
		"relics": relics.keys(),
	}


func from_dict(data: Dictionary) -> void:
	new_game()
	for id in data.get("defeated_bosses", []):
		defeated_bosses[id] = true
	for id in data.get("cleared_arenas", []):
		cleared_arenas[id] = true
	var coins: Dictionary = data.get("collected_coins", {})
	for room_id in coins:
		for coin_name in coins[room_id]:
			mark_coin(room_id, coin_name)
	for id in data.get("secrets", []):
		secrets[id] = true
	for id in data.get("relics", []):
		relics[id] = true


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


## Returning to a checkpoint (saving, dying or loading) revives weak and
## strong enemies everywhere.
func on_checkpoint_rest() -> void:
	wounds.clear()
	for room_id in dead_enemies.keys():
		_revive(room_id, ["weak", "strong"])


## Debug helper: revive every non-boss enemy in a room.
func revive_room(room_id: String) -> void:
	wounds.erase(room_id)
	_revive(room_id, ["weak", "strong"])


## An elite left the room damaged: remember its health.
func set_wound(room_id: String, spawn_id: String, health: float) -> void:
	if not wounds.has(room_id):
		wounds[room_id] = {}
	wounds[room_id][spawn_id] = health


## Health an elite keeps, or -1 when it is unhurt.
func get_wound(room_id: String, spawn_id: String) -> float:
	return wounds.get(room_id, {}).get(spawn_id, -1.0)


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


# ---------- Secrets & relics ----------

func open_secret(secret_id: String) -> void:
	secrets[secret_id] = true


func is_secret_open(secret_id: String) -> bool:
	return secrets.has(secret_id)


func take_relic(relic_id: String) -> void:
	relics[relic_id] = true


func has_relic(relic_id: String) -> bool:
	return relics.has(relic_id)
