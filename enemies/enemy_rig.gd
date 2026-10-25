class_name EnemyRig
extends Node2D
## Placeholder art for the BaseEnemy roster: one script, one drawing per
## `look`, posed from the enemy's state (wind-ups read clearly). It sits
## under Flip, so it is mirrored with the enemy's facing. Replace this node
## with real sprites / an AnimatedSprite2D; gameplay never reads it.

@export var look := "swooper"

## States that announce an attack: a white glint blinks above the head.
const TELEGRAPH_STATES: Array[String] = ["alert", "windup", "aim", "vanish", "crouch"]

var enemy: BaseEnemy


func _ready() -> void:
	enemy = get_parent().get_parent() as BaseEnemy


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if enemy == null:
		return
	modulate.a = enemy.visual_alpha
	var s := enemy.size
	if not enemy.alive:
		var k := clampf(1.0 - enemy.dead_time / 0.6, 0.0, 1.0)
		draw_rect(Rect2(-s.x / 2.0, -s.y * 0.3, s.x, s.y * 0.3), Color(0.15, 0.12, 0.15, k))
		return
	var fn := "_draw_" + look
	if has_method(fn):
		call(fn, s, enemy.state, enemy.state_time, enemy.t)
	if enemy.state in TELEGRAPH_STATES and fmod(enemy.state_time, 0.16) < 0.1:
		var top := Vector2(0, -s.y - 14.0)
		draw_rect(Rect2(top + Vector2(-2, -12), Vector2(4, 9)), Color.WHITE)
		draw_rect(Rect2(top + Vector2(-2, 0), Vector2(4, 4)), Color.WHITE)


func _eye(at: Vector2, alert: bool, r := 3.0) -> void:
	draw_circle(at, r, Color("#ff4d5e") if alert else Color("#ffe9a8"))


func _draw_swooper(s: Vector2, state: String, _st: float, t: float) -> void:
	var c := Vector2(0, -s.y / 2.0)
	var flap := sin(t * 18.0) * 0.6
	for side: float in [-1.0, 1.0]:
		var tip := c + Vector2(side * s.x * 0.95, -s.y * 0.2 + flap * s.y * 0.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(side * 4, -4), tip, c + Vector2(side * 6, 5)]), Color("#4b3f8f"))
	draw_circle(c, s.y * 0.45, Color("#6a5acd"))
	_eye(c + Vector2(5, -2), state in ["alert", "chase"])


func _draw_charger(s: Vector2, state: String, st: float, _t: float) -> void:
	var shake := Vector2(sin(st * 70.0) * 2.0, 0) if state == "windup" else Vector2.ZERO
	var lean := 0.12 if state == "charge" else 0.0
	var body := Rect2(-s.x / 2.0, -s.y, s.x, s.y * 0.8)
	draw_set_transform(shake, 0.0, Vector2.ONE)
	draw_rect(body, Color("#8b5a2b"))
	draw_rect(Rect2(body.position + Vector2(0, -4), Vector2(s.x * 0.7, 6)), Color("#6e4520")) # Mane.
	for i in 2: # Legs.
		draw_rect(Rect2(-s.x / 2.0 + 6 + i * (s.x - 20), -s.y * 0.2, 8, s.y * 0.2), Color("#5e3b18"))
	var head := Vector2(s.x / 2.0 - 2, -s.y * 0.62 + lean * 20.0)
	draw_colored_polygon(PackedVector2Array([head + Vector2(0, -6), head + Vector2(16, -16), head + Vector2(8, 0)]), Color("#f1e3c0")) # Horn.
	_eye(head + Vector2(-8, -8), state in ["windup", "charge"])
	draw_set_transform(Vector2.ZERO)


func _draw_thrower(s: Vector2, state: String, st: float, _t: float) -> void:
	draw_rect(Rect2(-s.x / 2.0, -s.y, s.x, s.y), Color("#6b8e5a"))
	draw_colored_polygon(PackedVector2Array([Vector2(-s.x / 2.0, -s.y + 10), Vector2(0, -s.y - 8), Vector2(s.x / 2.0, -s.y + 10)]), Color("#4f6b40")) # Hood.
	_eye(Vector2(6, -s.y + 12), state == "windup")
	var hand := Vector2(-4, -s.y * 0.75) if state == "windup" else Vector2(s.x / 2.0 + 2, -s.y * 0.5)
	draw_line(Vector2(0, -s.y * 0.55), hand, Color("#4f6b40"), 4.0)
	if state == "windup":
		draw_circle(hand, 6.0 + st * 4.0, Color("#ffc94d"))


