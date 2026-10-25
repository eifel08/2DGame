class_name MapExit
extends Resource
## One opening of a room, as the map sees it. It mirrors a Door in the room
## scene (same door_id, target_room, target_door); the smoke test checks that
## every Door has exactly one MapExit and the other way round.
##
## `side` and `at` place the connector stub on the room's outline: `at` is the
## cell along that side (from the top for left / right, from the left for
## top / bottom), counted inside the room's map rect.
##
## `suppressed` is not authored: MapAtlas.resolve_anomalies() sets it on both
## ends of a connection that cannot be drawn on a flat map (see MapAtlas).

const SIDES: Array[String] = ["left", "right", "top", "bottom"]

@export var door_id := ""
@export_enum("left", "right", "top", "bottom") var side := "right"
@export var at := 0
@export var target_room := ""
@export var target_door := ""
## A secret way (breakable wall, secret doorway). The map never gives it away:
## its connector is drawn only once both rooms are filled in.
@export var secret := false

## Set by MapAtlas.resolve_anomalies(): the map hides this connection, and
## (Config.map.seal_anomaly_entrances) the game seals its doorway in the room.
var suppressed := false


static func from_dict(data: Dictionary) -> MapExit:
	var e := MapExit.new()
	e.door_id = data.get("door", "")
	e.side = data.get("side", "right")
	e.at = int(data.get("at", 0))
	e.target_room = data.get("to", "")
	e.target_door = data.get("to_door", "")
	e.secret = bool(data.get("secret", false))
	assert(e.side in SIDES, "MapExit: unknown side '%s'" % e.side)
	return e


func is_horizontal() -> bool:
	return side == "left" or side == "right"
