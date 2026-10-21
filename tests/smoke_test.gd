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

	# --- New spells: Repulse Aegis, Stasis Field, Radiant Lance, Meteor Slam ---
	await _test_new_spells()

	# --- Spell pool and slot capacity (debug overlay) ---
	await _test_spell_management()

	# --- Meteor Slam ground hop, Stasis cost, camera look up / down ---
	await _test_slam_hop_and_look()

	# --- Secret walls: Type 1 hidden pockets (incl. camera limits), Type 2 secret doorways ---
	await _test_secret_walls()

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

	# --- Debug God Mode: hazards still teleport, but deal no damage ---
	await _reset()
	Config.upgrades.god_mode = true
	p.global_position = Vector2(pit_left - 100.0, p.global_position.y)
	await _frames(10)
	var hp_god := p.health.health
	p.global_position = Vector2(pit_left + 40.0, 22.0 * 32.0 - 2.0) # Drop straight into the spikes.
	await _frames(20)
	_check("God Mode hazard touch still teleports out", p.global_position.x < pit_left, p.global_position)
	_check("God Mode (debug) blocks hazard damage", is_equal_approx(p.health.health, hp_god), p.health.health)
	Config.upgrades.god_mode = false

	# --- Three damage sources: hazards ignore i-frames, enemies and projectiles do not ---
	await _test_damage_sources(pit_left)

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
	_check("inventory shows swap restriction", game.inventory.pool_grid.get_child_count() == game.ultimates.unlocked_abilities().size() and game.inventory.notice_label.text.contains("only"), game.inventory.notice_label.text)
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
	for rid in ["test_room", "boss_room", "arena_room", "secret_room", "upper_room", "hidden_vault"]:
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
		# The camera limits: the room's normal area plus any found hidden pocket,
		# never beyond the room's tiles.
		var bounds: Rect2 = game.camera.bounds
		_check("%s: camera limits lie within the room's tiles" % rid,
			game.room.get_full_bounds().grow(0.5).encloses(bounds) and bounds.encloses(game.room.get_bounds()), [bounds, game.room.get_full_bounds()])
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
	var gap_floor_y: float = floor_gap.global_position.y - 64.0 # Top of the 2-tile floor.
	var gap_mid: float = floor_gap.global_position.x
	_check("Rule B: you emerge at the threshold inside the floor gap, not on the floor",
		p.state_name() == "eject" and p.global_position.x > floor_gap.gap_left() and p.global_position.x < floor_gap.gap_right()
		and p.global_position.y > gap_floor_y and not floor_gap.get_trigger_rect().intersects(p.get_rect()),
		[p.state_name(), p.global_position, gap_floor_y])
	_check("Rule B: the ejection is not invulnerable", not p.health.is_invulnerable(), p.health.invuln_flags.keys())
	var target: Vector2 = game.last_ejection.target
	var side: float = game.last_ejection.side
	var path: Array[Vector2] = [p.global_position]
	for i in 120:
		await _frames(1)
		path.append(p.global_position)
		if p.state_name() != "eject":
			break
	var cleared_in_gap := false # Feet above the floor while still over the gap: it climbed out.
	var apex := INF
	var mid_air := false # A point between the gap edge and the landing spot, in the air.
	var backwards := false # Never drifts back toward the gap once moving sideways.
	var edge: float = floor_gap.gap_left() if side < 0 else floor_gap.gap_right()
	for i in path.size():
		var q: Vector2 = path[i]
		apex = minf(apex, q.y)
		if q.y < gap_floor_y and absf(q.x - gap_mid) < floor_gap.trigger_size.x / 2.0:
			cleared_in_gap = true
		if q.y < gap_floor_y - 10.0 and side * (q.x - edge) > 0.0 and side * (target.x - q.x) > 4.0:
			mid_air = true
		if i > 0 and side * (q.x - path[i - 1].x) < -0.01:
			backwards = true
	_check("Rule B: the player climbs out through the gap", cleared_in_gap, path.slice(0, 6))
	_check("Rule B: an arc launches the player up above the floor", gap_floor_y - apex >= 40.0, gap_floor_y - apex)
	_check("Rule B: the arc crosses the space between the gap and the landing spot",
		mid_air and not backwards and path.size() > 12, [mid_air, backwards, path.size()])
	_check("Rule B: with no input you land on the floor beside the gap, not back in it",
		p.grounded and p.state_name() == "normal" and game.room_id == "upper_room" and absf(p.global_position.y - gap_floor_y) < 1.0
		and side * (p.global_position.x - edge) >= Player.WIDTH / 2.0, [p.global_position, game.room_id])
	# Both sides of this gap are standable, so the side is random: both must occur.
	var sides_seen := {}
	for i in 24:
		game.load_room("upper_room", "floor", 0.0, Vector2(0, -500))
		sides_seen[float(game.last_ejection.side)] = true
		floor_gap = _door("floor")
	_check("Rule B: with floor on both sides, either side can be chosen", sides_seen.has(-1.0) and sides_seen.has(1.0), sides_seen)
	await _frames(60)
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
	# Rule A: wherever along the ceiling gap you drop in, you land on solid ground.
	var rule_a := true
	var landed_at := []
	for along in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		game.load_room("test_room", "ceiling", along, Vector2(0, 100))
		for i in 60:
			await _frames(1)
			if p.grounded:
				break
		landed_at.append(p.global_position)
		rule_a = rule_a and p.grounded and absf(p.global_position.y - wall_top.y) < 2.0 and game.room_id == "test_room"
	_check("Rule A: every point of the downward exit has ground right below it", rule_a, landed_at)
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
	var gate_sounds := Sfx.count("gate")
	var fx_before: Dictionary = game.effects.play_counts.duplicate()
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
	var new_fx := []
	for fx_name in game.effects.play_counts:
		if game.effects.play_counts[fx_name] > fx_before.get(fx_name, 0) and not fx_name in ["enemy_death", "spawn_portal", "coin_pickup", "hit_spark"]:
			new_fx.append(fx_name)
	_check("clearing an arena is silent apart from the gates: no fanfare, effect or text",
		Sfx.count("gate") > gate_sounds and Sfx.count("victory") == 0 and new_fx.is_empty(), new_fx)
	game.load_room("boss_room", "east")
	game.load_room("arena_room", "west")
	await _frames(3)
	p.global_position = Vector2(20 * 32, 512)
	await _frames(30)
	_check("a cleared arena room stays cleared", grounds.state == "cleared" and game.enemies.is_empty(), [grounds.state, game.enemies.size()])
	await _frames(60)

	# --- Rule C: the secret wall works while the arena locks every other door ---
	game.new_game()
	Config.upgrades.god_mode = true
	game.load_room("arena_room", "west")
	await _frames(30)
	p.global_position = Vector2(20 * 32, 512)
	for i in 60:
		await _frames(1)
		if game.arena_director.is_active():
			break
	var secret_door: Door = _door("east")
	_check("Rule C: during the arena, normal doors lock but the secret door does not",
		game.arena_director.is_active() and _door("west").locked and secret_door.secret and not secret_door.locked)
	var arena_wall: BreakableWall = game.breakables[0]
	p.global_position = Vector2(arena_wall.get_rect().position.x - 24.0, 512)
	p.facing = 1
	await _frames(3)
	for i in 3:
		Input.action_press(&"attack")
		await _frames(3)
		Input.action_release(&"attack")
		await _frames(30)
		p.global_position = Vector2(arena_wall.get_rect().position.x - 24.0, 512)
		p.facing = 1
	_check("Rule C: the secret wall breaks during an active arena", not arena_wall.intact and game.arena_director.is_active())
	Input.action_press(&"move_right")
	for i in 60:
		await _frames(1)
		if game.room_id == "secret_room":
			break
	Input.action_release(&"move_right")
	_check("Rule C: the secret exit can be used to leave mid-fight", game.room_id == "secret_room", game.room_id)
	game.load_room("arena_room", "east")
	await _frames(3)
	_check("leaving mid-fight leaves the arena uncleared, ready to retry",
		not game.world.is_arena_cleared("proving_grounds") and not game.arena_director.is_active() and not game.breakables[0].intact)
	# Back to the state the next block expects: arena cleared, wall intact.
	game.new_game()
	game.world.clear_arena("proving_grounds")
	game.load_room("arena_room", "west")
	await _frames(5)

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
	for sound in ["hit", "pogo", "hurt", "death", "save", "spawn", "break", "pickup", "gate", "boss_roar", "ui_move", "ui_confirm"]:
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

	# --- No celebrations anywhere (GUIDELINES.md, Rule D) ---
	var celebration_assets := []
	for sound in ["victory", "fanfare", "secret", "relic", "jingle"]:
		if Sfx.get_node_or_null(sound) != null:
			celebration_assets.append("sound " + sound)
	for fx_name in ["arena_clear", "boss_death", "victory"]:
		if ResourceLoader.exists("res://effects/fx/%s.tscn" % fx_name):
			celebration_assets.append("effect " + fx_name)
	for flare in ["wall_break", "relic_pickup"]:
		var scene_root: Node = load("res://effects/fx/%s.tscn" % flare).instantiate()
		for child in scene_root.get_children():
			if child is RingPlaceholder:
				celebration_assets.append("flash ring in " + flare)
		scene_root.free()
	_check("no celebration sounds, effects or flashes exist (bosses, arenas, secrets, relics)", celebration_assets.is_empty(), celebration_assets)
	_check("the HUD has no pop-up text system", not "banner_text" in game.hud and not game.hud.has_method("show_banner"))
	_check("the secret and relic sounds play nothing celebratory", Sfx.count("victory") == 0 and Sfx.count("secret") == 0 and Sfx.count("relic") == 0)

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


