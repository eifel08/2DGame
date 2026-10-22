class_name SpellCross
extends Control
## The spell loadout as a D-pad / cross diagram, used by the HUD and the
## inventory:
##
##              [Up]
##     [Left] [Center] [Right]
##             [Down]
##
##   Center       Mana Discharge, the neutral spell (fixed for good)
##   Up / Down    the Up and Down slots
##   Left, Right  BOTH show the one Side slot, so they always match
##
## Children (one per node, named Up / Left / Center / Right / Down):
##   HUD        SpellNodeView: icon, tier-colored frame, bright when affordable
##   inventory  AbilityCard buttons (interactive = true), keyboard focusable.
##              Focusing Left or Right gives that card the full focus frame and
##              the OPPOSITE side card a dim "mirror" frame, which shows they
##              share one slot without stealing the focus indicator.

const NODES: Array[String] = ["Up", "Left", "Center", "Right", "Down"]
const GRID := {"Up": Vector2i(1, 0), "Left": Vector2i(0, 1), "Center": Vector2i(1, 1), "Right": Vector2i(2, 1), "Down": Vector2i(1, 2)}
const SLOT_OF := {
	"Up": PlayerData.SLOT_UP, "Left": PlayerData.SLOT_SIDE, "Center": UltimateManager.NEUTRAL,
	"Right": PlayerData.SLOT_SIDE, "Down": PlayerData.SLOT_DOWN,
}

var ultimates: UltimateManager
var interactive := false
var cell := 24.0
var gap := 3.0
var nodes := {} ## node name -> Control (SpellNodeView or AbilityCard)


## Builds the five nodes. `p_cell`: node size in px; `p_gap`: space between.
func build(p_ultimates: UltimateManager, p_interactive: bool, p_cell: float, p_gap: float) -> void:
	ultimates = p_ultimates
	interactive = p_interactive
	cell = p_cell
	gap = p_gap
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not interactive else Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2.ONE * (cell * 3.0 + gap * 2.0)
	size = custom_minimum_size
	for node_name in NODES:
		var c: Control = AbilityCard.new() if interactive else SpellNodeView.new()
		c.name = node_name
		c.position = Vector2(GRID[node_name]) * (cell + gap)
		c.custom_minimum_size = Vector2(cell, cell)
		c.size = Vector2(cell, cell)
		add_child(c)
		nodes[node_name] = c
	if interactive:
		_link_focus()
		for node_name in ["Left", "Right"]:
			var card: AbilityCard = nodes[node_name]
			card.focus_entered.connect(_update_mirror)
			card.focus_exited.connect(_update_mirror)


## The directional slot (or UltimateManager.NEUTRAL) a node shows.
static func slot_of(node_name: String) -> int:
	return SLOT_OF[node_name]


## The other side node: Left <-> Right ("" for the rest).
static func mirror_of(node_name: String) -> String:
	return {"Left": "Right", "Right": "Left"}.get(node_name, "")


func card(node_name: String) -> Control:
	return nodes[node_name]


## Name of the node `c` is, or "".
func node_name_of(c: Control) -> String:
	for n in nodes:
		if nodes[n] == c:
			return n
	return ""


## Shows the current loadout. `max_energy` scales the inventory gauges.
func refresh(max_energy: float, energy := -1.0) -> void:
	for node_name in NODES:
		var ability := ultimates.get_slot(slot_of(node_name))
		if interactive:
			(nodes[node_name] as AbilityCard).show_ability(ability, max_energy)
		else:
			(nodes[node_name] as SpellNodeView).show_spell(ability, energy < 0.0 or (ability != null and energy >= ability.get_cost() - 0.0001))
	if interactive:
		_update_mirror()


## Dim mirror frame on the side card opposite the focused one.
func _update_mirror() -> void:
	for node_name in ["Left", "Right"]:
		var partner: AbilityCard = nodes[mirror_of(node_name)]
		(nodes[node_name] as AbilityCard).set_mirror(partner.has_focus())


## Explicit focus links inside the cross (arrows move like on a D-pad).
func _link_focus() -> void:
	var link := func(from: String, side: String, to: String) -> void:
		var c: Control = nodes[from]
		c.set("focus_neighbor_" + side, c.get_path_to(nodes[to]))
	link.call("Up", "bottom", "Center")
	link.call("Up", "left", "Left")
	link.call("Up", "right", "Right")
	link.call("Center", "top", "Up")
	link.call("Center", "bottom", "Down")
	link.call("Center", "left", "Left")
	link.call("Center", "right", "Right")
	link.call("Left", "right", "Center")
	link.call("Left", "top", "Up")
	link.call("Left", "bottom", "Down")
	link.call("Right", "left", "Center")
	link.call("Right", "top", "Up")
	link.call("Right", "bottom", "Down")
	link.call("Down", "top", "Center")
	link.call("Down", "left", "Left")
	link.call("Down", "right", "Right")
