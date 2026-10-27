class_name GearPickup
extends Collectible
## A pouch or a tool lying in the world. Taking it (E) adds it to the gear
## the player owns (GearManager.grant_pouch / grant_tool); it is equipped at
## the saved checkpoint (Inventory, Gear tab). A pickup is gone once its
## pouch or tool is owned, so nothing extra is saved. No autoloads here.
## Art: the placeholder (GearArt: a small sack for a pouch, a gem in a ring
## for a tool, coloured by tier) is drawn only while the Visual node is
## empty; put your own art into Visual.

@export_enum("pouch", "tool") var kind := "tool"
@export var gear_id := ""
## Only colours the placeholder; Game sets it from GearManager when the room loads.
var tier: GearTier.Tier = GearTier.Tier.WEAK

var _t := 0.0

@onready var visual: Node2D = get_node_or_null("Visual")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func get_rect() -> Rect2:
	return Rect2(global_position - Vector2(15, 38), Vector2(30, 38))


func _draw() -> void:
	draw_prompt()
	if visual and visual.get_child_count() > 0:
		return
	var col := GearArt.tier_color(tier)
	var center := Vector2(0, -20.0 + sin(_t * 2.6) * 2.0)
	draw_circle(center, 17.0 * (1.0 + sin(_t * 3.5) * 0.06), Color(col, 0.14))
	if kind == "pouch":
		GearArt.pouch(self, center, 10.0, col)
	else:
		GearArt.tool(self, center, 10.0, col)
