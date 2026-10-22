class_name GrappleHook
extends Node2D
## Grappling hook. Owned and stepped by CombatManager (after the player moves).
##
## Aiming (resolve_aim / aim_vector), read when the hook fires:
##   no direction held   45 degrees up, toward the facing side
##   Left or Right held  straight out to that side
##   Up held             straight up (wins over Left / Right, like attacks)
##   Down                RESERVED for a future modifier: Aim.DOWN exists, but
##                       no input selects it yet; holding Down fires the default.
##
## Phases (the player is in the "grapple" state, player/states/grapple_state.gd,
## from the throw until the hook lets go):
##   idle     nothing out; `cooldown` runs
##   fly      the tip travels up to Config.grapple.max_range. The player
##            hangs still in the air meanwhile (no gravity), so they do not
##            drop and snag on walls before the pull
##   pull     the hook holds; the state pulls the player to stop_point()
##   retract  the tip flies back to the player, then idle
##
## What the hook can hit (physics layers, see project.godot):
##   terrain  TERRAIN_MASK = layers 1 "world" (solid tiles, breakable walls,
##            closed arena gates) and 3 "one_way" (platforms). It latches and
##            pulls the player there. On a one-way platform the pull ends
##            standing ON the platform. An undiscovered hidden pocket wall
##            counts as terrain too, so the hook never reaches into a covered
##            pocket (GUIDELINES.md, Type 1).
##   enemies  layer 4 is NOT in the mask. Like every attack, enemies are hit
##            through CombatManager's enemy list (hitbox_active()). A hooked
##            enemy takes the standard attack damage, then the player is
##            pulled toward it, stops Config.grapple.enemy_safe_margin short
##            of its contact hitbox and rebounds upward, like a pogo.
##   hazards  spikes on floors, walls and ceilings (tiles with the "hazard"
##            flag; they have no collision). The flight path is checked
##            against their areas: the hook is deflected and comes back. It
##            never latches on or next to a hazard (anchor_is_safe).
##   ignored  the hidden-wall layers (5, 6).
##
## Outcomes are reported through Events (grapple_fired, grapple_latched,
## grapple_deflected, grapple_released, grapple_bounced, hit_landed);
## Feedback plays the sounds and effects.
## Art: replace Rope (Line2D) and Tip/Visual; the AnimationPlayer clips are
## "fly", "latch" and "retract".

enum Aim { DIAGONAL, HORIZONTAL, UP, DOWN }

const WORLD_LAYER := 1
const ONE_WAY_LAYER := 3
const TERRAIN_MASK := (1 << (WORLD_LAYER - 1)) | (1 << (ONE_WAY_LAYER - 1))
const HAND_OFFSET := Vector2(0.0, -4.0) ## Rope start, from the player's center.

@onready var rope: Line2D = $Rope
@onready var tip_node: Node2D = $Tip
@onready var anim: AnimationPlayer = $AnimationPlayer

var combat: CombatManager
var phase := "idle"
var tip := Vector2.ZERO ## Hook position (global).
var dir := Vector2.RIGHT ## Flight direction.
var travelled := 0.0
var anchor := Vector2.ZERO ## Where the hook holds (global).
var anchor_one_way := false ## The anchor is on a one-way platform.
var platform_top := 0.0 ## Top of that platform (feet height after the pull).
var target_enemy: Enemy ## The hooked enemy during an enemy pull, else null.
var _enemy_offset := Vector2.ZERO ## Anchor relative to the hooked enemy.
var cooldown := 0.0
var buffer := 0.0
var _anim_name := ""


func setup(p_combat: CombatManager) -> void:
	combat = p_combat
	reset()


## Room loads, respawns and resets: the hook is gone at once.
func reset() -> void:
	phase = "idle"
	target_enemy = null
	cooldown = 0.0
	buffer = 0.0
	travelled = 0.0
	if combat and combat.get_player().fsm.is_in("grapple"):
		combat.get_player().fsm.change("normal")
	_update_visual()


func is_idle() -> bool:
	return phase == "idle"


func is_flying() -> bool:
	return phase == "fly"


func is_pulling() -> bool:
	return phase == "pull"


# ---------- Aiming ----------

