extends Node2D
## Composition root. Wires every system together and drives the simulation
## from one fixed 60 Hz loop in a strict order, which makes hitstop trivial:
## while frozen, nothing steps (camera shake keeps going).

const DUMMY_SCENE := preload("res://enemies/dummy_enemy.tscn")
const FLYER_SCENE := preload("res://enemies/flying_dummy.tscn")

@onready var room: Room = $TestRoom
@onready var enemies_root: Node2D = $Enemies
@onready var player: Player = $Player
@onready var combat: CombatManager = $Combat
@onready var ultimates: UltimateManager = $Ultimates
@onready var effects: Effects = $Effects
@onready var feedback: Feedback = $Feedback
@onready var camera: CameraRig = $Camera
@onready var hud: Hud = $HudLayer/Hud
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var background: Control = $BackgroundLayer/Background

var input := InputState.new()
var enemies: Array[DummyEnemy] = []
var pending_respawn := false


func _ready() -> void:
	player.setup(input, room, room.get_player_spawn())
	combat.setup(self)
	ultimates.setup(UltimateContext.new(player, combat, effects, input))
	for ability in UltimateRegistry.create_default():
		ultimates.register(ability)
	feedback.setup(camera, effects)
	camera.setup(room.get_bounds())
	hud.setup(player, ultimates)
	background.setup(camera)
	debug_overlay.setup(self)

	# Energy: only basic attacks fill the shared meter.
	Events.hit_landed.connect(func(info: Dictionary) -> void:
		if info.grants_energy:
			player.health.gain_energy_from_hit())
	Events.player_died.connect(func(_p: Node) -> void: pending_respawn = true)

	reset_enemies()
	camera.snap_to(player)


func _physics_process(delta: float) -> void:
	input.poll()
	_handle_meta_input()
	Engine.time_scale = Config.debug.time_scale
	if Config.debug.paused:
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
	if input.was_pressed(&"cycle_ultimate"):
		input.consume(&"cycle_ultimate")
		ultimates.cycle(1)
	if input.was_pressed(&"reset_room"):
		input.consume(&"reset_room")
		reset_room()


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


func reset_player() -> void:
	ultimates.cancel_all()
	combat.reset()
	player.reset()
	camera.snap_to(player)


func reset_room() -> void:
	reset_player()
	reset_enemies()
	effects.clear()


func restore_defaults() -> void:
	Config.restore_defaults()
	debug_overlay.refresh()
