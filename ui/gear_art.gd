class_name GearArt
extends RefCounted
## Placeholder drawings for pouches and tools, shared by the pickups (world)
## and the inventory's Gear tab (UI). Plain static functions on any
## CanvasItem, no autoloads. Replace with textures later.

const TIER_COLORS: Array[Color] = [Color("#9fd99b"), Color("#6fb7ff"), Color("#ffad5c")] ## Weak, Medium, Strong.
const TIER_TAGS: Array[String] = ["W", "M", "S"]


static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier, 0, TIER_COLORS.size() - 1)]


## A small sack: round body, tied neck. `r` is the body radius.
static func pouch(c: CanvasItem, center: Vector2, r: float, col: Color, dim := false) -> void:
	var a := 0.45 if dim else 1.0
	var leather := Color(Color("#6b4f3a"), a)
	c.draw_circle(center + Vector2(0, r * 0.35), r, leather)
	c.draw_arc(center + Vector2(0, r * 0.35), r, 0.0, TAU, 24, Color(col, a), maxf(1.5, r * 0.18), true)
	c.draw_rect(Rect2(center + Vector2(-r * 0.45, -r * 0.9), Vector2(r * 0.9, r * 0.55)), leather)
	c.draw_line(center + Vector2(-r * 0.55, -r * 0.45), center + Vector2(r * 0.55, -r * 0.45), Color(col, a), maxf(1.5, r * 0.18))


## A gem in a ring. `r` is the ring radius.
static func tool(c: CanvasItem, center: Vector2, r: float, col: Color, dim := false) -> void:
	var a := 0.45 if dim else 1.0
	c.draw_circle(center, r, Color(Color("#1b2238"), a))
	c.draw_arc(center, r, 0.0, TAU, 24, Color(col, a), maxf(1.5, r * 0.2), true)
	var g := r * 0.7
	c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -g), center + Vector2(g * 0.85, 0),
		center + Vector2(0, g), center + Vector2(-g * 0.85, 0)]), Color(col, a))


## An empty slot of a tier: a dashed ring in the tier's colour.
static func empty_slot(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	for i in 12:
		var a0 := TAU * i / 12.0
		c.draw_arc(center, r, a0, a0 + TAU / 24.0, 3, Color(col, 0.7), 2.0, true)