func _test_new_spells() -> void:
	var p: Player = game.player
	var data: PlayerData = game.player_data
	var loadout := data.equipped.duplicate()
	_check("eight spells are registered and known from the start",
		game.ultimates.abilities.size() == 8 and data.unlocked.size() == 8, data.unlocked)

	# Repulse Aegis: a parry. Consumes all energy, a tiny window, enemy contact only.
	await _reset()
	var aegis: RepulseAegis = game.ultimates.get_ability("repulse_aegis")
	var window: float = Config.ultimates.repulse_aegis.window
	_check("aegis is a tight parry (no wind-up, a short window)",
		is_zero_approx(Config.ultimates.repulse_aegis.cast_time) and window <= 0.25, window)
	p.health.set_energy(10.0)
	await _cast_slot0("repulse_aegis")
	_check("aegis refused below its threshold", is_equal_approx(p.health.energy, 10.0) and not aegis.is_running, p.health.energy)
	var striker: DummyEnemy = game.spawn_enemy_kind("strong", p.global_position + Vector2(200, 0))
	striker.patrol = false
	await _frames(3)
	p.health.set_energy(80.0)
	await _cast_slot0("repulse_aegis")
	_check("aegis consumes all energy", is_zero_approx(p.health.energy) and is_equal_approx(aegis.consumed, 80.0), [p.health.energy, aegis.consumed])
	await _frames(1)
	_check("aegis window opens at once (within a few frames)", aegis.is_running and p.hit_guards.has(RepulseAegis.GUARD_ID))
	var striker_hp := striker.health
	p.global_position = striker.global_position # Contact right inside the window.
	await _frames(2)
	_check("a well-timed aegis negates contact damage", is_equal_approx(p.health.health, p.health.get_max_health()) and aegis.countered, p.health.health)
	_check("aegis strikes back with one and a half times the energy",
		is_equal_approx(aegis.last_reflected, 120.0) and is_equal_approx(striker_hp - striker.health, minf(120.0, striker_hp)),
		[aegis.last_reflected, striker_hp, striker.health])
	_check("aegis is spent after one counter", not aegis.is_running and p.hit_guards.is_empty())

	# Too early: the window closes before contact, the energy is gone, the hit lands.
	await _reset()
	var late: DummyEnemy = game.spawn_enemy_kind("strong", p.global_position + Vector2(200, 0))
	late.patrol = false
	await _frames(3)
	p.health.set_energy(80.0)
	await _cast_slot0("repulse_aegis")
	await _frames(int(ceil(window * 60.0)) + 4)
	_check("the aegis window closes quickly", not aegis.is_running and not aegis.countered and is_zero_approx(p.health.energy), aegis.remaining)
	p.global_position = late.global_position
	await _frames(2)
	_check("a mistimed aegis does not protect", p.health.health < p.health.get_max_health(), p.health.health)

	# Very short range: an enemy a hair from the body triggers it, one a step away does not.
	await _reset()
	var near: DummyEnemy = game.spawn_enemy_kind("strong", p.global_position + Vector2(200, 0))
	near.patrol = false
	await _frames(3)
	var touch_x: float = near.global_position.x - near.size.x / 2.0 - Player.WIDTH / 2.0
	p.global_position = Vector2(touch_x - 30.0, near.global_position.y)
	p.health.set_energy(50.0)
	await _cast_slot0("repulse_aegis")
	await _frames(int(ceil(window * 60.0)) + 4)
	_check("aegis does not reach an enemy a step away", not aegis.countered and is_equal_approx(near.health, near.max_health), near.health)
	p.global_position = Vector2(touch_x - 3.0, near.global_position.y)
	p.health.set_energy(50.0)
	await _cast_slot0("repulse_aegis")
	await _frames(2)
	_check("aegis counters an enemy at the player's skin", aegis.countered and near.health < near.max_health, near.health)

	# No projectile repel: a projectile hurts as usual during the window.
	await _reset()
	p.health.set_energy(40.0)
	await _cast_slot0("repulse_aegis")
	game.combat.projectiles.spawn({"position": p.get_center() + Vector2(14, 0), "velocity": Vector2(-200, 0), "hostile": true, "damage": 20.0})
	await _frames(3)
	_check("aegis does not block projectiles",
		is_equal_approx(p.health.health, p.health.get_max_health() - 20.0) and not aegis.countered, [p.health.health, aegis.countered])

	# Stasis Field: a short-range, short emergency freeze.
	await _reset()
	var stasis: StasisField = game.ultimates.get_ability("stasis_field")
	var sf: Dictionary = Config.ultimates.stasis_field
	_check("stasis is tuned as a quick emergency tool", sf.radius <= 100.0 and sf.duration <= 1.0 and sf.cast_time <= 0.1, sf)
	var frozen: DummyEnemy = _first_enemy(false)
	p.global_position = frozen.global_position + Vector2(-60, 0)
	p.health.set_energy(100.0)
	var far: Enemy = game.spawn_enemy_kind("weak", p.global_position + Vector2(-200, 0))
	game.combat.projectiles.spawn({"position": p.get_center() + Vector2(0, -60), "velocity": Vector2(0, -20), "hostile": true, "life": 9.0})
	await _cast_slot0("stasis_field")
	await _frames(3)
	_check("stasis spends its cost", is_equal_approx(p.health.energy, 100.0 - sf.cost), p.health.energy)
	var frozen_at := frozen.global_position
	var shot: Dictionary = game.combat.projectiles.list[0] if not game.combat.projectiles.list.is_empty() else {}
	var shot_at: Vector2 = shot.get("pos", Vector2.ZERO)
	await _frames(20)
	_check("stasis freezes enemies right next to the player", frozen.is_frozen() and frozen.global_position == frozen_at and stasis.frozen_enemies >= 1,
		[frozen.freeze_timer, frozen_at, frozen.global_position])
	_check("frozen enemies deal no contact damage", not frozen.deals_contact_damage())
	_check("stasis freezes projectiles in range", stasis.frozen_projectiles == 1 and shot.get("pos") == shot_at, [stasis.frozen_projectiles, shot_at, shot.get("pos")])
	_check("stasis is short-range: an enemy a few steps away is not frozen", not far.is_frozen(), far.global_position)
	await _frames(int(sf.duration * 60.0))
	_check("stasis wears off quickly", not frozen.is_frozen() and not stasis.is_running, frozen.freeze_timer)

	# Radiant Lance: a forward beam that damages; aiming up fires it vertically.
	await _reset()
	var lance: RadiantLance = game.ultimates.get_ability("radiant_lance")
	var beam_target: DummyEnemy = _first_enemy(false)
	beam_target.patrol = false
	await _frames(3)
	p.global_position = beam_target.global_position + Vector2(-160, 0)
	p.facing = 1
	p.health.set_energy(100.0)
	await _cast_slot0("radiant_lance")
	await _frames(20)
	_check("lance spends its cost", is_equal_approx(p.health.energy, 100.0 - Config.ultimates.radiant_lance.cost), p.health.energy)
	_check("lance fires forward and damages", lance.dir == Vector2.RIGHT and beam_target.health < beam_target.max_health, [lance.dir, beam_target.health])
	await _frames(30)
	p.health.set_energy(100.0)
	Input.action_press(&"move_up")
	await _cast_slot0("radiant_lance")
	await _frames(16)
	var rect := lance.beam_rect()
	Input.action_release(&"move_up")
	_check("lance aims straight up while holding up", lance.dir == Vector2.UP and rect.size.y > rect.size.x, [lance.dir, rect])

	# Meteor Slam: invulnerable dive, then a ground shockwave and landing i-frames.
	await _reset()
	var slam: MeteorSlam = game.ultimates.get_ability("meteor_slam")
	var slam_target: DummyEnemy = _first_enemy(false)
	slam_target.patrol = false
	await _frames(3)
	p.global_position = slam_target.global_position + Vector2(-50, -90)
	p.health.set_energy(100.0)
	var slams := slam.slam_count
	await _cast_slot0("meteor_slam")
	var dive_invulnerable := false
	for i in 30:
		if p.state_name() == "ability":
			dive_invulnerable = p.health.is_invulnerable()
			break
		await _frames(1)
	_check("slam dives with i-frames", dive_invulnerable, p.state_name())
	for i in 60:
		if slam.slam_count > slams:
			break
		await _frames(1)
	_check("slam lands on the ground", slam.slam_count == slams + 1 and p.grounded and p.state_name() == "normal", [slam.slam_count, p.grounded, p.state_name()])
	_check("slam grants landing i-frames", p.health.has_iframes(), p.health.iframe_timer)
	_check("slam shockwave damages nearby enemies", slam_target.health < slam_target.max_health, slam_target.health)

	await _reset()
	data.equipped = loadout
	Events.loadout_changed.emit()


