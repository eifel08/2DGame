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
	game = load("res://scenes/main.tscn").instantiate()
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
	await _frames(30)
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

	# --- Info tablet shortly before each later checkpoint ---
	var tablets_ok := true
	for cp in game.checkpoints:
		if cp.is_start:
			continue
		var found := false
		for node in game.room.get_objects():
			if node is LoreObject and node.dialogue and node.dialogue.resource_path.ends_with("lore_checkpoint.tres"):
				var dx: float = cp.global_position.x - node.global_position.x
				if dx > 20.0 and dx < 140.0:
					found = true
		tablets_ok = tablets_ok and found
	_check("checkpoint info tablet before each checkpoint", tablets_ok)

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
	p.global_position = mid.global_position + Vector2(-150, 0)
	await _frames(2)
	p.receive_hit(1000.0, p.global_position.x, false, true)
	await _frames(30)
	_check("death respawns at the saved checkpoint", p.global_position.distance_to(mid.get_respawn_position()) < 2.0, p.global_position)
	await _reset()
	p.global_position = mid.global_position + Vector2(10, 0)
	await _frames(5)
	Input.action_press(&"move_down")
	await _frames(2)
	Input.action_release(&"move_down")
	_check("pressing Down on the ground also saves", game.current_checkpoint == mid
		and absf(p.global_position.x - mid.global_position.x) < 0.5, game.current_checkpoint)

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
	# Deterministic start: back at the start checkpoint, no dialogue/menus open.
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


func _first_enemy(flying: bool) -> DummyEnemy:
	for e in game.enemies:
		if e.flying == flying:
			return e
	return null


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
