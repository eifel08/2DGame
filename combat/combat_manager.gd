class_name CombatManager
extends Node2D
## Owns every damage interaction:
##   - player melee: input, directional hitboxes, pogo, recoil
##   - the grappling hook (GrappleHook, child node "Grapple")
##   - a generic damage API used by ultimates and projectiles
##   - enemy contact damage and hazard damage to the player
##     (the three damage sources and their i-frame rules: combat/damage.gd)
## Outcomes are reported only through Events (hit_landed, pogo_bounced, ...).
## Also draws the placeholder slash and the debug hitboxes / animation labels.

@onready var projectiles: ProjectileSystem = $Projectiles
@onready var grapple: GrappleHook = $Grapple

var game: Node ## Composition root; provides player, room and enemies.
var attack := {} ## {dir, t, hit_set, pogoed} while a swing is active.
var cooldown := 0.0
var attack_buffer := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	projectiles.setup(self)
	grapple.setup(self)
	reset()


func reset() -> void:
	attack = {}
	cooldown = 0.0
	attack_buffer = 0.0
	projectiles.clear()
	if grapple.combat:
		grapple.reset()


func get_player() -> Player:
	return game.player


func get_enemies() -> Array:
	return game.enemies


func get_room() -> Room:
	return game.room


func step(delta: float) -> void:
	var c = Config.combat
	var p := get_player()
	cooldown -= delta
	attack_buffer -= delta
	if game.input.was_pressed(&"attack"):
		attack_buffer = c.attack_buffer_time

	if attack_buffer > 0.0 and attack.is_empty() and cooldown <= 0.0 and p.can_attack():
		_start_attack()
	if not attack.is_empty():
		_step_attack(delta)

	grapple.step(delta)
	projectiles.step(delta)
	_resolve_contact_damage()
	_resolve_hazards()
	_resolve_enemy_hazards()
	queue_redraw()


# ---------- Player melee ----------

func _attack_direction() -> String:
	var p := get_player()
	if game.input.is_down(&"move_up"):
		return "up"
	if game.input.is_down(&"move_down") and not p.grounded:
		return "down"
	return "right" if p.facing > 0 else "left"


func get_attack_hitbox(dir: String) -> Rect2:
	var p := get_player()
	var r := p.get_rect()
	var s := p.stat("attack_range_mul")
	match dir:
		"up":
			var size := Vector2(50, 56) * s
			return Rect2(r.get_center().x - size.x / 2.0, r.position.y - size.y + 6.0, size.x, size.y)
		"down": # Generous pogo box: wider and taller than the player.
			var size: Vector2 = Config.combat.pogo_hitbox * s
			return Rect2(r.get_center().x - size.x / 2.0, r.end.y - 10.0, size.x, size.y)
		_:
			var size := Vector2(60, 38) * s
			var x := r.end.x - 4.0 if dir == "right" else r.position.x - size.x + 4.0
			return Rect2(x, r.get_center().y - size.y / 2.0 - 2.0, size.x, size.y)


## The downward swing stays active longer (pogo leniency).
func active_end(dir: String) -> float:
	return Config.combat.pogo_active_end if dir == "down" else Config.combat.attack_active_end


func _start_attack() -> void:
	var p := get_player()
	var dir := _attack_direction()
	attack = {"dir": dir, "t": 0.0, "hit_set": {}, "pogoed": false}
	attack_buffer = 0.0
	cooldown = Config.combat.attack_cooldown
	p.attack_dir = dir
	p.facing_locked = true
	if dir == "left" or dir == "right":
		p.facing = 1 if dir == "right" else -1
	Events.attack_swung.emit(dir)


func _end_attack() -> void:
	attack = {}
	get_player().attack_dir = ""
	get_player().facing_locked = false


