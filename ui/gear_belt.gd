class_name GearBelt
extends Control
## The belt drawn in the Gear tab: a leather strap with a buckle and
## LOOPS loops. Each loop is a column: its BELT card (the worn pouch, drawn
## large, or an empty / locked loop) and, under it, the pouch's tool slots
## (SLOT cards) on the pouch's lower body, so tools appear inside the pouch.
## GearTab fills the cards; this only lays them out and draws the leather.

const LOOPS := 5 ## Belt loops drawn; the debug pouch limit goes up to 5.
const LOOP_SIZE := Vector2(134, 112)
const POUCH_HEIGHT := 70.0 ## The BELT card; the slot strip fills the rest.
const STRAP_Y := 14.0
const STRAP_H := 16.0

var loops: Array[Loop] = []


func _init() -> void:
	custom_minimum_size = Vector2(LOOPS * LOOP_SIZE.x + (LOOPS - 1) * 8.0, LOOP_SIZE.y)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for i in LOOPS:
		var loop := Loop.new()
		loop.custom_minimum_size = LOOP_SIZE
		row.add_child(loop)
		loops.append(loop)


func _draw() -> void:
	var strap := Rect2(0.0, STRAP_Y, size.x, STRAP_H)
	draw_rect(strap, GearArt.LEATHER.darkened(0.2))
	draw_line(strap.position + Vector2(0, 3), strap.position + Vector2(size.x, 3), Color(1, 1, 1, 0.12), 1.0) # Stitching.
	draw_line(strap.position + Vector2(0, STRAP_H - 3), strap.position + Vector2(size.x, STRAP_H - 3), Color(1, 1, 1, 0.12), 1.0)
	var buckle := Rect2(-6.0, STRAP_Y - 5.0, 14.0, STRAP_H + 10.0)
	draw_rect(buckle, Color("#c9b06b"), false, 3.0)


## One loop of the belt: the pouch card and the slot strip.
class Loop:
	extends Control

	var belt_card: GearCard
	var slot_row: HBoxContainer
	var has_pouch := false
	var slot_count := 0
	var tier_color := Color.WHITE

	func _init() -> void:
		belt_card = GearCard.new()
		belt_card.position = Vector2(4, 0)
		belt_card.size = Vector2(LOOP_SIZE.x - 8.0, POUCH_HEIGHT)
		belt_card.flat = true
		add_child(belt_card)
		slot_row = HBoxContainer.new()
		slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_row.add_theme_constant_override("separation", 4)
		slot_row.position = Vector2(4, POUCH_HEIGHT + 4.0)
		slot_row.size = Vector2(LOOP_SIZE.x - 8.0, LOOP_SIZE.y - POUCH_HEIGHT - 6.0)
		add_child(slot_row)

	## The pouch's lower body behind its slots.
	func _draw() -> void:
		if not has_pouch:
			return
		var w := clampf(slot_count * 34.0 + 10.0, 72.0, LOOP_SIZE.x - 8.0) # Just wide enough for its slots.
		var body := Rect2((LOOP_SIZE.x - w) / 2.0, POUCH_HEIGHT - 2.0, w, LOOP_SIZE.y - POUCH_HEIGHT)
		draw_rect(body, GearArt.LEATHER.darkened(0.35))
		draw_rect(body, Color(tier_color, 0.6), false, 1.5)
