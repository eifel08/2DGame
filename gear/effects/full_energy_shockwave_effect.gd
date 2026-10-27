class_name FullEnergyShockwaveEffect
extends GearEffect
## While the energy meter is completely full, every basic swing also sends a
## shockwave ahead of the strike: bonus damage to every enemy in its path.
## It never fills the meter (grants_energy false), never deflects and never
## pogos; it only adds damage. Feedback plays the "tool_shockwave" effect.

@export var bonus_mul := 0.3 ## Shockwave damage as a share of the swing's damage.
@export var reach := 72.0 ## How far the wave travels past the swing's hitbox (px).


static func make(p_bonus_mul: float, p_reach := 72.0) -> FullEnergyShockwaveEffect:
	var e := FullEnergyShockwaveEffect.new()
	e.bonus_mul = p_bonus_mul
	e.reach = p_reach
	return e


func on_attack_swung(ctx: UltimateContext, dir: String) -> void:
	var p := ctx.player
	if p.health.energy < p.health.get_max_energy() - 0.0001:
		return
	var rect := wave_rect(ctx.combat.get_attack_hitbox(dir), dir)
	var dir_y := -1.0 if dir == "up" else (1.0 if dir == "down" else 0.0)
	ctx.combat.damage_in_rect(rect, {
		"damage": Config.combat.attack_damage * p.stat("damage_mul") * bonus_mul,
		"knockback": Config.combat.enemy_knockback * 0.5,
		"source": "tool_shockwave",
		"grants_energy": false,
		"dir_y": dir_y,
	})
	var forward: Vector2 = {"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}.get(dir, Vector2.RIGHT)
	Events.tool_shockwave.emit(rect.get_center(), forward)


## The swing's hitbox stretched `reach` px further in the swing direction.
func wave_rect(box: Rect2, dir: String) -> Rect2:
	match dir:
		"left":
			return Rect2(box.position - Vector2(reach, 0.0), box.size + Vector2(reach, 0.0))
		"right":
			return Rect2(box.position, box.size + Vector2(reach, 0.0))
		"up":
			return Rect2(box.position - Vector2(0.0, reach), box.size + Vector2(0.0, reach))
		_:
			return Rect2(box.position, box.size + Vector2(0.0, reach))


func debug_text() -> String:
	return "full-energy shockwave +%d%%" % roundi(bonus_mul * 100.0)