func _test_spell_management() -> void:
	var p: Player = game.player
	var data: PlayerData = game.player_data
	var dbg: DebugOverlay = game.debug_overlay
	var loadout := data.equipped.duplicate()
	await _reset()

	# Capacity: fewer slots empties the extra ones and disables their keys.
	game.ultimates.set_capacity(2)
	_check("capacity limits the usable slots", game.ultimates.slot_count() == 2 and data.equipped[2] == "" and data.equipped[3] == ""
		and game.ultimates.get_slot(2) == null, data.equipped)
	_check("no equipping past the capacity", not game.ultimates.equip(2, "comet_dash"), data.equipped)
	p.health.set_energy(100.0)
	Input.action_press(&"ult_3")
	await _frames(2)
	Input.action_release(&"ult_3")
	_check("a key past the capacity does nothing", is_equal_approx(p.health.energy, 100.0), p.health.energy)
	game.inventory.toggle()
	await _frames(2)
	var shown: int = game.inventory.slot_cards.filter(func(c: Control) -> bool: return c.visible).size()
	game.inventory.toggle()
	_check("the inventory shows only usable slots", shown == 2, shown)

	# More slots than the default: keys 5-8 exist and work.
	game.ultimates.set_capacity(6)
	_check("capacity can grow past four", game.ultimates.equip(5, "stasis_field") and game.ultimates.get_slot(5) != null, data.equipped)
	await _frames(3)
	Input.action_press(&"ult_6")
	await _frames(2)
	Input.action_release(&"ult_6")
	_check("slot six casts with its own key", is_equal_approx(p.health.energy, 100.0 - Config.ultimates.stasis_field.cost), p.health.energy)
	_check("hotkeys 1-8 exist and are rebindable", InputMap.has_action(&"ult_8") and Settings.REBINDABLE.has("ult_8"))
	_check("capacity is saved", int(game.make_save_data().get("slot_capacity", 0)) == 6)
	game.ultimates.set_capacity(99)
	_check("capacity is clamped to the hotkey count", data.slot_capacity == PlayerData.MAX_SLOTS, data.slot_capacity)

	# Known spells: forgetting removes from the pool and the loadout.
	game.ultimates.set_capacity(4)
	game.ultimates.equip(0, "radiant_lance", true)
	game.ultimates.set_known("radiant_lance", false)
	_check("a forgotten spell leaves the pool and its slot",
		not data.is_unlocked("radiant_lance") and data.equipped[0] == "" and not game.ultimates.equip(0, "radiant_lance"), data.equipped)

	# Debug overlay controls drive the same rules.
	dbg.toggle()
	await _frames(2)
	_check("debug overlay lists every spell", dbg._known_checks.size() == game.ultimates.abilities.size())
	_check("debug checkbox mirrors a forgotten spell", not dbg._known_checks["radiant_lance"].button_pressed)
	dbg._known_checks["radiant_lance"].button_pressed = true
	_check("debug checkbox teaches a spell", data.is_unlocked("radiant_lance"))
	dbg._known_checks["meteor_slam"].button_pressed = false
	_check("debug checkbox forgets a spell", not data.is_unlocked("meteor_slam"))
	dbg._capacity_slider.value = 3
	_check("debug slider sets the capacity", data.slot_capacity == 3 and game.ultimates.slot_count() == 3, data.slot_capacity)
	dbg.toggle()

	game.ultimates.set_known("meteor_slam", true)
	game.ultimates.set_capacity(PlayerData.DEFAULT_CAPACITY)
	data.equipped = loadout
	Events.loadout_changed.emit()
	await _reset()


