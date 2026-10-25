class_name MapView
extends Control
## Draws the zone maps with their fog of war (MapState). Used by the quick
## view (ui/map_overlay.gd) and by the inventory's Map tab.
##
## Everything is drawn on one world grid (MapZone.world_origin places each
## zone), seen through a small camera: `center` (world cells) and `zoom` (px
## per cell). The camera eases toward its target every frame, so moving to
## another zone or zooming in / out is a smooth, continuous pan, never a cut.
##
## Two modes:
##   ZONE   one zone fills the view (quick view: always the player's zone)
##   WORLD  the whole world from above: every zone the player has been in,
##          as a frame in the zone's colour; the selected one is highlighted
##
## Inventory controls (the view has the focus, `interactive`):
##   arrows      WORLD: select the zone that way. ZONE: pan to the adjacent
##               zone that way. Nothing that way: Up returns to the tab row.
##   Enter       WORLD: zoom into the selected zone. ZONE: back to the world.
##   Backspace   ZONE: back to the world view.
##
## Fog of war: only zones whose map is owned show rooms (visible_reveal).
##   OUTLINED room  a wireframe (on the base map, not explored yet)
##   FILLED room    filled in (explored)
##   connector      a stub on the outline where a room has an exit. A secret
##                  exit shows only once both rooms are filled in; a
##                  suppressed exit (spatial anomaly) never shows. An exit into
##                  a zone whose map is not owned is drawn as an arrow.
##   player marker  Config.map.show_player_marker (precise_player_marker: where
##                  the player stands in the room, else the room's center).
## A zone without its map shows no room at all, only "No Map".
## Each zone has its own colour (MapZone.color); the palette comes from it.
## Placeholder art: everything is drawn here; restyle COLORS and _palette.

enum Mode { ZONE, WORLD }

const COLORS := {
	"background": Color(0.03, 0.04, 0.08, 0.92),
	"frame": Color("#6f7fb8"),
	"connector": Color(0.92, 0.94, 1.0, 0.9),
	"marker": Color("#ffd36b"),
	"title": Color("#ffd43b"),
	"hint": Color(1, 1, 1, 0.55),
	"selected": Color("#ffd36b"),
}
const MAX_CELL := 56.0
const MARGIN := 18.0
const TITLE_HEIGHT := 26.0
const PAN_RATE := 7.0 ## Camera easing rate (1/s): higher is snappier.
const WORLD_MARGIN := 1.0 ## Cells of air around the world view.
const ZONE_MARGIN := 0.5 ## Cells of air around a zone view.
const DIRECTIONS := {&"ui_up": Vector2.UP, &"ui_down": Vector2.DOWN, &"ui_left": Vector2.LEFT, &"ui_right": Vector2.RIGHT}

var game: Node
var mode := Mode.ZONE
## ZONE: the zone shown ("" = the player's zone). WORLD: the selected zone.
var zone_id := ""
var interactive := false ## The inventory tab: arrows, Enter and Backspace work.
var center := Vector2.ZERO ## Camera position, world cells.
var zoom := 40.0 ## Camera scale, px per world cell.
var _snap := true ## Jump straight to the target on the next frame.


func setup(p_game: Node) -> void:
	game = p_game
	clip_contents = true # Zones panned past the edge are cut off at the frame.
	Events.map_room_revealed.connect(func(_id: String, _reveal: int) -> void: queue_redraw())
	Events.map_acquired.connect(func(_id: String) -> void: queue_redraw())
	Events.room_entered.connect(func(_id: String) -> void: queue_redraw())


