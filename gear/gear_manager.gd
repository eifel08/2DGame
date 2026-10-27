class_name GearManager
extends RefCounted
## Pouches and tools: ownership, the pouch loadout and the slot rules, and
## turning what is equipped into gameplay.
##
## Rules
##   - Up to Config.gear.max_equipped_pouches pouches are equipped at once
##     (debug overlay, default 4). If the limit is lowered below what is
##     equipped, only the first ones in equip order stay active.
##   - A pouch slot takes a tool of its tier or lower (GearTier.can_hold).
##   - A tool sits in at most one slot; slotting it again moves it.
##   - An equipped pouch's curse is always active, filled or not. A tool
##     only works while its pouch is active.
##   - Tools stay in a pouch when the pouch is unequipped.
##
## Effects (GearEffect): every active curse and tool contributes
##   stat_mods()  merged (multiplied) into one persistent player modifier,
##                MODIFIER_ID, read through Player.stat()
##   on_* hooks   called from Events (health_damaged, attack_swung)
## Fusion: a fused tool (ToolFusion) is an ordinary ToolData, so nothing
## here changes when fusion arrives; add it with add_tool().

const MODIFIER_ID := "gear"

var ctx: UltimateContext
var data: PlayerData
var tools := {} ## id -> ToolData
var pouches := {} ## id -> PouchData
var _applied_max := -1 ## Config.gear.max_equipped_pouches at the last refresh.


func setup(p_ctx: UltimateContext, p_data: PlayerData) -> void:
	ctx = p_ctx
	data = p_data
	for t in GearRegistry.create_tools():
		add_tool(t)
	for p in GearRegistry.create_pouches():
		add_pouch(p)
	Events.health_damaged.connect(_on_health_damaged)
	Events.attack_swung.connect(_on_attack_swung)
	refresh()


func add_tool(tool: ToolData) -> void:
	tools[tool.id] = tool


func add_pouch(pouch: PouchData) -> void:
	pouches[pouch.id] = pouch


func get_tool(tool_id: String) -> ToolData:
	return tools.get(tool_id)


func get_pouch(pouch_id: String) -> PouchData:
	return pouches.get(pouch_id)


## A tool's tier, or a pouch's strongest slot (pickup art, UI colours).
func tier_of(kind: String, gear_id: String) -> GearTier.Tier:
	if kind == "pouch":
		var pouch := get_pouch(gear_id)
		var top := 0
		if pouch:
			for slot_tier in pouch.slots:
				top = maxi(top, slot_tier)
		return top as GearTier.Tier
	var tool := get_tool(gear_id)
	return tool.tier if tool else GearTier.Tier.WEAK


func max_pouches() -> int:
	return int(Config.gear.max_equipped_pouches)


## Called every simulation step: picks up a changed pouch limit.
func step(_delta: float) -> void:
	if _applied_max != max_pouches():
		refresh()


# ---------- Ownership ----------

func grant_tool(tool_id: String) -> bool:
	if not tools.has(tool_id) or data.owned_tools.has(tool_id):
		return false
	data.owned_tools.append(tool_id)
	return true


func grant_pouch(pouch_id: String) -> bool:
	if not pouches.has(pouch_id) or data.owned_pouches.has(pouch_id):
		return false
	data.owned_pouches.append(pouch_id)
	_contents(pouch_id) # Make its empty slots.
	return true


func grant_all() -> void:
	for tool_id in tools:
		grant_tool(tool_id)
	for pouch_id in pouches:
		grant_pouch(pouch_id)


# ---------- Pouches ----------

func is_equipped(pouch_id: String) -> bool:
	return data.equipped_pouches.has(pouch_id)


func can_equip_pouch(pouch_id: String) -> bool:
	return data.owned_pouches.has(pouch_id) and not is_equipped(pouch_id) \
		and data.equipped_pouches.size() < max_pouches()


func equip_pouch(pouch_id: String) -> bool:
	if not can_equip_pouch(pouch_id):
		return false
	data.equipped_pouches.append(pouch_id)
	refresh()
	return true


## The pouch leaves the loadout; its tools stay inside it.
func unequip_pouch(pouch_id: String) -> bool:
	if not is_equipped(pouch_id):
		return false
	data.equipped_pouches.erase(pouch_id)
	refresh()
	return true


## Equipped pouches that count (the first max_pouches() in equip order).
func active_pouches() -> Array[PouchData]:
	var out: Array[PouchData] = []
	for pouch_id in data.equipped_pouches.slice(0, max_pouches()):
		if pouches.has(pouch_id):
			out.append(pouches[pouch_id])
	return out


# ---------- Tools in slots ----------

