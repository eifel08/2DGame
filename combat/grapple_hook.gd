class_name GrappleHook
extends Node2D
## Grappling hook. Owned and stepped by CombatManager (after the player moves).
##
## Aiming: resolve_aim picks the rule, aim_vector turns it into a direction.
## Input and "airborne" (`not is_on_floor()`) are read on the frame the
## grapple key is pressed, even when the throw itself is buffered.
## Left / Right held on that frame turn the player first, so the hook goes the
## held way (also during a wall slide or an animation lock). Three rules:
##
##   | Key                  | State              | Angle            | Action |
##   | UP                   | grounded / airborne| 90, straight up  | pull   |
##   | DOWN                 | airborne only      | 45 up, facing    | swing  |
##   | anything else        | grounded / airborne| 0, facing        | pull   |
##   | (none, LEFT, RIGHT, DOWN on the ground)                              |
##
## Phases (the player is in the "grapple" state, player/states/grapple_state.gd,
## from the throw until the hook lets go):
##   idle     nothing out; `cooldown` runs
##   fly      the tip travels up to Config.grapple.max_range. The player
##            hangs still in the air meanwhile (no gravity)
##   pull     latched (pull mode): the state pulls the player to stop_point()
##   swing    latched (swing mode): the state swings the player on a rope of
##            fixed length around `anchor` (a pendulum). It lets go on jump /
##            grapple / dash, on damage, on touching terrain, or when the rope
##            crosses an enemy or a hazard (rope_obstructed)
##   hold     a pull that reached a grapple peg: the hook stays attached and
##            the player hangs still under the peg until any action but
##            Left / Right (GrappleState)
##   retract  the tip flies back to the player, then idle
##
## What the hook can hit (physics layers, see project.godot):
##   terrain  TERRAIN_MASK = layers 1 "world" (solid tiles, breakable walls,
##            closed arena gates) and 3 "one_way" (platforms). Three parallel
##            rays (the path and Config.grapple.hook_radius to each side) make
##            the hook forgiving. On a one-way platform a pull ends standing ON
##            it. An undiscovered hidden pocket wall counts as terrain too, so
##            the hook never reaches into a covered pocket (GUIDELINES.md, Type 1).
##   enemies  layer 4 is NOT in the mask. Like every attack, enemies are hit
##            through CombatManager's enemy list (hitbox_active()), with the
##            same forgiving radius. A hooked enemy is NOT hurt on contact:
##            the player is pulled toward it, stops
##            Config.grapple.enemy_safe_margin short of its contact hitbox,
##            rebounds upward (nearly a pogo) and only THEN strikes it for the
##            standard attack damage (strike_enemy). A pull that is cancelled
##            on the way deals no damage. In swing mode an enemy hit is a pull.
##   hazards  spikes on floors, walls and ceilings (tiles with the "hazard"
##            flag; they have no collision). The path is checked against their
##            areas with a thin tip (Config.grapple.hazard_radius): the hook is
##            deflected and comes back. It never latches on or next to a
##            hazard (anchor_is_safe).
##   pegs     GrapplePeg areas on layer 7 (PEG_MASK), found by the same three
##            rays (areas only). A swing throw swings on the peg; any other
##            throw pulls to it and then holds (phase "hold"). Pegs have no
##            body collision: the player passes through them.
##   movers   moving pegs and Platform objects (one-way layer) carry the
##            anchor: Game._update_movers calls follow_anchor() before the
##            player moves, so a pull, hold or swing rides along. A crumbled
##            breakable peg or platform makes the hook let go.
##   ignored  the hidden-wall layers (5, 6).
##
## Outcomes are reported through Events (grapple_fired, grapple_latched,
## grapple_deflected, grapple_released, grapple_bounced, grapple_swing_ended,
## hit_landed); Feedback plays the sounds and effects.
## Art: replace Rope (Line2D) and Tip/Visual; the AnimationPlayer clips are
## "fly", "latch" and "retract".

enum Aim { HORIZONTAL, UP, SWING }

