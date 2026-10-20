class_name AbilityCard
extends Button
## Icon-only ability button: a symbol plus an energy gauge (no text).
## Name and description appear in the inventory's detail area on focus.
## Fully keyboard operable: arrows move focus, Enter/Space presses.

var ability: UltimateAbility
var icon_view: AbilityIcon
var gauge: EnergyGauge
var key_label: Label


func _init() -> void:
	custom_minimum_size = Vector2(76, 76)
	focus_mode = Control.FOCUS_ALL
	icon_view = AbilityIcon.new()
	icon_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_view.offset_left = 12
	icon_view.offset_top = 8
	icon_view.offset_right = -12
	icon_view.offset_bottom = -20
	add_child(icon_view)
	gauge = EnergyGauge.new()
	gauge.anchor_right = 1.0
	gauge.anchor_top = 1.0
	gauge.anchor_bottom = 1.0
	gauge.offset_left = 10
	gauge.offset_right = -10
	gauge.offset_top = -14
	gauge.offset_bottom = -8
	add_child(gauge)
	key_label = Label.new()
	key_label.position = Vector2(6, 2)
	key_label.add_theme_font_size_override("font_size", 10)
	key_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(key_label)


## `key` > 0 shows the hotkey number in the corner (slot cards only).
func show_ability(p_ability: UltimateAbility, max_energy: float, key := 0, dim := false) -> void:
	ability = p_ability
	if ability:
		icon_view.set_icon(ability.icon, ability.color, dim)
		gauge.visible = true
		gauge.set_requirement(ability.get_cost(), max_energy)
	else:
		icon_view.set_icon("empty", Color.WHITE, dim)
		gauge.visible = false
	key_label.text = str(key) if key > 0 else ""