func tool_in(pouch_id: String, index: int) -> ToolData:
	var contents := _contents(pouch_id)
	return tools.get(contents[index]) if index >= 0 and index < contents.size() else null


func can_slot(pouch_id: String, index: int, tool_id: String) -> bool:
	var pouch := get_pouch(pouch_id)
	return pouch != null and data.owned_pouches.has(pouch_id) and data.owned_tools.has(tool_id) \
		and pouch.accepts(index, get_tool(tool_id))


## Puts a tool into a slot (moving it out of any other slot). An occupied
## slot has its tool replaced; the old tool goes back to the pool.
func slot_tool(pouch_id: String, index: int, tool_id: String) -> bool:
	if not can_slot(pouch_id, index, tool_id):
		return false
	_remove_everywhere(tool_id)
	_contents(pouch_id)[index] = tool_id
	refresh()
	return true


func clear_slot(pouch_id: String, index: int) -> bool:
	var contents := _contents(pouch_id)
	if index < 0 or index >= contents.size() or contents[index] == "":
		return false
	contents[index] = ""
	refresh()
	return true


## The pouch and slot a tool sits in, or {} when it is in the pool.
func find_tool(tool_id: String) -> Dictionary:
	for pouch_id in data.pouch_contents:
		var index: int = data.pouch_contents[pouch_id].find(tool_id)
		if index != -1:
			return {"pouch": pouch_id, "slot": index}
	return {}


## Fills the empty slots of the active pouches with owned free tools,
## strongest tools into the strongest slots first (debug).
func auto_fill() -> void:
	var free: Array = data.owned_tools.filter(func(id: String) -> bool: return find_tool(id).is_empty())
	free.sort_custom(func(a: String, b: String) -> bool: return tools[a].tier > tools[b].tier)
	for pouch in active_pouches():
		var contents := _contents(pouch.id)
		for i in contents.size():
			if contents[i] != "":
				continue
			for tool_id: String in free:
				if pouch.accepts(i, tools[tool_id]):
					contents[i] = tool_id
					free.erase(tool_id)
					break
	refresh()


## Unequips every pouch and empties every slot (debug).
func clear_all() -> void:
	data.equipped_pouches.clear()
	for pouch_id in data.pouch_contents:
		data.pouch_contents[pouch_id].fill("")
	refresh()


# ---------- Effects ----------

## Tools in the slots of the active pouches.
func active_tools() -> Array[ToolData]:
	var out: Array[ToolData] = []
	for pouch in active_pouches():
		var contents := _contents(pouch.id)
		for i in contents.size():
			var tool: ToolData = tools.get(contents[i])
			if tool and pouch.accepts(i, tool): # A slot never runs a tool too strong for it (e.g. an edited save).
				out.append(tool)
	return out


## Every effect in play: active curses, then active tools.
func active_effects() -> Array[GearEffect]:
	var out: Array[GearEffect] = []
	for pouch in active_pouches():
		out.append_array(pouch.curse)
	for tool in active_tools():
		out.append_array(tool.effects)
	return out


## Product of all stat_mods() of the active effects.
func combined_stats() -> Dictionary:
	var stats := {}
	for effect in active_effects():
		var mods := effect.stat_mods()
		for key in mods:
			stats[key] = stats.get(key, 1.0) * float(mods[key])
	return stats


## Re-applies the loadout to the player. Called after every change and on load.
func refresh() -> void:
	_applied_max = max_pouches()
	if ctx and ctx.player:
		ctx.player.set_persistent_modifier(MODIFIER_ID, combined_stats())
	Events.gear_changed.emit()


func _on_health_damaged(amount: float) -> void:
	for effect in active_effects():
		effect.on_player_damaged(ctx, amount)


func _on_attack_swung(dir: String) -> void:
	for effect in active_effects():
		effect.on_attack_swung(ctx, dir)


## The slot list of a pouch, created (all empty) and resized to the pouch's
## slots if needed, so saves stay valid when a pouch changes.
func _contents(pouch_id: String) -> Array[String]:
	var pouch := get_pouch(pouch_id)
	var size := pouch.slot_count() if pouch else 0
	if not data.pouch_contents.has(pouch_id):
		var empty: Array[String] = []
		data.pouch_contents[pouch_id] = empty
	var contents: Array[String] = data.pouch_contents[pouch_id]
	if contents.size() != size:
		var old := contents.size()
		contents.resize(size)
		for i in range(old, size):
			contents[i] = ""
	return contents


func _remove_everywhere(tool_id: String) -> void:
	for pouch_id in data.pouch_contents:
		var contents: Array = data.pouch_contents[pouch_id]
		for i in contents.size():
			if contents[i] == tool_id:
				contents[i] = ""