func _process(delta: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	step_camera(delta)
	queue_redraw() # The player marker moves.


## Eases the camera toward its target (or jumps there after a snap request).
func step_camera(delta: float) -> void:
	var target := camera_target()
	if _snap:
		center = target.center
		zoom = target.zoom
		_snap = false
		return
	var k := 1.0 - exp(-PAN_RATE * delta)
	center = center.lerp(target.center, k)
	zoom = lerpf(zoom, target.zoom, k)


# ---------- Mode and navigation ----------

## The zone in focus: the shown zone (ZONE) or the selected one (WORLD).
func shown_zone() -> MapZone:
	if game == null:
		return null
	if zone_id != "":
		return game.atlas.get_zone(zone_id)
	return game.map_state.current_zone()


## Quick view: the player's zone, no easing in from elsewhere.
func follow_player() -> void:
	mode = Mode.ZONE
	zone_id = ""
	_snap = true
	queue_redraw()


## The world from above, with the player's zone selected. `snap`: no easing.
func show_world(snap := false) -> void:
	mode = Mode.WORLD
	var listed := listed_zones()
	var here := game.map_state.current_zone() as MapZone
	if here and listed.has(here.zone_id):
		zone_id = here.zone_id
	elif zone_id == "" or not listed.has(zone_id):
		zone_id = listed[0] if not listed.is_empty() else ""
	_snap = snap
	queue_redraw()


## Zooms into `id` (smoothly from where the camera is).
func focus_zone(id: String) -> void:
	mode = Mode.ZONE
	zone_id = id
	queue_redraw()


## Zones the view can select or pan to: the player has been there (map or
## not) or owns its map. In atlas order.
func listed_zones() -> Array[String]:
	var ids: Array[String] = []
	var state: MapState = game.map_state
	for id in game.atlas.zone_ids():
		if state.has_map(id) or state.is_zone_visited(id):
			ids.append(id)
	return ids


## The nearest listed zone from `from_id` in direction `dir` (world grid,
## within 60 degrees of it), or "".
func neighbour_zone(from_id: String, dir: Vector2) -> String:
	var from := game.atlas.get_zone(from_id) as MapZone
	if from == null:
		return ""
	var origin := zone_box(from).get_center()
	var best := ""
	var best_d := INF
	for id in listed_zones():
		if id == from_id:
			continue
		var c := zone_box(game.atlas.get_zone(id)).get_center()
		var to := c - origin
		if to.length() < 0.01 or to.normalized().dot(dir) < 0.5:
			continue
		if to.length() < best_d:
			best_d = to.length()
			best = id
	return best


## Arrow input: select (WORLD) or pan to (ZONE) the zone that way. Returns
## false when there is none.
func move(dir: Vector2) -> bool:
	var from := shown_zone()
	if from == null:
		return false
	var next := neighbour_zone(from.zone_id, dir)
	if next == "":
		return false
	zone_id = next
	queue_redraw()
	return true


## Enter: zoom in (WORLD) or out (ZONE).
func toggle_zoom() -> void:
	if mode == Mode.WORLD:
		if zone_id != "":
			focus_zone(zone_id)
	else:
		var keep := shown_zone()
		show_world()
		if keep:
			zone_id = keep.zone_id # Keep the zone you were looking at selected.


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	for action in DIRECTIONS:
		if event.is_action_pressed(action):
			if move(DIRECTIONS[action]):
				accept_event()
			return # Nothing that way: normal focus moves (Up: the tab row).
	if event.is_action_pressed(&"ui_accept"):
		toggle_zoom()
		accept_event()
	elif event.is_action_pressed(&"menu_clear") and mode == Mode.ZONE:
		toggle_zoom()
		accept_event()


# ---------- Camera ----------

func _view_rect() -> Rect2:
	return Rect2(Vector2(MARGIN, MARGIN + TITLE_HEIGHT), size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + TITLE_HEIGHT))


## Where the camera is heading: {center, zoom}.
func camera_target() -> Dictionary:
	var bounds := Rect2()
	if mode == Mode.WORLD:
		for id in listed_zones():
			var b := zone_box(game.atlas.get_zone(id))
			bounds = b if not bounds.has_area() else bounds.merge(b)
		bounds = bounds.grow(WORLD_MARGIN)
	else:
		var zone := shown_zone()
		if zone:
			bounds = zone_box(zone).grow(ZONE_MARGIN)
	if not bounds.has_area():
		return {"center": center, "zoom": zoom}
	var avail := _view_rect().size
	var fit := minf(MAX_CELL, minf(avail.x / bounds.size.x, avail.y / bounds.size.y))
	return {"center": bounds.get_center(), "zoom": fit}


## The part of a zone the player may see, world cells: with its map, the rooms
## the map shows (so the frame never gives away an undiscovered room);
## without it, the whole zone (shown only as an empty "No Map" frame).
func zone_box(zone: MapZone) -> Rect2:
	var state: MapState = game.map_state
	if not state.has_map(zone.zone_id):
		return Rect2(zone.get_world_bounds())
	var box := Rect2()
	for r in zone.rooms:
		if state.visible_reveal(r.room_id) != MapState.Reveal.UNKNOWN:
			var rect := Rect2(zone.world_rect(r))
			box = rect if not box.has_area() else box.merge(rect)
	return box if box.has_area() else Rect2(zone.get_world_bounds())


