extends Node2D
## Composition root. Wires every system together and drives the simulation
## from one fixed 60 Hz loop in a strict order, which makes hitstop trivial:
## while frozen, nothing steps (camera shake keeps going). Dialogue, the
## inventory and room transitions pause the simulation the same way.
##
## Rooms are separate scenes loaded on demand (ROOM_SCENES). Progress that
## must survive room loads (dead enemies, bosses, arenas, shards) lives in
## WorldState; see core/world_state.gd for the respawn hierarchy.
##
## Save slots: when started from the title screen, Saves.active_slot is set
## and the slot is written at every checkpoint save and on lasting progress
## (boss, arena, secret, relic). Running this scene directly starts a new
## game that is not saved (handy for testing).

const ROOM_SCENES := {
	"test_room": preload("res://world/test_room.tscn"),
	"boss_room": preload("res://world/boss_room.tscn"),
	"arena_room": preload("res://world/arena_room.tscn"),
	"secret_room": preload("res://world/secret_room.tscn"),
	"upper_room": preload("res://world/upper_room.tscn"),
}
const START_ROOM := "test_room"
const ENEMY_SCENES := {
	"weak": preload("res://enemies/dummy_enemy.tscn"),
	"flyer": preload("res://enemies/flying_dummy.tscn"),
	"strong": preload("res://enemies/strong_dummy.tscn"),
	"boss": preload("res://enemies/boss_sentinel.tscn"),
}
const COIN_SCENE := preload("res://world/objects/coin.tscn")
const RESPAWN_FADE_TIME := 0.45
## Abilities the player starts with equipped, in hotkey order (keys 1-4).
## Every registered ability starts known (in the pool); the debug overlay
## can forget or relearn them.
const STARTING_ABILITIES: Array[String] = ["nova_burst", "spirit_volley", "ascendant_form", "comet_dash"]

@onready var room_root: Node2D = $RoomRoot
@onready var enemies_root: Node2D = $Enemies
@onready var pickups_root: Node2D = $Pickups
@onready var player: Player = $Player
@onready var combat: CombatManager = $Combat
@onready var ultimates: UltimateManager = $Ultimates
@onready var effects: Effects = $Effects
@onready var feedback: Feedback = $Feedback
@onready var camera: CameraRig = $Camera
@onready var hud: Hud = $HudLayer/Hud
@onready var fade: ColorRect = $FadeLayer/Fade
@onready var dialogue: DialogueBox = $DialogueBox
@onready var inventory: InventoryMenu = $Inventory
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var background: Control = $BackgroundLayer/Background

var input := InputState.new()
var player_data := PlayerData.new()
var world := WorldState.new()
var arena_director := ArenaDirector.new()
var room: Room
var room_id := ""
var enemies: Array[Enemy] = []
var checkpoints: Array[Checkpoint] = []
var interactables: Array[Interactable] = []
var doors: Array[Door] = []
var coins: Array[Coin] = []
var breakables: Array[BreakableWall] = []
var relics: Array[Relic] = []
var playtime := 0.0
## Set false before adding to the tree to skip the opening trance (tests).
var start_in_trance := true
var current_checkpoint: Checkpoint ## The saved checkpoint, if it is in this room.
## Where death respawns the player: {room, checkpoint (node name), position}.
var respawn := {}
var focused_interactable: Interactable
var pending_respawn := false
var _pending_door := {} ## {room, door}: a doorway was entered this step.
## Screen fade while moving between rooms or respawning:
## {phase: "out"/"in", time, duration, on_black: Callable}.
var transition := {}


