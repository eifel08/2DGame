class_name ArenaEncounter
extends Node2D
## Data + gates for an arena encounter. Children: "Waves" with one Node2D per
## wave, each holding Marker2D spawn points (meta "kind": weak / flyer /
## strong / boss). Edit waves by moving or adding markers in the editor.
## The logic (start, waves, clear) lives in core/arena_director.gd.
## No autoloads here (the generator builds this node).

@export var arena_id := ""
@export var trigger_rect := Rect2() ## Local rect: entering it starts the encounter.
@export var gate_rects: Array[Rect2] = [] ## Local rects sealed while the encounter runs.

var gates_closed := false
var _gate_bodies: Array[StaticBody2D] = []


func get_trigger_rect() -> Rect2:
	return Rect2(to_global(trigger_rect.position), trigger_rect.size)


func wave_count() -> int:
	var waves := get_node_or_null("Waves")
	return waves.get_child_count() if waves else 0


## [{position, kind}, ...] for wave `index`.
func wave_spawns(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker in get_node("Waves").get_child(index).get_children():
		result.append({"position": marker.global_position, "kind": marker.get_meta("kind", "weak")})
	return result


## Closed gates are solid (world collision layer) and drawn as bars.
func set_gates(closed: bool) -> void:
	gates_closed = closed
	for body in _gate_bodies:
		body.queue_free()
	_gate_bodies.clear()
	if closed:
		for r in gate_rects:
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = r.size
			shape.shape = rect
			shape.position = r.get_center()
			body.add_child(shape)
			add_child(body)
			_gate_bodies.append(body)
	queue_redraw()


func _draw() -> void:
	if not gates_closed:
		return
	for r in gate_rects:
		draw_rect(r, Color(0.08, 0.09, 0.16, 0.95))
		for i in 4:
			var x := r.position.x + 4.0 + i * (r.size.x - 8.0) / 3.0
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("#b9c2e6"), 2.0)
