class_name ProjectileSystem
extends Node2D
## Lightweight projectiles. Player projectiles (abilities) hit enemies through
## CombatManager.apply_damage(); optional homing steers toward the nearest
## living enemy. Hostile projectiles (boss shards, shockwaves) hit the player.
##
## DEFLECT RULE: a hostile projectile is either
##   deflectable      a warm gold orb with a white ring. A standard MELEE swing
##                    that touches it swats it back (deflect_in_rect): it
##                    turns friendly, flies at its shooter and hurts enemies.
##   non-deflectable  (default) a dark crimson / violet shape with a spiky rim.
##                    Swings pass through it; only dodging helps.
## Magic never deflects anything: only CombatManager's melee calls deflect.

var combat: CombatManager
var list: Array[Dictionary] = []


func setup(p_combat: CombatManager) -> void:
	combat = p_combat


func clear() -> void:
	list.clear()


## opts: position, velocity, radius, damage, life, homing, color, source, knockback,
## delay, hostile (hits the player), shape ("orb", "wave" or "spike"), owner
## (the enemy that fired it, so a counter can strike back), deflectable
## (hostile only: a melee swing can swat it back), gravity (px/s^2, arcs)
func spawn(opts: Dictionary) -> void:
	list.append({
		"pos": opts.position,
		"vel": opts.velocity,
		"radius": opts.get("radius", 7.0),
		"damage": opts.get("damage", 10.0),
		"life": opts.get("life", 2.5),
		"homing": opts.get("homing", 0.0),
		"color": opts.get("color", Color("#99ffff")),
		"source": opts.get("source", "projectile"),
		"knockback": opts.get("knockback", 120.0),
		"delay": opts.get("delay", 0.0),
		"hostile": opts.get("hostile", false),
		"shape": opts.get("shape", "orb"),
		"owner": opts.get("owner"),
		"deflectable": opts.get("deflectable", false),
		"gravity": opts.get("gravity", 0.0),
		"deflected": false,
		"frozen": 0.0, ## > 0: held in place and harmless (Stasis Field).
		"trail": [],
		"dead": false,
	})


func hostile_count() -> int:
	return list.filter(func(pr: Dictionary) -> bool: return pr.hostile).size()


## Melee only. Every deflectable hostile projectile touching `rect` is swatted
## back: it turns friendly, speeds up, aims at its shooter (or flies back the
## way it came) and deals `damage` to the enemy it hits. Returns the count.
func deflect_in_rect(rect: Rect2, damage: float) -> int:
	var count := 0
	for pr in list:
		if pr.dead or not pr.hostile or not pr.deflectable:
			continue
		if not Geom.circle_overlaps_rect(pr.pos, pr.radius + 4.0, rect):
			continue
		var speed: float = maxf(420.0, (pr.vel as Vector2).length() * 1.4)
		var shooter: Node = pr.owner if is_instance_valid(pr.owner) else null
		var dir: Vector2 = -(pr.vel as Vector2).normalized()
		if shooter and shooter.alive:
			dir = (shooter.get_center() - pr.pos as Vector2).normalized()
		pr.vel = dir * speed
		pr.hostile = false
		pr.deflected = true
		pr.gravity = 0.0
		pr.homing = 0.0
		pr.damage = damage
		pr.source = "deflect"
		pr.life = maxf(pr.life, 1.5)
		pr.color = Color("#fff3c4")
		count += 1
		Events.projectile_deflected.emit(pr.pos)
	return count


func _nearest_enemy(from: Vector2, max_dist := 700.0) -> Node:
	var best: Node = null
	var best_d := max_dist * max_dist
	for e in combat.get_enemies():
		if not e.hitbox_active():
			continue
		var d := from.distance_squared_to(e.get_center())
		if d < best_d:
			best_d = d
			best = e
	return best


## Holds hostile projectiles inside the circle in place for `duration`.
## Frozen projectiles neither move, age nor hurt. Returns how many froze.
func freeze_in_circle(center: Vector2, radius: float, duration: float) -> int:
	var count := 0
	for pr in list:
		if pr.hostile and center.distance_to(pr.pos) <= radius + pr.radius:
			pr.frozen = maxf(pr.frozen, duration)
			count += 1
	return count


