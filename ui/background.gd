extends Control
## Far background: a dark gradient sky with two faint parallax layers of
## distant arches. Kept low-contrast with soft, fading tops so nothing back
## here can be mistaken for a floor or wall you could stand on.

const LAYERS := [
	{"factor": 0.15, "color": Color(0.08, 0.1, 0.2, 0.55), "spacing": 260.0, "height": 230.0},
	{"factor": 0.35, "color": Color(0.1, 0.12, 0.24, 0.45), "spacing": 170.0, "height": 150.0},
]

var camera: Camera2D


func setup(p_camera: Camera2D) -> void:
	camera = p_camera


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var view := size
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(view.x, 0), view, Vector2(0, view.y)]),
		PackedColorArray([Color("#090b1a"), Color("#090b1a"), Color("#141029"), Color("#141029")]))
	if camera == null:
		return
	var cam := camera.global_position - view / 2.0
	for layer in LAYERS:
		var spacing: float = layer.spacing
		var col: Color = layer.color
		var offset := -fmod(cam.x * layer.factor, spacing)
		var base_y: float = view.y - cam.y * layer.factor * 0.3 + 120.0
		var x := offset - spacing
		while x < view.x + spacing:
			# Arch silhouette whose top fades out (no flat, solid-looking ledge).
			var w := spacing * 0.42
			var top: float = base_y - layer.height
			draw_polygon(
				PackedVector2Array([Vector2(x, top + 40.0), Vector2(x + w, top + 40.0), Vector2(x + w, base_y + 400.0), Vector2(x, base_y + 400.0)]),
				PackedColorArray([Color(col, 0.0), Color(col, 0.0), col, col]))
			draw_arc(Vector2(x + w / 2.0, top + 40.0), w / 2.0, PI, TAU, 16, Color(col, col.a * 0.35), 2.0, true)
			x += spacing