## World cells -> local pixels.
func to_screen(world: Vector2) -> Vector2:
	return _view_rect().get_center() + (world - center) * zoom


func world_to_screen_rect(r: Rect2) -> Rect2:
	return Rect2(to_screen(r.position), r.size * zoom)


## A room's rect in local pixels.
func room_screen_rect(r: MapRoom) -> Rect2:
	return world_to_screen_rect(Rect2(game.atlas.world_rect(r)))


## Where the player marker is drawn (local coordinates), or Vector2.INF when
## it is not shown (switched off, no map of the zone, a room on no map).
func marker_position() -> Vector2:
	if game == null or not Config.map.show_player_marker:
		return Vector2.INF
	var state: MapState = game.map_state
	var r := game.atlas.get_room(state.current_room) as MapRoom
	if r == null or not state.has_current_map():
		return Vector2.INF
	var rect := room_screen_rect(r)
	if not Config.map.precise_player_marker or game.room == null:
		return rect.get_center()
	var bounds: Rect2 = game.room.get_bounds()
	var at: Vector2 = game.player.get_center()
	var frac := ((at - bounds.position) / bounds.size).clamp(Vector2.ZERO, Vector2.ONE)
	var inner := rect.grow(-minf(4.0, rect.size.x * 0.2)) # A little inside the outline.
	return inner.position + frac * inner.size


## True when the connector of `e` (an exit of `r`) is drawn.
func connector_visible(r: MapRoom, e: MapExit) -> bool:
	var state: MapState = game.map_state
	if e.suppressed or state.visible_reveal(r.room_id) == MapState.Reveal.UNKNOWN:
		return false
	if e.secret:
		return state.is_filled(r.room_id) and state.is_filled(e.target_room)
	return true


## The zone's colours: fill (explored), current (the player's room), edge,
## outline (wireframe) and frame (world view).
static func palette(zone: MapZone) -> Dictionary:
	var c := zone.color
	return {
		"fill": Color(c.darkened(0.45), 0.95),
		"current": c,
		"edge": c.lightened(0.45),
		"outline": Color(c.lightened(0.2), 0.75),
		"frame": Color(c, 0.55),
		"tint": Color(c, 0.08),
	}


# ---------- Drawing ----------

