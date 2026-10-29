class_name GearArt
extends RefCounted
## Placeholder drawings for pouches and tools, shared by the pickups (world)
## and the inventory's Gear tab (UI). Every pouch and every tool has its own
## drawing that shows what it does (or what its curse costs); unknown ids
## fall back to a generic sack or gem. Plain static functions on any
## CanvasItem, no autoloads. Replace with textures later.
##
##   Tools                    drawing
##   longreach_ribbon         a sword swing whose arc runs on into an arrow (reach)
##   wayfarer_anklet          a winged boot with speed lines (running speed)
##   scar_lantern             a lantern holding a drop of blood that turns into a bolt (wounds into energy)
##   quickening_hourglass     an hourglass with sand rising and a turn-back arrow (shorter recovery)
##   brimming_crest           a crest brimming over into wave rings (full-energy shockwave)
##   Pouches (curse)
##   patched_satchel          a patched satchel, a bolt leaking through a tear (spells cost more)
##   hollow_reliquary         a twin-chambered reliquary dripping energy (energy leak)
##   bloodbound_coffer        a three-lock iron coffer bound with a blood drop (enemies hit harder)

const TIER_COLORS: Array[Color] = [Color("#9fd99b"), Color("#6fb7ff"), Color("#ffad5c")] ## Weak, Medium, Strong.
const TIER_TAGS: Array[String] = ["W", "M", "S"]
const ENERGY := Color("#4fd1ff")
const BLOOD := Color("#ff5e6c")
const LEATHER := Color("#6b4f3a")
const IRON := Color("#7b8198")
const INK := Color("#1b2238")


static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier, 0, TIER_COLORS.size() - 1)]