func _ready() -> void:
	combat.setup(self)
	ultimates.setup(UltimateContext.new(player, combat, effects, input), player_data)
	for ability in UltimateRegistry.create_default():
		ultimates.register(ability)
	for i in STARTING_ABILITIES.size():
		player_data.unlock(STARTING_ABILITIES[i])
		player_data.equip(i, STARTING_ABILITIES[i])
	for ability_id in ultimates.abilities:
		player_data.unlock(ability_id)
	feedback.setup(camera, effects)
	hud.setup(player, ultimates, player_data)
	hud.boss_provider = active_boss
	background.setup(camera)
	inventory.setup(self)
	pause_menu.setup(self)
	debug_overlay.setup(self)

	# Energy: only basic attacks fill the shared meter.
	Events.hit_landed.connect(func(info: Dictionary) -> void:
		if info.grants_energy:
			player.health.gain_energy_from_hit())
	Events.player_died.connect(func(_p: Node) -> void: pending_respawn = true)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_hazard_respawn.connect(func(_p: Node, _from: Vector2, _to: Vector2) -> void: camera.snap_to(player))

	# UI is always laid out left-to-right, even with an RTL system locale:
	# see project.godot (root_node_layout_direction) and the LTR panels.
	hud.layout_direction = Control.LAYOUT_DIRECTION_LTR
	fade.color.a = 0.0

	Events.boss_defeated.connect(func(_b: Node) -> void: write_save())
	Events.arena_cleared.connect(func(_id: String) -> void: write_save())

	_load_room_scene(START_ROOM)
	player.setup(input, room, room.get_player_spawn())
	for cp in checkpoints:
		if cp.is_start:
			activate_checkpoint(cp, false)
	if Saves.active_slot >= 0 and not Saves.pending_data.is_empty():
		apply_save_data(Saves.pending_data)
	else:
		player.reset()
		camera.snap_to(player)
		if start_in_trance:
			player.enter_trance()
		write_save() # A new game in a slot gets its first save right away.


func _physics_process(delta: float) -> void:
	input.poll()
	_handle_meta_input()
	Engine.time_scale = Config.debug.time_scale

	# Things that pause the simulation (running effects freeze too).
	effects.set_paused(pause_menu.is_open() or not transition.is_empty() or dialogue.is_open()
		or inventory.is_open() or debug_overlay.navigating or Config.debug.paused or feedback.hitstop_timer > 0.0)
	if pause_menu.is_open():
		input.end_step()
		return
	if not transition.is_empty():
		_step_transition(delta)
		input.end_step()
		return
	if dialogue.is_open():
		dialogue.step(delta, input)
		input.end_step()
		return
	if inventory.is_open() or debug_overlay.navigating or Config.debug.paused:
		input.end_step()
		return

	playtime += delta
	camera.step_shake(delta)
	# Hitstop: freeze the simulation. Input edges are kept (no end_step) so
	# presses made during the freeze still register afterwards.
	if feedback.step_hitstop(delta):
		return

	player.step(delta)
	for enemy in enemies:
		enemy.step(delta)
	combat.step(delta)
	ultimates.step(delta)
	arena_director.step(delta)
	_update_doors()
	_update_checkpoints()
	_update_pickups(delta)
	_update_interaction()
	feedback.step(delta, player)
	effects.step(delta)
	camera.follow(player, delta)

	if not _pending_door.is_empty():
		var door: Dictionary = _pending_door
		_pending_door = {}
		load_room(door.room, door.door, door.offset, door.velocity)

	# Death: wait for the collapse animation, then fade to the checkpoint.
	if pending_respawn and player.death_finished():
		pending_respawn = false
		effects.play("player_death", player.get_center())
		_begin_fade(respawn_at_checkpoint, RESPAWN_FADE_TIME)
	input.end_step()


func _handle_meta_input() -> void:
	if input.was_pressed(&"toggle_debug"):
		input.consume(&"toggle_debug")
		debug_overlay.toggle()
	if input.was_pressed(&"debug_navigate"):
		input.consume(&"debug_navigate")
		debug_overlay.set_navigating(not debug_overlay.navigating)
	if input.was_pressed(&"pause"):
		input.consume(&"pause")
		if inventory.is_open():
			inventory.toggle()
		elif not dialogue.is_open() and not debug_overlay.navigating and transition.is_empty():
			pause_menu.toggle()
	if input.was_pressed(&"inventory"):
		input.consume(&"inventory")
		if not dialogue.is_open() and not debug_overlay.navigating and transition.is_empty() and not pause_menu.is_open():
			inventory.toggle()
	if input.was_pressed(&"reset_room"):
		input.consume(&"reset_room")
		if not inventory.is_open() and not dialogue.is_open() and not debug_overlay.navigating:
			reset_room()


# ---------- Rooms ----------

