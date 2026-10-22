class_name AbilityCard
extends Button
## Icon-only ability button: a symbol plus an energy gauge (no text).
## Name and description appear in the inventory's detail area on focus.
## Fully keyboard operable: arrows move focus, Enter/Space presses.
## Focus frame: a full gold frame. `mirror` draws a dim, thinner gold
## frame instead: the spell cross sets it on the side card opposite the
## focused one (both side cards show the same slot).

const FOCUS_COLOR := Color(1.0, 0.83, 0.42, 1.0)
const MIRROR_COLOR := Color(1.0, 0.83, 0.42, 0.4)

var ability: UltimateAbility
var icon_view: AbilityIcon
var gauge: EnergyGauge
var key_label: Label
var mirror := false ## Dim "same slot" frame (see SpellCross).


func _init() -> void:
	custom_minimum_size = Vector2(76, 76)
	focus_mode = Control.FOCUS_ALL
	# Mouse hover moves the keyboard focus, so both input styles agree.
	mouse_entered.connect(func() -> void:
		if is_visible_in_tree():
			grab_focus())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
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


## `key`: a short label for the corner (e.g. "Up"), or "" for none.
func show_ability(p_ability: UltimateAbility, max_energy: float, key := "", dim := false) -> void:
	ability = p_ability
	if ability:
		icon_view.set_icon(ability.icon, ability.color, dim)
		gauge.visible = true
		gauge.set_requirement(ability.get_cost(), max_energy)
	else:
		icon_view.set_icon("empty", Color.WHITE, dim)
		gauge.visible = false
	key_label.text = key


func set_mirror(on: bool) -> void:
	if mirror != on:
		mirror = on
		queue_redraw()


func _draw() -> void:
	if has_focus(): # Primary selection: full gold frame.
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.5), FOCUS_COLOR, false, 3.0)
	elif mirror: # Secondary: a dim, thinner frame on the linked side card.
		draw_rect(Rect2(Vector2.ZERO, size).grow(-3.0), MIRROR_COLOR, false, 1.5)
