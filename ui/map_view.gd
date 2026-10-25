class_name MapView
extends Control
## Draws one zone map with its fog of war (MapState). Used by the quick view
## (ui/map_overlay.gd) and by the inventory's Map tab.
##
##   UNKNOWN room   nothing
##   OUTLINED room  a wireframe (the base map shows it, not explored yet)
##   FILLED room    filled in (explored)
##   connector      a short stub on the outline where a room has an exit. A
##                  secret exit shows only once both rooms are filled in; a
##                  suppressed exit (spatial anomaly) never shows. An exit into
##                  another zone is drawn as an arrow leaving the map.
##   player marker  Config.map.show_player_marker; placed where the player
##                  stands inside the room (Config.map.precise_player_marker)
##                  or at the room's center.
##
## `zone_id` empty: the zone of the room the player is in. In the inventory,
## Left / Right switch between the zones the player knows (cycle_zone).
## Placeholder art: everything is drawn here; restyle the COLORS freely.

const COLORS := {
	"background": Color(0.03, 0.04, 0.08, 0.92),
	"frame": Color("#6f7fb8"),
	"outline": Color(0.55, 0.62, 0.85, 0.75),
	"fill": Color(0.24, 0.3, 0.52, 0.95),
	"fill_edge": Color(0.75, 0.82, 1.0, 1.0),
	"current": Color(0.34, 0.42, 0.7, 1.0),
	"connector": Color(0.9, 0.93, 1.0, 0.9),
	"marker": Color("#ffd36b"),
	"title": Color("#ffd43b"),
	"hint": Color(1, 1, 1, 0.5),
}
const MAX_CELL := 56.0
const MARGIN := 18.0
const TITLE_HEIGHT := 26.0

var game: Node
var zone_id := ""


func setup(p_game: Node) -> void:
	game = p_game
	Events.map_room_revealed.connect(func(_id: String, _reveal: int) -> void: queue_redraw())
	Events.map_acquired.connect(func(_id: String) -> void: queue_redraw())
	Events.room_entered.connect(func(_id: String) -> void: queue_redraw())


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw() # The player marker moves.


## The zone drawn now (`zone_id`, or the player's current zone).
func shown_zone() -> MapZone:
	if game == null:
		return null
	if zone_id != "":
		return game.atlas.get_zone(zone_id)
	return game.map_state.current_zone()


## Switches to the next / previous zone the player knows. Returns the zone_id.
func cycle_zone(step: int) -> String:
	var known: Array[String] = game.map_state.known_zones()
	var shown := shown_zone()
	if shown and not known.has(shown.zone_id):
		known.append(shown.zone_id)
	if known.is_empty():
		return ""
	var i := known.find(shown.zone_id) if shown else -1
	zone_id = known[posmod(i + step, known.size())]
	queue_redraw()
	return zone_id


## Back to following the player's zone.
func follow_player() -> void:
	zone_id = ""
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		cycle_zone(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right"):
		cycle_zone(1)
		accept_event()


# ---------- Layout ----------

## Pixels per map cell and the top-left of cell (0, 0), fitted to the size.
func _layout(zone: MapZone) -> Dictionary:
	var bounds := zone.get_cell_bounds()
	var avail := size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + TITLE_HEIGHT)
	var cell := minf(MAX_CELL, minf(avail.x / maxf(bounds.size.x, 1), avail.y / maxf(bounds.size.y, 1)))
	var used := Vector2(bounds.size) * cell
	var origin := Vector2(MARGIN, MARGIN + TITLE_HEIGHT) + (avail - used) / 2.0 - Vector2(bounds.position) * cell
	return {"cell": cell, "origin": origin}


func room_rect(r: MapRoom, layout: Dictionary) -> Rect2:
	var origin: Vector2 = layout.origin
	var cell: float = layout.cell
	return Rect2(origin + Vector2(r.rect.position) * cell, Vector2(r.rect.size) * cell)


## Where the player marker is drawn (local coordinates), or Vector2.INF when
## it is not shown (switched off, another zone on screen, a room on no map).
func marker_position() -> Vector2:
	if game == null or not Config.map.show_player_marker:
		return Vector2.INF
	var zone := shown_zone()
	var state: MapState = game.map_state
	if zone == null or not zone.has_room(state.current_room):
		return Vector2.INF
	var rect := room_rect(zone.get_room(state.current_room), _layout(zone))
	if not Config.map.precise_player_marker or game.room == null:
		return rect.get_center()
	var bounds: Rect2 = game.room.get_bounds()
	var at: Vector2 = game.player.get_center()
	var frac := ((at - bounds.position) / bounds.size).clamp(Vector2.ZERO, Vector2.ONE)
	# Keep the marker a little inside the outline.
	var inner := rect.grow(-minf(4.0, rect.size.x * 0.2))
	return inner.position + frac * inner.size