## A tool's drawing inside a ring of its tier colour. `r` is the ring radius.
## `dim` draws it half greyed out (equipped elsewhere, like the spell pool).
static func tool(c: CanvasItem, center: Vector2, r: float, col: Color, dim := false, tool_id := "") -> void:
	var a := 0.4 if dim else 1.0
	c.draw_circle(center, r, Color(INK, a))
	c.draw_arc(center, r, 0.0, TAU, 28, Color(col, a), maxf(1.5, r * 0.14), true)
	var s := r * 0.62
	var w := maxf(1.5, r * 0.13)
	match tool_id:
		"longreach_ribbon":
			c.draw_line(center + Vector2(-s * 0.9, s * 0.9), center + Vector2(-s * 0.2, s * 0.2), Color(IRON, a), w * 1.4, true) # Hilt.
			c.draw_arc(center + Vector2(-s * 0.4, s * 0.4), s * 1.05, -PI * 0.5, 0.0, 12, Color(Color.WHITE, a), w, true) # Swing.
			_arrow(c, center + Vector2(s * 0.35, s * 0.05), Vector2(1, 0.15).normalized(), s * 0.7, Color(col, a), w)
		"wayfarer_anklet":
			var boot := PackedVector2Array([center + Vector2(-s * 0.3, -s * 0.8), center + Vector2(s * 0.15, -s * 0.8),
				center + Vector2(s * 0.15, s * 0.25), center + Vector2(s * 0.85, s * 0.45), center + Vector2(s * 0.85, s * 0.8),
				center + Vector2(-s * 0.3, s * 0.8)])
			c.draw_colored_polygon(boot, Color(LEATHER.lightened(0.25), a))
			c.draw_line(center + Vector2(-s * 0.3, -s * 0.35), center + Vector2(s * 0.15, -s * 0.35), Color(col, a), w, true) # Anklet.
			c.draw_line(center + Vector2(s * 0.15, -s * 0.6), center + Vector2(s * 0.7, -s * 0.95), Color(Color.WHITE, a), w, true) # Wing.
			for i in 3:
				var y := -s * 0.3 + i * s * 0.4
				c.draw_line(center + Vector2(-s * 1.05, y), center + Vector2(-s * 0.55, y), Color(col, a * 0.8), w * 0.8, true)
		"scar_lantern":
			c.draw_rect(Rect2(center + Vector2(-s * 0.55, -s * 0.55), Vector2(s * 1.1, s * 1.35)), Color(IRON, a), false, w)
			c.draw_arc(center + Vector2(0, -s * 0.55), s * 0.35, PI, TAU, 10, Color(IRON, a), w, true) # Handle.
			_drop(c, center + Vector2(-s * 0.15, s * 0.15), s * 0.32, Color(BLOOD, a))
			_bolt(c, center + Vector2(s * 0.22, s * 0.1), s * 0.5, Color(ENERGY, a), w)
		"quickening_hourglass":
			var top := PackedVector2Array([center + Vector2(-s * 0.6, -s * 0.85), center + Vector2(s * 0.6, -s * 0.85), center])
			var bottom := PackedVector2Array([center, center + Vector2(s * 0.6, s * 0.85), center + Vector2(-s * 0.6, s * 0.85)])
			c.draw_polyline(top + PackedVector2Array([top[0]]), Color(Color.WHITE, a), w, true)
			c.draw_polyline(bottom + PackedVector2Array([bottom[0]]), Color(Color.WHITE, a), w, true)
			c.draw_colored_polygon(PackedVector2Array([center + Vector2(-s * 0.35, -s * 0.5), center + Vector2(s * 0.35, -s * 0.5), center]), Color(col, a)) # Sand on top: it rises.
			c.draw_arc(center, s * 1.05, PI * 0.15, PI * 0.85, 10, Color(col, a * 0.8), w * 0.8, true)
			_arrow(c, center + Vector2(-s * 0.95, s * 0.35), Vector2(0, -1), s * 0.4, Color(col, a * 0.8), w * 0.8)
		"brimming_crest":
			var crest := PackedVector2Array([center + Vector2(-s * 0.55, -s * 0.7), center + Vector2(s * 0.55, -s * 0.7),
				center + Vector2(s * 0.55, s * 0.05), center + Vector2(0, s * 0.6), center + Vector2(-s * 0.55, s * 0.05)])
			c.draw_colored_polygon(crest, Color(col.darkened(0.35), a))
			c.draw_rect(Rect2(center + Vector2(-s * 0.35, -s * 0.5), Vector2(s * 0.7, s * 0.55)), Color(ENERGY, a)) # Full to the brim.
			for i in 2:
				c.draw_arc(center + Vector2(0, -s * 0.1), s * (0.95 + i * 0.3), -PI * 0.35, PI * 0.35, 10, Color(Color.WHITE, a * (0.8 - i * 0.3)), w * 0.8, true)
				c.draw_arc(center + Vector2(0, -s * 0.1), s * (0.95 + i * 0.3), PI * 0.65, PI * 1.35, 10, Color(Color.WHITE, a * (0.8 - i * 0.3)), w * 0.8, true)
		_:
			var g := s
			c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -g), center + Vector2(g * 0.85, 0),
				center + Vector2(0, g), center + Vector2(-g * 0.85, 0)]), Color(col, a))


