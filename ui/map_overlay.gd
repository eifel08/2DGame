class_name MapOverlay
extends CanvasLayer
## The map quick view: shown in front of the player while the Map key is held
## (the player is in the "map_read" state, MapReadState). It never pauses the
## game: enemies keep moving and the player can be hit. A hit ends the state,
## which closes this overlay at once (Events.map_closed).
##
## Without the map of the current zone the quick view does not open: the Map
## key shows a short "No Map" notice instead (Events.map_denied). It is a
## plain answer to the key press, not a pop-up for an event (Rule F).

const PANEL_SIZE := Vector2(640, 330)
const NOTICE_TIME := 1.4 ## How long "No Map" stays (s); it fades out over the last part.
const NOTICE_TEXT := "No Map"

var game: Node
var backdrop: ColorRect
var view: MapView
var notice: Label
var notice_timer := 0.0


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
	backdrop.visible = false

	notice = Label.new()
	notice.name = "NoMapNotice"
	notice.text = NOTICE_TEXT
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 22)
	notice.add_theme_color_override("font_color", Color("#ffe9b0"))
	notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	notice.add_theme_constant_override("outline_size", 6)
	notice.anchor_left = 0.5
	notice.anchor_right = 0.5
	notice.anchor_top = 0.5
	notice.anchor_bottom = 0.5
	notice.offset_left = -120.0
	notice.offset_right = 120.0
	notice.offset_top = -110.0 # Above the player, who stands mid-screen.
	notice.offset_bottom = -70.0
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.visible = false
	add_child(notice)

	Events.map_opened.connect(_open)
	Events.map_closed.connect(func(_reason: String) -> void: backdrop.visible = false)
	Events.map_denied.connect(show_no_map)


func is_open() -> bool:
	return backdrop.visible


func is_notice_shown() -> bool:
	return notice.visible


func _open() -> void:
	notice_timer = 0.0
	notice.visible = false
	view.follow_player() # The quick view always shows where the player is.
	backdrop.visible = true


## "No Map": the Map key was pressed in a zone whose map is not owned.
func show_no_map() -> void:
	notice_timer = NOTICE_TIME
	notice.modulate.a = 1.0
	notice.visible = true


func _process(delta: float) -> void:
	# Safety net: the overlay never outlives the quick view state.
	if backdrop.visible and not game.player.is_reading_map():
		backdrop.visible = false
	if notice_timer > 0.0:
		notice_timer -= delta
		notice.modulate.a = clampf(notice_timer / 0.4, 0.0, 1.0)
		if notice_timer <= 0.0:
			notice.visible = false