func _draw_brute(s: Vector2, state: String, st: float, _t: float) -> void:
	draw_rect(Rect2(-s.x / 2.0, -s.y, s.x, s.y), Color("#7a3e2e"))
	draw_rect(Rect2(-s.x / 2.0 + 4, -s.y + 6, s.x - 8, 10), Color("#5a2a1e")) # Brow.
	_eye(Vector2(s.x * 0.2, -s.y + 20), state == "windup", 4.0)
	# The club: raised high in the wind-up, slammed down in the smash.
	var grip := Vector2(s.x * 0.35, -s.y * 0.55)
	var angle := -2.4 if state == "windup" else (0.2 if state in ["smash", "recover"] else -0.8)
	if state == "windup":
		angle -= minf(st, 0.6) * 0.5
	var d := Vector2.from_angle(angle)
	var head := grip + d * 48.0
	draw_line(grip, head, Color("#6b4423"), 9.0)
	draw_circle(head, 13.0, Color("#5a3a20"))
	for i in 3:
		draw_circle(head + Vector2.from_angle(i * TAU / 3.0 + angle) * 9.0, 3.0, Color("#c0c6d0"))


func _draw_ambusher(s: Vector2, state: String, _st: float, _t: float) -> void:
	var col := Color("#2e5d6b") if state != "ghost" else Color("#9fe8ff")
	draw_colored_polygon(PackedVector2Array([Vector2(-s.x / 2.0, 0), Vector2(-s.x / 2.0 + 4, -s.y * 0.8), Vector2(0, -s.y),
		Vector2(s.x / 2.0 - 4, -s.y * 0.8), Vector2(s.x / 2.0, 0)]), col)
	draw_rect(Rect2(-4, -s.y * 0.85, 14, 5), Color("#0b1a20")) # Mask slit.
	_eye(Vector2(6, -s.y * 0.83), state in ["appear", "strike", "ghost"], 2.5)
	if state in ["appear", "strike"]:
		draw_line(Vector2(s.x * 0.3, -s.y * 0.5), Vector2(s.x / 2.0 + (30 if state == "strike" else 8), -s.y * 0.55), Color("#e6f7ff"), 3.0)
	if state == "ghost":
		draw_arc(Vector2(0, -s.y / 2.0), s.y * 0.7, 0.0, TAU, 24, Color(0.62, 0.9, 1.0, 0.8), 2.0)


func _draw_shellback(s: Vector2, _state: String, _st: float, t: float) -> void:
	var body := Rect2(-s.x / 2.0 + 6, -s.y, s.x - 12, s.y)
	draw_rect(body, Color("#5b4a6b"))
	# The soft, open top (the only weak spot): pulsing pink.
	var glow := 0.6 + 0.3 * sin(t * 4.0)
	draw_rect(Rect2(body.position + Vector2(2, -4), Vector2(body.size.x - 4, 8)), Color(1.0, 0.5, 0.6, glow))
	# Side plates on BOTH sides.
	for side: float in [-1.0, 1.0]:
		var x := side * (s.x / 2.0) - (6.0 if side > 0 else 0.0)
		draw_rect(Rect2(x, -s.y - 2, 6, s.y + 2), Color("#c0c8d8"))
		draw_rect(Rect2(x, -s.y - 2, 6, s.y + 2), Color("#5e6678"), false, 1.5)
	_eye(Vector2(s.x * 0.18, -s.y * 0.45), false, 2.5)


func _draw_urchin(s: Vector2, state: String, st: float, t: float) -> void:
	var c := Vector2(0, -s.y / 2.0)
	var swell := 1.0 + (minf(st / 0.55, 1.0) * 0.35 if state == "windup" else 0.0)
	var r := s.x * 0.38 * swell
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0 + t * 0.4)
		draw_line(c + d * r * 0.8, c + d * r * 1.6, Color("#ffd1dc") if state == "windup" else Color("#c23a5a"), 3.0)
	draw_circle(c, r, Color("#5b2a4a"))
	_eye(c + Vector2(4, -2), state == "windup")


