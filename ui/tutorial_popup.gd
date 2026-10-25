class_name TutorialPopup
extends CanvasLayer
## Full-screen tutorial / discovery window. It covers the whole screen and
## explains a mechanic with an animated drawing, key caps for the player's
## own bindings and a one- or two-word title. Almost no text.
## While it is open the game simulation is paused (core/game.gd).
## ANY key closes it (also a gamepad button or a mouse click), after a short
## guard so a key already on its way down does not skip it unseen. The key
## that closes it never reaches the game (Game skips the next steps).
##
## Ids (see TITLES): movement items, progression pickups, the altar, and the
## basic actions (move, jump, heal, mana_discharge) that Game.learn_* show.
## Art: every drawing is a placeholder in _draw_<id>(); replace freely.

const GUARD_TIME := 0.25 ## Presses this soon after opening are ignored.
const SWALLOW_STEPS := 2 ## Simulation steps skipped after closing.

const TITLES := {
	"move": "MOVE",
	"jump": "JUMP",
	"heal": "HEAL",
	"mana_discharge": "MANA DISCHARGE",
	"double_jump": "DOUBLE JUMP",
	"dash": "DASH",
	"wall_climb": "WALL CLIMB",
	"grapple": "GRAPPLING HOOK",
	"meditation": "CONCENTRATION",
	"health_potion": "HEALTH POTION",
	"mana_potion": "MANA POTION",
	"spell_scroll": "SPELL SCROLL",
}
const HEALTH_COLOR := Color("#ff5e6c")
const ENERGY_COLOR := Color("#4fd1ff")

var current := "" ## Id on screen, "" when closed.
var queue: Array[String] = [] ## Ids waiting for the current one to close.
var screen: Control
var time := 0.0
var swallow := 0 ## Simulation steps still to skip after a close.


func _ready() -> void:
	layer = 60
	screen = Control.new()
	screen.name = "Screen"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.layout_direction = Control.LAYOUT_DIRECTION_LTR
	screen.draw.connect(_draw_screen)
	add_child(screen)
	screen.visible = false


func is_open() -> bool:
	return current != ""


func open(id: String) -> void:
	if not TITLES.has(id):
		push_warning("TutorialPopup: unknown tutorial '%s'" % id)
		return
	if is_open():
		if id != current and not queue.has(id):
			queue.append(id)
		return
	current = id
	time = 0.0
	screen.visible = true
	screen.queue_redraw()
	Events.tutorial_opened.emit(id)


func close() -> void:
	if not is_open():
		return
	var id := current
	current = ""
	screen.visible = false
	swallow = SWALLOW_STEPS
	Events.tutorial_closed.emit(id)
	if not queue.is_empty():
		open(queue.pop_front())


## Game asks once per physics step: true while the step must not run
## (open, or right after a close so the dismissing key does nothing).
func blocks_step() -> bool:
	if is_open():
		return true
	if swallow > 0:
		swallow -= 1
		return true
	return false


func _process(delta: float) -> void:
	if is_open():
		time += delta
		screen.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var dismiss := false
	if event is InputEventKey:
		dismiss = event.pressed and not event.echo
	elif event is InputEventJoypadButton or event is InputEventMouseButton:
		dismiss = event.pressed
	if not dismiss:
		return
	get_viewport().set_input_as_handled()
	if time >= GUARD_TIME:
		close()


# ---------- Drawing ----------

func _draw_screen() -> void:
	var c := screen
	var vs := c.size
	c.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.07, 1.0)) # Opaque: the game is hidden.
	var font := ThemeDB.fallback_font
	var title: String = TITLES.get(current, "")
	c.draw_string(font, Vector2(0, vs.y * 0.13), title, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 34, Color("#ffd43b"))
	var art := Rect2(vs.x * 0.12, vs.y * 0.18, vs.x * 0.76, vs.y * 0.62)
	c.draw_rect(art, Color(1, 1, 1, 0.04))
	c.draw_rect(art, Color(1, 1, 1, 0.12), false, 2.0)
	var fn := "_draw_" + current
	if has_method(fn):
		call(fn, c, art, time)
	# The only sentence: how to go on.
	var blink := 0.45 + 0.35 * sin(time * 4.0)
	c.draw_string(font, Vector2(0, vs.y * 0.955), "any key", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 14, Color(1, 1, 1, blink))