static func resolve_aim(axis_x: int, axis_y: int) -> Aim:
	if axis_y < 0:
		return Aim.UP
	# Reserved: `if axis_y > 0: return Aim.DOWN` once the down modifier is designed.
	if axis_x != 0:
		return Aim.HORIZONTAL
	return Aim.DIAGONAL


static func aim_vector(aim: Aim, axis_x: int, facing: int) -> Vector2:
	match aim:
		Aim.UP:
			return Vector2.UP
		Aim.HORIZONTAL:
			return Vector2(signf(axis_x), 0.0)
		# Aim.DOWN: reserved, never selected yet (falls through to the default).
		_:
			return Vector2(facing, -1.0).normalized()


# ---------- Per-step update ----------

func can_fire(p: Player) -> bool:
	return Config.upgrades.grapple and phase == "idle" and cooldown <= 0.0 \
		and p.fsm.is_in("normal") and combat.attack.is_empty()


func step(delta: float) -> void:
	var p := combat.get_player()
	if phase == "idle":
		cooldown -= delta
	buffer -= delta
	if combat.game.input.was_pressed(&"grapple"):
		buffer = Config.grapple.buffer_time
	if buffer > 0.0 and can_fire(p):
		fire(p)
	match phase:
		"fly":
			_step_fly(delta, p)
		"retract":
			_step_retract(delta, p)
		"pull":
			if target_enemy:
				anchor = target_enemy.global_position + _enemy_offset
	_update_visual()
	if _anim_name != "" and anim.has_animation(_anim_name):
		anim.advance(delta) # Manual mode: hitstop freezes the hook too.


func fire(p: Player) -> void:
	var ix := p.input.axis_x()
	var aim := resolve_aim(ix, p.input.axis_y())
	dir = aim_vector(aim, ix, p.facing)
	if aim == Aim.HORIZONTAL:
		p.facing = ix
	tip = rope_origin(p)
	travelled = 0.0
	target_enemy = null
	anchor_one_way = false
	buffer = 0.0
	phase = "fly"
	_play("fly")
	Events.grapple_fired.emit(tip, dir)
	p.fsm.change("grapple", {"hook": self}) # Hangs in the air while the hook flies.


func rope_origin(p: Player) -> Vector2:
	return p.get_center() + HAND_OFFSET


func _step_fly(delta: float, p: Player) -> void:
	var g = Config.grapple
	var dist: float = minf(g.hook_speed * delta, g.max_range - travelled)
	var from := tip
	var r: float = g.hook_radius

	# Terrain: physics ray on the world and one-way layers only.
	var terrain_d := INF
	var query := PhysicsRayQueryParameters2D.create(from, from + dir * dist, TERRAIN_MASK, [p.get_rid()])
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		terrain_d = from.distance_to(hit.position)
	for wall in combat.game.hidden_pockets:
		if not wall.discovered:
			terrain_d = minf(terrain_d, Geom.box_cast_distance(from, Vector2.ZERO, dir, wall.get_rect()))

	# Hazards: their areas, along the path.
	var hazard_d := INF
	var path := Rect2(from, Vector2.ZERO).expand(from + dir * dist).grow(r)
	for h in combat.get_room().hazards_in(path):
		hazard_d = minf(hazard_d, Geom.box_cast_distance(from, Vector2(r, r), dir, h))

	# Enemies: the first living hitbox along the path.
	var enemy: Enemy = null
	var enemy_d := INF
	for e in combat.get_enemies():
		if not e.hitbox_active():
			continue
		var d := Geom.box_cast_distance(from, Vector2(r, r), dir, e.get_rect())
		if d <= dist and d < enemy_d:
			enemy_d = d
			enemy = e

	var first := minf(minf(terrain_d, hazard_d), enemy_d)
	if first > dist:
		tip = from + dir * dist
		travelled += dist
		if travelled >= g.max_range - 0.01:
			release()
		return
	tip = from + dir * first
	if hazard_d <= first:
		_deflect()
	elif enemy and enemy_d <= first:
		_hook_enemy(enemy, p)
	else:
		_hook_terrain(p)


## The hook touched a hazard: no latch, it bounces off and comes back.
func _deflect() -> void:
	Events.grapple_deflected.emit(tip)
	release()


