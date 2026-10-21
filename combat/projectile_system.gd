class_name ProjectileSystem
extends Node2D
## Lightweight projectiles. Player projectiles (abilities) hit enemies through
## CombatManager.apply_damage(); optional homing steers toward the nearest
## living enemy. Hostile projectiles (boss shards, shockwaves) hit the player.

var combat: CombatManager
var list: Array[Dictionary] = []


func setup(p_combat: CombatManager) -> void:
	combat = p_combat


func clear() -> void:
	list.clear()


## opts: position, velocity, radius, damage, life, homing, color, source, knockback,
## delay, hostile (hits the player), shape ("orb" or "wave"), owner (the enemy
## that fired it, so a counter can strike back)
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
		"frozen": 0.0, ## > 0: held in place and harmless (Stasis Field).
		"trail": [],
		"dead": false,
	})


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
		pr.pos += pr.vel * delta

		if room.is_solid_at(pr.pos):
			pr.dead = true
			continue
		if pr.hostile:
			var player: Player = combat.get_player()
			if Geom.circle_overlaps_rect(pr.pos, pr.radius, player.get_rect()):
				var shooter: Node = pr.owner if is_instance_valid(pr.owner) else null
				player.receive_hit(pr.damage, pr.pos.x - signf(pr.vel.x), false, false, shooter)
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
