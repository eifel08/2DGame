class_name Effects
extends Node2D
## Purely visual effects. Nothing here affects gameplay.
##
## Every effect is a scene in effects/fx/<name>.tscn (root: FxPlayer) and is
## started by name:  effects.play("hit_spark", position)
## Options: "rotation" (radians), "scale" (float), "tint" (Color, multiplies
## the effect's colors). To change how an effect looks, edit or replace its
## scene; to add one, add a scene (tools/build_assets.gd makes placeholders).
## The debug damage numbers are drawn here directly (debug view only).

const FX_DIR := "res://effects/fx/"

var texts: Array[Dictionary] = []
var play_counts := {} ## fx name -> times played (tests, debugging)
var fx_root: Node2D
var _scenes := {}


func _ready() -> void:
	fx_root = Node2D.new()
	fx_root.name = "Fx"
	add_child(fx_root)


func play(fx_name: String, pos: Vector2, opts := {}) -> FxPlayer:
	play_counts[fx_name] = play_counts.get(fx_name, 0) + 1
	var scene: PackedScene = _scenes.get(fx_name)
	if scene == null:
		var path := FX_DIR + fx_name + ".tscn"
		if not ResourceLoader.exists(path):
			push_warning("Effects: no effect scene " + path)
			return null
		scene = load(path)
		_scenes[fx_name] = scene
	var fx := scene.instantiate() as FxPlayer
	fx.position = pos
	fx.rotation = opts.get("rotation", 0.0)
	if opts.has("scale"):
		fx.scale = Vector2.ONE * float(opts.scale)
	if opts.has("tint"):
		fx.modulate = opts.tint
	fx_root.add_child(fx)
	return fx


func count(fx_name: String) -> int:
	return play_counts.get(fx_name, 0)


func active_count() -> int:
	return fx_root.get_child_count()


## Freezes running effects while the game is paused (menus, hitstop).
func set_paused(paused: bool) -> void:
	fx_root.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT


func clear() -> void:
	texts.clear()
	for fx in fx_root.get_children():
		fx.queue_free()


func float_text(pos: Vector2, text: String, color := Color.WHITE) -> void:
	texts.append({"pos": pos + Vector2(randf_range(-6, 6), 0), "text": text, "color": color, "life": 0.7, "max_life": 0.7})


func step(delta: float) -> void:
	for t in texts:
		t.life -= delta
		t.pos.y -= 40.0 * delta
	texts = texts.filter(func(e: Dictionary) -> bool: return e.life > 0.0)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for t in texts:
		var a: float = maxf(0.0, t.life / t.max_life)
		var pos: Vector2 = t.pos - Vector2(40, 0)
		draw_string(font, pos + Vector2(1, 1), t.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(0, 0, 0, a))
		draw_string(font, pos, t.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(t.color, a))