func _draw_turret(s: Vector2, state: String, _st: float, _t: float) -> void:
	draw_rect(Rect2(-s.x / 2.0, -s.y * 0.55, s.x, s.y * 0.55), Color("#59606e"))
	var pivot := Vector2(0, -s.y * 0.55 - 6)
	draw_circle(pivot, s.x * 0.3, Color("#7a8394"))
	var turret := enemy as TurretEnemy
	var aim := Vector2(turret.aim_dir.x * enemy.facing, turret.aim_dir.y) if turret else Vector2.RIGHT
	draw_line(pivot, pivot + aim * 22.0, Color("#3b404b"), 7.0)
	if state == "aim": # The sight line: tracks, then locks.
		var locked := turret and enemy.state_time >= turret.aim_time - turret.lock_time
		draw_line(pivot + aim * 22.0, pivot + aim * 700.0, Color(1, 0.2, 0.3, 0.9 if locked else 0.4), 2.0 if locked else 1.0)
	_eye(pivot, state == "aim", 3.5)


func _draw_orb_sentry(s: Vector2, state: String, st: float, t: float) -> void:
	var c := Vector2(0, -s.y / 2.0)
	var hot := state == "windup"
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_circle(c + d * s.x * 0.55, 5.0 + (2.0 if hot else 0.0), Color("#d6b8ff") if hot else Color("#5d2aa8"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s.y * 0.45), c + Vector2(s.x * 0.45, 0), c + Vector2(0, s.y * 0.45),
		c + Vector2(-s.x * 0.45, 0)]), Color("#8a3df0"))
	draw_circle(c, 6.0 + (sin(st * 30.0) * 2.0 if hot else sin(t * 3.0)), Color("#f0e6ff"))


func _draw_hopper(s: Vector2, state: String, _st: float, _t: float) -> void:
	var sq := Vector2(1.25, 0.7) if state == "crouch" else (Vector2(0.85, 1.2) if state == "hop" else Vector2.ONE)
	var w := s.x * sq.x
	var h := s.y * sq.y
	draw_rect(Rect2(-w / 2.0, -h, w, h), Color("#7bc96f"))
	for side: float in [-1.0, 1.0]:
		draw_rect(Rect2(side * w / 2.0 - (4.0 if side > 0 else 0.0), -4, 4, 4), Color("#4f8f45")) # Feet.
	_eye(Vector2(w * 0.2, -h + 5), false, 2.5)


func _draw_crawler(s: Vector2, state: String, _st: float, t: float) -> void:
	var crawler := enemy as CrawlerEnemy
	var n := crawler.normal if crawler else Vector2.UP
	var center := Vector2(0, -s.y / 2.0)
	draw_set_transform(center, n.angle() + PI / 2.0)
	for i in 3: # Legs on the surface side.
		var x := -s.x * 0.35 + i * s.x * 0.35
		var wiggle := sin(t * 14.0 + i) * 3.0
		draw_line(Vector2(x, 2), Vector2(x + wiggle, s.y / 2.0), Color("#6b3a10"), 2.5)
	draw_colored_polygon(PackedVector2Array([Vector2(-s.x / 2.0, s.y * 0.3), Vector2(-s.x * 0.3, -s.y * 0.45), Vector2(s.x * 0.3, -s.y * 0.45),
		Vector2(s.x / 2.0, s.y * 0.3)]), Color("#b5651d"))
	draw_line(Vector2(-s.x * 0.3, -s.y * 0.1), Vector2(s.x * 0.3, -s.y * 0.1), Color("#7a4310"), 2.0)
	_eye(Vector2(0, s.y * 0.05), state == "fall", 2.5)
	draw_set_transform(Vector2.ZERO)


func _draw_phalanx(s: Vector2, state: String, _st: float, _t: float) -> void:
	draw_rect(Rect2(-s.x / 2.0, -s.y, s.x - 6, s.y), Color("#5a6b8c"))
	draw_rect(Rect2(-s.x / 2.0, -s.y - 6, s.x - 6, 10), Color("#9aa6bf")) # Helmet (the open top).
	_eye(Vector2(2, -s.y + 10), state == "windup", 2.5)
	# Spear: pulled back in the wind-up, thrust past the shield.
	var tip_x := s.x / 2.0 + (8.0 if state == "windup" else (58.0 if state == "thrust" else 26.0))
	draw_line(Vector2(-6, -s.y * 0.55), Vector2(tip_x, -s.y * 0.55), Color("#b08a5a"), 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(tip_x + 8, -s.y * 0.55), Vector2(tip_x, -s.y * 0.55 - 4), Vector2(tip_x, -s.y * 0.55 + 4)]), Color("#d8dde6"))
	# Tower shield on the front, nearly as tall as the body.
	var shield := Rect2(s.x / 2.0 - 8, -s.y - 2, 9, s.y + 2)
	draw_rect(shield, Color("#8c7a3a"))
	draw_rect(shield, Color("#e2c044"), false, 2.0)
