extends Node2D
## Composition root. Wires every system together and drives the simulation
## from one fixed 60 Hz loop in a strict order, which makes hitstop trivial:
## while frozen, nothing steps (camera shake keeps going). Dialogue, the
## inventory and room transitions pause the simulation the same way.
##
## Rooms are separate scenes loaded on demand (ROOM_SCENES). Progress that
## must survive room loads (dead enemies, bosses, arenas, shards) lives in
## WorldState; see core/world_state.gd for the respawn hierarchy.

const ROOM_SCENES := {
	"test_room": preload("res://world/test_room.tscn"),
	"boss_room": preload("res://world/boss_room.tscn"),
}
const START_ROOM := "test_room"
const ENEMY_SCENES := {
	"weak": preload("res://enemies/dummy_enemy.tscn"),
	"flyer": preload("res://enemies/flying_dummy.tscn"),
	"strong": preload("res://enemies/strong_dummy.tscn"),
	"boss": preload("res://enemies/boss_sentinel.tscn"),
}
const COIN_SCENE := preload("res://world/objects/coin.tscn")
const FADE_TIME := 0.22
## Abilities the player starts with, in hotkey order (keys 1-4).
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
var current_checkpoint: Checkpoint ## The saved checkpoint, if it is in this room.
## Where death respawns the player: {room, checkpoint (node name), position}.
var respawn := {}
var focused_interactable: Interactable
var pending_respawn := false
var transition := {} ## {phase: "out"/"in", time, room, door} while moving between rooms.


func _ready() -> void:
	for i in STARTING_ABILITIES.size():
		player_data.unlock(STARTING_ABILITIES[i])
		player_data.equip(i, STARTING_ABILITIES[i])

	combat.setup(self)
	ultimates.setup(UltimateContext.new(player, combat, effects, input), player_data)
	for ability in UltimateRegistry.create_default():
		ultimates.register(ability)
	feedback.setup(camera, effects)
	hud.setup(player, ultimates, player_data)
	hud.boss_provider = active_boss
	background.setup(camera)
	inventory.setup(self)
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

	_load_room_scene(START_ROOM)
	player.setup(input, room, room.get_player_spawn())
	for cp in checkpoints:
		if cp.is_start:
			activate_checkpoint(cp, false)
	player.reset()
	camera.snap_to(player)


func _physics_process(delta: float) -> void:
	input.poll()
	_handle_meta_input()
	Engine.time_scale = Config.debug.time_scale

	# Things that pause the simulation.
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

	if pending_respawn:
		pending_respawn = false
		effects.burst(player.get_center(), {"count": 40, "color": Color("#ff6b6b"), "speed": 400.0, "size": 5.0})
		reset_player()
	input.end_step()


func _handle_meta_input() -> void:
	if input.was_pressed(&"toggle_debug"):
		input.consume(&"toggle_debug")
		debug_overlay.toggle()
	if input.was_pressed(&"debug_navigate"):
		input.consume(&"debug_navigate")
		debug_overlay.set_navigating(not debug_overlay.navigating)
	if input.was_pressed(&"inventory"):
		input.consume(&"inventory")
		if not dialogue.is_open() and not debug_overlay.navigating and transition.is_empty():
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
		if node is Coin:
			coins.append(node)
			if world.is_coin_collected(id, node.name):
				node.collect()
	_spawn_room_enemies()
	arena_director.setup(self, room.get_arena())
	camera.setup(room.get_bounds())
	Events.room_entered.emit(id)


## Loads `id` and places the player at the door `arrival_door` (or the
## room's spawn point when empty).
func load_room(id: String, arrival_door := "") -> void:
	_load_room_scene(id)
	var arrival := room.get_player_spawn()
	for door in doors:
		if door.door_id == arrival_door:
			arrival = door.get_arrival_position()
			player.facing = door.inward
	player.global_position = arrival
	player.velocity = Vector2.ZERO
	player.safe_point = arrival
	camera.snap_to(player)


func _update_doors() -> void:
	var locked := arena_director.is_active()
	var pr := player.get_rect()
	for door in doors:
		door.locked = locked
		if not locked and door.get_trigger_rect().intersects(pr):
			begin_transition(door.target_room, door.target_door)
			return


func begin_transition(target_room: String, target_door: String) -> void:
	transition = {"phase": "out", "time": 0.0, "room": target_room, "door": target_door}


func _step_transition(delta: float) -> void:
	transition.time += delta
	var k := clampf(transition.time / FADE_TIME, 0.0, 1.0)
	if transition.phase == "out":
		fade.color.a = k
		if k >= 1.0:
			load_room(transition.room, transition.door)
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
func spawn_enemy_kind(kind: String, at: Vector2, spawn_id := "") -> Enemy:
	var enemy: Enemy = ENEMY_SCENES[kind].instantiate()
	if enemy is BossSentinel and world.is_boss_defeated(enemy.boss_id):
		enemy.free()
		return null
	enemies_root.add_child(enemy)
	enemy.spawn_id = spawn_id
	enemy.setup(room, at, player)
	if enemy is BossSentinel:
		enemy.combat = combat
	enemies.append(enemy)
	return enemy


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
			effects.burst(coin.global_position + Vector2(0, -11), {"count": 6, "color": Color("#9aa7c7"), "speed": 90.0, "gravity": -60.0, "life": 0.35, "size": 3.0})
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

## Respawns the player at the saved checkpoint (loading its room if needed).
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
	spawn_enemy_kind(k, home, "")


## Debug: a completely new playthrough (bosses and arenas come back).
func new_game() -> void:
	world.new_game()
	respawn = {}
	_load_room_scene(START_ROOM)
	for cp in checkpoints:
		if cp.is_start:
			activate_checkpoint(cp, false)
	reset_player()


func restore_defaults() -> void:
	Config.restore_defaults()
	debug_overlay.refresh()
