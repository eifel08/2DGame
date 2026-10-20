class_name ArenaDirector
extends RefCounted
## Runs the arena encounter of the current room. Entering the trigger seals
## the gates and spawns the waves in order (weak / strong enemies, optionally
## a boss last). The next wave starts once every enemy of the current wave is
## dead. After the last wave the gates open and the arena is cleared for the
## rest of the playthrough (WorldState): it never repeats. Dying aborts the
## encounter; it starts over fresh next time.

const WAVE_DELAY := 0.9

var game: Node
var arena: ArenaEncounter
var state := "none" ## none, idle, active, cleared
var wave := -1
var wave_enemies: Array[Enemy] = []
var _timer := 0.0


func setup(p_game: Node, p_arena: ArenaEncounter) -> void:
	game = p_game
	arena = p_arena
	wave = -1
	wave_enemies.clear()
	if arena == null:
		state = "none"
	elif game.world.is_arena_cleared(arena.arena_id):
		state = "cleared"
	else:
		state = "idle"
	if arena:
		arena.set_gates(false)


func is_active() -> bool:
	return state == "active"


func step(delta: float) -> void:
	match state:
		"idle":
			if arena.get_trigger_rect().intersects(game.player.get_rect()):
				_start()
		"active":
			wave_enemies = wave_enemies.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and e.alive)
			if wave_enemies.is_empty():
				_timer -= delta
				if _timer <= 0.0:
					_spawn_next_wave()


func _start() -> void:
	state = "active"
	wave = -1
	_timer = WAVE_DELAY * 0.6
	arena.set_gates(true)
	Events.arena_started.emit(arena.arena_id)


func _spawn_next_wave() -> void:
	wave += 1
	if wave >= arena.wave_count():
		_clear()
		return
	for spawn in arena.wave_spawns(wave):
		var enemy: Enemy = game.spawn_enemy_kind(spawn.kind, spawn.position, "", true)
		if enemy:
			wave_enemies.append(enemy)
	_timer = WAVE_DELAY
	Events.arena_wave_started.emit(arena.arena_id, wave)


func _clear() -> void:
	state = "cleared"
	arena.set_gates(false)
	game.world.clear_arena(arena.arena_id)
	Events.arena_cleared.emit(arena.arena_id)


## Player died or left: remove this attempt's enemies and reopen the gates.
func abort() -> void:
	if state != "active":
		return
	for enemy in wave_enemies:
		if is_instance_valid(enemy):
			game.remove_enemy(enemy)
	wave_enemies.clear()
	wave = -1
	state = "idle"
	arena.set_gates(false)
