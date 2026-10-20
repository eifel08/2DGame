class_name Effects
extends Node2D
## Purely visual effects: sparks, rings, floating damage numbers and dash
## afterimages. Nothing here affects gameplay. Afterimages are drawn on a
## child layer that sits behind the player.

const GHOST_Z := 2 ## Just below the player (z_index 3).

var particles: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var texts: Array[Dictionary] = []
var ghosts: Array[Dictionary] = []
var _back: Node2D


func _ready() -> void:
	_back = Node2D.new()
	_back.name = "GhostLayer"
	_back.z_as_relative = false
	_back.z_index = GHOST_Z
	add_child(_back)
	_back.draw.connect(_draw_ghosts)


func clear() -> void:
	particles.clear()
	rings.clear()
	texts.clear()
	ghosts.clear()


## opts: count, color, speed, life, size, gravity, angle, spread
func burst(pos: Vector2, opts := {}) -> void:
	var count: int = opts.get("count", 10)
	var speed: float = opts.get("speed", 220.0)
	var life: float = opts.get("life", 0.4)
	var size: float = opts.get("size", 4.0)
	var angle: float = opts.get("angle", 0.0)
	var spread: float = opts.get("spread", TAU)
	for i in count:
		var a := angle + randf_range(-spread / 2.0, spread / 2.0)
		particles.append({
			"pos": pos,
			"vel": Vector2.from_angle(a) * speed * randf_range(0.35, 1.0),
			"life": life, "max_life": life,
			"size": size * randf_range(0.6, 1.2),
			"color": opts.get("color", Color.WHITE),
			"gravity": opts.get("gravity", 600.0),
		})


func ring(pos: Vector2, opts := {}) -> void:
	var life: float = opts.get("life", 0.35)
	rings.append({
		"pos": pos, "radius": opts.get("radius", 60.0), "life": life, "max_life": life,
		"color": opts.get("color", Color.WHITE), "width": opts.get("width", 4.0),
	})


func float_text(pos: Vector2, text: String, color := Color.WHITE) -> void:
	texts.append({"pos": pos + Vector2(randf_range(-6, 6), 0), "text": text, "color": color, "life": 0.7, "max_life": 0.7})


func ghost(rect: Rect2, color := Color(0.63, 0.9, 1.0, 0.5)) -> void:
	ghosts.append({"rect": rect, "color": color, "life": 0.18, "max_life": 0.18})


func step(delta: float) -> void:
	for p in particles:
		p.life -= delta
		p.vel.y += p.gravity * delta
		p.pos += p.vel * delta
	for r in rings:
		r.life -= delta
	for t in texts:
		t.life -= delta
		t.pos.y -= 40.0 * delta
	for g in ghosts:
		g.life -= delta
	var alive := func(e: Dictionary) -> bool: return e.life > 0.0
	particles = particles.filter(alive)
	rings = rings.filter(alive)
	texts = texts.filter(alive)
	ghosts = ghosts.filter(alive)
	queue_redraw()
	_back.queue_redraw()


func _draw_ghosts() -> void:
	for g in ghosts:
		_back.draw_rect(g.rect, Color(g.color, g.color.a * g.life / g.max_life))


func _draw() -> void:
	for p in particles:
		var s: float = p.size
		draw_rect(Rect2(p.pos - Vector2(s, s) / 2.0, Vector2(s, s)), Color(p.color, maxf(0.0, p.life / p.max_life)))
	for r in rings:
		var k: float = 1.0 - r.life / r.max_life
		draw_arc(r.pos, r.radius * (0.2 + 0.8 * k), 0.0, TAU, 48, Color(r.color, 1.0 - k), r.width * (1.0 - k) + 1.0, true)
	var font := ThemeDB.fallback_font
	for t in texts:
		var a: float = maxf(0.0, t.life / t.max_life)
		var pos: Vector2 = t.pos - Vector2(40, 0)
		draw_string(font, pos + Vector2(1, 1), t.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(0, 0, 0, a))
		draw_string(font, pos, t.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(t.color, a))