func _hook_terrain(p: Player) -> void:
	anchor = tip
	if not anchor_is_safe(anchor):
		_deflect()
		return
	if not p.fsm.is_in("grapple"):
		release()
		return
	# A point just past the hit, inside the collider, tells what was hit.
	var inside := anchor + dir * 2.0
	var room := combat.get_room()
	anchor_one_way = room.is_one_way_at(inside)
	if anchor_one_way:
		platform_top = room.cell_rect_at(inside).position.y
	_start_pull(false)


## Standard attack damage (with the player's damage modifiers), then a pull
## that stops short of the enemy's contact hitbox and ends in a rebound.
## A killed enemy means no pull.
func _hook_enemy(enemy: Enemy, p: Player) -> void:
	var c = Config.combat
	anchor = tip
	combat.apply_damage(enemy, {
		"damage": c.attack_damage * p.stat("damage_mul"),
		"direction": Vector2(dir.x if dir.x != 0.0 else signf(enemy.get_center().x - p.get_center().x), dir.y * 0.5),
		"knockback": c.enemy_knockback * Config.grapple.enemy_knockback_mul,
		"source": "grapple",
		"strength": 0.8,
		"position": anchor,
	})
	if not enemy.hitbox_active() or not p.fsm.is_in("grapple"):
		release()
		return
	target_enemy = enemy
	_enemy_offset = anchor - enemy.global_position
	_start_pull(true)


func _start_pull(on_enemy_hit: bool) -> void:
	phase = "pull"
	_play("latch")
	Events.grapple_latched.emit(anchor, on_enemy_hit)


## Lets go: the tip flies back to the player.
func release() -> void:
	if phase == "idle" or phase == "retract":
		return
	phase = "retract"
	target_enemy = null
	_play("retract")
	Events.grapple_released.emit(tip)


## Called by GrappleState.exit(): however the state ended, the hook comes back.
func on_state_ended() -> void:
	if phase == "fly" or phase == "pull":
		release()


func _step_retract(delta: float, p: Player) -> void:
	var home := rope_origin(p)
	var to := home - tip
	var dist := Config.grapple.retract_speed * delta
	if to.length() <= dist:
		phase = "idle"
		cooldown = Config.grapple.cooldown
		_play("")
		return
	tip += to.normalized() * dist


# ---------- Pull targets (read by GrappleState) ----------

## Where the player's CENTER should stop:
##   wall / ceiling   where the player's box first touches the anchor
##   one-way platform standing on the platform, above the anchor
##   enemy            where the box touches the enemy's contact hitbox grown
##                    by the safety margin
## Returns the current center when the target is gone or already reached.
func stop_point(p: Player) -> Vector2:
	var c := p.get_center()
	if anchor_one_way and target_enemy == null:
		return Vector2(anchor.x, platform_top - Player.HEIGHT / 2.0 - 0.5)
	var half := Vector2(Player.WIDTH, Player.HEIGHT) / 2.0
	var rect: Rect2
	var aim_at := anchor
	if target_enemy:
		if not is_instance_valid(target_enemy) or not target_enemy.hitbox_active():
			return c
		rect = target_enemy.get_rect().grow(Config.grapple.enemy_safe_margin)
		aim_at = target_enemy.get_center()
	else:
		rect = Rect2(anchor, Vector2.ZERO).grow(1.0)
	var to := aim_at - c
	if to.length() < 0.001:
		return c
	var d := Geom.box_cast_distance(c, half, to.normalized(), rect)
	if d == INF:
		return c
	return c + to.normalized() * d


func on_enemy() -> bool:
	return target_enemy != null


## False when the anchor touches a hazard (spikes): the hook does not hold
## there, so it never drags the player into one.
func anchor_is_safe(point: Vector2) -> bool:
	return not combat.get_room().find_hazard(Rect2(point - Vector2(10, 10), Vector2(20, 20))).has_area()


# ---------- Visuals (placeholders) ----------

func _play(clip: String) -> void:
	_anim_name = clip
	if clip != "" and anim.has_animation(clip):
		anim.play(clip)
		anim.advance(0.0)


func _update_visual() -> void:
	if not is_node_ready():
		return
	visible = phase != "idle"
	if not visible or combat == null:
		return
	var from := rope_origin(combat.get_player())
	var at := anchor if phase == "pull" else tip
	rope.points = PackedVector2Array([to_local(from), to_local(at)])
	tip_node.position = to_local(at)
	var along := at - from
	tip_node.rotation = along.angle() if along.length() > 1.0 else dir.angle()