## True when the connector of `e` (an exit of `r`) is drawn.
func connector_visible(r: MapRoom, e: MapExit) -> bool:
	var state: MapState = game.map_state
	if e.suppressed or state.reveal_of(r.room_id) == MapState.Reveal.UNKNOWN:
		return false
	if e.secret:
		return state.is_filled(r.room_id) and state.is_filled(e.target_room)
	return true


# ---------- Drawing ----------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.background)
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.frame, false, 2.0)
	var font := ThemeDB.fallback_font
	var zone := shown_zone()
	if zone == null:
		draw_string(font, Vector2(MARGIN, MARGIN + 14), "No map of this place.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLORS.hint)
		return
	var state: MapState = game.map_state
	var title := zone.display_name
	if game.map_state.known_zones().size() > 1:
		title = "<  %s  >" % title
	draw_string(font, Vector2(MARGIN, MARGIN + 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLORS.title)
	if not state.has_map(zone.zone_id):
		draw_string(font, Vector2(MARGIN, MARGIN + 14), "No map found yet", HORIZONTAL_ALIGNMENT_RIGHT, size.x - MARGIN * 2.0, 12, COLORS.hint)

	var layout := _layout(zone)
	var cell: float = layout.cell
	for r in zone.rooms:
		var reveal := state.reveal_of(r.room_id)
		if reveal == MapState.Reveal.UNKNOWN:
			continue
		var rect := room_rect(r, layout).grow(-2.0)
		if reveal == MapState.Reveal.FILLED:
			draw_rect(rect, COLORS.current if r.room_id == state.current_room else COLORS.fill)
			draw_rect(rect, COLORS.fill_edge, false, 2.0)
		else:
			_draw_wireframe(rect)
	for r in zone.rooms:
		for e in r.exits:
			if connector_visible(r, e):
				_draw_connector(r, e, layout, zone)

	var marker := marker_position()
	if marker != Vector2.INF:
		var radius := clampf(cell * 0.12, 3.0, 6.0)
		draw_circle(marker, radius + 1.5, Color(0, 0, 0, 0.8))
		draw_circle(marker, radius, COLORS.marker)


## Outline only, with corner ticks, so it reads as "known, not explored".
func _draw_wireframe(rect: Rect2) -> void:
	draw_rect(rect, COLORS.outline, false, 1.5)
	var tick := minf(6.0, rect.size.x * 0.25)
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		var sx := 1.0 if corner.x == rect.position.x else -1.0
		var sy := 1.0 if corner.y == rect.position.y else -1.0
		draw_line(corner, corner + Vector2(tick * sx, 0), COLORS.fill_edge, 2.0)
		draw_line(corner, corner + Vector2(0, tick * sy), COLORS.fill_edge, 2.0)


func _draw_connector(r: MapRoom, e: MapExit, layout: Dictionary, zone: MapZone) -> void:
	var cell: float = layout.cell
	var origin: Vector2 = layout.origin
	var c: Vector2 = origin + (Vector2(r.exit_cell(e)) + Vector2(0.5, 0.5)) * cell
	var half := cell * 0.5
	var dir: Vector2 = {"left": Vector2.LEFT, "right": Vector2.RIGHT, "top": Vector2.UP, "bottom": Vector2.DOWN}[e.side]
	var edge: Vector2 = c + dir * half
	var across := Vector2(-dir.y, dir.x) * minf(5.0, cell * 0.16)
	var leaves_zone := not zone.has_room(e.target_room)
	if leaves_zone:
		var tip: Vector2 = edge + dir * minf(10.0, cell * 0.3)
		draw_line(edge - dir * 3.0, tip, COLORS.connector, 2.0)
		draw_line(tip, tip - dir * 4.0 + across, COLORS.connector, 2.0)
		draw_line(tip, tip - dir * 4.0 - across, COLORS.connector, 2.0)
	else:
		draw_line(edge - dir * 3.0 + across, edge - dir * 3.0 - across, COLORS.connector, 2.0)
		draw_line(edge - dir * 3.0, edge + dir * 3.0, COLORS.connector, 3.0)
