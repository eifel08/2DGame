class_name AbilityArt
extends RefCounted
## Placeholder drawings shared by the movement pickups (world) and the
## tutorial popups (UI): the player figure, movement ability symbols, key caps,
## arrows and bars. Plain static functions on any CanvasItem, no autoloads, so
## object scenes can use them too. Replace with textures later.

const PLAYER_COLOR := Color("#7fd1ff")
const GROUND_COLOR := Color("#4a5374")
const ARROW_COLOR := Color("#ffd36b")

## Movement ability colors (pickups, popups).
const COLORS := {
	"double_jump": Color("#bff6ff"),
	"dash": Color("#d9f6ff"),
	"wall_climb": Color("#9fe0a0"),
	"grapple": Color("#e8dcb8"),
}


## The player as the placeholder rig draws it: a rounded body with an eye.
## `feet` is the bottom-center; `h` the height (width is 0.55 h).
static func figure(c: CanvasItem, feet: Vector2, h: float, facing := 1, col := PLAYER_COLOR, squash := 1.0) -> void:
	var hh := h * squash
	var w := h * 0.55 / sqrt(squash)
	var body := Rect2(feet.x - w / 2.0, feet.y - hh, w, hh)
	c.draw_rect(body, col)
	c.draw_rect(Rect2(body.position + Vector2(0, -h * 0.04), Vector2(w, h * 0.08)), col) # Rounded-looking top.
	var eye := Vector2(feet.x + facing * w * 0.18, feet.y - hh * 0.78)
	c.draw_rect(Rect2(eye - Vector2(w * 0.12, h * 0.05), Vector2(w * 0.3, h * 0.1)), Color("#1a2238"))


## A faint copy of the figure (motion trails, "before" poses).
static func ghost(c: CanvasItem, feet: Vector2, h: float, alpha: float, facing := 1) -> void:
	figure(c, feet, h, facing, Color(PLAYER_COLOR, alpha))


static func ground(c: CanvasItem, from_x: float, to_x: float, y: float) -> void:
	c.draw_rect(Rect2(from_x, y, to_x - from_x, 10.0), GROUND_COLOR)
	c.draw_line(Vector2(from_x, y), Vector2(to_x, y), Color("#7f8bb8"), 2.0)


static func wall(c: CanvasItem, x: float, top: float, bottom: float, width := 26.0) -> void:
	c.draw_rect(Rect2(x, top, width, bottom - top), GROUND_COLOR)
	c.draw_line(Vector2(x, top), Vector2(x, bottom), Color("#7f8bb8"), 2.0)


static func arrow(c: CanvasItem, from: Vector2, to: Vector2, col := ARROW_COLOR, width := 4.0) -> void:
	c.draw_line(from, to, col, width, true)
	var d := (to - from).normalized()
	var head := width * 3.2
	c.draw_colored_polygon(PackedVector2Array([to + d * head * 0.4, to - d * head + d.orthogonal() * head * 0.7,
		to - d * head - d.orthogonal() * head * 0.7]), col)


## A dashed curve through `points` (jump arcs, swing paths).
static func dashed(c: CanvasItem, points: PackedVector2Array, col: Color, width := 3.0) -> void:
	for i in range(0, points.size() - 1, 2):
		c.draw_line(points[i], points[i + 1], col, width, true)


## A key cap with its label, centered at `center`. `pressed` darkens it.
static func keycap(c: CanvasItem, center: Vector2, label: String, pressed := false, scale := 1.0) -> void:
	var font := ThemeDB.fallback_font
	var size := int(20 * scale)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := maxf(44.0 * scale, tw + 24.0 * scale)
	var h := 44.0 * scale
	var offset := Vector2(0, 4.0 * scale) if pressed else Vector2.ZERO
	var r := Rect2(center - Vector2(w, h) / 2.0, Vector2(w, h))
	c.draw_rect(Rect2(r.position + Vector2(0, 6.0 * scale), r.size), Color("#1b2033"))
	r.position += offset
	c.draw_rect(r, Color("#e9ecf7") if not pressed else Color("#ffd36b"))
	c.draw_rect(r, Color("#1b2033"), false, 2.0)
	c.draw_string(font, Vector2(r.position.x, r.get_center().y + size * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color("#1b2033"))


## A labelled bar (health / energy). `frame` is the full width of its maximum.
static func bar(c: CanvasItem, pos: Vector2, frame: float, fill: float, col: Color, height := 18.0) -> void:
	c.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(frame + 6, height + 6)), Color(0, 0, 0, 0.6))
	c.draw_rect(Rect2(pos, Vector2(frame, height)), Color(1, 1, 1, 0.08))
	c.draw_rect(Rect2(pos, Vector2(clampf(fill, 0.0, frame), height)), col)
	c.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(frame + 6, height + 6)), Color(1, 1, 1, 0.5), false, 2.0)


## Movement ability symbol inside a radius `r` (pickups and popups).
static func movement_symbol(c: CanvasItem, ability_id: String, center: Vector2, r: float, col: Color) -> void:
	var w := maxf(2.0, r * 0.16)
	match ability_id:
		"double_jump": # Two stacked upward chevrons.
			for i in 2:
				var y := center.y + r * 0.35 - i * r * 0.62
				c.draw_polyline(PackedVector2Array([Vector2(center.x - r * 0.6, y + r * 0.3), Vector2(center.x, y - r * 0.3),
					Vector2(center.x + r * 0.6, y + r * 0.3)]), col, w, true)
		"dash": # A forward arrow with speed lines.
			arrow(c, center + Vector2(-r * 0.3, 0), center + Vector2(r * 0.55, 0), col, w)
			for i in 3:
				var y := center.y + (i - 1) * r * 0.38
				c.draw_line(Vector2(center.x - r * 0.95, y), Vector2(center.x - r * 0.45, y), Color(col, 0.6), w * 0.7, true)
		"wall_climb": # A wall with a zigzag climbing up it.
			c.draw_rect(Rect2(center.x + r * 0.45, center.y - r * 0.9, r * 0.35, r * 1.8), col)
			c.draw_polyline(PackedVector2Array([center + Vector2(-r * 0.7, r * 0.8), center + Vector2(r * 0.3, r * 0.35),
				center + Vector2(-r * 0.5, -r * 0.1), center + Vector2(r * 0.3, -r * 0.6)]), col, w, true)
		"grapple": # A hook on a rope.
			c.draw_line(center + Vector2(-r * 0.8, r * 0.8), center + Vector2(r * 0.15, -r * 0.15), Color(col, 0.7), w * 0.7, true)
			c.draw_arc(center + Vector2(r * 0.3, -r * 0.3), r * 0.4, -PI * 0.25, PI * 1.1, 14, col, w, true)
			c.draw_line(center + Vector2(r * 0.3, -r * 0.7), center + Vector2(r * 0.3, -r * 0.3), col, w, true)
		_:
			c.draw_circle(center, r * 0.3, col)
