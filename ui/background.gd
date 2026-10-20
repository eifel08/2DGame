extends Control
## Gradient sky plus two parallax layers of silhouettes, drawn behind the world.

const LAYERS := [
	{"factor": 0.2, "color": Color("#151a36"), "spacing": 220.0, "height": 260.0},
	{"factor": 0.45, "color": Color("#1a2142"), "spacing": 140.0, "height": 170.0},
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
		PackedColorArray([Color("#0d1024"), Color("#0d1024"), Color("#1b1532"), Color("#1b1532")]))
	if camera == null:
		return
	var cam := camera.global_position - view / 2.0
	for layer in LAYERS:
		var spacing: float = layer.spacing
		var offset := -fmod(cam.x * layer.factor, spacing)
		var base_y: float = view.y - cam.y * layer.factor * 0.3
		var x := offset - spacing
		while x < view.x + spacing:
			draw_rect(Rect2(x, base_y - layer.height, spacing * 0.45, layer.height + 400.0), layer.color)
			x += spacing