func _test_slam_hop_and_look() -> void:
	var p: Player = game.player
	var cam: CameraRig = game.camera
	_check("stasis field costs double (80 energy)", is_equal_approx(Config.ultimates.stasis_field.cost, 80.0), Config.ultimates.stasis_field.cost)

	# Meteor Slam from the ground: a vulnerable hop first, then the invulnerable dive.
	await _reset()
	var slam: MeteorSlam = game.ultimates.get_ability("meteor_slam")
	var ground_y := p.global_position.y
	_check("slam test starts on the ground", p.grounded)
	p.health.set_energy(100.0)
	var slams := slam.slam_count
	await _cast_slot0("meteor_slam")
	var hop_seen := false
	var hop_vulnerable := true
	var hop_height := 0.0
	var dive_invulnerable := false
	for i in 90:
		if p.state_name() == "ability" and slam.phase == "hop":
			hop_seen = true
			hop_vulnerable = hop_vulnerable and not p.health.is_invulnerable()
			hop_height = maxf(hop_height, ground_y - p.global_position.y)
		elif p.state_name() == "ability" and slam.phase == "dive":
			dive_invulnerable = p.health.is_invulnerable()
		if slam.slam_count > slams:
			break
		await _frames(1)
	_check("a ground cast hops up first", hop_seen and hop_height >= 30.0, hop_height)
	_check("the hop is a vulnerable wind-up", hop_seen and hop_vulnerable)
	_check("after the hop the dive is invulnerable and slams", dive_invulnerable and slam.slam_count == slams + 1
		and p.grounded and absf(p.global_position.y - ground_y) < 1.0, [dive_invulnerable, slam.slam_count, p.global_position.y])

	# A hit during the hop lands and cancels the slam.
	await _reset()
	p.health.set_energy(100.0)
	slams = slam.slam_count
	await _cast_slot0("meteor_slam")
	for i in 10:
		if slam.phase == "hop" and p.state_name() == "ability":
			break
		await _frames(1)
	var hp := p.health.health
	var hit := p.receive_hit(10.0, p.global_position.x + 20.0, false, false, null, Damage.Source.ENEMY)
	await _frames(40)
	_check("a hit during the hop lands and cancels the slam",
		hit and p.health.health < hp and slam.slam_count == slams and not slam.is_running, [hit, p.health.health, slam.slam_count])

	# Camera look: hold Up / Down while standing still; never outside the room.
	await _reset()
	await _frames(40)
	var base_y := cam.global_position.y
	var room_rect: Rect2 = game.room.get_bounds().grow(1.0)
	Input.action_press(&"move_up")
	await _frames(6)
	Input.action_release(&"move_up")
	await _frames(10)
	_check("a quick tap of Up does not move the camera", absf(cam.global_position.y - base_y) < 2.0, cam.global_position.y - base_y)
	Input.action_press(&"move_up")
	var inside := true
	for i in 80:
		await _frames(1)
		inside = inside and room_rect.encloses(cam.view_rect())
	_check("holding Up while standing still looks up", cam.global_position.y < base_y - 60.0, cam.global_position.y - base_y)
	Input.action_press(&"move_right")
	await _frames(40)
	_check("moving stops the look", absf(cam.look_offset) < 10.0, cam.look_offset)
	Input.action_release(&"move_right")
	Input.action_release(&"move_up")
	await _reset()
	await _frames(40)
	base_y = cam.global_position.y
	Input.action_press(&"move_up")
	await _frames(60)
	Input.action_release(&"move_up")
	for i in 90:
		await _frames(1)
		inside = inside and room_rect.encloses(cam.view_rect())
	_check("releasing Up brings the camera back", absf(cam.global_position.y - base_y) < 3.0, cam.global_position.y - base_y)
	# Look down from the top of the central hanging wall.
	p.global_position = Vector2(_door("ceiling").global_position.x, 4.0 * 32.0)
	p.velocity = Vector2.ZERO
	await _frames(40)
	base_y = cam.global_position.y
	Input.action_press(&"move_down")
	for i in 80:
		await _frames(1)
		inside = inside and room_rect.encloses(cam.view_rect())
	Input.action_release(&"move_down")
	_check("holding Down while standing still looks down", cam.global_position.y > base_y + 60.0 and p.grounded, cam.global_position.y - base_y)
	_check("the look never shows anything outside the room", inside)
	await _frames(30)
	await _reset()