## Unloads the current room and builds `id`: tiles, objects, enemies (as
## WorldState allows), arena. Entering a room revives its weak enemies.
func _load_room_scene(id: String) -> void:
	arena_director.abort()
	for enemy in enemies:
		enemy.queue_free()
	enemies.clear()
	for coin in coins:
		if coin.dropped:
			coin.queue_free()
	coins.clear()
	checkpoints.clear()
	interactables.clear()
	doors.clear()
	breakables.clear()
	relics.clear()
	current_checkpoint = null
	focused_interactable = null
	combat.reset()
	effects.clear()
	if room:
		room_root.remove_child(room)
		room.queue_free()

	room_id = id
	room = ROOM_SCENES[id].instantiate()
	room_root.add_child(room)
	world.on_room_entered(id)
	player.room = room

	for node in room.get_objects():
		if node is Checkpoint:
			checkpoints.append(node)
			if respawn.get("room", "") == id and node.name == respawn.get("checkpoint", ""):
				current_checkpoint = node
				node.set_lit(true, false)
		if node is Interactable:
			interactables.append(node)
		if node is Door:
			doors.append(node)
		if node is BreakableWall:
			breakables.append(node)
			if world.is_secret_open(node.secret_id):
				node.open()
		if node is Relic:
			relics.append(node)
			if world.has_relic(node.relic_id):
				node.collect()
		if node is Coin:
			coins.append(node)
			if world.is_coin_collected(id, node.name):
				node.collect()
	_spawn_room_enemies()
	arena_director.setup(self, room.get_arena())
	camera.setup(room.get_bounds())
	Events.room_entered.emit(id)


## Loads `id` and places the player at the door `arrival_door` (or the
## room's spawn). `offset` and `velocity` carry the player's position along
## the opening and speed over from the other room, so passing through an
## opening is seamless: no fade, no stop.
func load_room(id: String, arrival_door := "", offset := 0.0, velocity := Vector2.ZERO) -> void:
	_load_room_scene(id)
	var arrival := room.get_player_spawn()
	var arrival_velocity := Vector2(velocity.x, 0.0)
	for door in doors:
		if door.door_id == arrival_door:
			arrival = door.arrival_for(offset)
			arrival_velocity = door.arrival_velocity(velocity)
			match door.vertical:
				0:
					player.facing = door.inward
				-1: # Arriving from above (a downward transition): Rule A.
					arrival = _landing_arrival(door, arrival)
				1: # Arriving from below (an upward transition): Rule B.
					var eject := _ejection_arrival(door)
					if not eject.is_empty():
						arrival = eject.position
						arrival_velocity = eject.velocity
						player.facing = eject.side
	player.global_position = arrival
	player.velocity = arrival_velocity
	player.is_jumping = false # No jump cut on the far side: the momentum carries over whole.
	player.safe_point = arrival
	camera.snap_to(player)


# ---------- Room-design rules A / B (see GUIDELINES.md) ----------

const TILE := 32.0
const LANDING_DEPTH := 128.0 ## Rule A: ground must lie at most this far below a drop-in point.
const EJECT_MARGIN := 24.0 ## Rule B: distance from the gap edge to the player's center.
const EJECT_LIFT := 24.0 ## Rule B: the player appears this far above the floor ("offset up").
const EJECT_HOP := Vector2(60.0, -280.0) ## Rule B: small hop away from the gap.


## Rule A (downward transitions): the player must land on solid ground right
## after entering. Keeps `arrival` if ground lies below it, otherwise moves
## it along the gap to the nearest point that has ground below.
func _landing_arrival(door: Door, arrival: Vector2) -> Vector2:
	if _has_ground_below(arrival):
		return arrival
	var lo := door.gap_left() + Player.WIDTH / 2.0 + 2.0
	var hi := door.gap_right() - Player.WIDTH / 2.0 - 2.0
	for d in range(8, int(door.trigger_size.x) + 8, 8):
		for side in [-1.0, 1.0]:
			var x: float = clampf(arrival.x + side * d, lo, hi)
			if _has_ground_below(Vector2(x, arrival.y)):
				return Vector2(x, arrival.y)
	push_warning("Rule A: no ground below the downward exit '%s' in %s" % [door.door_id, room_id])
	return arrival