func _draw() -> void:
	if size.x < MARGIN * 4.0 or size.y < MARGIN * 2.0 + TITLE_HEIGHT * 2.0:
		return # Not laid out yet.
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.background)
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.frame, false, 2.0)
	if game == null:
		return
	var font := ThemeDB.fallback_font
	var focus := shown_zone()
	var state: MapState = game.map_state

	# Clip to the view: zones around the focused one show at the edges while
	# panning, so moving between zones reads as one continuous world.
	var view := _view_rect()
	for zone in game.atlas.zones:
		if mode == Mode.WORLD and not listed_zones().has(zone.zone_id):
			continue
		var frame := world_to_screen_rect(zone_box(zone))
		if not frame.intersects(view):
			continue
		var pal := palette(zone)
		if mode == Mode.WORLD:
			draw_rect(frame, pal.tint)
			var selected: bool = focus != null and zone.zone_id == focus.zone_id
			draw_rect(frame, COLORS.selected if selected else pal.frame, false, 3.0 if selected else 1.5)
			draw_string(font, _label_spot(zone, frame, font), zone.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				COLORS.selected if selected else pal.edge)
		if not state.has_map(zone.zone_id):
			# No map: not a single room, only the notice.
			if mode == Mode.WORLD or (focus and focus.zone_id == zone.zone_id):
				draw_string(font, Vector2(frame.position.x, frame.get_center().y + 6), "No Map", HORIZONTAL_ALIGNMENT_CENTER,
					frame.size.x, 16, COLORS.hint)
			continue
		_draw_zone_rooms(zone, pal)

	var marker := marker_position()
	if marker != Vector2.INF:
		var radius := clampf(zoom * 0.12, 2.5, 6.0)
		draw_circle(marker, radius + 1.5, Color(0, 0, 0, 0.8))
		draw_circle(marker, radius, COLORS.marker)

	# Title strip (drawn last, over anything panned under it).
	draw_rect(Rect2(Vector2(2, 2), Vector2(size.x - 4, MARGIN + TITLE_HEIGHT - 6)), COLORS.background)
	var title: String = "World Map" if mode == Mode.WORLD else (focus.display_name if focus else "No Map")
	draw_string(font, Vector2(MARGIN, MARGIN + 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		COLORS.title if focus == null or mode == Mode.WORLD else palette(focus).edge.lightened(0.3))
	if mode == Mode.WORLD and focus:
		draw_string(font, Vector2(MARGIN, MARGIN + 14), focus.display_name, HORIZONTAL_ALIGNMENT_RIGHT, size.x - MARGIN * 2.0, 13, COLORS.selected)


## Where a zone's name goes in the world view: just above its frame, else
## just below, else inside, whichever does not run into another zone.
func _label_spot(zone: MapZone, frame: Rect2, font: Font) -> Vector2:
	var w := font.get_string_size(zone.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var spots := [frame.position + Vector2(2, -5), Vector2(frame.position.x + 2, frame.end.y + 15), frame.position + Vector2(6, 15)]
	for spot: Vector2 in spots:
		var label := Rect2(spot - Vector2(0, 12), Vector2(w, 14))
		var clear := _view_rect().grow(MARGIN).encloses(label)
		for id in listed_zones():
			if id != zone.zone_id and world_to_screen_rect(zone_box(game.atlas.get_zone(id))).intersects(label):
				clear = false
		if clear:
			return spot
	return spots[spots.size() - 1]


func _draw_zone_rooms(zone: MapZone, pal: Dictionary) -> void:
	var state: MapState = game.map_state
	for r in zone.rooms:
		var reveal := state.visible_reveal(r.room_id)
		if reveal == MapState.Reveal.UNKNOWN:
			continue
		var rect := room_screen_rect(r).grow(-minf(2.0, zoom * 0.05)).abs()
		if reveal == MapState.Reveal.FILLED:
			draw_rect(rect, pal.current if r.room_id == state.current_room else pal.fill)
			draw_rect(rect, pal.edge, false, 2.0)
		else:
			_draw_wireframe(rect, pal)
	for r in zone.rooms:
		for e in r.exits:
			if connector_visible(r, e):
				_draw_connector(r, e)


## Outline only, with corner ticks, so it reads as "known, not explored".
func _draw_wireframe(rect: Rect2, pal: Dictionary) -> void:
	draw_rect(rect, pal.outline, false, 1.5)
	var tick := minf(6.0, rect.size.x * 0.25)
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		var sx := 1.0 if corner.x == rect.position.x else -1.0
		var sy := 1.0 if corner.y == rect.position.y else -1.0
		draw_line(corner, corner + Vector2(tick * sx, 0), pal.edge, 2.0)
		draw_line(corner, corner + Vector2(0, tick * sy), pal.edge, 2.0)


func _draw_connector(r: MapRoom, e: MapExit) -> void:
	var cell_center := Vector2(game.atlas.zone_of(r.room_id).world_origin + r.exit_cell(e)) + Vector2(0.5, 0.5)
	var c := to_screen(cell_center)
	var dir: Vector2 = {"left": Vector2.LEFT, "right": Vector2.RIGHT, "top": Vector2.UP, "bottom": Vector2.DOWN}[e.side]
	var edge: Vector2 = c + dir * zoom * 0.5
	var across := Vector2(-dir.y, dir.x) * minf(5.0, zoom * 0.16)
	var target_zone := game.atlas.zone_of(e.target_room) as MapZone
	if target_zone and not game.map_state.has_map(target_zone.zone_id):
		# Into a zone whose map is not owned: an arrow leaving the map.
		var tip: Vector2 = edge + dir * minf(10.0, zoom * 0.3)
		draw_line(edge - dir * 3.0, tip, COLORS.connector, 2.0)
		draw_line(tip, tip - dir * 4.0 + across, COLORS.connector, 2.0)
		draw_line(tip, tip - dir * 4.0 - across, COLORS.connector, 2.0)
	else:
		draw_line(edge - dir * 3.0 + across, edge - dir * 3.0 - across, COLORS.connector, 2.0)
		draw_line(edge - dir * 3.0, edge + dir * 3.0, COLORS.connector, 3.0)