func _test_secret_walls() -> void:
	await _test_hidden_pocket()
	await _test_west_pocket_camera()
	await _test_secret_doorway()
	# The two types are documented for designers and AI assistants alike.
	var doc := FileAccess.get_file_as_string("res://GUIDELINES.md")
	var documented := true
	for needle in ["## Secret walls", "Type 1", "Type 2", "Hidden Pocket", "Secret Doorway",
			"HiddenPocketWall", "SecretDoorway", "camera", "semi-transparent", "back and forth"]:
		documented = documented and doc.contains(needle)
	_check("GUIDELINES.md documents both secret wall types", documented)


## Type 1 in the Upper Galleries: the alcove under the east block.
func _test_hidden_pocket() -> void:
	var p: Player = game.player
	game.world.secrets.erase("galleries_alcove")
	var wall := await _enter_galleries(-120.0)
	_check("the Upper Galleries have a Type 1 hidden pocket", wall != null and wall.secret_id == "galleries_alcove" and wall.pass_dir == 1)
	if wall == null:
		return
	var visual := wall.get_node("Visual") as CanvasItem
	_check("Type 1 placeholder wall is drawn at 50% opacity", is_equal_approx(visual.modulate.a, 0.5) and visual.visible, visual.modulate)
	_check("Type 1 is not a tile (no attack or tile collision involved)", not game.room.is_solid_at(wall.get_rect().get_center()))
	_check("enemies always collide with hidden pocket walls",
		game.enemies[0].collision_mask & (1 << (HiddenPocketWall.ENEMY_LAYER - 1)) != 0
		and p.collision_mask & (1 << (HiddenPocketWall.PLAYER_LAYER - 1)) != 0)
	# Everything inside the pocket is covered until it is found.
	var cover := wall.get_node("Cover") as Node2D
	var inside := []
	for c in game.coins:
		if wall.pocket_rect.has_point(c.global_position - Vector2(0, 4)):
			inside.append(c.name)
	var spawn_inside := false
	for sp in game.room.get_enemy_spawns():
		spawn_inside = spawn_inside or wall.pocket_rect.has_point(sp.position - Vector2(0, 4))
	_check("the pocket holds shards and an enemy", inside.size() == 2 and spawn_inside, [inside, wall.pocket_rect])
	_check("an unfound pocket is covered: its shards and enemies are hidden",
		wall.is_covered() and cover.z_index > 2 and cover.get_child_count() >= 6, [cover.z_index, cover.get_child_count()])
	var left_edge := wall.get_rect().position.x
	var right_edge := wall.get_rect().end.x

	# Unfound and approached from the pocket side: solid.
	await _place_galleries(wall, 70.0)
	await _hold(&"move_left", 45)
	_check("an unfound pocket wall is solid from the pocket side",
		p.global_position.x >= right_edge + Player.WIDTH / 2.0 - 1.0 and wall.player_blocked and not wall.discovered, p.global_position)

	# From the entry side: walk straight through, no attack. Found for good.
	var found := []
	var on_found := func(id: String) -> void: found.append(id)
	Events.hidden_pocket_found.connect(on_found)
	await _place_galleries(wall, -90.0)
	var hp := p.health.health
	var fx_before: Dictionary = game.effects.play_counts.duplicate()
	var passed_inside := false
	Input.action_press(&"move_right")
	for i in 60:
		await _frames(1)
		passed_inside = passed_inside or wall.get_rect().intersects(p.get_rect())
		if p.global_position.x > right_edge + Player.WIDTH:
			break
	Input.action_release(&"move_right")
	Events.hidden_pocket_found.disconnect(on_found)
	_check("the player walks through a Type 1 wall from the entry side",
		passed_inside and p.global_position.x > right_edge + Player.WIDTH / 2.0 and p.attack_dir == "" and is_equal_approx(p.health.health, hp), p.global_position)
	_check("passing through finds the pocket and saves it",
		wall.discovered and game.world.is_secret_open("galleries_alcove") and found == ["galleries_alcove"], [wall.discovered, found])
	_check("a found pocket is permanently un-hidden (wall and cover gone)", not wall.is_covered() and not visual.visible)
	_check("finding a pocket plays no effect (Rule D)", game.effects.play_counts == fx_before, game.effects.play_counts)
	await _hold(&"move_left", 45)
	_check("a found pocket wall is passable both ways", p.global_position.x < left_edge - Player.WIDTH / 2.0, p.global_position)

	# Room transition: it stays revealed.
	game.load_room("test_room", "ceiling", 0.0, Vector2(0, 100))
	await _frames(20)
	wall = await _enter_galleries(70.0)
	_check("after a room transition the pocket is still revealed", wall.discovered and not wall.is_covered() and not wall.player_blocked)
	await _hold(&"move_left", 45)
	_check("after a room transition its wall is still open", p.global_position.x < wall.get_rect().position.x - Player.WIDTH / 2.0, p.global_position)

	# Save data: lost on a new game, restored by loading the save.
	var data: Dictionary = game.make_save_data()
	_check("the save file lists the found pocket", (data.secrets as Array).has("galleries_alcove"), data.secrets)
	game.world.new_game()
	wall = await _enter_galleries(70.0)
	_check("without the save it is hidden again (sanity check)", not wall.discovered and wall.is_covered())
	game.apply_save_data(data)
	await _frames(5)
	wall = await _enter_galleries(70.0)
	_check("loading the save restores the revealed pocket", wall.discovered and not wall.is_covered() and not wall.player_blocked)
	await _reset()


