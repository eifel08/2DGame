class_name SpellNodeView
extends Control
## One node of the HUD spell cross (SpellCross): the spell's icon in a small
## box, framed in its energy-tier color and bright when there is enough
## energy. An empty slot shows the "empty" symbol, a locked slot a padlock. Placeholder art: replace
## _draw() (or this node) with textures later.

var ability: UltimateAbility
var affordable := false
var locked := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_spell(p_ability: UltimateAbility, p_ready: bool, p_locked := false) -> void:
	ability = p_ability
	affordable = p_ready
	locked = p_locked
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.55))
	if locked:
		draw_rect(r, Color(1, 1, 1, 0.1), false, 1.0)
		AbilityIcon.draw_symbol(self, "locked", r.get_center(), size.x * 0.36, Color(1, 1, 1, 0.3))
		return
	if ability == null:
		draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)
		AbilityIcon.draw_symbol(self, "empty", r.get_center(), size.x * 0.36, Color(1, 1, 1, 0.5))
		return
	var tier := Config.energy_tier_color(ability.get_cost())
	draw_rect(r, Color(tier, 1.0 if affordable else 0.4), false, 2.0 if affordable else 1.0)
	AbilityIcon.draw_symbol(self, ability.icon, r.get_center() + Vector2(0, 1), size.x * 0.32, Color(ability.color, 1.0 if affordable else 0.35))