## True when the player's whole width has ground within LANDING_DEPTH below.
func _has_ground_below(feet: Vector2) -> bool:
	for dx in [-Player.WIDTH / 2.0 + 1.0, Player.WIDTH / 2.0 - 1.0]:
		var found := false
		for dy in range(0, int(LANDING_DEPTH) + 1, 8):
			if room.is_ground_at(feet + Vector2(dx, dy)):
				found = true
				break
		if not found:
			return false
	return true


## Rule B (upward transitions): the player appears up and to ONE side of
## the floor gap, over standable floor, so they never drop straight back
## into the transition zone. With floor on both sides the side is random.
## Returns {position, velocity, side}, or {} if neither side can be stood on.
func _ejection_arrival(door: Door) -> Dictionary:
	var options := []
	for side in [-1, 1]:
		var x: float = (door.gap_left() - EJECT_MARGIN) if side < 0 else (door.gap_right() + EJECT_MARGIN)
		var surface := _floor_surface(x, door.global_position.y - TILE / 2.0)
		if surface < INF:
			options.append({"side": side, "x": x, "surface": surface})
	if options.is_empty():
		push_warning("Rule B: no standable floor beside the upward exit '%s' in %s" % [door.door_id, room_id])
		return {}
	var pick: Dictionary = options[randi() % options.size()]
	return {
		"position": Vector2(pick.x, pick.surface - EJECT_LIFT),
		"velocity": Vector2(pick.side * EJECT_HOP.x, EJECT_HOP.y),
		"side": pick.side,
	}


## Top of the floor column at `x`, starting from a solid point at depth
## `from_y` (inside the floor). INF when there is no floor under the whole
## player width, or no head room above it.
func _floor_surface(x: float, from_y: float) -> float:
	var y := from_y
	for dx in [-Player.WIDTH / 2.0, 0.0, Player.WIDTH / 2.0]:
		if not room.is_solid_at(Vector2(x + dx, y)):
			return INF
	while room.is_solid_at(Vector2(x, y - TILE)):
		y -= TILE
	var surface := floorf(y / TILE) * TILE
	for dy in [8.0, Player.HEIGHT]:
		if room.is_solid_at(Vector2(x, surface - dy)):
			return INF
	return surface


## Doors lock while an arena fight runs, EXCEPT secret doors behind a
## breakable wall (Rule C): breaking the wall and leaving must always work.
func _update_doors() -> void:
	var arena_lock := arena_director.is_active()
	var pr := player.get_rect()
	for door in doors:
		door.locked = arena_lock and not door.secret
		if not door.locked and door.get_trigger_rect().intersects(pr):
			begin_transition(door.target_room, door.target_door, door.offset_of(player.global_position))
			return


## Openings switch rooms at once, with no fade, sound or wait. The load
## runs at the end of the current step so nothing is swapped mid-update.
func begin_transition(target_room: String, target_door: String, offset := 0.0) -> void:
	if not _pending_door.is_empty():
		return
	_pending_door = {"room": target_room, "door": target_door, "offset": offset, "velocity": player.velocity}


## Fades to black, runs `on_black`, then fades back in.
func _begin_fade(on_black: Callable, duration: float) -> void:
	transition = {"phase": "out", "time": 0.0, "duration": duration, "on_black": on_black}


func _step_transition(delta: float) -> void:
	transition.time += delta
	var k := clampf(transition.time / transition.duration, 0.0, 1.0)
	if transition.phase == "out":
		fade.color.a = k
		if k >= 1.0:
			transition.on_black.call()
			transition.phase = "in"
			transition.time = 0.0
	else:
		fade.color.a = 1.0 - k
		if k >= 1.0:
			fade.color.a = 0.0
			transition = {}


# ---------- Enemies ----------

## Instantiates an enemy of `kind` (weak / flyer / strong / boss). Returns
## null for a boss that is already defeated in this playthrough.
## `telegraph`: arena wave spawns only. The enemy appears through a short
## portal, harmless and untouchable, and never directly on top of the player.
func spawn_enemy_kind(kind: String, at: Vector2, spawn_id := "", telegraph := false) -> Enemy:
	var enemy: Enemy = ENEMY_SCENES[kind].instantiate()
	if enemy is BossSentinel and world.is_boss_defeated(enemy.boss_id):
		enemy.free()
		return null
	if telegraph:
		at = _spawn_point_away_from_player(at)
	enemies_root.add_child(enemy)
	enemy.spawn_id = spawn_id
	enemy.setup(room, at, player, telegraph)
	if enemy is BossSentinel:
		enemy.combat = combat
		enemy.effects = effects
	enemies.append(enemy)
	return enemy