## Type 1 beyond the room's normal area: the Testing Halls' west pocket.
## The camera may not scroll there until the player has broken through.
func _test_west_pocket_camera() -> void:
	var p: Player = game.player
	var cam: CameraRig = game.camera
	game.world.secrets.erase("halls_west_alcove")
	game.load_room("test_room")
	var wall: HiddenPocketWall = game.hidden_pockets[0] if not game.hidden_pockets.is_empty() else null
	_check("the Testing Halls have a west Type 1 pocket", wall != null and wall.secret_id == "halls_west_alcove" and wall.pass_dir == -1)
	if wall == null:
		return
	var floor_y: float = wall.global_position.y
	_check("the west pocket lies outside the room's normal area",
		is_zero_approx(game.room.get_bounds().position.x) and game.room.get_full_bounds().position.x < 0.0
		and wall.pocket_rect.end.x <= 0.0 and wall.is_covered(), [game.room.get_bounds(), wall.pocket_rect])
	_check("unfound, the camera limits stop at the normal room edge", is_zero_approx(cam.bounds.position.x), cam.bounds)
	p.fsm.change("normal")
	p.global_position = Vector2(60.0, floor_y)
	p.velocity = Vector2.ZERO
	cam.snap_to(p)
	await _frames(30)
	_check("standing at the west wall, the camera shows nothing left of the room", cam.view_rect().position.x >= -0.5, cam.view_rect())

	# From inside the pocket (unfound): solid toward the room.
	p.global_position = Vector2(wall.pocket_rect.get_center().x, floor_y)
	p.velocity = Vector2.ZERO
	await _frames(8)
	await _hold(&"move_right", 45)
	_check("the unfound west wall is solid from the pocket side",
		p.global_position.x <= wall.get_rect().position.x - Player.WIDTH / 2.0 + 1.0 and not wall.discovered, p.global_position)

	# Break through from the room: found, and the camera may now follow.
	p.global_position = Vector2(90.0, floor_y)
	p.velocity = Vector2.ZERO
	cam.snap_to(p)
	await _frames(8)
	Input.action_press(&"move_left")
	var clamped_while_entering := true
	for i in 90:
		await _frames(1)
		if not wall.discovered:
			clamped_while_entering = clamped_while_entering and cam.view_rect().position.x >= -0.5
		if p.global_position.x < wall.pocket_rect.get_center().x:
			break
	Input.action_release(&"move_left")
	_check("the camera stays clamped until the player breaks through", clamped_while_entering)
	_check("breaking through finds the west pocket", wall.discovered and not wall.is_covered() and game.world.is_secret_open("halls_west_alcove"))
	_check("once found, the camera limits include the pocket", cam.bounds.position.x <= wall.pocket_rect.position.x, cam.bounds)
	await _frames(60)
	var full: Rect2 = game.room.get_full_bounds().grow(1.0)
	_check("the camera scrolls left to show the pocket, never past the tiles",
		cam.view_rect().position.x < 0.0 and full.encloses(cam.view_rect()), cam.view_rect())

	# The reveal is permanent: after leaving and coming back, the camera may still go there.
	game.load_room("upper_room")
	game.load_room("test_room")
	wall = game.hidden_pockets[0]
	_check("after a room transition the west pocket stays found and in camera range",
		wall.discovered and not wall.is_covered() and cam.bounds.position.x <= wall.pocket_rect.position.x, cam.bounds)
	await _reset()