func _step_attack(delta: float) -> void:
	var c = Config.combat
	var p := get_player()
	attack.t += delta

	# Interrupted (hurt, dash, cast...) or finished -> end the swing.
	if not p.can_attack() or attack.t >= c.attack_duration:
		_end_attack()
		return
	if attack.t < c.attack_active_start or attack.t > active_end(attack.dir):
		return

	var dir: String = attack.dir
	var box := get_attack_hitbox(dir)
	var dir_x := 1.0 if dir == "right" else (-1.0 if dir == "left" else 0.0)
	var dir_y := -1.0 if dir == "up" else (1.0 if dir == "down" else 0.0)
	var connected := false

	for enemy in get_enemies():
		var er: Rect2 = enemy.get_rect()
		if not enemy.hitbox_active() or attack.hit_set.has(enemy) or not box.intersects(er):
			continue
		attack.hit_set[enemy] = true
		var hx := dir_x if dir_x != 0.0 else signf(enemy.get_center().x - p.get_center().x)
		var applied := apply_damage(enemy, {
			"damage": c.attack_damage * p.stat("damage_mul"),
			"direction": Vector2(hx, dir_y),
			"knockback": c.enemy_knockback,
			"source": "melee",
			"grants_energy": true,
			"position": box.intersection(er).get_center(),
		})
		if applied > 0.0:
			connected = true

	# Breakable walls (hidden passages) take hits from any swing. Rule C
	# (GUIDELINES.md): never gate this on arena state; secret exits must
	# stay breakable during an arena fight.
	for wall in game.breakables:
		if wall.intact and not attack.hit_set.has(wall) and box.intersects(wall.get_rect()):
			attack.hit_set[wall] = true
			game.hit_breakable(wall, box.intersection(wall.get_rect()).get_center())
			if dir_x != 0.0:
				p.velocity.x = -dir_x * c.recoil_velocity

	# Down-attacks also bounce off spikes. Never off lava: a pogo over lava
	# falls in (hazard damage + safe-ground respawn, _resolve_hazards).
	var on_hazard := dir == "down" and get_room().find_hazard(box, false).has_area()

	if dir == "down" and (connected or on_hazard) and not attack.pogoed:
		attack.pogoed = true
		p.pogo(c.pogo_velocity)
		Events.pogo_bounced.emit(p.global_position + Vector2(0, 10), on_hazard and not connected)
	elif connected and dir_x != 0.0:
		p.velocity.x = -dir_x * c.recoil_velocity # Recoil sells the impact.


# ---------- Generic damage API (ultimates, projectiles) ----------

## opts: damage, direction (Vector2), knockback, source, grants_energy, strength, position.
func apply_damage(target: Node, opts: Dictionary) -> float:
	var applied: float = target.take_hit(opts.get("damage", 0.0), opts.get("direction", Vector2.ZERO), opts.get("knockback", 0.0))
	if applied <= 0.0:
		return 0.0
	Events.hit_landed.emit({
		"target": target,
		"damage": applied,
		"position": opts.get("position", target.get_center()),
		"source": opts.get("source", "unknown"),
		"grants_energy": opts.get("grants_energy", false),
		"strength": opts.get("strength", 1.0),
	})
	if not target.alive:
		Events.enemy_killed.emit(target)
	return applied


## Damages each living enemy inside the circle once per `hit_set`.
func damage_in_circle(center: Vector2, radius: float, opts: Dictionary, hit_set := {}) -> int:
	var count := 0
	for enemy in get_enemies():
		if not enemy.hitbox_active() or hit_set.has(enemy) or not Geom.circle_overlaps_rect(center, radius, enemy.get_rect()):
			continue
		hit_set[enemy] = true
		var o := opts.duplicate()
		o["direction"] = (enemy.get_center() - center).normalized()
		apply_damage(enemy, o)
		count += 1
	return count


func damage_in_rect(rect: Rect2, opts: Dictionary, hit_set := {}) -> int:
	var count := 0
	for enemy in get_enemies():
		if not enemy.hitbox_active() or hit_set.has(enemy) or not rect.intersects(enemy.get_rect()):
			continue
		hit_set[enemy] = true
		var o := opts.duplicate()
		var dx := signf(enemy.get_center().x - rect.get_center().x)
		o["direction"] = Vector2(dx if dx != 0.0 else 1.0, opts.get("dir_y", 0.0))
		apply_damage(enemy, o)
		count += 1
	return count


# ---------- Damage to the player ----------

func _resolve_contact_damage() -> void:
	var p := get_player()
	var pr := p.get_rect()
	for enemy in get_enemies():
		if enemy.deals_contact_damage() and pr.intersects(enemy.get_rect()):
			if p.receive_hit(Config.combat.contact_damage * enemy.contact_damage_mul, enemy.get_center().x, false, false, enemy, Damage.Source.ENEMY):
				return


## Environmental hazards ignore i-frames (Damage.Source.HAZARD).
func _resolve_hazards() -> void:
	var p := get_player()
	var r := p.get_rect().grow_individual(-2.0, -4.0, -2.0, 0.0)
	if get_room().find_hazard(r).has_area():
		p.hazard_respawn(Config.combat.hazard_damage)