const SPAWN_CLEARANCE := 110.0


func _spawn_point_away_from_player(at: Vector2) -> Vector2:
	if absf(at.x - player.global_position.x) >= SPAWN_CLEARANCE or absf(at.y - player.global_position.y) > 120.0:
		return at
	for dir in [signf(at.x - player.global_position.x), -signf(at.x - player.global_position.x)]:
		var d: float = dir if dir != 0.0 else 1.0
		var moved := Vector2(player.global_position.x + d * (SPAWN_CLEARANCE + 30.0), at.y)
		if not room.is_solid_at(moved + Vector2(0, -16)) and room.get_bounds().has_point(moved + Vector2(0, -16)):
			return moved
	return at


func remove_enemy(enemy: Enemy) -> void:
	enemies.erase(enemy)
	enemy.queue_free()


func _spawn_room_enemies() -> void:
	for spawn in room.get_enemy_spawns():
		if not world.is_dead(room_id, spawn.id):
			spawn_enemy_kind(spawn.kind, spawn.position, spawn.id)


func _on_enemy_killed(enemy: Node) -> void:
	drop_currency(enemy.get_center(), enemy.currency_drop)
	if enemy is BossSentinel:
		world.defeat_boss(enemy.boss_id)
		Events.boss_defeated.emit(enemy)
	elif enemy.spawn_id != "":
		world.mark_dead(room_id, enemy.spawn_id, enemy.tier)


## The living boss of the current room (for the HUD bar), or null.
func active_boss() -> BossSentinel:
	for enemy in enemies:
		if enemy is BossSentinel and enemy.alive:
			return enemy
	return null


## Re-creates every room enemy that WorldState allows and heals survivors.
## Revived enemies come back through a spawn telegraph.
func _refresh_room_enemies() -> void:
	var living := {}
	for enemy in enemies.duplicate():
		if enemy.spawn_id == "":
			continue
		if enemy.alive:
			living[enemy.spawn_id] = true
			enemy.restore_full_health()
		else:
			remove_enemy(enemy)
	for spawn in room.get_enemy_spawns():
		if not living.has(spawn.id) and not world.is_dead(room_id, spawn.id):
			spawn_enemy_kind(spawn.kind, spawn.position, spawn.id)


# ---------- Checkpoints ----------

## Checkpoints never save passively. `at_checkpoint` (loadout changes) is
## only true while standing at the checkpoint the player has saved at.
func _update_checkpoints() -> void:
	player.at_checkpoint = current_checkpoint != null \
		and current_checkpoint.get_interact_rect().intersects(player.get_rect())


## Makes `cp` the respawn point for deaths.
func activate_checkpoint(cp: Checkpoint, announce := true) -> void:
	if is_instance_valid(current_checkpoint) and current_checkpoint != cp:
		current_checkpoint.set_lit(false)
	current_checkpoint = cp
	cp.set_lit(true, announce)
	respawn = {"room": room_id, "checkpoint": String(cp.name), "position": cp.get_respawn_position()}
	player.spawn_position = cp.get_respawn_position()
	if announce:
		Events.checkpoint_activated.emit(cp)


## Explicit save (E or Down at a flame): the checkpoint becomes the respawn
## point, the player snaps to its exact center and health is fully restored.
## Saving also lets weak and strong enemies return (bosses never do).
## No text is shown; the optional tablet before each flame explains it.
func save_at_checkpoint(cp: Checkpoint) -> void:
	activate_checkpoint(cp, cp != current_checkpoint)
	player.global_position = cp.get_respawn_position()
	player.velocity = Vector2.ZERO
	player.safe_point = cp.get_respawn_position()
	player.health.full_heal()
	player.at_checkpoint = true
	world.on_checkpoint_rest()
	_refresh_room_enemies()
	Events.player_rested.emit(cp)
	player.enter_trance() # Saving, loading and respawning all wake from a trance.
	write_save()


# ---------- Interaction & dialogue ----------