## Type 2 between the Upper Galleries (entry side) and the Hidden Vault (exit side).
func _test_secret_doorway() -> void:
	var p: Player = game.player
	game.load_room("upper_room")
	var doorway: SecretDoorway = game.secret_doorways[0] if not game.secret_doorways.is_empty() else null
	_check("the Upper Galleries have a Type 2 secret doorway", doorway != null and doorway.is_entry())
	if doorway == null:
		return
	var entry := doorway.get_node("EntryVisual") as CanvasItem
	var exit := doorway.get_node("ExitVisual") as CanvasItem
	_check("entry side: semi-transparent", entry.visible and not exit.visible and is_equal_approx(entry.modulate.a, 0.5), entry.modulate)
	_check("a secret doorway has no collision and no tile",
		not game.room.is_solid_at(doorway.get_rect().get_center()) and doorway.find_children("*", "CollisionObject2D").is_empty())
	var secrets_before: int = game.world.secrets.size()
	var trips := 0
	for trip in 2: # Back and forth twice: it never disappears.
		await _walk_galleries_to_vault(doorway)
		if game.room_id != "hidden_vault":
			break
		var back: SecretDoorway = game.secret_doorways[0]
		var exit_visual := back.get_node("ExitVisual") as CanvasItem
		var tiles: TileMapLayer = game.room.tiles
		var wall_cell := tiles.local_to_map(tiles.to_local(back.get_rect().position + Vector2(16, -16)))
		var sprite := exit_visual.get_child(0) as Sprite2D if exit_visual.get_child_count() > 0 else null
		_check("exit side (trip %d): looks exactly like the wall next to it" % (trip + 1),
			not back.is_entry() and exit_visual.visible and is_equal_approx(exit_visual.modulate.a, 1.0)
			and not (back.get_node("EntryVisual") as CanvasItem).visible and sprite != null
			and int(sprite.region_rect.position.x / 32.0) == tiles.get_cell_atlas_coords(wall_cell).x,
			[exit_visual.modulate, sprite.region_rect if sprite else null, tiles.get_cell_atlas_coords(wall_cell)])
		p.global_position = back.global_position + Vector2(-90.0, 0.0)
		p.velocity = Vector2.ZERO
		await _frames(8)
		Input.action_press(&"move_right")
		for i in 90:
			await _frames(1)
			if game.room_id == "upper_room":
				break
		Input.action_release(&"move_right")
		if game.room_id != "upper_room":
			break
		doorway = game.secret_doorways[0]
		trips += 1
	_check("a secret doorway works back and forth, again and again", trips == 2, [trips, game.room_id])
	_check("the entry side stays semi-transparent after use (never consumed)",
		doorway.is_entry() and (doorway.get_node("EntryVisual") as CanvasItem).visible
		and is_equal_approx((doorway.get_node("EntryVisual") as CanvasItem).modulate.a, 0.5))
	_check("a secret doorway is not saved as a found secret", game.world.secrets.size() == secrets_before, game.world.secrets)
	await _reset()