## Key caps for actions in a row under the drawing. `lit` (per cap) shows a
## pressed key. Entries: action names, or "+" for a plus sign.
func _keys(c: Control, art: Rect2, entries: Array, lit: Array = []) -> void:
	var font := ThemeDB.fallback_font
	var y := art.end.y + c.size.y * 0.075
	var step := 120.0
	var x := art.get_center().x - step * (entries.size() - 1) / 2.0
	for i in entries.size():
		var e: String = entries[i]
		if e == "+":
			c.draw_string(font, Vector2(x - 20, y + 10), "+", HORIZONTAL_ALIGNMENT_CENTER, 40, 28, Color(1, 1, 1, 0.8))
		else:
			AbilityArt.keycap(c, Vector2(x, y), _key(e), i < lit.size() and lit[i])
		x += step


func _key(action: String) -> String:
	var k := Settings.key_name(action)
	return k if k != "" else "?"


static func _ground_y(art: Rect2) -> float:
	return art.end.y - 46.0


static func _loop(t: float, period: float) -> float:
	return fmod(t, period) / period


# --- Basic actions (shown only through Game.learn_*) ---

func _draw_move(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	AbilityArt.ground(c, art.position.x + 30, art.end.x - 30, gy)
	var cx := art.get_center().x
	var x := cx + sin(t * 1.8) * 200.0
	var dir := 1 if cos(t * 1.8) > 0.0 else -1
	for i in range(3, 0, -1):
		AbilityArt.ghost(c, Vector2(cx + sin((t - i * 0.06) * 1.8) * 200.0, gy), 64, 0.12 * (4 - i), dir)
	AbilityArt.figure(c, Vector2(x, gy), 64, dir)
	AbilityArt.arrow(c, Vector2(cx - 60, gy - 120), Vector2(cx - 160, gy - 120), Color(AbilityArt.ARROW_COLOR, 1.0 if dir < 0 else 0.3))
	AbilityArt.arrow(c, Vector2(cx + 60, gy - 120), Vector2(cx + 160, gy - 120), Color(AbilityArt.ARROW_COLOR, 1.0 if dir > 0 else 0.3))
	_keys(c, art, ["move_left", "move_right"], [dir < 0, dir > 0])


func _draw_jump(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	AbilityArt.ground(c, art.position.x + 30, art.end.x - 30, gy)
	var x0 := art.get_center().x - 160.0
	var path := func(s: float) -> Vector2:
		return Vector2(x0 + s * 320.0, gy - 170.0 * 4.0 * s * (1.0 - s))
	_dashed_path(c, path, 0.0, 1.0)
	var ph := _loop(t, 1.6)
	var s := clampf((ph - 0.15) / 0.7, 0.0, 1.0)
	AbilityArt.figure(c, path.call(s), 64, 1, AbilityArt.PLAYER_COLOR, 0.85 if s == 0.0 else 1.0)
	_keys(c, art, ["jump"], [ph > 0.1 and ph < 0.35])


func _draw_heal(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	var cx := art.get_center().x
	AbilityArt.ground(c, art.position.x + 30, art.end.x - 30, gy)
	var ph := _loop(t, 2.4)
	var k := clampf(ph / 0.7, 0.0, 1.0)
	AbilityArt.figure(c, Vector2(cx, gy), 64, 1, Color("#8dffb0"), 0.92 + 0.04 * sin(t * 10.0))
	for i in 5: # Rising green motes.
		var mp := fmod(t * 0.8 + i * 0.2, 1.0)
		var mx := cx + (i - 2) * 16.0
		_plus(c, Vector2(mx, gy - 20 - mp * 110.0), 7.0, Color(0.55, 1.0, 0.7, 1.0 - mp))
	var bx := cx - 150.0
	var by := art.position.y + 40.0
	AbilityArt.bar(c, Vector2(bx, by), 300, 140, HEALTH_COLOR)
	c.draw_rect(Rect2(bx + 140, by, 70 * k, 18), Color.WHITE if k < 1.0 else HEALTH_COLOR) # White, then red.
	AbilityArt.bar(c, Vector2(bx, by + 36), 300, 300 - 120 * k, ENERGY_COLOR)
	_keys(c, art, ["heal"], [ph < 0.8])
	_hold_mark(c, art)


func _draw_mana_discharge(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	var cx := art.get_center().x
	AbilityArt.ground(c, art.position.x + 30, art.end.x - 30, gy)
	var ph := _loop(t, 1.8)
	AbilityArt.figure(c, Vector2(cx, gy), 64, 1, Color("#d6a8ff") if ph < 0.15 else AbilityArt.PLAYER_COLOR)
	if ph >= 0.12:
		var k := (ph - 0.12) / 0.88
		c.draw_arc(Vector2(cx, gy - 32), 30.0 + k * 190.0, 0.0, TAU, 64, Color(0.75, 0.9, 1.0, 1.0 - k), 6.0, true)
	var bx := cx - 150.0
	AbilityArt.bar(c, Vector2(bx, art.position.y + 40.0), 300, 300.0 if ph < 0.12 else 0.0, ENERGY_COLOR)
	_keys(c, art, ["spell"], [ph < 0.2])


# --- Movement items ---

func _draw_double_jump(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	AbilityArt.ground(c, art.position.x + 30, art.end.x - 30, gy)
	var x0 := art.get_center().x - 220.0
	# One path: a jump to its apex, a second jump from mid-air, the fall.
	var path := func(s: float) -> Vector2:
		var x := x0 + s * 440.0
		if s < 0.35:
			var u := s / 0.35
			return Vector2(x, gy - 120.0 * (1.0 - (1.0 - u) * (1.0 - u)))
		if s < 0.65:
			var u := (s - 0.35) / 0.3
			return Vector2(x, gy - 120.0 - 110.0 * (1.0 - (1.0 - u) * (1.0 - u)))
		var u := (s - 0.65) / 0.35
		return Vector2(x, gy - 230.0 * (1.0 - u * u))
	_dashed_path(c, path, 0.0, 1.0)
	var mid: Vector2 = path.call(0.35)
	c.draw_arc(mid + Vector2(0, -10), 26.0, 0.0, TAU, 32, Color(0.75, 0.96, 1.0, 0.8), 3.0, true)
	var ph := _loop(t, 2.2)
	var s := clampf((ph - 0.1) / 0.8, 0.0, 1.0)
	AbilityArt.figure(c, path.call(s), 60)
	var first := ph > 0.06 and ph < 0.22
	var second := s > 0.33 and s < 0.45
	_keys(c, art, ["jump", "+", "jump"], [first, false, second])


func _draw_dash(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	AbilityArt.ground(c, art.position.x + 30, art.end.x - 30, gy)
	var x0 := art.position.x + 120.0
	var x1 := art.end.x - 120.0
	var ph := _loop(t, 1.8)
	var k := clampf((ph - 0.3) / 0.18, 0.0, 1.0)
	var x := lerpf(x0, x1, k)
	if k > 0.0 and k < 1.0 or (ph > 0.48 and ph < 0.6):
		for i in 5:
			AbilityArt.ghost(c, Vector2(x - (i + 1) * 46.0 * minf(1.0, k * 4.0), gy), 60, 0.35 - i * 0.06)
		for i in 3:
			var y := gy - 14.0 - i * 18.0
			c.draw_line(Vector2(x - 220, y), Vector2(x - 40, y), Color(0.85, 0.96, 1.0, 0.5), 3.0)
	AbilityArt.figure(c, Vector2(x, gy), 60, 1, Color.WHITE if k > 0.0 and k < 1.0 else AbilityArt.PLAYER_COLOR, 0.75 if k > 0.0 and k < 1.0 else 1.0)
	_keys(c, art, ["dash"], [ph > 0.25 and ph < 0.45])


func _draw_wall_climb(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	var wx := art.get_center().x + 90.0
	AbilityArt.ground(c, art.position.x + 30, wx, gy)
	AbilityArt.wall(c, wx, art.position.y + 40.0, gy + 10.0, 40.0)
	# Zigzag up the one wall: touch, jump off and back, higher each time.
	var pts := PackedVector2Array([Vector2(wx - 90, gy)])
	var rise := (gy - art.position.y - 70.0) / 4.0
	for i in 4:
		pts.append(Vector2(wx - 17, gy - 30.0 - i * rise)) # On the wall (feet).
		pts.append(Vector2(wx - 85, gy - 30.0 - (i + 0.6) * rise)) # Pushed away.
	pts.append(Vector2(wx - 17, gy - 30.0 - 4.0 * rise))
	for i in pts.size() - 1:
		AbilityArt.dashed(c, PackedVector2Array([pts[i], pts[i].lerp(pts[i + 1], 0.5), pts[i].lerp(pts[i + 1], 0.5), pts[i + 1]]),
			Color(0.62, 0.88, 0.63, 0.5))
	var ph := _loop(t, 3.0)
	var f := ph * (pts.size() - 1)
	var i0 := mini(int(f), pts.size() - 2)
	var pos := pts[i0].lerp(pts[i0 + 1], f - i0)
	var on_wall := absf(pos.x - (wx - 17)) < 12.0
	if on_wall: # Wall friction: a slide streak.
		c.draw_line(Vector2(wx - 3, pos.y - 50), Vector2(wx - 3, pos.y), Color(1, 1, 1, 0.5), 3.0)
	AbilityArt.figure(c, pos + Vector2(0, 0), 54, -1 if on_wall else 1, Color("#6fb8e0") if on_wall else AbilityArt.PLAYER_COLOR)
	_keys(c, art, ["move_right", "+", "jump"], [true, false, on_wall])


func _draw_grapple(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	var mid := art.get_center().x
	# Left: a straight throw pulls you to the wall ahead.
	var wx := mid - 60.0
	AbilityArt.ground(c, art.position.x + 30, wx, gy)
	AbilityArt.wall(c, wx, art.position.y + 20.0, gy + 10.0, 26.0)
	var ph := _loop(t, 2.4)
	var start := Vector2(art.position.x + 80.0, gy)
	var anchor := Vector2(wx, gy - 150.0)
	var fly := clampf(ph / 0.2, 0.0, 1.0)
	var pull := clampf((ph - 0.25) / 0.35, 0.0, 1.0)
	var feet := start.lerp(anchor + Vector2(-16, 26), pull * pull * (3.0 - 2.0 * pull))
	if fly < 1.0 and pull == 0.0:
		feet = start.lerp(start + Vector2(0, -60), fly) # Hop, then hang while the hook flies.
	elif pull == 0.0:
		feet = start + Vector2(0, -60)
	var hand := feet + Vector2(10, -40)
	var tip := hand.lerp(anchor, fly) if pull == 0.0 else anchor
	c.draw_line(hand, tip, Color("#e8dcb8"), 3.0, true)
	c.draw_circle(tip, 6.0, Color("#e8dcb8"))
	AbilityArt.figure(c, feet, 54)
	# Right: Down + hook in the air swings on the ceiling.
	var cx := mid + 190.0
	var ceil := art.position.y + 30.0
	c.draw_rect(Rect2(cx - 120, ceil - 14, 240, 14), AbilityArt.GROUND_COLOR)
	var pivot := Vector2(cx, ceil)
	var ang := sin(t * 2.2) * 0.9
	var body := pivot + Vector2(sin(ang), cos(ang)) * 170.0
	var arc := PackedVector2Array()
	for i in 24:
		var a := lerpf(-0.9, 0.9, i / 23.0)
		arc.append(pivot + Vector2(sin(a), cos(a)) * 190.0)
	AbilityArt.dashed(c, arc, Color(1, 1, 1, 0.3))
	c.draw_line(pivot, body, Color("#e8dcb8"), 3.0, true)
	c.draw_circle(pivot, 6.0, Color("#e8dcb8"))
	AbilityArt.figure(c, body + Vector2(0, 46), 46, 1 if cos(t * 2.2) > 0.0 else -1)
	c.draw_line(Vector2(mid + 40, art.position.y + 20), Vector2(mid + 40, art.end.y - 20), Color(1, 1, 1, 0.15), 2.0)
	_keys(c, art, ["grapple", "move_down", "+", "grapple"], [ph < 0.15, true, false, true])


# --- Progression pickups and the altar ---

func _draw_meditation(c: Control, art: Rect2, t: float) -> void:
	var gy := _ground_y(art)
	var ax := art.get_center().x - 130.0
	AbilityArt.ground(c, art.position.x + 30, art.end.x - 30, gy)
	_altar(c, Vector2(ax, gy), t)
	var ph := _loop(t, 3.2)
	var k := clampf(ph / 0.65, 0.0, 1.0)
	AbilityArt.figure(c, Vector2(ax, gy - 4), 60, 1, Color("#b9a8ff"), 0.72)
	c.draw_arc(Vector2(ax, gy - 30), 52.0, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Color("#b9a8ff"), 4.0, true)
	for i in 4:
		var mp := fmod(t * 0.6 + i * 0.25, 1.0)
		c.draw_circle(Vector2(ax + (i - 1.5) * 22.0, gy - 10 - mp * 120.0), 3.0, Color(0.73, 0.66, 1.0, 1.0 - mp))
	AbilityArt.arrow(c, Vector2(ax + 80, gy - 120), Vector2(ax + 160, gy - 120))
	_cross(c, Vector2(ax + 290, gy - 130), 46.0, k >= 1.0)
	_keys(c, art, ["interact"], [ph < 0.12])


func _draw_health_potion(c: Control, art: Rect2, t: float) -> void:
	var cy := art.get_center().y
	var px := art.position.x + 140.0
	_flask(c, Vector2(px, cy + 10), 1.0 + 0.05 * sin(t * 4.0))
	AbilityArt.arrow(c, Vector2(px + 70, cy), Vector2(px + 150, cy))
	_grow_bar(c, Vector2(px + 190, cy - 9), t, HEALTH_COLOR)
	_plus(c, Vector2(px + 190 + 330, cy - 40), 14.0, HEALTH_COLOR)


func _draw_mana_potion(c: Control, art: Rect2, t: float) -> void:
	var cy := art.get_center().y
	var px := art.position.x + 140.0
	_bottle(c, Vector2(px, cy + 10), 1.0 + 0.05 * sin(t * 4.0))
	AbilityArt.arrow(c, Vector2(px + 70, cy), Vector2(px + 150, cy))
	_grow_bar(c, Vector2(px + 190, cy - 9), t, ENERGY_COLOR)
	_plus(c, Vector2(px + 190 + 330, cy - 40), 14.0, ENERGY_COLOR)


## Three steps: 1 learn (touch the scroll), 2 equip at your flame (inventory),
## 3 cast (Spell + direction).
func _draw_spell_scroll(c: Control, art: Rect2, t: float) -> void:
	var font := ThemeDB.fallback_font
	var gy := _ground_y(art)
	var w := art.size.x / 3.0
	var ph := _loop(t, 3.0)
	for i in 3:
		var x0 := art.position.x + w * i
		c.draw_string(font, Vector2(x0 + 14, art.position.y + 34), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.5))
		if i > 0:
			c.draw_line(Vector2(x0, art.position.y + 16), Vector2(x0, art.end.y - 16), Color(1, 1, 1, 0.15), 2.0)
		AbilityArt.ground(c, x0 + 20, x0 + w - 20, gy)
	# 1: walk into the scroll; it is gone, the spell is yours.
	var c1 := art.position.x + w * 0.5
	var walk := clampf(ph / 0.4, 0.0, 1.0)
	if walk < 1.0:
		_scroll(c, Vector2(c1 + 40, gy - 30))
	else:
		c.draw_arc(Vector2(c1 + 40, gy - 30), 24.0, 0.0, TAU, 32, Color(1, 0.95, 0.75, 0.6), 3.0, true)
	AbilityArt.figure(c, Vector2(c1 - 70 + 110 * walk, gy), 50)
	# 2: at your flame, put it on a direction in the inventory.
	var c2 := art.position.x + w * 1.5
	_flame(c, Vector2(c2 - 60, gy), t)
	AbilityArt.figure(c, Vector2(c2 - 20, gy), 50)
	_cross(c, Vector2(c2 + 70, gy - 120), 26.0, true, ph > 0.5)
	AbilityArt.keycap(c, Vector2(c2 + 70, gy - 30), _key("inventory"), ph > 0.4 and ph < 0.55, 0.8)
	# 3: Spell + the direction casts it.
	var c3 := art.position.x + w * 2.5
	AbilityArt.figure(c, Vector2(c3, gy), 50)
	if ph > 0.7:
		var k := (ph - 0.7) / 0.3
		c.draw_arc(Vector2(c3, gy - 25), 20.0 + k * 90.0, 0.0, TAU, 48, Color(0.84, 0.66, 1.0, 1.0 - k), 5.0, true)
	_keys(c, art, ["spell", "+", "move_up"], [ph > 0.68, false, ph > 0.68])


# ---------- Small drawings ----------

func _dashed_path(c: Control, path: Callable, from: float, to: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		pts.append(path.call(lerpf(from, to, i / 40.0)) + Vector2(0, -30))
	AbilityArt.dashed(c, pts, Color(1, 1, 1, 0.3))


func _plus(c: Control, at: Vector2, r: float, col: Color) -> void:
	c.draw_rect(Rect2(at - Vector2(r, r * 0.3), Vector2(r * 2.0, r * 0.6)), col)
	c.draw_rect(Rect2(at - Vector2(r * 0.3, r), Vector2(r * 0.6, r * 2.0)), col)


func _hold_mark(c: Control, art: Rect2) -> void:
	# A small clock arc beside the key: hold it down.
	var at := Vector2(art.get_center().x + 50, art.end.y + c.size.y * 0.075)
	c.draw_arc(at, 12.0, -PI / 2.0, -PI / 2.0 + TAU * fmod(time, 1.0), 24, Color(1, 1, 1, 0.8), 3.0, true)


## A bar whose frame grows: the new maximum.
func _grow_bar(c: Control, pos: Vector2, t: float, col: Color) -> void:
	var k := clampf(_loop(t, 2.4) / 0.5, 0.0, 1.0)
	var frame := lerpf(200.0, 300.0, k * k * (3.0 - 2.0 * k))
	AbilityArt.bar(c, pos, frame, frame, col, 22.0)
	if k < 1.0:
		c.draw_rect(Rect2(pos + Vector2(200, -3), Vector2(frame - 200, 28)), Color(1, 1, 1, 0.35 * (1.0 - k)))


func _flask(c: Control, at: Vector2, s: float) -> void: # Health Potion: red, round.
	c.draw_circle(at, 46.0 * s, Color(1, 0.37, 0.42, 0.18))
	c.draw_circle(at + Vector2(0, 8), 28.0 * s, HEALTH_COLOR)
	c.draw_rect(Rect2(at + Vector2(-8, -36) * s, Vector2(16, 20) * s), Color("#ffb3bb"))
	c.draw_rect(Rect2(at + Vector2(-10, -46) * s, Vector2(20, 10) * s), Color("#9a6b3f"))
	c.draw_circle(at + Vector2(-10, 0) * s, 5.0 * s, Color(1, 1, 1, 0.7))


func _bottle(c: Control, at: Vector2, s: float) -> void: # Mana Potion: blue, tall, angular.
	c.draw_circle(at, 50.0 * s, Color(0.31, 0.55, 1.0, 0.18))
	var body := PackedVector2Array()
	for p in [Vector2(0, -14), Vector2(20, 0), Vector2(20, 30), Vector2(0, 44), Vector2(-20, 30), Vector2(-20, 0)]:
		body.append(at + p * s)
	c.draw_colored_polygon(body, Color("#3d7bff"))
	c.draw_rect(Rect2(at + Vector2(-6, -46) * s, Vector2(12, 34) * s), Color("#a9c8ff"))
	c.draw_rect(Rect2(at + Vector2(-8, -56) * s, Vector2(16, 10) * s), Color("#3a4a8a"))
	c.draw_rect(Rect2(at + Vector2(-13, 4) * s, Vector2(5, 22) * s), Color(1, 1, 1, 0.7))


func _scroll(c: Control, at: Vector2) -> void:
	c.draw_circle(at, 24.0, Color(0.84, 0.66, 1.0, 0.18))
	c.draw_rect(Rect2(at - Vector2(13, 16), Vector2(26, 32)), Color("#e9d9a6"))
	c.draw_rect(Rect2(at - Vector2(17, 20), Vector2(34, 5)), Color("#7a5230"))
	c.draw_rect(Rect2(at + Vector2(-17, 15), Vector2(34, 5)), Color("#7a5230"))
	c.draw_circle(at + Vector2(0, 5), 5.0, Color("#a96bff"))


func _flame(c: Control, feet: Vector2, t: float) -> void:
	c.draw_rect(Rect2(feet + Vector2(-4, -50), Vector2(8, 50)), Color("#737f99"))
	var f := 1.0 + 0.12 * sin(t * 9.0)
	c.draw_colored_polygon(PackedVector2Array([feet + Vector2(0, -80 * f), feet + Vector2(12, -56), feet + Vector2(0, -48),
		feet + Vector2(-12, -56)]), Color("#ffb347"))


func _altar(c: Control, feet: Vector2, t: float) -> void:
	c.draw_rect(Rect2(feet + Vector2(-44, -14), Vector2(88, 14)), Color("#5a6178"))
	c.draw_rect(Rect2(feet + Vector2(-24, -44), Vector2(48, 30)), Color("#6f7894"))
	var rune := feet + Vector2(0, -110 - 6.0 * sin(t * 2.0))
	c.draw_arc(rune, 18.0, 0.0, TAU, 32, Color("#b9a8ff"), 4.0, true)
	c.draw_circle(rune, 6.0, Color("#efe9ff"))


## The spell cross (Up, Left, Center, Right, Down). `open` unlocks the Up
## slot (padlock -> empty); `filled` puts a spell into it.
func _cross(c: Control, center: Vector2, cell: float, open: bool, filled := false) -> void:
	var g := cell + 6.0
	var spots := {"Up": Vector2(0, -g), "Left": Vector2(-g, 0), "Center": Vector2.ZERO, "Right": Vector2(g, 0), "Down": Vector2(0, g)}
	for n in spots:
		var r := Rect2(center + spots[n] - Vector2(cell, cell) / 2.0, Vector2(cell, cell))
		c.draw_rect(r, Color(0, 0, 0, 0.6))
		var mid := r.get_center()
		if n == "Center":
			c.draw_rect(r, Color("#6ee7a8"), false, 2.0)
			AbilityIcon.draw_symbol(c, "discharge", mid, cell * 0.32, Color("#a8e6ff"))
		elif n == "Up" and open:
			c.draw_rect(r, Color("#ffd36b"), false, 3.0)
			if filled:
				AbilityIcon.draw_symbol(c, "nova", mid, cell * 0.32, Color("#d6a8ff"))
			else:
				AbilityIcon.draw_symbol(c, "empty", mid, cell * 0.36, Color.WHITE)
		else:
			c.draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
			AbilityIcon.draw_symbol(c, "locked", mid, cell * 0.36, Color(1, 1, 1, 0.45))