func _update_interaction() -> void:
	var best: Interactable = null
	var best_d := INF
	var pr := player.get_rect()
	for it in interactables:
		if it.can_interact() and it.get_interact_rect().intersects(pr):
			var d := it.global_position.distance_squared_to(player.global_position)
			if d < best_d:
				best_d = d
				best = it
	for it in interactables:
		it.highlighted = it == best
	focused_interactable = best
	if best == null or not player.can_attack():
		return
	# Checkpoints also save with Down while standing on the ground.
	var down_save := best is Checkpoint and player.grounded and input.was_pressed(&"move_down")
	if input.was_pressed(&"interact") or down_save:
		best.interact(self)


func open_dialogue(data: DialogueData) -> void:
	dialogue.open(data)


# ---------- Currency ----------

func _update_pickups(delta: float) -> void:
	var pr := player.get_rect().grow(4.0)
	for coin in coins:
		coin.step(delta, room)
		if coin.collected:
			continue
		# Shards that touch a hazard are lost.
		if room.find_hazard(coin.get_rect()).has_area():
			coin.collect()
			effects.play("coin_fizzle", coin.global_position + Vector2(0, -11))
			continue
		if coin.get_rect().intersects(pr):
			coin.collect()
			if not coin.dropped:
				world.mark_coin(room_id, coin.name)
			player_data.add_currency(coin.value)
			Events.currency_collected.emit(coin.value, coin.global_position)
	for coin in coins.duplicate():
		if coin.dropped and coin.collected:
			coins.erase(coin)
			coin.queue_free()
	for relic in relics:
		if not relic.collected and relic.get_rect().intersects(pr):
			collect_relic(relic)


## Permanent upgrade: raises max health or max energy for this save.
func collect_relic(relic: Relic) -> void:
	relic.collect()
	world.take_relic(relic.relic_id)
	if relic.stat == "max_energy":
		player.health.max_energy_bonus += relic.amount
	else:
		player.health.max_health_bonus += relic.amount
		player.health.full_heal()
	Events.relic_collected.emit(relic.relic_id, relic.global_position)
	write_save()


## A swing hit a breakable wall; the last hit opens the hidden passage.
## Rule C: this never checks arena state; walls break during fights too.
func hit_breakable(wall: BreakableWall, at: Vector2) -> void:
	effects.play("wall_hit", at)
	camera.add_trauma(0.15)
	if wall.hit():
		world.open_secret(wall.secret_id)
		Events.secret_found.emit(wall.secret_id, wall.get_rect().get_center())
		write_save()
	else:
		Sfx.play("hit", 0.6)