func step(delta: float) -> void:
	var room := combat.get_room()
	for pr in list:
		if pr.frozen > 0.0:
			pr.frozen -= delta
			continue
		pr.life -= delta
		if pr.life <= 0.0:
			pr.dead = true
			continue

		# Steer toward the target after a short launch delay.
		pr.delay -= delta
		var target: Node = _nearest_enemy(pr.pos) if pr.homing > 0.0 and pr.delay <= 0.0 else null
		if target:
			var vel: Vector2 = pr.vel
			var want := (target.get_center() - pr.pos as Vector2).angle()
			var diff := wrapf(want - vel.angle(), -PI, PI)
			var turn := clampf(diff, -pr.homing * delta, pr.homing * delta)
			pr.vel = Vector2.from_angle(vel.angle() + turn) * minf(vel.length() * 1.03, 900.0)

		pr.trail.append(pr.pos)
		if pr.trail.size() > 6:
			pr.trail.pop_front()
		if pr.gravity != 0.0:
			pr.vel += Vector2(0.0, pr.gravity) * delta
		pr.pos += pr.vel * delta

		if room.is_solid_at(pr.pos):
			pr.dead = true
			continue
		if pr.hostile:
			var player: Player = combat.get_player()
			if Geom.circle_overlaps_rect(pr.pos, pr.radius, player.get_rect()):
				var shooter: Node = pr.owner if is_instance_valid(pr.owner) else null
				player.receive_hit(pr.damage, pr.pos.x - signf(pr.vel.x), false, false, shooter, Damage.Source.PROJECTILE)
				pr.dead = true
			continue
		for e in combat.get_enemies():
			if not e.hitbox_active() or not Geom.circle_overlaps_rect(pr.pos, pr.radius, e.get_rect()):
				continue
			combat.apply_damage(e, {
				"damage": pr.damage,
				"direction": Vector2(signf(pr.vel.x) if pr.vel.x != 0.0 else 1.0, 0.0),
				"knockback": pr.knockback,
				"source": pr.source,
				"strength": 0.4,
				"position": pr.pos,
			})
			pr.dead = true
			break
	list = list.filter(func(pr: Dictionary) -> bool: return not pr.dead)
	queue_redraw()


func _draw() -> void:
	for pr in list:
		if pr.frozen > 0.0:
			draw_arc(pr.pos, pr.radius + 5.0, 0.0, TAU, 16, Color("#bfe6ff"), 2.0, true)
		if pr.hostile and not pr.deflectable and pr.shape != "wave":
			_draw_hazardous(pr)
			continue
		if pr.hostile and pr.deflectable:
			# Deflectable: warm gold, white ring (reads as "hit it back").
			draw_circle(pr.pos, pr.radius + 4.0, Color(1.0, 0.85, 0.4, 0.25))
			draw_circle(pr.pos, pr.radius, Color("#ffc94d"))
			draw_arc(pr.pos, pr.radius + 2.0, 0.0, TAU, 16, Color.WHITE, 2.0, true)
			draw_circle(pr.pos, pr.radius * 0.4, Color.WHITE)
			continue
		if pr.shape == "wave":
			var h: float = pr.radius * 2.4
			draw_rect(Rect2(pr.pos.x - 5.0, pr.pos.y + pr.radius - h, 10.0, h), pr.color)
			draw_rect(Rect2(pr.pos.x - 9.0, pr.pos.y + pr.radius - h * 0.6, 18.0, h * 0.6), Color(pr.color, 0.4))
			continue
		var n: int = pr.trail.size()
		for i in n:
			var k := float(i) / n
			draw_circle(pr.trail[i], pr.radius * k, Color(pr.color, k * 0.5))
		draw_circle(pr.pos, pr.radius, pr.color)
		draw_circle(pr.pos, pr.radius * 0.45, Color.WHITE)


## Non-deflectable hostile shots: dark, red-violet, a spiky rim (reads as
## "do not touch"). Spikes are drawn as darts along their flight.
func _draw_hazardous(pr: Dictionary) -> void:
	var col: Color = pr.color
	var n: int = pr.trail.size()
	for i in n:
		var k := float(i) / n
		draw_circle(pr.trail[i], pr.radius * k * 0.8, Color(col, k * 0.35))
	if pr.shape == "spike":
		var d: Vector2 = (pr.vel as Vector2).normalized() if pr.vel != Vector2.ZERO else Vector2.RIGHT
		var tip: Vector2 = pr.pos + d * pr.radius * 1.8
		var back: Vector2 = pr.pos - d * pr.radius * 1.4
		draw_colored_polygon(PackedVector2Array([tip, back + d.orthogonal() * pr.radius * 0.7, back - d.orthogonal() * pr.radius * 0.7]), col)
		draw_line(back, tip, Color("#2a0b18"), 1.5)
		return
	var pts := PackedVector2Array()
	for i in 16:
		var r: float = pr.radius * (1.45 if i % 2 == 0 else 0.95)
		pts.append(pr.pos + Vector2.from_angle(TAU * i / 16.0 + pr.life * 6.0) * r)
	draw_colored_polygon(pts, col)
	draw_circle(pr.pos, pr.radius * 0.55, Color("#2a0b18"))
