extends Node
## Headless smoke test. Drives the real game through Input actions and checks
## the core mechanics. Run from the project folder:
##   godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
## Exit code 0 = all checks passed.

var game: Node
var failures: Array[String] = []
var passed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	# Keep test files away from the player's real saves and settings.
	Saves.save_dir = "user://test_saves"
	Settings.config_path = "user://test_settings.cfg"
	for i in Saves.SLOT_COUNT:
		Saves.delete_slot(i)
	game = load("res://scenes/game.tscn").instantiate()
	game.start_in_trance = false
	add_child(game)
	await _frames(30)
	var p: Player = game.player

	# --- Grounded and running ---
	_check("starts grounded", p.grounded)
	Input.action_press(&"move_right")
	await _frames(24)
	_check("reaches max run speed", is_equal_approx(p.velocity.x, Config.movement.max_run_speed), p.velocity.x)
	_check("run animation", p.animator.current == "run", p.animator.current)
	Input.action_release(&"move_right")
	await _frames(10)
	_check("stops crisply", is_zero_approx(p.velocity.x), p.velocity.x)

	# --- Variable jump height ---
	var tap := await _jump_height(2)
	var hold := await _jump_height(25)
	_check("tap jump is lower than held jump", tap < hold * 0.6, "tap %d hold %d" % [tap, hold])

	# --- Double jump ---
	await _reset()
	Input.action_press(&"jump")
	await _frames(15)
	Input.action_release(&"jump")
	await _frames(3)
	Input.action_press(&"jump")
	await _frames(2)
	_check("double jump used", p.air_jumps_used == 1, p.air_jumps_used)
	Input.action_release(&"jump")
	await _frames(90)

	# --- Coyote time: jump shortly after walking off a ledge ---
	await _reset()
	p.global_position = Vector2(7 * 32 + 4, 6 * 32) # On top of the left pillar.
	await _frames(10)
	Input.action_press(&"move_right")
	while p.grounded:
		await _frames(1)
	await _frames(3) # 3 frames (50 ms) after leaving the ledge.
	Input.action_release(&"move_right")
	Input.action_press(&"jump")
	await _frames(2)
	_check("coyote jump works", p.velocity.y < -500.0, p.velocity.y)
	Input.action_release(&"jump")
	await _frames(90)

	# --- Dash with i-frames ---
	await _reset()
	Input.action_press(&"dash")
	await _frames(3) # Press registers next frame, dash velocity applies the frame after.
	_check("dash state", p.state_name() == "dash", p.state_name())
	_check("dash speed", is_equal_approx(absf(p.velocity.x), Config.movement.dash_speed), p.velocity.x)
	_check("dash is invulnerable", p.health.is_invulnerable())
	Input.action_release(&"dash")
	await _frames(40)

	# --- Wall friction (slide) + wall jump (left shaft) ---
	p.global_position = Vector2(32 + Player.WIDTH / 2.0 + 1.0, 320) # Next to the room's left wall.
	p.velocity = Vector2.ZERO
	Input.action_press(&"move_left")
	await _frames(20)
	_check("wall friction slows the fall", p.wall_sliding and p.velocity.y <= Config.movement.wall_slide_speed + 0.1, [p.wall_sliding, p.velocity.y])
	_check("wall slide animation", p.animator.current == "wall_slide", p.animator.current)
	Input.action_press(&"jump")
	await _frames(2)
	_check("wall jump pushes away and up", p.velocity.x > 150.0 and p.velocity.y < -500.0, p.velocity)
	Input.action_release(&"jump")
	Input.action_release(&"move_left")
	await _frames(90)

	# --- Climb a single wall with consecutive (tapped) wall jumps ---
	await _reset()
	var wall_face := 30.0 * 32.0 # Left face of the central hanging wall.
	p.global_position = Vector2(wall_face - Player.WIDTH / 2.0 - 1.0, 560.0)
	p.velocity = Vector2.ZERO
	var climb_start := p.global_position.y
	var climb_min := climb_start
	var wall_jumps := 0
	var tap_left := 0
	Input.action_press(&"move_right")
	for f in 240:
		if tap_left > 0:
			tap_left -= 1
			if tap_left == 0:
				Input.action_release(&"jump")
		elif p.wall_dir == 1 and not p.grounded:
			Input.action_press(&"jump")
			tap_left = 2
			wall_jumps += 1
		await _frames(1)
		climb_min = minf(climb_min, p.global_position.y)
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	_check("a single wall can be climbed with tapped wall jumps", climb_start - climb_min > 250.0 and wall_jumps >= 3,
		"climbed %d px in %d jumps" % [climb_start - climb_min, wall_jumps])
	await _frames(90)

	# --- Melee hit gives damage + energy ---
	await _reset()
	Config.upgrades.god_mode = true
	var dummy: DummyEnemy = _first_enemy(false)
	dummy.patrol = false
	await _frames(5)
	p.global_position = dummy.global_position + Vector2(-40, 0)
	p.facing = 1
	var hp_before := dummy.health
	Input.action_press(&"attack")
	await _frames(20)
	Input.action_release(&"attack")
	_check("attack damages dummy", dummy.health < hp_before, dummy.health)
	_check("attack fills energy", p.health.energy > 0.0, p.health.energy)

	# --- Pogo on the flying dummy ---
	var flyer: DummyEnemy = _first_enemy(true)
	flyer.patrol = false
	p.global_position = flyer.global_position + Vector2(0, -flyer.size.y - 30)
	p.velocity = Vector2(0, 100)
	Input.action_press(&"move_down")
	Input.action_press(&"attack")
	await _frames(8)
	_check("pogo bounce", p.velocity.y < -400.0, p.velocity.y)
	Input.action_release(&"attack")
	Input.action_release(&"move_down")
	await _frames(90)
	# Forgiving pogo: a wide downward hitbox still connects 50 px off-centre.
	p.global_position = flyer.global_position + Vector2(50, -flyer.size.y - 30)
	p.velocity = Vector2(0, 100)
	Input.action_press(&"move_down")
	Input.action_press(&"attack")
	await _frames(8)
	_check("off-centre pogo still bounces", p.velocity.y < -400.0, p.velocity.y)
	Input.action_release(&"attack")
	Input.action_release(&"move_down")
	await _frames(90)
	Config.upgrades.god_mode = false

	# --- Chunk healing (risk-reward) ---
	var v = Config.vitals
	var full_chunk_frames := int(ceil((v.heal_windup + v.heal_chunk_time) * 60.0)) + 6
	var half_chunk_frames := int((v.heal_windup + v.heal_chunk_time * 0.5) * 60.0)
	await _reset()
	p.health.health = 40.0
	p.health.set_energy(v.heal_chunk_energy - 1.0)
	Input.action_press(&"heal")
	await _frames(30)
	_check("heal cannot start below one chunk of energy",
		p.state_name() != "heal" and is_equal_approx(p.health.health, 40.0) and is_equal_approx(p.health.energy, v.heal_chunk_energy - 1.0), p.state_name())
	Input.action_release(&"heal")
	await _frames(3)

	p.health.set_energy(100.0)
	Input.action_press(&"heal")
	await _frames(half_chunk_frames)
	_check("channeling drains energy and shows pending (white) health",
		p.health.pending_heal > 0.0 and is_equal_approx(p.health.health, 40.0) and p.health.energy < 100.0, [p.health.pending_heal, p.health.energy])
	Input.action_release(&"heal")
	await _frames(3)
	_check("releasing early loses the energy and restores nothing",
		is_equal_approx(p.health.health, 40.0) and is_zero_approx(p.health.pending_heal) and p.health.energy < 100.0, [p.health.health, p.health.energy])

	p.health.set_energy(100.0)
	Input.action_press(&"heal")
	await _frames(half_chunk_frames)
	var pending_before_hit := p.health.pending_heal
	p.receive_hit(10.0, p.global_position.x - 20.0)
	await _frames(2)
	_check("taking damage interrupts the chunk: pending health vanishes",
		pending_before_hit > 0.0 and is_zero_approx(p.health.pending_heal) and is_equal_approx(p.health.health, 30.0) and p.health.energy < 100.0,
		[p.health.pending_heal, p.health.health])
	Input.action_release(&"heal")

	await _reset()
	p.health.health = 40.0
	p.health.set_energy(100.0)
	Input.action_press(&"heal")
	await _frames(full_chunk_frames)
	_check("a completed chunk turns pending into real health",
		is_equal_approx(p.health.health, 40.0 + v.heal_chunk_health) and is_zero_approx(p.health.pending_heal)
		and is_equal_approx(p.health.energy, 100.0 - v.heal_chunk_energy), [p.health.health, p.health.energy])
	Input.action_release(&"heal") # Inside the pause window.
	await _frames(40)
	_check("releasing in the pause window starts no second chunk",
		is_equal_approx(p.health.health, 40.0 + v.heal_chunk_health) and is_equal_approx(p.health.energy, 100.0 - v.heal_chunk_energy), [p.health.health, p.health.energy])
	Input.action_press(&"heal")
	await _frames(int(ceil((v.heal_windup + v.heal_chunk_time * 2.0 + v.heal_chunk_pause) * 60.0)) + 10)
	Input.action_release(&"heal")
	# Two more chunks: the second starts by itself after the pause. Health is capped at max.
	_check("holding through the pause keeps healing chunk after chunk",
		is_equal_approx(p.health.health, minf(p.health.get_max_health(), 40.0 + v.heal_chunk_health * 3.0))
		and is_equal_approx(p.health.energy, 100.0 - v.heal_chunk_energy * 3.0),
		[p.health.health, p.health.energy])
	await _frames(5)

	# --- All four ultimates ---
	for ult_id in ["nova_burst", "spirit_volley", "ascendant_form", "comet_dash"]:
		await _reset()
		var key: StringName = UltimateManager.SLOT_ACTIONS[game.ultimates.slot_of(ult_id)]
		var target: DummyEnemy = _first_enemy(false)
		target.patrol = false
		await _frames(3)
		p.global_position = target.global_position + Vector2(-80, 0)
		p.facing = 1
		p.health.set_energy(100.0)
		var cost: float = Config.ultimates[ult_id].cost
		Input.action_press(key)
		await _frames(2)
		Input.action_release(key)
		_check("%s (key %s) spends its cost" % [ult_id, key], is_equal_approx(p.health.energy, 100.0 - cost), p.health.energy)
		await _frames(60)
		if ult_id == "ascendant_form":
			_check("ascendant form buffs the player", p.stat("damage_mul") > 1.0, p.modifiers.keys())
		else:
			_check("%s damages the dummy" % ult_id, target.health < target.max_health, target.health)

	# --- Insufficient energy is refused ---
	await _reset()
	var ascendant_key: StringName = UltimateManager.SLOT_ACTIONS[game.ultimates.slot_of("ascendant_form")]
	p.health.set_energy(50.0)
	Input.action_press(ascendant_key)
	await _frames(2)
	Input.action_release(ascendant_key)
	_check("ultimate refused without energy", is_equal_approx(p.health.energy, 50.0) and p.state_name() == "normal", p.health.energy)

	# --- Contact damage + i-frames ---
	await _reset()
	var toucher: DummyEnemy = _first_enemy(false)
	toucher.patrol = false
	p.global_position = toucher.global_position
	await _frames(3)
	_check("contact damage", p.health.health < p.health.get_max_health(), p.health.health)
	_check("i-frames after hit", p.health.has_iframes(), p.health.iframe_timer)

	# --- Gravity default ---
	_check("gravity default is 2100", is_equal_approx(Config.movement.gravity, 2100.0), Config.movement.gravity)

	# --- Hazard: damage + respawn at the last safe ground (left pit, columns 18-21) ---
	await _reset()
	var pit_left := 18.0 * 32.0
	p.global_position = Vector2(pit_left - 100.0, p.global_position.y) # Safe floor before the pit.
	await _frames(10)
	var safe_before := p.safe_point
	_check("safe point recorded on solid ground", safe_before.x < pit_left - 40.0, safe_before)
	var hp_full := p.health.health
	Input.action_press(&"move_right")
	var respawn := {}
	var on_respawn := func(_pl: Node, from_pos: Vector2, to_pos: Vector2) -> void:
		respawn["from"] = from_pos
		respawn["to"] = to_pos
	Events.player_hazard_respawn.connect(on_respawn)
	for i in 120:
		await _frames(1)
		if not respawn.is_empty():
			break
	Input.action_release(&"move_right")
	Events.player_hazard_respawn.disconnect(on_respawn)
	_check("hazard deals damage", p.health.health < hp_full, p.health.health)
	_check("spikes send the player back to safe ground (not the checkpoint)",
		not respawn.is_empty() and respawn.from.x >= pit_left - Player.WIDTH
		and respawn.to.x < pit_left - 40.0
		and respawn.to.distance_to(game.current_checkpoint.get_respawn_position()) > 50.0
		and p.global_position.distance_to(respawn.to) < 1.0, [respawn, p.global_position])
	await _frames(30)
	_check("player is not stuck in the hazard", not game.room.find_hazard(p.get_rect()).has_area() and p.global_position.x < pit_left, p.global_position)
	_check("hazard hit grants i-frames", p.health.has_iframes() or p.health.health < hp_full)

	# --- Hazard while invulnerable: still teleports, no damage ---
	await _reset()
	Config.upgrades.god_mode = true
	p.global_position = Vector2(pit_left - 100.0, p.global_position.y)
	await _frames(10)
	var hp_god := p.health.health
	p.global_position = Vector2(pit_left + 40.0, 22.0 * 32.0 - 2.0) # Drop straight into the spikes.
	await _frames(20)
	_check("invulnerable hazard touch teleports out", p.global_position.x < pit_left, p.global_position)
	_check("invulnerable hazard touch deals no damage", is_equal_approx(p.health.health, hp_god), p.health.health)
	Config.upgrades.god_mode = false

	# --- Pogo off spikes does not trigger the hazard ---
	await _reset()
	var pit_right := 46.0 * 32.0
	p.global_position = Vector2(pit_right + 80.0, 22.0 * 32.0 - 70.0)
	p.velocity = Vector2(0, 200)
	var hp_pogo := p.health.health
	Input.action_press(&"move_down")
	Input.action_press(&"attack")
	var bounced := false
	for i in 30:
		await _frames(1)
		if p.velocity.y < -400.0:
			bounced = true
			break
	Input.action_release(&"attack")
	Input.action_release(&"move_down")
	_check("pogo off spikes", bounced and is_equal_approx(p.health.health, hp_pogo), [p.velocity.y, p.health.health])
	await _frames(60)

	# --- Numbers are hidden by default, shown with Hitboxes & Stats ---
	_check("stats hidden by default", not Config.stats_visible())
	Config.debug.show_hitboxes = true
	_check("stats visible with hitbox toggle", Config.stats_visible())
	Config.debug.show_hitboxes = false

	# --- Lethal spikes: death respawns at the checkpoint ---
	await _reset()
	p.global_position = Vector2(pit_left - 100.0, p.global_position.y)
	await _frames(10)
	p.health.health = 5.0
	p.global_position = Vector2(pit_left + 40.0, 22.0 * 32.0 - 2.0)
	await _await_respawn()
	_check("lethal spike hit respawns at the checkpoint",
		p.global_position.distance_to(game.current_checkpoint.get_respawn_position()) < 2.0
		and is_equal_approx(p.health.health, p.health.get_max_health()), [p.global_position, p.health.health])

	# --- Shards that touch spikes disappear ---
	await _reset()
	var shards_now: int = game.player_data.currency
	game.drop_currency(Vector2(49.5 * 32.0, 22.0 * 32.0 - 40.0), 6) # Over the centre of the right pit.
	await _frames(90)
	var dropped_left := 0
	for c in game.coins:
		if c.dropped:
			dropped_left += 1
	_check("shards falling on spikes despawn", dropped_left == 0 and game.player_data.currency == shards_now, [dropped_left, game.player_data.currency])

	# --- Empty slots (0-4 equipped) ---
	await _reset()
	var loadout: Array = game.player_data.equipped.duplicate()
	await _frames(3)
	_check("slot can be emptied at a checkpoint", game.ultimates.unequip(1) and game.ultimates.get_slot(1) == null)
	_check("loadout has 3 equipped", game.player_data.equipped_count() == 3, game.player_data.equipped)
	p.health.set_energy(100.0)
	Input.action_press(&"ult_2")
	await _frames(2)
	Input.action_release(&"ult_2")
	_check("empty slot key does nothing", is_equal_approx(p.health.energy, 100.0) and p.state_name() == "normal", p.health.energy)
	for i in 4:
		game.ultimates.unequip(i)
	_check("all slots can be empty", game.player_data.equipped_count() == 0)
	for i in loadout.size():
		game.player_data.equip(i, loadout[i])
	Events.loadout_changed.emit()

	# --- No numbers in ability descriptions / lore / inventory ---
	var digit := RegEx.create_from_string("[0-9]")
	var numeric_text := []
	for ability in game.ultimates.abilities.values():
		if digit.search(ability.description) or digit.search(ability.display_name):
			numeric_text.append(ability.id)
	for page in load("res://dialogue/lore_ultimates.tres").pages:
		if digit.search(page):
			numeric_text.append(page)
	_check("ability texts and lore contain no numbers", numeric_text.is_empty(), numeric_text)

	# --- Keyboard-only inventory: tabs with arrows, unequip, equip, replace ---
	await _reset()
	await _frames(3)
	Input.action_press(&"inventory")
	await _frames(2)
	Input.action_release(&"inventory")
	var inv: InventoryMenu = game.inventory
	var eq: Array[String] = game.player_data.equipped
	inv.tabs.current_tab = 0
	inv.tab_bar.grab_focus()
	await _frames(1)
	await _ui_action(&"ui_right")
	_check("right arrow switches to the abilities tab", inv.tabs.current_tab == 1, inv.tabs.current_tab)
	await _ui_action(&"ui_left")
	_check("left arrow switches back to the status tab", inv.tabs.current_tab == 0, inv.tabs.current_tab)
	await _ui_action(&"ui_right")
	await _ui_action(&"ui_down")
	_check("down enters the slot row", get_viewport().gui_get_focus_owner() == inv.slot_cards[0], get_viewport().gui_get_focus_owner())
	await _ui_action(&"ui_accept")
	_check("confirm on an equipped slot unequips it", eq[0] == "", eq)
	await _focus_pool_card(inv, "nova_burst")
	await _ui_action(&"ui_accept")
	_check("confirm on a free ability asks for a slot",
		inv.pending_ability_id == "nova_burst" and get_viewport().gui_get_focus_owner() == inv.slot_cards[0], inv.pending_ability_id)
	await _ui_action(&"ui_accept")
	_check("the ability goes into the chosen slot", eq[0] == "nova_burst" and inv.pending_ability_id == "", eq)
	await _focus_pool_card(inv, "spirit_volley")
	await _ui_action(&"ui_accept")
	_check("confirm on an equipped ability in the grid unequips it", eq[1] == "", eq)
	await _ui_action(&"ui_accept") # Spirit Volley is free now -> choose a slot.
	await _ui_action(&"ui_right") # From the first free slot (2) to slot 3 (occupied).
	await _ui_action(&"ui_accept")
	_check("choosing an occupied slot replaces its ability",
		eq[2] == "spirit_volley" and not eq.has("ascendant_form") and eq[1] == "", eq)
	await _focus_pool_card(inv, "ascendant_form")
	await _ui_action(&"ui_accept")
	await _ui_action(&"menu_clear")
	_check("Backspace cancels the slot choice", inv.pending_ability_id == "" and not eq.has("ascendant_form"), eq)
	var crisp := true
	for card in inv.pool_cards:
		crisp = crisp and not card.icon_view.dim
	_check("unlocked abilities keep crisp icons (no greyed-out state)", crisp)
	_check("no empty-slot placeholder card", inv.pool_grid.get_child_count() == inv.pool_cards.size())
	var details_numeric := digit.search(inv.detail_name.text + inv.detail_desc.text) != null
	var card_text := ""
	for card in inv.pool_cards + inv.slot_cards:
		card_text += card.text
	_check("inventory shows icons, no text or numbers on cards", card_text == "" and not details_numeric, card_text)
	Input.action_press(&"inventory")
	await _frames(2)
	Input.action_release(&"inventory")
	_check("keyboard: inventory closes", not inv.is_open())
	for i in loadout.size():
		game.player_data.equip(i, loadout[i])

	# --- Left-to-right order and text ---
	var hud: Hud = game.hud
	_check("HUD slot strip runs 1-2-3-4 left to right",
		hud.slot_rect(0).position.x < hud.slot_rect(1).position.x and hud.slot_rect(2).position.x < hud.slot_rect(3).position.x)
	_check("inventory slots run 1-2-3-4 left to right",
		inv.slot_cards[0].get_index() == 0 and inv.slot_cards[3].get_index() == 3 and inv.panel.layout_direction == Control.LAYOUT_DIRECTION_LTR)
	var tl: Label = game.dialogue.text_label
	_check("dialogue text is LTR and does not re-wrap while typing",
		tl.text_direction == Control.TEXT_DIRECTION_LTR and tl.visible_characters_behavior == TextServer.VC_CHARS_AFTER_SHAPING)

	# --- One checkpoint info tablet, only at the first checkpoint ---
	var tablet_spots := []
	for rid in game.ROOM_SCENES:
		var scene_root: Node = (game.ROOM_SCENES[rid] as PackedScene).instantiate()
		for node in scene_root.get_node("Objects").get_children():
			if node is LoreObject and node.dialogue and node.dialogue.resource_path.ends_with("lore_checkpoint.tres"):
				tablet_spots.append([rid, node.position.x])
		scene_root.free()
	var start_cp: Checkpoint = null
	for cp in game.checkpoints:
		if cp.is_start:
			start_cp = cp
	_check("the checkpoint tablet appears once, just before the first checkpoint",
		tablet_spots.size() == 1 and tablet_spots[0][0] == "test_room"
		and start_cp.global_position.x - tablet_spots[0][1] > 20.0 and start_cp.global_position.x - tablet_spots[0][1] < 140.0, tablet_spots)

	# --- 4 dedicated ultimate keys, no switching ---
	_check("ultimate hotkeys 1-4 exist", InputMap.has_action(&"ult_1") and InputMap.has_action(&"ult_4"))
	_check("no ultimate switching action", not InputMap.has_action(&"cycle_ultimate"))
	_check("energy tiers have distinct colors",
		Config.energy_tier_color(25.0) != Config.energy_tier_color(50.0)
		and Config.energy_tier_color(50.0) != Config.energy_tier_color(100.0))

	# --- Dialogue with the guide NPC (pauses the game) ---
	await _reset()
	var npc: LoreObject = _find_object("Npc1")
	p.global_position = npc.global_position + Vector2(-20, 0)
	await _frames(3)
	_check("NPC shows interaction prompt", game.focused_interactable == npc and npc.highlighted)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("dialogue opens", game.dialogue.is_open())
	var paused_x := p.global_position.x
	Input.action_press(&"move_right")
	await _frames(20)
	Input.action_release(&"move_right")
	_check("game paused during dialogue", is_equal_approx(p.global_position.x, paused_x), p.global_position.x)
	await _close_dialogue()
	_check("dialogue closes after the last page", not game.dialogue.is_open())
	var lore_count := 0
	for node in game.room.get_objects():
		if node is LoreObject and node.dialogue != null:
			lore_count += 1
	_check("room has NPC + lore tablets", lore_count >= 4, lore_count)

	# --- Saving at a checkpoint: center + full heal, no text ---
	await _reset()
	p.health.health = 30.0
	p.global_position = game.current_checkpoint.global_position + Vector2(-16, 0)
	await _frames(3)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("saving fully heals", is_equal_approx(p.health.health, p.health.get_max_health()), p.health.health)
	_check("saving snaps the player to the checkpoint centre",
		absf(p.global_position.x - game.current_checkpoint.global_position.x) < 0.5, p.global_position)
	_check("saving shows no explanation text", not game.dialogue.is_open())

	# --- Currency ---
	await _reset()
	var shards_before: int = game.player_data.currency
	var coin: Coin = null
	for c in game.coins:
		if not c.dropped and not c.collected:
			coin = c
			break
	p.global_position = coin.global_position
	await _frames(3)
	_check("collecting a shard adds currency", game.player_data.currency == shards_before + coin.value, game.player_data.currency)
	var victim: DummyEnemy = _first_enemy(false)
	var coins_before: int = game.coins.size()
	victim.kill()
	Events.enemy_killed.emit(victim)
	var dropped_value := 0
	for c in game.coins:
		if c.dropped:
			dropped_value += c.value
	_check("enemies drop shards", game.coins.size() > coins_before and dropped_value == victim.currency_drop, dropped_value)

	# --- Loadout: swaps only at a checkpoint ---
	await _reset()
	var data: PlayerData = game.player_data
	var original := data.equipped.duplicate()
	await _frames(3)
	_check("starts at a checkpoint", p.at_checkpoint)
	_check("swap allowed at checkpoint", game.ultimates.equip(0, "comet_dash") and data.equipped[0] == "comet_dash" and data.equipped[3] == original[0], data.equipped)
	p.global_position += Vector2(200, 0)
	await _frames(3)
	_check("swap refused away from checkpoint", not p.at_checkpoint and not game.ultimates.equip(0, original[0]), data.equipped)
	Input.action_press(&"inventory")
	await _frames(2)
	Input.action_release(&"inventory")
	_check("inventory opens", game.inventory.is_open())
	_check("inventory shows swap restriction", game.inventory.pool_grid.get_child_count() == 4 and game.inventory.notice_label.text.contains("only"), game.inventory.notice_label.text)
	var frozen_x := p.global_position.x
	Input.action_press(&"move_right")
	await _frames(10)
	Input.action_release(&"move_right")
	_check("game paused in inventory", is_equal_approx(p.global_position.x, frozen_x))
	Input.action_press(&"inventory")
	await _frames(2)
	Input.action_release(&"inventory")
	_check("inventory closes", not game.inventory.is_open())
	for i in original.size():
		data.equip(i, original[i])

	# --- Enemies die on hazards ---
	await _reset()
	var faller: DummyEnemy = _first_enemy(false)
	faller.patrol = false
	faller.global_position = Vector2(46.0 * 32.0 + 60.0, 23.0 * 32.0) # Inside the right pit.
	await _frames(3)
	_check("enemy touching spikes dies", not faller.alive)

	# --- Checkpoints: explicit saving only, death respawn ---
	await _reset()
	var mid: Checkpoint = _find_object("Checkpoint2")
	p.global_position = mid.global_position + Vector2(-14, 0)
	await _frames(5)
	_check("standing at a checkpoint does not save", game.current_checkpoint != mid and not mid.lit)
	_check("loadout locked until saved here", not p.at_checkpoint)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check("pressing E saves the checkpoint", game.current_checkpoint == mid and mid.lit and p.at_checkpoint)
	_check("saving at a checkpoint starts the trance", p.state_name() == "trance", p.state_name())
	p.fsm.change("normal")
	p.global_position = mid.global_position + Vector2(-150, 0)
	await _frames(2)
	p.receive_hit(1000.0, p.global_position.x, false, true)
	await _await_respawn()
	_check("death respawns at the saved checkpoint", p.global_position.distance_to(mid.get_respawn_position()) < 2.0, p.global_position)
	await _reset()
	p.global_position = mid.global_position + Vector2(10, 0)
	await _frames(5)
	Input.action_press(&"move_down")
	await _frames(2)
	Input.action_release(&"move_down")
	_check("pressing Down on the ground also saves", game.current_checkpoint == mid
		and absf(p.global_position.x - mid.global_position.x) < 0.5, game.current_checkpoint)
	await _frames(20)
	_check("holding Down does not break the save trance", p.state_name() == "trance", p.state_name())
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	_check("a fresh press wakes the player after saving", p.state_name() != "trance", p.state_name())
	await _frames(40)

	# --- Layout: no open space beyond walls, camera never shows outside the room ---
	for rid in ["test_room", "boss_room", "arena_room", "secret_room", "upper_room"]:
		game.load_room(rid)
		await _frames(2)
		var uncovered := []
		for cell in game.room.border_openings():
			var c: Vector2 = game.room.cell_center(cell)
			var covered := false
			for door in game.doors:
				if door.get_trigger_rect().grow_individual(0, 0, 0, 2).has_point(c):
					covered = true
			if not covered:
				uncovered.append(cell)
		_check("%s: every border opening is a door" % rid, uncovered.is_empty(), uncovered)
		var bounds: Rect2 = game.room.get_bounds()
		var view_ok := true
		for corner in [bounds.position + Vector2(40, 40), Vector2(bounds.end.x - 40, bounds.position.y + 40),
				Vector2(bounds.position.x + 40, bounds.end.y - 40), bounds.end - Vector2(40, 40)]:
			p.global_position = corner
			game.camera.snap_to(p)
			game.camera.add_trauma(1.0)
			for i in 5:
				game.camera.step_shake(1.0 / 60.0)
				view_ok = view_ok and bounds.encloses(game.camera.view_rect())
		_check("%s: camera view stays inside the room even while shaking" % rid, view_ok)
	game.load_room("test_room")
	var tiles: TileMapLayer = game.room.tiles
	_check("wall faces bordering open space are lit (edge tiles)",
		(tiles.get_cell_atlas_coords(Vector2i(0, 10)).x & 2) != 0 and tiles.get_cell_atlas_coords(Vector2i(10, 23)).x == 0,
		[tiles.get_cell_atlas_coords(Vector2i(0, 10)), tiles.get_cell_atlas_coords(Vector2i(10, 23))])

	# --- Heal readiness glow on the energy meter ---
	await _reset()
	p.health.set_energy(Config.vitals.heal_chunk_energy - 1.0)
	_check("no heal glow below one chunk of energy", not game.hud.heal_ready())
	p.health.set_energy(Config.vitals.heal_chunk_energy)
	_check("heal glow once a full chunk is affordable", game.hud.heal_ready())

	# --- Room transition through the doorway ---
	await _reset()
	var east: Door = _door("east")
	p.global_position = east.global_position + Vector2(-90, 0)
	await _frames(3)
	var door_sounds := Sfx.count("door")
	Input.action_press(&"move_right")
	var crossing_speed := 0.0
	for i in 120:
		crossing_speed = p.velocity.x
		await _frames(1)
		if game.room_id == "boss_room":
			break
	_check("crossing an opening is seamless: no fade, no sound, speed kept",
		game.transition.is_empty() and game.fade.color.a < 0.01 and Sfx.count("door") == door_sounds
		and is_equal_approx(p.velocity.x, crossing_speed), [p.velocity.x, crossing_speed])
	Input.action_release(&"move_right")
	await _frames(30)
	_check("walking through the east door enters the boss room", game.room_id == "boss_room", game.room_id)
	var west: Door = _door("west")
	_check("player arrives beside the boss room door",
		p.global_position.distance_to(west.get_arrival_position()) < 40.0 and game.fade.color.a < 0.01, p.global_position)
	Input.action_press(&"move_left")
	for i in 120:
		await _frames(1)
		if game.room_id == "test_room":
			break
	Input.action_release(&"move_left")
	await _frames(30)
	_check("walking back through the door returns to the test room", game.room_id == "test_room"
		and p.global_position.distance_to(_door("east").get_arrival_position()) < 40.0, [game.room_id, p.global_position])

	# --- Openings carry no visual markers ---
	var unmarked := true
	for rid in game.ROOM_SCENES:
		var scene_root: Node = (game.ROOM_SCENES[rid] as PackedScene).instantiate()
		for node in scene_root.get_node("Objects").get_children():
			if node is Door:
				unmarked = unmarked and node.get_child_count() == 0 and not node.has_method("_draw")
		scene_root.free()
	_check("doors are invisible triggers in wall gaps (nothing drawn)", unmarked)

	# --- Ceiling gap in the first room leads up to the Upper Galleries ---
	await _reset()
	var ceiling: Door = _door("ceiling")
	_check("the first room has a gap in its ceiling", ceiling != null and ceiling.vertical == -1
		and not game.room.is_solid_at(ceiling.global_position + Vector2(0, 16)), ceiling)
	var wall_top := Vector2(ceiling.global_position.x, 4.0 * 32.0) # Top of the central hanging wall.
	p.global_position = wall_top
	p.velocity = Vector2.ZERO
	await _frames(10)
	_check("the central wall top is a ledge under the gap", p.grounded, p.global_position)
	Input.action_press(&"jump")
	for i in 60:
		await _frames(1)
		if game.room_id == "upper_room":
			break
	Input.action_release(&"jump")
	_check("jumping up through the ceiling gap enters the Upper Galleries", game.room_id == "upper_room" and game.transition.is_empty(), game.room_id)
	var floor_gap: Door = _door("floor")
	_check("you rise out of the floor gap, still moving up", p.velocity.y < 0.0 and floor_gap != null
		and absf(p.global_position.x - floor_gap.global_position.x) < 64.0, [p.velocity, p.global_position])
	Input.action_press(&"move_right")
	for i in 90:
		await _frames(1)
		if p.grounded:
			break
	Input.action_release(&"move_right")
	_check("steering aside lands on the upper floor", p.grounded and game.room_id == "upper_room", [p.global_position, game.room_id])
	var kinds := {}
	for e in game.enemies:
		kinds[e.tier if not (e is DummyEnemy and e.flying) else "flyer"] = true
	_check("the Upper Galleries hold standard enemies only (no boss, no arena)",
		kinds.has("weak") and kinds.has("strong") and kinds.has("flyer") and not kinds.has("boss") and game.room.get_arena() == null, kinds)
	p.global_position = Vector2(floor_gap.global_position.x, floor_gap.global_position.y - 70.0)
	p.velocity = Vector2(0, 200)
	for i in 60:
		await _frames(1)
		if game.room_id == "test_room":
			break
	_check("dropping through the floor gap falls back into the first room", game.room_id == "test_room" and p.velocity.y > 0.0, game.room_id)
	for i in 90:
		await _frames(1)
		if p.grounded:
			break
	_check("the fall lands on the ledge under the gap", p.grounded and absf(p.global_position.y - wall_top.y) < 2.0, p.global_position)
	await _reset()

	# --- Enemy persistence and respawn hierarchy ---
	game.new_game()
	await _reset()
	var weak: DummyEnemy = _first_enemy(false)
	var weak_id := weak.spawn_id
	weak.kill()
	Events.enemy_killed.emit(weak)
	await _frames(240)
	_check("weak enemy does not respawn by itself", not weak.alive and _enemy_by_id(weak_id) == weak, weak_id)
	game.load_room("boss_room", "west")
	game.load_room("test_room", "east")
	await _frames(2)
	var revived := _enemy_by_id(weak_id)
	_check("weak enemy respawns after a room transition", revived != null and revived.alive)
	var survivor: DummyEnemy = _first_enemy(false)
	var survivor_id := survivor.spawn_id
	survivor.take_hit(30.0, Vector2.ZERO, 0.0)
	game.load_room("boss_room", "west")
	game.load_room("test_room", "east")
	await _frames(2)
	var back := _enemy_by_id(survivor_id)
	_check("damaged survivor is back at full health after leaving and returning",
		back != null and is_equal_approx(back.health, back.max_health), back.health if back else -1.0)
	var strong: DummyEnemy = null
	for e in game.enemies:
		if e.tier == "strong":
			strong = e
	var strong_id := strong.spawn_id
	strong.kill()
	Events.enemy_killed.emit(strong)
	game.load_room("boss_room", "west")
	game.load_room("test_room", "east")
	await _frames(2)
	_check("strong enemy stays dead across room transitions", _enemy_by_id(strong_id) == null)
	p.global_position = game.checkpoints[0].global_position
	await _frames(3)
	game.save_at_checkpoint(game.checkpoints[0])
	await _frames(2)
	var strong_back := _enemy_by_id(strong_id)
	_check("strong enemy respawns when saving at a checkpoint", strong_back != null and strong_back.alive)

	# --- Boss: tracks and targets the player ---
	game.new_game()
	game.world.clear_arena("sentinel_arena") # Fight the boss on its own here.
	game.load_room("boss_room", "west")
	Config.upgrades.god_mode = true
	var boss: BossSentinel = game.spawn_enemy_kind("boss", Vector2(900, 512), "")
	p.global_position = Vector2(400, 512)
	await _frames(60)
	_check("boss faces the player (left)", boss.facing == -1, boss.facing)
	_check("boss walks toward the player", boss.state != "stalk" or boss.velocity.x < 0.0, [boss.state, boss.velocity.x])
	p.global_position = Vector2(1150, 512)
	await _frames(40)
	_check("boss turns to track the player (right)", boss.facing == 1, boss.facing)
	boss._launch("charge")
	await _frames(1)
	_check("charge is aimed at the player's position",
		boss.velocity.x > 0.0 and absf(boss.last_target_position.x - p.global_position.x) < 2.0, [boss.velocity.x, boss.last_target_position])
	await _frames(70)
	p.global_position = Vector2(520, 512)
	boss.global_position = Vector2(900, 512)
	boss._launch("leap")
	var landed := false
	for i in 90:
		await _frames(1)
		if boss.state == "recover":
			landed = true
			break
	_check("leap lands on the player's position", landed and absf(boss.global_position.x - 520.0) < 70.0, boss.global_position)
	await _frames(40)
	game.combat.projectiles.clear()
	p.global_position = Vector2(boss.global_position.x - 300.0, 512) # Shards need room to fly.
	boss._launch("volley")
	await _frames(3)
	var aimed := false
	for pr in game.combat.projectiles.list:
		if pr.hostile:
			var to_player: Vector2 = (p.get_center() - pr.pos).normalized()
			aimed = aimed or (pr.vel as Vector2).normalized().dot(to_player) > 0.9
	_check("volley shards are aimed at the player", aimed)
	Config.upgrades.god_mode = false
	await _frames(60)
	boss.take_hit(boss.max_health * 0.55, Vector2.ZERO, 0.0)
	_check("boss enters phase 2 below half health", boss.phase == 2)
	boss.kill()
	Events.enemy_killed.emit(boss)
	_check("defeated boss is recorded", game.world.is_boss_defeated(boss.boss_id))
	_check("defeated boss never respawns", game.spawn_enemy_kind("boss", Vector2(900, 512), "") == null)
	game.world.on_checkpoint_rest()
	_check("not even after a checkpoint save", game.spawn_enemy_kind("boss", Vector2(900, 512), "") == null)

	# --- Arena waves: weak/strong waves, boss last, cleared forever ---
	game.new_game()
	Config.upgrades.god_mode = true
	game.load_room("boss_room", "west")
	await _frames(2)
	var director: ArenaDirector = game.arena_director
	p.global_position = game.room.get_arena().get_trigger_rect().get_center() + Vector2(0, 200)
	p.global_position.y = 512
	await _frames(30) # Lets the boss-defeat hitstop from the previous test run out.
	_check("entering the arena starts it and seals the door", director.is_active() and _door("west").locked and game.room.get_arena().gates_closed,
		[director.state, _door("west").locked, game.room.get_arena().gates_closed, p.global_position, game.room.get_arena().get_trigger_rect()])
	var fanfares := Sfx.count("victory")
	var boss_freeze := 0.0
	var waves_seen := []
	for i in 600:
		await _frames(1)
		if director.state == "cleared":
			break
		boss_freeze = maxf(boss_freeze, game.feedback.hitstop_timer if waves_seen.has(2) else 0.0)
		for e in director.wave_enemies:
			if e.alive and e.flash_timer <= 0.0:
				if not waves_seen.has(director.wave):
					waves_seen.append(director.wave)
				var kind: String = "boss" if e is BossSentinel else e.tier
				waves_seen.append(kind)
				e.kill()
				Events.enemy_killed.emit(e)
	_check("arena runs its waves (weak, strong, then the boss)",
		waves_seen.has("weak") and waves_seen.has("strong") and waves_seen.has("boss") and waves_seen.find("boss") > waves_seen.find("strong"), waves_seen)
	_check("a boss defeat has no fanfare, celebration effect or freeze",
		Sfx.count("victory") == fanfares and game.effects.count("boss_death") == 0 and boss_freeze <= 0.0, [Sfx.count("victory") - fanfares, boss_freeze])
	_check("arena is cleared and the door opens", director.state == "cleared" and not _door("west").locked and not game.room.get_arena().gates_closed)
	game.load_room("test_room", "east")
	game.load_room("boss_room", "west")
	await _frames(5)
	p.global_position = Vector2(600, 512)
	await _frames(10)
	_check("cleared arena never repeats", director.state == "cleared" and game.enemies.is_empty(), [director.state, game.enemies.size()])
	Config.upgrades.god_mode = false

	game.new_game()
	game.load_room("boss_room", "west")
	await _frames(2)
	p.global_position = Vector2(600, 512)
	await _frames(60)
	_check("arena active again in a new game", director.is_active())
	p.receive_hit(1000.0, p.global_position.x, false, true)
	await _await_respawn()
	_check("dying in the arena returns to the checkpoint and resets the arena",
		game.room_id == "test_room" and not game.world.is_arena_cleared("sentinel_arena"), game.room_id)
	game.new_game()

	# --- Death: collapse animation, then back at the checkpoint like a save ---
	game.new_game()
	await _reset()
	var fallen: DummyEnemy = _first_enemy(false)
	var fallen_id := fallen.spawn_id
	fallen.kill()
	Events.enemy_killed.emit(fallen)
	var heavy: Enemy = null
	for e in game.enemies:
		if e.tier == "strong" and e.alive:
			heavy = e
	var heavy_id := heavy.spawn_id
	heavy.kill()
	Events.enemy_killed.emit(heavy)
	await _frames(2)
	_check("dead enemy has no contact damage or hurtbox", not fallen.deals_contact_damage() and not fallen.hitbox_active())
	_check("dead enemy cannot be hit", is_zero_approx(fallen.take_hit(10.0, Vector2.ZERO, 0.0)))
	_check("dead enemy body collision is disabled", fallen.shape.disabled)
	p.health.set_energy(40.0)
	var death_sounds := Sfx.count("death")
	p.receive_hit(1000.0, p.global_position.x, false, true)
	await _frames(10)
	_check("a lethal hit plays the death animation before respawning",
		p.is_dying() and p.animator.current == "dying" and Sfx.count("death") > death_sounds, [p.state_name(), p.animator.current])
	_check("the dying player is invulnerable", p.health.is_invulnerable())
	await _await_respawn()
	_check("after respawning the player floats in a trance", p.state_name() == "trance" and p.animator.current == "trance",
		[p.state_name(), p.animator.current])
	_check("energy is 0 after respawning", is_zero_approx(p.health.energy), p.health.energy)
	var fallen_back := _enemy_by_id(fallen_id)
	var heavy_back := _enemy_by_id(heavy_id)
	_check("death respawn revives weak and strong enemies",
		fallen_back != null and fallen_back.alive and heavy_back != null and heavy_back.alive)

	# --- Trance: a held key does not break it, a fresh press does ---
	p.fsm.change("normal")
	Input.action_press(&"move_right")
	await _frames(5)
	p.enter_trance()
	await _frames(30)
	_check("a key held from before keeps the trance", p.state_name() == "trance", p.state_name())
	Input.action_press(&"jump")
	await _frames(3)
	_check("a fresh button press breaks the trance", p.state_name() != "trance", p.state_name())
	Input.action_release(&"jump")
	Input.action_release(&"move_right")
	await _frames(30)

	# --- Telegraphed spawns ---
	await _reset()
	var portal: Enemy = game.spawn_enemy_kind("weak", p.global_position, "", true)
	_check("a telegraphed spawn never appears on top of the player",
		absf(portal.global_position.x - p.global_position.x) >= game.SPAWN_CLEARANCE, portal.global_position)
	_check("a spawning enemy is harmless and untouchable",
		portal.is_spawning() and not portal.deals_contact_damage() and is_zero_approx(portal.take_hit(5.0, Vector2.ZERO, 0.0)))
	await _frames(3)
	_check("the spawn uses the portal effect and the spawn clip (no timer)",
		game.effects.count("spawn_portal") > 0 and portal.anim.assigned_animation == "spawn", portal.anim.assigned_animation)
	await _frames(22)
	_check("the spawn telegraph is short (under half a second)", not portal.is_spawning() and portal.hitbox_active())
	game.remove_enemy(portal)
	var plain_spawns := Sfx.count("spawn")
	game.spawn_enemy(false)
	await _frames(2)
	var plain: Enemy = game.enemies[-1]
	_check("outside arenas, enemies spawn without a telegraph", not plain.is_spawning() and Sfx.count("spawn") == plain_spawns)
	game.remove_enemy(plain)

	# --- Boss death: roar and dissolve ---
	game.new_game()
	game.world.clear_arena("sentinel_arena")
	game.load_room("boss_room", "west")
	var dying_boss: BossSentinel = game.spawn_enemy_kind("boss", Vector2(900, 512), "")
	p.global_position = Vector2(300, 512)
	await _frames(5)
	var roars := Sfx.count("boss_roar")
	dying_boss.kill()
	Events.enemy_killed.emit(dying_boss)
	await _frames(2)
	_check("the boss roars when it dies", Sfx.count("boss_roar") > roars)
	_check("the dead boss stops hurting at once", not dying_boss.hitbox_active() and not dying_boss.deals_contact_damage())
	_check("a boss defeat shows no text pop-up", not "banner_text" in game.hud)
	_check("the boss is still visible while it screams", dying_boss.visible and not dying_boss.is_dissolved())
	for i in 300:
		await _frames(1)
		if dying_boss.is_dissolved():
			break
	_check("the boss dissolves after the scream (dissolve clip + particle effect)",
		dying_boss.is_dissolved() and game.effects.count("boss_dissolve") > 0)

	# --- Proving Grounds: a dedicated arena room that stays cleared ---
	game.new_game()
	Config.upgrades.god_mode = true
	game.load_room("arena_room", "west")
	await _frames(30)
	var grounds: ArenaDirector = game.arena_director
	var victories := Sfx.count("victory")
	p.global_position = Vector2(20 * 32, 512)
	for i in 900:
		await _frames(1)
		if grounds.state == "cleared":
			break
		for e in grounds.wave_enemies:
			if e.alive:
				e.kill()
				Events.enemy_killed.emit(e)
	_check("the Proving Grounds arena runs and clears", grounds.state == "cleared" and game.world.is_arena_cleared("proving_grounds"), grounds.state)
	_check("clearing an arena plays a victory sound and effect (no text)",
		Sfx.count("victory") > victories and game.effects.count("arena_clear") > 0)
	game.load_room("boss_room", "east")
	game.load_room("arena_room", "west")
	await _frames(3)
	p.global_position = Vector2(20 * 32, 512)
	await _frames(30)
	_check("a cleared arena room stays cleared", grounds.state == "cleared" and game.enemies.is_empty(), [grounds.state, game.enemies.size()])
	await _frames(60)

	# --- Hidden passage: breakable wall to the Hidden Shrine ---
	var wall: BreakableWall = game.breakables[0]
	_check("the hidden wall starts intact", wall.intact)
	_check("the hidden wall fills the outer wall gap exactly", is_equal_approx(wall.get_rect().end.x, game.room.get_bounds().end.x)
		and wall.get_rect().size == Vector2(32, 96), wall.get_rect())
	p.global_position = Vector2(wall.get_rect().position.x - 24.0, 512)
	p.facing = 1
	Input.action_press(&"move_right")
	await _frames(30)
	Input.action_release(&"move_right")
	_check("the intact wall blocks the way (no transition)", game.room_id == "arena_room" and p.get_rect().end.x <= wall.get_rect().position.x + 0.5,
		[game.room_id, p.get_rect().end.x])
	p.global_position = Vector2(wall.get_rect().position.x - 24.0, 512)
	await _frames(5)
	for i in 3:
		Input.action_press(&"attack")
		await _frames(3)
		Input.action_release(&"attack")
		await _frames(30)
	_check("three hits break the hidden wall", not wall.intact and game.world.is_secret_open("proving_grounds_wall"), wall.hits)
	_check("a broken wall opens at once, with no message", game.effects.count("wall_break") > 0 and not wall.visible)
	Input.action_press(&"move_right")
	var walk_frames := 0
	for i in 120:
		await _frames(1)
		walk_frames += 1
		if game.room_id == "secret_room":
			break
	_check("walking through the gap enters the shrine with no fade or wait",
		game.room_id == "secret_room" and walk_frames < 40 and game.transition.is_empty() and game.fade.color.a < 0.01, walk_frames)
	Input.action_release(&"move_right")
	await _frames(30)
	_check("the hidden passage leads to the Hidden Shrine", game.room_id == "secret_room", game.room_id)
	var base_max := p.health.get_max_health()
	var relic: Relic = game.relics[0]
	p.global_position = relic.global_position
	await _frames(5)
	_check("the relic raises max health", relic.collected and is_equal_approx(p.health.get_max_health(), base_max + 25.0),
		[relic.collected, p.health.get_max_health()])
	game.load_room("arena_room", "east")
	await _frames(2)
	_check("the broken wall stays open", not game.breakables[0].intact)
	game.load_room("secret_room", "west")
	await _frames(2)
	_check("the relic stays collected", game.relics[0].collected)
	Config.upgrades.god_mode = false

	# --- Save slots ---
	game.new_game()
	await _reset()
	Saves.active_slot = 0
	game.player_data.currency = 37
	game.world.defeat_boss("test_boss")
	game.world.open_secret("test_secret")
	game.write_save()
	var slot0 := Saves.read_slot(0)
	_check("a save stores currency, bosses, secrets and the checkpoint",
		int(slot0.get("currency", 0)) == 37 and Array(slot0.get("defeated_bosses", [])).has("test_boss")
		and Array(slot0.get("secrets", [])).has("test_secret") and slot0.get("room", "") == "test_room", slot0)
	for s in range(1, Saves.SLOT_COUNT):
		Saves.active_slot = s
		game.player_data.currency = s
		game.write_save()
	var independent := Saves.SLOT_COUNT == 5
	for s in range(1, Saves.SLOT_COUNT):
		independent = independent and int(Saves.read_slot(s).currency) == s
	_check("5 independent save slots", independent and int(Saves.read_slot(0).currency) == 37)
	_check("slot summary names the location", Saves.summary(0).contains("Testing Halls"), Saves.summary(0))
	# Progress made after the save is lost on load; respawnables are reset.
	Saves.active_slot = 0
	game.player_data.currency = 999
	game.world.new_game()
	var lost: DummyEnemy = _first_enemy(false)
	var lost_id := lost.spawn_id
	lost.kill()
	Events.enemy_killed.emit(lost)
	p.health.set_energy(50.0)
	p.global_position += Vector2(300, 0)
	game.apply_save_data(Saves.read_slot(0))
	await _frames(3)
	_check("loading restores the saved currency and progress",
		game.player_data.currency == 37 and game.world.is_boss_defeated("test_boss") and game.world.is_secret_open("test_secret"))
	_check("loading places the player at the checkpoint with 0 energy, in a trance",
		p.global_position.distance_to(game.respawn.position) < 2.0 and is_zero_approx(p.health.energy) and p.state_name() == "trance",
		[p.global_position, p.health.energy, p.state_name()])
	var lost_back := _enemy_by_id(lost_id)
	_check("loading resets respawnable enemies", lost_back != null and lost_back.alive)
	Saves.active_slot = -1
	p.fsm.change("normal")
	game.new_game()

	# --- Pause menu (keyboard and mouse) ---
	await _reset()
	Input.action_press(&"pause")
	await _frames(2)
	Input.action_release(&"pause")
	await _frames(1)
	_check("the pause key opens the pause menu", game.pause_menu.is_open()
		and get_viewport().gui_get_focus_owner() == game.pause_menu.resume_button)
	var paused_at := p.global_position
	Input.action_press(&"move_right")
	await _frames(10)
	Input.action_release(&"move_right")
	_check("the game is paused behind the menu", p.global_position.is_equal_approx(paused_at), p.global_position)
	await _ui_action(&"ui_accept")
	_check("Enter on Resume closes the pause menu", not game.pause_menu.is_open())
	game.pause_menu.toggle()
	await _frames(2)
	await _click(game.pause_menu.resume_button)
	_check("a mouse click on Resume closes the pause menu", not game.pause_menu.is_open())

	# --- Settings: volume and key rebinding ---
	Settings.set_value("sfx_volume", 0.5)
	var sfx_bus := AudioServer.get_bus_index("SFX")
	_check("the SFX volume setting drives the SFX bus", absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.5)) < 0.01)
	Settings.rebind("jump", KEY_K)
	_check("a rebound key shows in the controls list", Settings.key_name("jump") == "K", Settings.key_name("jump"))
	Settings.reset_controls()
	_check("reset controls restores the default key", Settings.key_name("jump") != "K", Settings.key_name("jump"))
	Settings.set_value("sfx_volume", 0.9)

	# --- Placeholder architecture: sounds and effects are swappable nodes ---
	var sounds_ok := true
	for sound in ["hit", "pogo", "hurt", "death", "save", "spawn", "break", "secret", "relic", "boss_roar", "victory", "ui_move", "ui_confirm"]:
		var node := Sfx.get_node_or_null(sound) as AudioStreamPlayer
		sounds_ok = sounds_ok and node != null and node.stream != null and node.bus == &"SFX"
	_check("every sound is its own AudioStreamPlayer node with a stream", sounds_ok)
	var fx: FxPlayer = game.effects.play("hit_spark", Vector2(300, 300))
	_check("effects are scenes played by name", fx != null and fx.get_child_count() > 0 and fx.is_inside_tree())
	await _frames(int(fx.lifetime * 60.0) + 10)
	_check("a finished effect frees itself", not is_instance_valid(fx))
	var anims_ok := true
	for kind in ["weak", "flyer", "strong", "boss"]:
		var e: Enemy = game.ENEMY_SCENES[kind].instantiate()
		var ap := e.get_node("AnimationPlayer") as AnimationPlayer
		anims_ok = anims_ok and ap.has_animation("spawn") and ap.has_animation("dead") and e.has_node("Flip/Rig")
		if kind == "boss":
			anims_ok = anims_ok and ap.has_animation("roar") and ap.has_animation("dissolve")
		e.free()
	_check("enemy visuals are rig + AnimationPlayer clips (spawn, dead, roar, dissolve)", anims_ok)
	var pap := p.get_node("AnimationPlayer") as AnimationPlayer
	_check("the player has trance and dying clips", pap.has_animation("trance") and pap.has_animation("dying"))

	# --- HUD shows the bound hotkeys on the ability slots ---
	_check("HUD slots show keys 1-4 by default", game.hud.hotkey_label(0) == "1" and game.hud.hotkey_label(3) == "4",
		[game.hud.hotkey_label(0), game.hud.hotkey_label(3)])
	Settings.rebind("ult_1", KEY_Q)
	_check("HUD slot follows a rebound key", game.hud.hotkey_label(0) == "Q", game.hud.hotkey_label(0))
	Settings.reset_controls()

	# --- The pause menu has no path to the inventory ---
	var has_inventory_button := false
	for b in game.pause_menu.find_children("*", "Button", true, false):
		has_inventory_button = has_inventory_button or (b as Button).text.contains("Inventory")
	_check("the pause menu has no Inventory option", not has_inventory_button)

	# --- Debug overlay and toggles ---
	Input.action_press(&"toggle_debug")
	await _frames(2)
	Input.action_release(&"toggle_debug")
	_check("debug overlay opens", game.debug_overlay.panel.visible)
	_check("stats visible while debug overlay is open", Config.stats_visible())
	Input.action_press(&"debug_navigate")
	await _frames(2)
	Input.action_release(&"debug_navigate")
	var dbg_focus := get_viewport().gui_get_focus_owner()
	var nav_x := p.global_position.x
	Input.action_press(&"move_right")
	await _frames(10)
	Input.action_release(&"move_right")
	_check("debug overlay keyboard mode focuses controls and pauses",
		game.debug_overlay.navigating and dbg_focus != null and game.debug_overlay.panel.is_ancestor_of(dbg_focus)
		and is_equal_approx(p.global_position.x, nav_x), dbg_focus)
	Input.action_press(&"debug_navigate")
	await _frames(2)
	Input.action_release(&"debug_navigate")
	_check("debug keyboard mode exits", not game.debug_overlay.navigating)
	Config.upgrades.double_jump = false
	await _reset()
	Input.action_press(&"jump")
	await _frames(15)
	Input.action_release(&"jump")
	await _frames(3)
	Input.action_press(&"jump")
	await _frames(2)
	_check("double jump toggle respected", p.air_jumps_used == 0, p.air_jumps_used)
	Input.action_release(&"jump")
	game.restore_defaults()

	# --- Title screen: Play -> slot select, Settings (keyboard and mouse) ---
	game.queue_free()
	await _frames(3)
	var title: TitleScreen = load("res://scenes/title.tscn").instantiate()
	title.change_scene = false
	add_child(title)
	await _frames(3)
	_check("the title screen focuses Play", get_viewport().gui_get_focus_owner() == title.play_button)
	await _ui_action(&"ui_down")
	_check("arrow keys move between title buttons", get_viewport().gui_get_focus_owner() == title.settings_button)
	await _ui_action(&"ui_accept")
	_check("Enter on Settings opens the settings", title.settings.visible and not title.main_panel.visible)
	await _ui_action(&"ui_cancel")
	_check("Esc leaves the settings", title.main_panel.visible and not title.settings.visible)
	await _ui_action(&"ui_down")
	await _ui_action(&"ui_accept")
	await _ui_action(&"ui_up")
	_check("Up from the first setting wraps to Back", get_viewport().gui_get_focus_owner() == title.settings.back_button,
		get_viewport().gui_get_focus_owner())
	await _ui_action(&"ui_down")
	_check("Down from Back wraps to the first setting", get_viewport().gui_get_focus_owner() == title.settings._first)
	for i in 40:
		await _ui_action(&"ui_down")
		if get_viewport().gui_get_focus_owner() == title.settings.back_button:
			break
	_check("Down alone reaches the last button (Back) in the settings", get_viewport().gui_get_focus_owner() == title.settings.back_button)
	await _ui_action(&"ui_cancel")
	_check("leaving the settings focuses Play again", get_viewport().gui_get_focus_owner() == title.play_button)
	await _ui_action(&"ui_accept")
	_check("Play opens the slot select with 5 slots", title.slots_panel.visible and title.slot_buttons.size() == 5)
	_check("used slots show their summary", title.slot_buttons[0].text.contains("Testing Halls"), title.slot_buttons[0].text)
	var labels_ok := true
	for b in title.slot_buttons:
		labels_ok = labels_ok and not b.text.contains("Slot")
	Saves.delete_slot(4)
	title.refresh_slots()
	_check("slots carry no 'Slot N' label; an empty slot reads New Game", labels_ok and title.slot_buttons[4].text == "New Game",
		title.slot_buttons[4].text)
	await _ui_action(&"ui_cancel")
	_check("Esc returns from the slot select", title.main_panel.visible and not title.slots_panel.visible)
	await _click(title.settings_button)
	_check("a mouse click opens the settings", title.settings.visible)
	await _ui_action(&"ui_cancel")
	await _click(title.play_button)
	_check("a mouse click on Play opens the slot select", title.slots_panel.visible)
	await _click(title.slot_buttons[2])
	_check("a mouse click chooses a save slot", title.chosen_slot == 2 and Saves.active_slot == 2, title.chosen_slot)
	Saves.active_slot = -1
	title.queue_free()
	for i in Saves.SLOT_COUNT:
		Saves.delete_slot(i)

	print("\nSMOKE TEST: %d passed, %d failed" % [passed, failures.size()])
	for f in failures:
		print("  FAIL ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _jump_height(hold_frames: int) -> float:
	await _reset()
	var p: Player = game.player
	var start_y := p.global_position.y
	var min_y := start_y
	Input.action_press(&"jump")
	for i in 80:
		if i == hold_frames:
			Input.action_release(&"jump")
		await _frames(1)
		min_y = minf(min_y, p.global_position.y)
	Input.action_release(&"jump")
	await _frames(30)
	return start_y - min_y


func _reset() -> void:
	# Deterministic start: test room, start checkpoint, no dialogue/menus open.
	if game.room_id != "test_room":
		game.load_room("test_room", "east")
	for cp in game.checkpoints:
		if cp.is_start:
			game.activate_checkpoint(cp, false)
	if game.dialogue.is_open():
		game.dialogue.close()
	if game.inventory.is_open():
		game.inventory.toggle()
	game.reset_room()
	await _frames(20)


func _find_object(node_name: String) -> Node:
	return game.room.get_node("Objects/" + node_name)


func _close_dialogue() -> void:
	for i in 60:
		if not game.dialogue.is_open():
			return
		Input.action_press(&"interact")
		await _frames(2)
		Input.action_release(&"interact")
		await _frames(1)


## Sends a GUI/menu action press + release, like a key on the keyboard.
func _ui_action(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(1)
	await _frames(1)


## Moves keyboard focus onto the grid card of `ability_id` using arrows only.
func _focus_pool_card(inv: InventoryMenu, ability_id: String) -> void:
	if not get_viewport().gui_get_focus_owner() in inv.pool_cards:
		await _ui_action(&"ui_down")
	for i in 6:
		await _ui_action(&"ui_left")
	for i in 6:
		var f := get_viewport().gui_get_focus_owner() as AbilityCard
		if f and f.ability and f.ability.id == ability_id:
			return
		await _ui_action(&"ui_right")


func _door(door_id: String) -> Door:
	for d in game.doors:
		if d.door_id == door_id:
			return d
	return null


func _first_enemy(flying: bool) -> DummyEnemy:
	for e in game.enemies:
		if e is DummyEnemy and e.tier == "weak" and e.flying == flying:
			return e
	return null


func _enemy_by_id(spawn_id: String) -> Enemy:
	for e in game.enemies:
		if e.spawn_id == spawn_id:
			return e
	return null


## Waits for the death animation and the fade back to the checkpoint.
func _await_respawn() -> void:
	var p: Player = game.player
	for i in 300:
		await _frames(1)
		if p.state_name() == "trance" and game.transition.is_empty():
			break
	await _frames(2)


## Left mouse click in the middle of a control.
func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	await _frames(1)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.pressed = pressed
		get_viewport().push_input(ev, true)
		await _frames(1)
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		passed += 1
		print("  ok   ", label)
	else:
		failures.append("%s (%s)" % [label, str(detail)])
		print("  FAIL ", label, "  -> ", detail)
