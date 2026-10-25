class_name MapOverlay
extends CanvasLayer
## The map quick view: shown in front of the player while the Map key is held
## (the player is in the "map_read" state, MapReadState). It never pauses the
## game: enemies keep moving and the player can be hit. A hit ends the state,
## which closes this overlay at once (Events.map_closed).

const PANEL_SIZE := Vector2(640, 330)

var game: Node
var backdrop: ColorRect
var view: MapView


func setup(p_game: Node) -> void:
	game = p_game
	layer = 6 # Above the HUD (5), below menus and popups.
	backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.35)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	view = MapView.new()
	view.name = "MapView"
	view.layout_direction = Control.LAYOUT_DIRECTION_LTR
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.anchor_left = 0.5
	view.anchor_right = 0.5
	view.anchor_top = 0.5
	view.anchor_bottom = 0.5
	view.offset_left = -PANEL_SIZE.x / 2.0
	view.offset_right = PANEL_SIZE.x / 2.0
	view.offset_top = -PANEL_SIZE.y / 2.0
	view.offset_bottom = PANEL_SIZE.y / 2.0
	backdrop.add_child(view)
	view.setup(game)
	visible = false
	Events.map_opened.connect(_open)
	Events.map_closed.connect(func(_reason: String) -> void: visible = false)


func is_open() -> bool:
	return visible


func _open() -> void:
	view.follow_player() # The quick view always shows where the player is.
	visible = true


func _process(_delta: float) -> void:
	# Safety net: the overlay never outlives the quick view state.
	if visible and not game.player.is_reading_map():
		visible = false