## Enemies die instantly when they touch a hazard (knocked into spikes, etc.).
func _resolve_enemy_hazards() -> void:
	for enemy in get_enemies():
		if enemy.alive and get_room().find_hazard(enemy.get_rect()).has_area():
			if enemy.kill():
				Events.enemy_killed.emit(enemy)


# ---------- Drawing ----------

func _draw() -> void:
	var dbg = Config.debug
	if not attack.is_empty():
		_draw_slash()
	if dbg.show_hitboxes:
		_draw_hitboxes()
	if dbg.show_anim_labels:
		_draw_labels()


func _draw_slash() -> void:
	var c = Config.combat
	var p := get_player()
	var dir: String = attack.dir
	var box := get_attack_hitbox(dir)
	var progress := minf(1.0, attack.t / c.attack_active_end)
	var rot: float = {"right": 0.0, "left": PI, "up": -PI / 2.0, "down": PI / 2.0}[dir]
	var span := 2.2
	var start := -span / 2.0
	var finish := start + span * minf(1.0, progress * 1.4)
	var radius := maxf(box.size.x, box.size.y) * 0.45
	var center := box.get_center() + Vector2(-radius * 0.6, 0.0).rotated(rot)
	var alpha := 1.0 - maxf(0.0, progress - 0.6) * 2.5
	var col := Color("#ffcf6b") if p.stat("damage_mul") > 1.0 else Color.WHITE
	draw_arc(center, radius, start + rot, finish + rot, 24, Color(col, alpha), 6.0, true)
	draw_arc(center, radius * 0.75, start + rot, finish + rot, 24, Color(col, alpha * 0.5), 2.0, true)


func _draw_hitboxes() -> void:
	var c = Config.combat
	var p := get_player()
	draw_rect(p.get_rect(), Color("#4dabf7") if p.health.is_invulnerable() else Color("#69db7c"), false, 1.0)
	for enemy in get_enemies():
		draw_rect(enemy.get_rect(), Color("#ffa94d"), false, 1.0)
	_draw_world_collision()
	# Hazard respawn target.
	var sp := p.safe_point
	draw_line(sp + Vector2(-8, 0), sp + Vector2(8, 0), Color("#69db7c"), 2.0)
	draw_line(sp, sp + Vector2(0, -20), Color("#69db7c"), 1.0)
	draw_string(ThemeDB.fallback_font, sp + Vector2(-30, -24), "safe point", HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color("#69db7c"))
	if not attack.is_empty():
		var active: bool = attack.t >= c.attack_active_start and attack.t <= active_end(attack.dir)
		draw_rect(get_attack_hitbox(attack.dir), Color("#ff3b3b") if active else Color(1, 1, 1, 0.4), false, 1.0)


## Debug: solid tile outlines near the camera, door triggers and arena areas,
## so the visual layout can be checked against the real collision.
func _draw_world_collision() -> void:
	var room := get_room()
	var view: Rect2 = game.camera.view_rect().grow(32.0)
	var ts := Vector2(room.tiles.tile_set.tile_size)
	var first := room.tiles.local_to_map(room.tiles.to_local(view.position))
	var last := room.tiles.local_to_map(room.tiles.to_local(view.end))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var center := room.cell_center(Vector2i(x, y))
			if room.is_solid_at(center):
				draw_rect(Rect2(center - ts / 2.0, ts), Color(0.4, 0.9, 1.0, 0.18), false, 1.0)
	for door in game.doors:
		draw_rect(door.get_trigger_rect(), Color("#ffd36b"), false, 1.0)
	var arena := room.get_arena()
	if arena:
		draw_rect(arena.get_trigger_rect(), Color(1.0, 0.4, 0.8, 0.5), false, 1.0)


func _draw_labels() -> void:
	var font := ThemeDB.fallback_font
	var p := get_player()
	var label := "%s / %s" % [p.state_name(), p.animator.current]
	draw_string(font, p.get_rect().position + Vector2(-40, -8), label, HORIZONTAL_ALIGNMENT_CENTER, 102, 10)
	for enemy in get_enemies():
		var er: Rect2 = enemy.get_rect()
		draw_string(font, er.position + Vector2(-30, -14), enemy._anim_name, HORIZONTAL_ALIGNMENT_CENTER, er.size.x + 60, 10)