## A pouch's drawing. `r` is about half its width. `dim` greys it out.
static func pouch(c: CanvasItem, center: Vector2, r: float, col: Color, dim := false, pouch_id := "") -> void:
	var a := 0.4 if dim else 1.0
	var w := maxf(1.5, r * 0.12)
	match pouch_id:
		"patched_satchel":
			var body := Rect2(center + Vector2(-r, -r * 0.45), Vector2(r * 2.0, r * 1.25))
			c.draw_rect(body, Color(LEATHER, a))
			c.draw_rect(body, Color(col, a), false, w)
			c.draw_colored_polygon(PackedVector2Array([body.position, body.position + Vector2(body.size.x, 0),
				center + Vector2(r * 0.8, r * 0.05), center + Vector2(-r * 0.8, r * 0.05)]), Color(LEATHER.lightened(0.15), a)) # Flap.
			c.draw_rect(Rect2(center + Vector2(-r * 0.75, r * 0.25), Vector2(r * 0.45, r * 0.4)), Color(Color("#a08c6e"), a)) # Patches.
			c.draw_rect(Rect2(center + Vector2(r * 0.35, -r * 0.35), Vector2(r * 0.4, r * 0.3)), Color(Color("#8c7a5e"), a))
			c.draw_arc(center + Vector2(0, -r * 0.45), r * 0.55, PI, TAU, 12, Color(LEATHER.darkened(0.3), a), w, true) # Strap.
			_bolt(c, center + Vector2(r * 0.15, r * 0.55), r * 0.35, Color(ENERGY, a * 0.85), w * 0.8) # Leaking through a tear.
		"hollow_reliquary":
			var box := Rect2(center + Vector2(-r, -r * 0.55), Vector2(r * 2.0, r * 1.3))
			c.draw_rect(box, Color(Color("#8a8fa3"), a))
			c.draw_rect(box, Color(col, a), false, w)
			c.draw_line(center + Vector2(0, -r * 0.55), center + Vector2(0, r * 0.75), Color(INK, a), w, true) # Two chambers.
			c.draw_colored_polygon(PackedVector2Array([box.position, box.position + Vector2(box.size.x, 0),
				center + Vector2(0, -r * 0.95)]), Color(Color("#a3a8bb"), a)) # Roof.
			for x in [-r * 0.5, r * 0.5]:
				c.draw_circle(center + Vector2(x, r * 0.05), r * 0.22, Color(INK, a)) # Hollow windows.
				_drop(c, center + Vector2(x, r * 1.05), r * 0.16, Color(ENERGY, a)) # Seeping out.
		"bloodbound_coffer":
			var box := Rect2(center + Vector2(-r, -r * 0.5), Vector2(r * 2.0, r * 1.25))
			c.draw_rect(box, Color(IRON.darkened(0.25), a))
			c.draw_rect(box, Color(col, a), false, w)
			c.draw_line(center + Vector2(-r, -r * 0.05), center + Vector2(r, -r * 0.05), Color(IRON, a), w, true) # Lid line.
			for i in 3: # Three locks of different sizes.
				var lr := r * (0.12 + i * 0.05)
				c.draw_rect(Rect2(center + Vector2(-r * 0.6 + i * r * 0.6 - lr, r * 0.15), Vector2(lr * 2.0, lr * 2.0)), Color(Color("#c9b06b"), a))
			c.draw_line(center + Vector2(-r * 1.05, -r * 0.3), center + Vector2(r * 1.05, r * 0.4), Color(BLOOD.darkened(0.2), a), w, true) # Bound.
			_drop(c, center + Vector2(r * 0.85, -r * 0.65), r * 0.22, Color(BLOOD, a))
		_:
			c.draw_circle(center + Vector2(0, r * 0.35), r, Color(LEATHER, a))
			c.draw_arc(center + Vector2(0, r * 0.35), r, 0.0, TAU, 24, Color(col, a), w, true)
			c.draw_rect(Rect2(center + Vector2(-r * 0.45, -r * 0.9), Vector2(r * 0.9, r * 0.55)), Color(LEATHER, a))


## An empty slot of a tier: a dashed ring in the tier's colour.
static func empty_slot(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	for i in 12:
		var a0 := TAU * i / 12.0
		c.draw_arc(center, r, a0, a0 + TAU / 24.0, 3, Color(col, 0.7), 2.0, true)


## An empty belt loop: two stitched straps where a pouch can hang.
static func belt_loop(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	for x in [-r * 0.6, r * 0.6]:
		c.draw_rect(Rect2(center + Vector2(x - r * 0.12, -r * 0.5), Vector2(r * 0.24, r * 1.0)), Color(col, 0.35), false, 1.5)


static func _arrow(c: CanvasItem, from: Vector2, dir: Vector2, length: float, col: Color, w: float) -> void:
	var tip := from + dir * length
	c.draw_line(from, tip, col, w, true)
	var side := dir.orthogonal() * length * 0.35
	c.draw_colored_polygon(PackedVector2Array([tip + dir * length * 0.3, tip + side, tip - side]), col)


static func _bolt(c: CanvasItem, center: Vector2, h: float, col: Color, w: float) -> void:
	c.draw_polyline(PackedVector2Array([center + Vector2(h * 0.25, -h), center + Vector2(-h * 0.2, 0), center + Vector2(h * 0.2, 0),
		center + Vector2(-h * 0.25, h)]), col, w, true)


static func _drop(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	c.draw_circle(center, r, col)
	c.draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.85, -r * 0.4), center + Vector2(r * 0.85, -r * 0.4),
		center + Vector2(0, -r * 2.0)]), col)