## Bursts `amount` shards out of `origin` (used when enemies die).
func drop_currency(origin: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	var pieces := clampi(amount / 2, 1, 5)
	for i in pieces:
		var coin: Coin = COIN_SCENE.instantiate()
		coin.value = amount / pieces + (1 if i < amount % pieces else 0)
		coin.dropped = true
		pickups_root.add_child(coin)
		coin.global_position = origin
		coin.velocity = Vector2(randf_range(-160.0, 160.0), randf_range(-420.0, -260.0))
		coins.append(coin)


# ---------- Respawn / reset helpers ----------

## Death respawn and save loading: back at the saved checkpoint, exactly like
## a checkpoint save (weak and strong enemies return), with 0 energy and the
## player floating in a trance until a button is pressed.
func respawn_at_checkpoint() -> void:
	ultimates.cancel_all()
	arena_director.abort()
	world.on_checkpoint_rest()
	if not respawn.is_empty() and respawn.room != room_id:
		_load_room_scene(respawn.room)
	else:
		_refresh_room_enemies()
	if not respawn.is_empty():
		player.spawn_position = respawn.position
	combat.reset()
	player.reset() # Full health, energy 0.
	player.safe_point = player.spawn_position
	player.enter_trance()
	camera.snap_to(player)
	Events.player_respawned.emit(player)


## Respawns the player at the saved checkpoint (debug/tests: no revive, no trance).
func reset_player() -> void:
	ultimates.cancel_all()
	arena_director.abort()
	if not respawn.is_empty() and respawn.room != room_id:
		_load_room_scene(respawn.room)
	if not respawn.is_empty():
		player.spawn_position = respawn.position
	combat.reset()
	player.reset()
	camera.snap_to(player)


## Debug (R key / overlay): revives every non-boss enemy here, restores the
## placed shards and respawns the player. Bosses and cleared arenas stay.
func reset_room() -> void:
	world.revive_room(room_id)
	world.reset_room_coins(room_id)
	reset_player()
	reset_enemies()
	effects.clear()
	for coin in coins.duplicate():
		if coin.dropped:
			coins.erase(coin)
			coin.queue_free()
		else:
			coin.restore()


## Debug: re-creates the room's enemies from their spawn points.
func reset_enemies() -> void:
	arena_director.abort()
	for enemy in enemies:
		enemy.queue_free()
	enemies.clear()
	world.revive_room(room_id)
	_spawn_room_enemies()


## Debug: spawn an unsaved enemy in front of the player.
func spawn_enemy(flying: bool, kind := "") -> void:
	var k := kind if kind != "" else ("flyer" if flying else "weak")
	var home := player.global_position + Vector2(player.facing * 110.0, -30.0 if k == "flyer" else 0.0)
	# Avoid spawning inside walls: fall back to the player's position.
	if room.is_solid_at(home + Vector2(0, -8)):
		home = player.global_position + Vector2(0, -30.0 if k == "flyer" else 0.0)
	spawn_enemy_kind(k, home)


## Debug: a completely new playthrough (bosses and arenas come back).
func new_game() -> void:
	world.new_game()
	respawn = {}
	pending_respawn = false
	_pending_door = {}
	transition = {}
	fade.color.a = 0.0
	_load_room_scene(START_ROOM)
	for cp in checkpoints:
		if cp.is_start:
			activate_checkpoint(cp, false)
	reset_player()


func restore_defaults() -> void:
	Config.restore_defaults()
	debug_overlay.refresh()


# ---------- Save slots ----------

## Everything a save slot stores (respawnable enemies are not stored).
func make_save_data() -> Dictionary:
	var pos: Vector2 = respawn.get("position", player.spawn_position)
	var data := world.to_dict()
	data.merge({
		"room": respawn.get("room", room_id),
		"checkpoint": respawn.get("checkpoint", ""),
		"position": [pos.x, pos.y],
		"currency": player_data.currency,
		"unlocked": player_data.unlocked.duplicate(),
		"equipped": player_data.equipped.duplicate(),
		"slot_capacity": player_data.slot_capacity,
		"max_health_bonus": player.health.max_health_bonus,
		"max_energy_bonus": player.health.max_energy_bonus,
		"playtime": playtime,
	})
	return data


func write_save() -> void:
	if Saves.active_slot >= 0:
		Saves.write_slot(Saves.active_slot, make_save_data())


## Loading a save: progress restored, player at the saved checkpoint with 0
## energy (in a trance), respawnable enemies reset.
func apply_save_data(data: Dictionary) -> void:
	world.from_dict(data)
	player_data.currency = int(data.get("currency", 0))
	var unlocked: Array[String] = []
	for id in data.get("unlocked", STARTING_ABILITIES):
		unlocked.append(String(id))
	player_data.unlocked = unlocked
	var equipped := PlayerData.empty_slots()
	var saved_equipped: Array = data.get("equipped", [])
	for i in mini(saved_equipped.size(), equipped.size()):
		equipped[i] = String(saved_equipped[i])
	player_data.equipped = equipped
	player_data.set_capacity(int(data.get("slot_capacity", PlayerData.DEFAULT_CAPACITY)))
	player.health.max_health_bonus = float(data.get("max_health_bonus", 0.0))
	player.health.max_energy_bonus = float(data.get("max_energy_bonus", 0.0))
	playtime = float(data.get("playtime", 0.0))
	var pos: Array = data.get("position", [])
	respawn = {
		"room": data.get("room", START_ROOM),
		"checkpoint": data.get("checkpoint", ""),
		"position": Vector2(pos[0], pos[1]) if pos.size() == 2 else room.get_player_spawn(),
	}
	_load_room_scene(respawn.room)
	respawn_at_checkpoint()
	Events.loadout_changed.emit()


## Pause menu: leave to the title screen (progress is kept up to the last save).
func quit_to_title() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/title.tscn")