const WORLD_LAYER := 1
const ONE_WAY_LAYER := 3
const TERRAIN_MASK := (1 << (WORLD_LAYER - 1)) | (1 << (ONE_WAY_LAYER - 1))
const PEG_MASK := GrapplePeg.MASK
const HAND_OFFSET := Vector2(0.0, -4.0) ## Rope start, from the player's center.

@onready var rope: Line2D = $Rope
@onready var tip_node: Node2D = $Tip
@onready var anim: AnimationPlayer = $AnimationPlayer

var combat: CombatManager
var phase := "idle"
var swing_mode := false ## Fired as a swing (Down in the air): latching starts a pendulum.
var tip := Vector2.ZERO ## Hook position (global).
var dir := Vector2.RIGHT ## Flight direction.
var travelled := 0.0
var anchor := Vector2.ZERO ## Where the hook holds (global).
var anchor_one_way := false ## The anchor is on a one-way platform.
var platform_top := 0.0 ## Top of that platform (feet height after the pull).
var target_enemy: Enemy ## The hooked enemy during an enemy pull, else null.
var target_peg: GrapplePeg ## The hooked peg (pull, hold or swing), else null.
var anchor_platform: Platform ## The hooked Platform object, else null.
var _platform_offset := Vector2.ZERO ## Anchor relative to that platform.
var _enemy_offset := Vector2.ZERO ## Anchor relative to the hooked enemy.
var cooldown := 0.0
var buffer := 0.0
## Read on the frame the grapple key was pressed (used by fire()).
var _press_x := 0
var _press_y := 0
var _press_airborne := false
var _anim_name := ""


func setup(p_combat: CombatManager) -> void:
	combat = p_combat
	reset()


## Room loads, respawns and resets: the hook is gone at once.
func reset() -> void:
	phase = "idle"
	target_enemy = null
	target_peg = null
	anchor_platform = null
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


func is_swinging() -> bool:
	return phase == "swing"


func is_holding() -> bool:
	return phase == "hold"


func is_latched() -> bool:
	return phase == "pull" or phase == "swing" or phase == "hold"


# ---------- Aiming ----------

## The three rules. `axis_y`: -1 Up held, 1 Down held, 0 neither.
static func resolve_aim(axis_y: int, airborne: bool) -> Aim:
	if axis_y < 0:
		return Aim.UP # 1. Up, grounded or airborne: 90 degrees, pull.
	if axis_y > 0 and airborne:
		return Aim.SWING # 2. Down, airborne only: 45 degrees up, swing.
	return Aim.HORIZONTAL # 3. Everything else: 0 degrees, pull.


## `side`: 1 right, -1 left (the player's facing, already turned by fire()).
static func aim_vector(aim: Aim, side: int) -> Vector2:
	match aim:
		Aim.UP:
			return Vector2.UP
		Aim.SWING:
			return Vector2(side, -1.0).normalized()
	return Vector2(side, 0.0)


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
		_press_x = p.input.axis_x()
		_press_y = p.input.axis_y()
		_press_airborne = not p.is_on_floor()
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
	if _press_x != 0:
		p.facing = _press_x # Left / Right win over any other facing.
		p.flip.scale.x = p.facing # Show the turn on this frame too.
	var aim := resolve_aim(_press_y, _press_airborne)
	dir = aim_vector(aim, p.facing)
	swing_mode = aim == Aim.SWING
	tip = rope_origin(p)
	travelled = 0.0
	target_enemy = null
	target_peg = null
	anchor_platform = null
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

	# Terrain: three parallel rays on the world and one-way layers.
	var terrain := _cast_terrain(from, dist, r, p)
	var terrain_d: float = terrain.distance
	for wall in combat.game.hidden_pockets:
		if not wall.discovered:
			var d := Geom.box_cast_distance(from, Vector2(r, r), dir, wall.get_rect())
			if d < terrain_d:
				terrain_d = d
				terrain.point = from + dir * d

	# Hazards: their areas, along the path, with a thin tip.
	var hazard_d := INF
	var hr: float = g.hazard_radius
	var path := Rect2(from, Vector2.ZERO).expand(from + dir * dist).grow(hr)
	for h in combat.get_room().hazards_in(path):
		hazard_d = minf(hazard_d, Geom.box_cast_distance(from, Vector2(hr, hr), dir, h))

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

	# Pegs: their own layer, the same forgiving rays.
	var peg := _cast_pegs(from, dist, r, p)
	var peg_d: float = peg.distance

	var first := minf(minf(minf(terrain_d, hazard_d), enemy_d), peg_d)
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
	elif peg.peg and peg_d <= first:
		_hook_peg(peg.peg, p)
	else:
		tip = terrain.point # The surface point (a side ray may have caught it).
		_hook_terrain(p, terrain.collider)


