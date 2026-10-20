extends Node2D
## Composition root. Wires every system together and drives the simulation
## from one fixed 60 Hz loop in a strict order, which makes hitstop trivial:
## while frozen, nothing steps (camera shake keeps going). Dialogue and the
## inventory pause the simulation the same way.

const DUMMY_SCENE := preload("res://enemies/dummy_enemy.tscn")
const FLYER_SCENE := preload("res://enemies/flying_dummy.tscn")
const COIN_SCENE := preload("res://world/objects/coin.tscn")
## Abilities the player starts with, in hotkey order (keys 1-4).
const STARTING_ABILITIES: Array[String] = ["nova_burst", "spirit_volley", "ascendant_form", "comet_dash"]

@onready var room: Room = $TestRoom
@onready var enemies_root: Node2D = $Enemies
@onready var pickups_root: Node2D = $Pickups
@onready var player: Player = $Player
@onready var combat: CombatManager = $Combat
@onready var ultimates: UltimateManager = $Ultimates
@onready var effects: Effects = $Effects
@onready var feedback: Feedback = $Feedback
@onready var camera: CameraRig = $Camera
@onready var hud: Hud = $HudLayer/Hud
@onready var dialogue: DialogueBox = $DialogueBox
@onready var inventory: InventoryMenu = $Inventory
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var background: Control = $BackgroundLayer/Background

var input := InputState.new()
var player_data := PlayerData.new()
var enemies: Array[DummyEnemy] = []
var checkpoints: Array[Checkpoint] = []
var interactables: Array[Interactable] = []
var coins: Array[Coin] = []
var current_checkpoint: Checkpoint
var focused_interactable: Interactable
var pending_respawn := false


func _ready() -> void:
	for i in STARTING_ABILITIES.size():
		player_data.unlock(STARTING_ABILITIES[i])
		player_data.equip(i, STARTING_ABILITIES[i])
	for node in room.get_objects():
		if node is Checkpoint:
			checkpoints.append(node)
		if node is Interactable:
			interactables.append(node)
		if node is Coin:
			coins.append(node)

	player.setup(input, room, room.get_player_spawn())
	combat.setup(self)
	ultimates.setup(UltimateContext.new(player, combat, effects, input), player_data)
	for ability in UltimateRegistry.create_default():
		ultimates.register(ability)
	feedback.setup(camera, effects)
	camera.setup(room.get_bounds())
	hud.setup(player, ultimates, player_data)
	background.setup(camera)
	inventory.setup(self)
	debug_overlay.setup(self)

	# Energy: only basic attacks fill the shared meter.
	Events.hit_landed.connect(func(info: Dictionary) -> void:
		if info.grants_energy:
			player.health.gain_energy_from_hit())
	Events.player_died.connect(func(_p: Node) -> void: pending_respawn = true)
	Events.enemy_killed.connect(func(enemy: Node) -> void: drop_currency(enemy.get_center(), enemy.currency_drop))
	Events.player_hazard_respawn.connect(func(_p: Node, _from: Vector2, _to: Vector2) -> void: camera.snap_to(player))

	for cp in checkpoints:
		if cp.is_start:
			activate_checkpoint(cp, false)
	reset_enemies()
	camera.snap_to(player)


func _physics_process(delta: float) -> void:
	input.poll()
	_handle_meta_input()
	Engine.time_scale = Config.debug.time_scale

	# UI that pauses the simulation.
	if dialogue.is_open():
		dialogue.step(delta, input)
		input.end_step()
		return
	if inventory.is_open() or Config.debug.paused:
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
	if input.was_pressed(&"inventory"):
		input.consume(&"inventory")
		if not dialogue.is_open():
			inventory.toggle()
	if input.was_pressed(&"reset_room"):
		input.consume(&"reset_room")
		if not inventory.is_open() and not dialogue.is_open():
			reset_room()


# ---------- Checkpoints ----------

func _update_checkpoints() -> void:
	player.at_checkpoint = false
	var pr := player.get_rect()
	for cp in checkpoints:
		if cp.get_interact_rect().intersects(pr):
			if cp != current_checkpoint:
				activate_checkpoint(cp, true)
			player.at_checkpoint = true


## Makes `cp` the respawn point for deaths and hazard hits.
func activate_checkpoint(cp: Checkpoint, announce := true) -> void:
	if current_checkpoint and current_checkpoint != cp:
		current_checkpoint.set_lit(false)
	current_checkpoint = cp
	cp.set_lit(true, announce)
	player.spawn_position = cp.get_respawn_position()
	if announce:
		Events.checkpoint_activated.emit(cp)


## Dedicated healing: resting at a checkpoint fully restores health.
func rest_at_checkpoint(cp: Checkpoint) -> void:
	activate_checkpoint(cp, cp != current_checkpoint)
	player.health.full_heal()
	player.velocity.x = 0.0
	Events.player_rested.emit(cp)
	dialogue.open_lines("Checkpoint", PackedStringArray([
		"You rest by the flame. Your health is fully restored.",
		"While you stand here, you can change your equipped abilities in the inventory (I or Tab).",
	]))


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
	if best and input.was_pressed(&"interact") and player.can_attack():
		best.interact(self)


func open_dialogue(data: DialogueData) -> void:
	dialogue.open(data)


# ---------- Currency ----------

func _update_pickups(delta: float) -> void:
	var pr := player.get_rect().grow(4.0)
	for coin in coins:
		coin.step(delta, room)
		if not coin.collected and coin.get_rect().intersects(pr):
			coin.collect()
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


# ---------- Spawning / reset helpers (debug overlay and R key) ----------

func reset_enemies() -> void:
	for enemy in enemies:
		enemy.queue_free()
	enemies.clear()
	for spawn in room.get_enemy_spawns():
		_add_enemy(spawn.position, spawn.flying)


func spawn_enemy(flying: bool) -> void:
	var home := player.global_position + Vector2(player.facing * 110.0, -30.0 if flying else 0.0)
	# Avoid spawning inside walls: fall back to the player's position.
	if room.is_solid_at(home + Vector2(0, -8)):
		home = player.global_position + Vector2(0, -30.0 if flying else 0.0)
	_add_enemy(home, flying)


func _add_enemy(home: Vector2, flying: bool) -> void:
	var enemy: DummyEnemy = (FLYER_SCENE if flying else DUMMY_SCENE).instantiate()
	enemies_root.add_child(enemy)
	enemy.setup(room, home)
	enemies.append(enemy)


## Respawns the player at the current checkpoint.
func reset_player() -> void:
	ultimates.cancel_all()
	combat.reset()
	player.reset()
	camera.snap_to(player)


## Resets the player, enemies and placed shards. Checkpoints, collected
## currency and the loadout are progression and are kept.
func reset_room() -> void:
	reset_player()
	reset_enemies()
	effects.clear()
	for coin in coins.duplicate():
		if coin.dropped:
			coins.erase(coin)
			coin.queue_free()
		else:
			coin.restore()


func restore_defaults() -> void:
	Config.restore_defaults()
	debug_overlay.refresh()