func _walk_galleries_to_vault(doorway: SecretDoorway) -> void:
	var p: Player = game.player
	for e in game.enemies:
		e.kill()
	p.fsm.change("normal")
	p.global_position = doorway.global_position + Vector2(90.0, 0.0)
	p.velocity = Vector2.ZERO
	await _frames(8)
	Input.action_press(&"move_left")
	for i in 90:
		await _frames(1)
		if game.room_id == "hidden_vault":
			break
	Input.action_release(&"move_left")
	await _frames(4)
	_check("walking into the secret doorway enters the Hidden Vault", game.room_id == "hidden_vault", game.room_id)


## Loads the Upper Galleries (no door), clears its enemies and puts the player
## on the floor `dx` px from the hidden pocket wall. Returns the wall.
func _enter_galleries(dx: float) -> HiddenPocketWall:
	game.load_room("upper_room")
	var wall: HiddenPocketWall = game.hidden_pockets[0] if not game.hidden_pockets.is_empty() else null
	if wall:
		await _place_galleries(wall, dx)
	return wall


func _place_galleries(wall: HiddenPocketWall, dx: float) -> void:
	var p: Player = game.player
	for e in game.enemies:
		e.kill()
	p.fsm.change("normal")
	p.global_position = Vector2(wall.global_position.x + dx, wall.global_position.y)
	p.velocity = Vector2.ZERO
	p.health.iframe_timer = 0.0
	await _frames(8)


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(4)


## Damage.Source rules: ENEMY and PROJECTILE respect i-frames; HAZARD never does.
func _test_damage_sources(pit_left: float) -> void:
	var p: Player = game.player
	var hazard_dmg: float = Config.combat.hazard_damage
	var spike_drop := Vector2(pit_left + 40.0, 22.0 * 32.0 - 2.0)

	await _reset()
	p.health.iframe_timer = 2.0
	_check("i-frames block enemies and projectiles but not hazards",
		p.health.blocks(Damage.Source.ENEMY) and p.health.blocks(Damage.Source.PROJECTILE) and not p.health.blocks(Damage.Source.HAZARD))

	# Recent-hit i-frames: spikes still hurt.
	p.global_position = Vector2(pit_left - 100.0, p.global_position.y)
	await _frames(10)
	var hp := p.health.health
	p.health.iframe_timer = 2.0
	p.global_position = spike_drop
	await _frames(20)
	_check("spikes hurt through i-frames from a recent hit",
		is_equal_approx(p.health.health, hp - hazard_dmg) and p.global_position.x < pit_left, [p.health.health, p.global_position])

	# Every invulnerability flag (dash, cast, ability) is ignored by hazards too.
	await _reset()
	p.global_position = Vector2(pit_left - 100.0, p.global_position.y)
	await _frames(10)
	hp = p.health.health
	p.health.set_invulnerable("dash", true)
	p.global_position = spike_drop
	await _frames(20)
	p.health.set_invulnerable("dash", false)
	_check("spikes hurt through dash invulnerability", is_equal_approx(p.health.health, hp - hazard_dmg), p.health.health)

	# Meteor Slam into the spikes: its dive i-frames do not save the player.
	await _reset()
	var slam: MeteorSlam = game.ultimates.get_ability("meteor_slam")
	p.global_position = Vector2(pit_left - 100.0, p.global_position.y)
	await _frames(10)
	hp = p.health.health
	var slams := slam.slam_count
	p.global_position = spike_drop + Vector2(0, -110)
	p.health.set_energy(100.0)
	await _cast_slot0("meteor_slam")
	var dived := false
	for i in 40:
		if p.state_name() == "ability":
			dived = p.health.is_invulnerable()
		if p.health.health < hp:
			break
		await _frames(1)
	await _frames(5)
	_check("meteor slam i-frames do not block spikes",
		dived and is_equal_approx(p.health.health, hp - hazard_dmg) and p.global_position.x < pit_left and slam.slam_count == slams,
		[dived, p.health.health, p.global_position, slam.slam_count])

	# I-frames still protect against enemies...
	await _reset()
	var dummy: DummyEnemy = _first_enemy(false)
	dummy.patrol = false
	await _frames(3)
	hp = p.health.health
	p.health.iframe_timer = 2.0
	p.global_position = dummy.global_position
	await _frames(3)
	_check("i-frames still block enemy contact", is_equal_approx(p.health.health, hp), p.health.health)
	# ...and projectiles (from enemies, or fired by a hazard).
	await _reset()
	hp = p.health.health
	p.health.iframe_timer = 2.0
	game.combat.projectiles.spawn({"position": p.get_center() + Vector2(14, 0), "velocity": Vector2(-200, 0), "hostile": true, "damage": 20.0})
	await _frames(4)
	_check("i-frames still block projectiles", is_equal_approx(p.health.health, hp) and game.combat.projectiles.list.is_empty(), p.health.health)
	p.health.iframe_timer = 0.0
	game.combat.projectiles.spawn({"position": p.get_center() + Vector2(14, 0), "velocity": Vector2(-200, 0), "hostile": true, "damage": 20.0})
	await _frames(4)
	_check("without i-frames a projectile hurts", is_equal_approx(p.health.health, hp - 20.0), p.health.health)
	await _reset()


## Puts an ability in slot 1 (ignoring the checkpoint rule) and presses its key.
func _cast_slot0(ability_id: String) -> void:
	game.ultimates.equip(0, ability_id, true)
	Input.action_press(&"ult_1")
	await _frames(2)
	Input.action_release(&"ult_1")


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