## The nearest terrain hit of three parallel rays: the path itself and one
## ray `r` to each side. Returns {distance (along the path), point, collider}.
## A side ray that starts inside solid (the player hugging a wall) is skipped,
## so it never latches on the wall the player stands against.
func _cast_terrain(from: Vector2, dist: float, r: float, p: Player) -> Dictionary:
	var best := {"distance": INF, "point": from, "collider": null}
	var space := get_world_2d().direct_space_state
	var side := dir.orthogonal() * r
	for offset in [Vector2.ZERO, side, -side]:
		var start: Vector2 = from + offset
		if offset != Vector2.ZERO and combat.get_room().is_solid_at(start):
			continue
		var query := PhysicsRayQueryParameters2D.create(start, start + dir * dist, TERRAIN_MASK, [p.get_rid()])
		query.hit_from_inside = offset == Vector2.ZERO
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var d: float = (hit.position - start).dot(dir)
		if d < best.distance:
			best = {"distance": d, "point": hit.position, "collider": hit.collider}
	return best


## The nearest peg hit of the same three rays, on the peg layer (areas
## only). A ray that starts inside a peg ignores it. Returns {distance, peg}.
func _cast_pegs(from: Vector2, dist: float, r: float, p: Player) -> Dictionary:
	var best := {"distance": INF, "peg": null}
	var space := get_world_2d().direct_space_state
	var side := dir.orthogonal() * r
	for offset in [Vector2.ZERO, side, -side]:
		var start: Vector2 = from + offset
		var query := PhysicsRayQueryParameters2D.create(start, start + dir * dist, PEG_MASK, [p.get_rid()])
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not (hit.collider is GrapplePeg):
			continue
		var d: float = (hit.position - start).dot(dir)
		if d < best.distance:
			best = {"distance": d, "peg": hit.collider}
	return best


## The hook touched a hazard: no latch, it bounces off and comes back.
func _deflect() -> void:
	Events.grapple_deflected.emit(tip)
	release()


func _hook_terrain(p: Player, collider: Object = null) -> void:
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
	if collider is Platform: # A platform object: one-way, and it may move.
		anchor_platform = collider
		_platform_offset = anchor - anchor_platform.global_position
		anchor_one_way = true
		platform_top = anchor_platform.top_y()
	_latch(false)


## No damage yet: the player is pulled toward the enemy first. The hit lands
## when the pull arrives and the player rebounds (strike_enemy).
func _hook_enemy(enemy: Enemy, p: Player) -> void:
	anchor = tip
	if not p.fsm.is_in("grapple"):
		release()
		return
	target_enemy = enemy
	_enemy_offset = anchor - enemy.global_position
	swing_mode = false # Enemies are never swing anchors.
	_latch(true)


## A peg holds at its center. Swing throw: a pendulum. Otherwise: a pull
## that ends in a hold (begin_hold).
func _hook_peg(peg: GrapplePeg, p: Player) -> void:
	if not p.fsm.is_in("grapple"):
		release()
		return
	target_peg = peg
	anchor = peg.global_position
	tip = anchor
	peg.on_hooked() # A breakable peg starts to crumble.
	_latch(false)


## Keeps a latched anchor on its moving peg or platform (Game._update_movers,
## right after they moved). A crumbled one makes the hook let go.
func follow_anchor() -> void:
	if not is_latched():
		return
	if target_peg:
		if not target_peg.active:
			release()
			return
		anchor = target_peg.global_position
	elif anchor_platform:
		if not anchor_platform.solid:
			release()
			return
		anchor = anchor_platform.global_position + _platform_offset
		platform_top = anchor_platform.top_y()


## Called by GrappleState when a pull reaches a peg: the hook stays attached.
func begin_hold() -> void:
	phase = "hold"


func _latch(on_enemy_hit: bool) -> void:
	phase = "swing" if swing_mode else "pull"
	_play("latch")
	Events.grapple_latched.emit(anchor, on_enemy_hit)


## The delayed enemy hit, called by GrappleState when the pull arrives and
## the player rebounds: the standard attack damage (with the player's damage
## modifiers). Returns the damage dealt (0 when the enemy is gone).
func strike_enemy(p: Player) -> float:
	var enemy := target_enemy
	if not is_instance_valid(enemy) or not enemy.hitbox_active():
		return 0.0
	var c = Config.combat
	var away := signf(enemy.get_center().x - p.get_center().x)
	return combat.apply_damage(enemy, {
		"damage": c.attack_damage * p.stat("damage_mul"),
		"direction": Vector2(away if away != 0.0 else float(p.facing), 0.0),
		"knockback": c.enemy_knockback * Config.grapple.enemy_knockback_mul,
		"source": "grapple",
		"strength": 0.8,
		"position": enemy.get_center(),
	})


## Lets go: the tip flies back to the player.
func release() -> void:
	if phase == "idle" or phase == "retract":
		return
	phase = "retract"
	target_enemy = null
	target_peg = null
	anchor_platform = null
	_play("retract")
	Events.grapple_released.emit(tip)


## Called by GrappleState.exit(): however the state ended, the hook comes back.
func on_state_ended() -> void:
	if phase == "fly" or is_latched():
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


# ---------- Targets and rope checks (read by GrappleState) ----------

## Where the player's CENTER should stop in a pull:
##   wall / ceiling   where the player's box first touches the anchor
##   one-way platform standing on the platform, above the anchor
##   enemy            where the box touches the enemy's contact hitbox grown
##                    by the safety margin
##   peg              hanging under it: the hands at the peg (hang_point)
## Returns the current center when the target is gone or already reached.
func stop_point(p: Player) -> Vector2:
	var c := p.get_center()
	if target_peg:
		return hang_point()
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


## The player's center while hanging from the hooked peg.
func hang_point() -> Vector2:
	return anchor + Vector2(0.0, Player.HEIGHT / 2.0)


func on_peg() -> bool:
	return target_peg != null


func on_enemy() -> bool:
	return target_enemy != null


## True when the hooked enemy can still be struck.
func enemy_alive() -> bool:
	return is_instance_valid(target_enemy) and target_enemy.hitbox_active()


## True when the rope from `from` to `to` crosses a living enemy or a hazard.
## A swing lets go at once when it does.
func rope_obstructed(from: Vector2, to: Vector2) -> bool:
	var seg := to - from
	var length := seg.length()
	if length < 0.001:
		return false
	var d := seg / length
	for e in combat.get_enemies():
		if e.hitbox_active() and Geom.box_cast_distance(from, Vector2.ZERO, d, e.get_rect()) <= length:
			return true
	for h in combat.get_room().hazards_in(Rect2(from, Vector2.ZERO).expand(to).grow(1.0)):
		if Geom.box_cast_distance(from, Vector2.ZERO, d, h) <= length:
			return true
	return false


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
	var at := anchor if is_latched() else tip
	rope.points = PackedVector2Array([to_local(from), to_local(at)])
	tip_node.position = to_local(at)
	var along := at - from
	tip_node.rotation = along.angle() if along.length() > 1.0 else dir.angle()
