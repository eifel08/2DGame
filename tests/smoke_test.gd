extends Node
## Headless smoke test. Drives the real game through Input actions and checks
## the core mechanics. Run from the project folder:
##   godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
## Exit code 0 = all checks passed.

var game: Node
var failures: Array[String] = []
var passed := 0


const PLATFORM_SCENE_PATHS := {
	"standard": "res://world/objects/platform.tscn",
	"moving": "res://world/objects/platform_moving.tscn",
	"breakable": "res://world/objects/platform_breakable.tscn",
}
const PEG_SCENE_PATHS := {
	"standard": "res://world/objects/grapple_peg.tscn",
	"moving": "res://world/objects/grapple_peg_moving.tscn",
	"breakable": "res://world/objects/grapple_peg_breakable.tscn",
}

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
	game.tutorials_enabled = false # The popups are checked on their own (_test_tutorials).
	add_child(game)
	await _frames(30)
	var p: Player = game.player

	# --- A new game: low stats, no spells, locked slots, Mana Discharge only ---
	await _test_starting_state()
	await _test_no_movement_at_start()
	_grant_test_kit() # The checks below use the full kit and 100 / 100.
	await _frames(2)
	_check("scrolls of known spells and altars of open slots are gone",
		_objects_of(SpellScroll).all(func(s: SpellScroll) -> bool: return s.collected) and _objects_of(MeditationAltar).all(func(a: MeditationAltar) -> bool: return a.spent))
	await _reset()

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

	# --- Four spells, cast with Spell + a direction ---
	for ult_id in ["nova_burst", "spirit_volley", "ascendant_form", "comet_dash"]:
		await _reset()
		var target: DummyEnemy = _first_enemy(false)
		target.patrol = false
		await _frames(3)
		p.global_position = target.global_position + Vector2(-80, 0)
		p.facing = 1
		p.health.set_energy(100.0)
		var cost: float = Config.ultimates[ult_id].cost
		var slot := PlayerData.SLOT_SIDE if ult_id == "comet_dash" else PlayerData.SLOT_UP
		await _cast_spell(ult_id, slot)
		_check("%s (Spell + %s) spends its cost" % [ult_id, PlayerData.SLOT_NAMES[slot]], is_equal_approx(p.health.energy, 100.0 - cost), p.health.energy)
		await _frames(60)
		if ult_id == "ascendant_form":
			_check("ascendant form buffs the player", p.stat("damage_mul") > 1.0, p.modifiers.keys())
		else:
			_check("%s damages the dummy" % ult_id, target.health < target.max_health, target.health)

	# --- Insufficient energy is refused ---
	await _reset()
	p.health.set_energy(50.0)
	await _cast_spell("ascendant_form")
	_check("a spell is refused without energy", is_equal_approx(p.health.energy, 50.0) and p.state_name() == "normal", p.health.energy)

	# --- New spells: Repulse Aegis, Stasis Field, Radiant Lance, Meteor Slam ---
	await _test_new_spells()

	# --- Spell + direction, the spell pool, Mana Discharge, max stats ---
	await _test_spell_management()

	# --- Meteor Slam ground hop, Stasis cost, camera look up / down ---
	await _test_slam_hop_and_look()

	# --- Grappling hook: aiming, terrain pull, enemy damage + safe stop, cancels ---
	await _test_grapple()

	# --- Grapple pegs: hook-only layer, static hold, swing ---
	await _test_grapple_pegs()

	# --- Ember Crossing: lava, moving / breakable platforms and pegs, a full run ---
	await _test_lava_room()

	# --- Key bindings: no WASD defaults, no duplicates, swap on conflict, Grapple on S ---
	await _test_keybindings()

	# --- Secret walls: Type 1 hidden pockets (incl. camera limits), Type 2 secret doorways ---
	await _test_secret_walls()

	# --- Progression: potions, spell scrolls, meditation altars, saves ---
	await _test_progression()

	# --- Movement items and full-screen tutorial popups ---
	await _test_tutorials()

	# --- Bestiary: BaseEnemy roster, deflect / parry, the testing hall ---
	await _test_bestiary()

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

	# --- Empty slots (0-3 directional spells; Mana Discharge is fixed) ---
	await _reset()
	var loadout: Array = game.player_data.equipped.duplicate()
	await _frames(3)
	_check("the Side slot can be emptied at a checkpoint",
		game.ultimates.unequip(PlayerData.SLOT_SIDE) and game.ultimates.get_slot(PlayerData.SLOT_SIDE) == null)
	_check("loadout has 2 directional spells left", game.player_data.equipped_count() == 2, game.player_data.equipped)
	p.health.set_energy(100.0)
	Input.action_press(&"move_right")
	Input.action_press(&"spell")
	await _frames(2)
	Input.action_release(&"spell")
	Input.action_release(&"move_right")
	_check("Spell + an empty direction does nothing (no fallback to the neutral spell)",
		is_equal_approx(p.health.energy, 100.0) and p.state_name() == "normal", p.health.energy)
	for i in PlayerData.SLOT_COUNT:
		game.ultimates.unequip(i)
	_check("all directional slots can be empty", game.player_data.equipped_count() == 0)
	_check("Mana Discharge can never be removed",
		not game.ultimates.unequip(UltimateManager.NEUTRAL, true) and game.ultimates.get_slot(UltimateManager.NEUTRAL) is ManaDischarge)
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
	var cross: SpellCross = inv.cross
	_check("down enters the spell cross (Up)", get_viewport().gui_get_focus_owner() == cross.card("Up"), get_viewport().gui_get_focus_owner())
	await _ui_action(&"ui_accept")
	_check("confirm on an equipped cross node unequips it", eq[PlayerData.SLOT_UP] == "", eq)
	await _focus_pool_card(inv, "nova_burst")
	await _ui_action(&"ui_accept")
	_check("confirm on a free spell asks for a node (focus: the first empty one)",
		inv.pending_ability_id == "nova_burst" and get_viewport().gui_get_focus_owner() == cross.card("Up"), inv.pending_ability_id)
	await _ui_action(&"ui_accept")
	_check("the spell goes into the chosen slot", eq[PlayerData.SLOT_UP] == "nova_burst" and inv.pending_ability_id == "", eq)
	await _focus_pool_card(inv, "comet_dash")
	await _ui_action(&"ui_accept")
	_check("confirm on an equipped spell in the pool unequips it", eq[PlayerData.SLOT_SIDE] == "", eq)
	await _ui_action(&"ui_accept") # Comet Dash is free now -> choose a node (focus: Left, the empty Side slot).
	_check("an empty Side slot is chosen through the Left card", get_viewport().gui_get_focus_owner() == cross.card("Left"), get_viewport().gui_get_focus_owner())
	await _ui_action(&"ui_down") # Left -> Down (occupied by Meteor Slam).
	await _ui_action(&"ui_accept")
	_check("choosing an occupied node replaces its spell",
		eq[PlayerData.SLOT_DOWN] == "comet_dash" and not eq.has("meteor_slam") and eq[PlayerData.SLOT_SIDE] == "", eq)
	await _focus_pool_card(inv, "stasis_field")
	await _ui_action(&"ui_accept")
	cross.card("Right").grab_focus()
	await _frames(1)
	await _ui_action(&"ui_accept")
	_check("the Right card fills the same Side slot", eq[PlayerData.SLOT_SIDE] == "stasis_field", eq)
	_check("both side cards always show the same spell",
		cross.card("Left").ability == cross.card("Right").ability and cross.card("Left").ability.id == "stasis_field")
	_check("the center card is Mana Discharge", cross.card("Center").ability is ManaDischarge)
	cross.card("Left").grab_focus()
	await _frames(1)
	_check("focusing Left: Left has the focus frame, Right a dim mirror frame",
		cross.card("Left").has_focus() and cross.card("Right").mirror and not cross.card("Left").mirror)
	await _ui_action(&"ui_right") # Left -> Center
	_check("focusing the center: no mirror frames", cross.card("Center").has_focus() and not cross.card("Left").mirror and not cross.card("Right").mirror)
	await _ui_action(&"ui_right") # Center -> Right
	_check("focusing Right: Left gets the mirror frame", cross.card("Right").has_focus() and cross.card("Left").mirror and not cross.card("Right").mirror)
	_check("the mirror frame is dimmer than the focus frame", AbilityCard.MIRROR_COLOR.a < AbilityCard.FOCUS_COLOR.a)
	var before_center := eq.duplicate()
	cross.card("Center").grab_focus()
	await _frames(1)
	await _ui_action(&"ui_accept")
	await _ui_action(&"menu_clear")
	_check("Mana Discharge (center) cannot be removed or replaced", eq == before_center and game.ultimates.get_slot(UltimateManager.NEUTRAL) is ManaDischarge, eq)
	var pool_ids := inv.pool_cards.map(func(c: AbilityCard) -> String: return c.ability.id)
	_check("Mana Discharge is not in the pool of equippable spells", not pool_ids.has("mana_discharge"), pool_ids)
	await _focus_pool_card(inv, "spirit_volley")
	await _ui_action(&"ui_accept")
	await _ui_action(&"menu_clear")
	_check("Backspace cancels the slot choice", inv.pending_ability_id == "" and not eq.has("spirit_volley"), eq)
	var crisp := true
	for card in inv.pool_cards:
		crisp = crisp and not card.icon_view.dim
	_check("unlocked abilities keep crisp icons (no greyed-out state)", crisp)
	_check("no empty-slot placeholder card", inv.pool_grid.get_child_count() == inv.pool_cards.size())
	var details_numeric := digit.search(inv.detail_name.text + inv.detail_desc.text) != null
	var card_text := ""
	for card in inv.pool_cards + inv.cross.nodes.values():
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
	var hc := hud.spell_cross
	var at := func(n: String) -> Vector2: return (hc.card(n) as Control).position
	_check("HUD spell cross: a D-pad (Up above, Down below, Left and Right beside the center)",
		at.call("Up").y < at.call("Center").y and at.call("Down").y > at.call("Center").y
		and at.call("Left").x < at.call("Center").x and at.call("Right").x > at.call("Center").x
		and is_equal_approx(at.call("Up").x, at.call("Center").x) and is_equal_approx(at.call("Left").y, at.call("Center").y))
	hc.refresh(p.health.get_max_energy(), p.health.energy)
	var view := func(n: String) -> UltimateAbility: return (hc.card(n) as SpellNodeView).ability
	_check("HUD spell cross shows the loadout (Mana Discharge in the center, the Side spell on both sides)",
		view.call("Center") is ManaDischarge and view.call("Left") == view.call("Right")
		and view.call("Up") == game.ultimates.get_slot(PlayerData.SLOT_UP) and view.call("Down") == game.ultimates.get_slot(PlayerData.SLOT_DOWN))
	_check("HUD node hierarchy: Hud/SpellCross/{Up, Left, Center, Right, Down}",
		hud.get_node_or_null("SpellCross/Up") != null and hud.get_node_or_null("SpellCross/Right") != null and hud.get_node_or_null("SpellCross/Center") != null)
	_check("the inventory is laid out left to right", inv.panel.layout_direction == Control.LAYOUT_DIRECTION_LTR)
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

	# --- One Spell button (+ direction), no numbered hotkeys, no switching ---
	_check("one Spell button exists; the numbered hotkeys are gone",
		InputMap.has_action(&"spell") and not InputMap.has_action(&"ult_1") and not InputMap.has_action(&"ult_8") and Settings.REBINDABLE.has("spell"))
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
	_check("swap allowed at checkpoint", game.ultimates.equip(PlayerData.SLOT_UP, "comet_dash") and data.equipped[PlayerData.SLOT_UP] == "comet_dash"
		and data.equipped[PlayerData.SLOT_SIDE] == original[PlayerData.SLOT_UP], data.equipped)
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
	var relic: Relic = game.relics.filter(func(r: Relic) -> bool: return not r is Potion)[0]
	p.global_position = relic.global_position
	await _frames(5)
	_check("the relic raises max health", relic.collected and is_equal_approx(p.health.get_max_health(), base_max + 25.0),
		[relic.collected, p.health.get_max_health()])
	game.load_room("arena_room", "east")
	await _frames(2)
	_check("the broken wall stays open", not game.breakables[0].intact)
	game.load_room("secret_room", "west")
	await _frames(2)
	_check("the relic stays collected", game.relics.filter(func(r: Relic) -> bool: return not r is Potion)[0].collected)
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

	# --- No celebrations anywhere (GUIDELINES.md, Rule F) ---
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

	# --- HUD shows the bound Spell key on the spell cross ---
	_check("HUD shows the Spell key (U by default)", game.hud.spell_key_label() == "U", game.hud.spell_key_label())
	Settings.rebind("spell", KEY_Q)
	_check("HUD follows a rebound Spell key", game.hud.spell_key_label() == "Q", game.hud.spell_key_label())
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
	_check("nine spells are registered; the eight equippable ones are known with the full kit",
		game.ultimates.abilities.size() == 9 and data.unlocked.size() == 8 and not data.unlocked.has("mana_discharge"), data.unlocked)

	# Repulse Aegis: a parry. Consumes all energy, a tiny window, enemy contact only.
	await _reset()
	var aegis: RepulseAegis = game.ultimates.get_ability("repulse_aegis")
	var window: float = Config.ultimates.repulse_aegis.window
	_check("aegis is a tight parry (no wind-up, a short window)",
		is_zero_approx(Config.ultimates.repulse_aegis.cast_time) and window <= 0.25, window)
	p.health.set_energy(10.0)
	await _cast_spell("repulse_aegis")
	_check("aegis refused below its threshold", is_equal_approx(p.health.energy, 10.0) and not aegis.is_running, p.health.energy)
	var striker: DummyEnemy = game.spawn_enemy_kind("strong", p.global_position + Vector2(200, 0))
	striker.patrol = false
	await _frames(3)
	p.health.set_energy(80.0)
	await _cast_spell("repulse_aegis")
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
	await _cast_spell("repulse_aegis")
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
	await _cast_spell("repulse_aegis")
	await _frames(int(ceil(window * 60.0)) + 4)
	_check("aegis does not reach an enemy a step away", not aegis.countered and is_equal_approx(near.health, near.max_health), near.health)
	p.global_position = Vector2(touch_x - 3.0, near.global_position.y)
	p.health.set_energy(50.0)
	await _cast_spell("repulse_aegis")
	await _frames(2)
	_check("aegis counters an enemy at the player's skin", aegis.countered and near.health < near.max_health, near.health)

	# No projectile repel: a projectile hurts as usual during the window.
	await _reset()
	p.health.set_energy(40.0)
	await _cast_spell("repulse_aegis")
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
	await _cast_spell("stasis_field")
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

	# Radiant Lance: a forward beam that damages; Up / Down never aim it.
	await _reset()
	var lance: RadiantLance = game.ultimates.get_ability("radiant_lance")
	var beam_target: DummyEnemy = _first_enemy(false)
	beam_target.patrol = false
	await _frames(3)
	p.global_position = beam_target.global_position + Vector2(-160, 0)
	p.facing = 1
	p.health.set_energy(100.0)
	await _cast_spell("radiant_lance", PlayerData.SLOT_SIDE)
	await _frames(20)
	_check("lance spends its cost", is_equal_approx(p.health.energy, 100.0 - Config.ultimates.radiant_lance.cost), p.health.energy)
	_check("lance fires forward and damages", lance.dir == Vector2.RIGHT and beam_target.health < beam_target.max_health, [lance.dir, beam_target.health])
	await _frames(30)
	p.health.set_energy(100.0)
	for aim in [&"move_up", &"move_down"]:
		Input.action_press(aim)
		await _cast_spell("radiant_lance", PlayerData.SLOT_UP if aim == &"move_up" else PlayerData.SLOT_DOWN)
		await _frames(16)
		var rect := lance.beam_rect()
		Input.action_release(aim)
		_check("lance stays horizontal toward facing while holding %s" % aim, lance.dir == Vector2.RIGHT and rect.size.x > rect.size.y, [lance.dir, rect])
		await _frames(30)
		p.health.set_energy(100.0)

	# Comet Dash: always a horizontal charge toward facing, even with Up or Down held.
	var comet: CometDash = game.ultimates.get_ability("comet_dash")
	for aim in [&"move_up", &"move_down"]:
		await _reset()
		p.global_position = Vector2(150, 420)
		p.velocity = Vector2.ZERO
		p.facing = -1
		p.health.set_energy(100.0)
		await _frames(1)
		Input.action_press(aim)
		await _cast_spell("comet_dash", PlayerData.SLOT_UP if aim == &"move_up" else PlayerData.SLOT_DOWN)
		var charged := 0
		var max_vy := 0.0
		for i in 30:
			if p.state_name() == "ability":
				charged += 1
				max_vy = maxf(max_vy, absf(p.velocity.y))
			await _frames(1)
		Input.action_release(aim)
		_check("comet dash stays horizontal toward facing while holding %s" % aim,
			comet.dir == Vector2.LEFT and p.facing == -1 and charged > 0 and max_vy < 1.0, [comet.dir, p.facing, charged, max_vy])

	# Meteor Slam: invulnerable dive, then a ground shockwave and landing i-frames.
	await _reset()
	var slam: MeteorSlam = game.ultimates.get_ability("meteor_slam")
	var slam_target: DummyEnemy = _first_enemy(false)
	slam_target.patrol = false
	await _frames(3)
	p.global_position = slam_target.global_position + Vector2(-50, -90)
	p.health.set_energy(100.0)
	var slams := slam.slam_count
	await _cast_spell("meteor_slam", PlayerData.SLOT_DOWN)
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

	# Spell + direction picks the slot. Up wins, then Down, then the sides.
	var pick := UltimateManager.slot_for_input
	_check("Spell alone is the neutral spell; Up / Down / Left / Right pick their slots",
		pick.call(0, 0) == UltimateManager.NEUTRAL and pick.call(0, -1) == PlayerData.SLOT_UP and pick.call(0, 1) == PlayerData.SLOT_DOWN
		and pick.call(1, 0) == PlayerData.SLOT_SIDE and pick.call(-1, 0) == PlayerData.SLOT_SIDE)
	_check("Up wins over Left / Right, Down too", pick.call(1, -1) == PlayerData.SLOT_UP and pick.call(-1, 1) == PlayerData.SLOT_DOWN)
	_check("the default (full kit) loadout: Lance up, Comet Dash to the side, Meteor Slam down",
		game.DEFAULT_LOADOUT == ["radiant_lance", "comet_dash", "meteor_slam"], game.DEFAULT_LOADOUT)

	# A Side spell goes toward the held side (the player turns).
	p.facing = 1
	p.health.set_energy(100.0)
	game.ultimates.equip(PlayerData.SLOT_SIDE, "stasis_field", true)
	Input.action_press(&"move_left")
	Input.action_press(&"spell")
	await _frames(2)
	Input.action_release(&"spell")
	Input.action_release(&"move_left")
	_check("Spell + Left casts the Side spell facing left",
		p.facing == -1 and is_equal_approx(p.health.energy, 100.0 - Config.ultimates.stasis_field.cost), [p.facing, p.health.energy])
	await _frames(30)

	# Mana Discharge is fixed for good.
	game.ultimates.set_known("mana_discharge", false)
	_check("Mana Discharge cannot be forgotten, equipped or unequipped",
		data.is_unlocked("mana_discharge") and not game.ultimates.equip(PlayerData.SLOT_UP, "mana_discharge", true)
		and not data.equipped.has("mana_discharge") and not game.ultimates.unequip(UltimateManager.NEUTRAL, true))

	# Known spells: forgetting removes from the pool and the loadout.
	game.ultimates.equip(PlayerData.SLOT_UP, "radiant_lance", true)
	game.ultimates.set_known("radiant_lance", false)
	_check("a forgotten spell leaves the pool and its slot",
		not data.is_unlocked("radiant_lance") and data.equipped[PlayerData.SLOT_UP] == "" and not game.ultimates.equip(PlayerData.SLOT_UP, "radiant_lance"), data.equipped)

	# Debug overlay controls drive the same rules.
	dbg.toggle()
	await _frames(2)
	_check("debug overlay lists every equippable spell", dbg._known_checks.size() == game.ultimates.abilities.size() - 1 and not dbg._known_checks.has("mana_discharge"))
	_check("debug checkbox mirrors a forgotten spell", not dbg._known_checks["radiant_lance"].button_pressed)
	dbg._known_checks["radiant_lance"].button_pressed = true
	_check("debug checkbox teaches a spell", data.is_unlocked("radiant_lance"))
	dbg._known_checks["meteor_slam"].button_pressed = false
	_check("debug checkbox forgets a spell", not data.is_unlocked("meteor_slam"))
	dbg.toggle()
	game.ultimates.set_known("meteor_slam", true)

	# Saves keep the three directional slots only.
	var saved: Dictionary = game.make_save_data()
	_check("the save stores the Up / Side / Down slots (no capacity, no neutral spell)",
		(saved.equipped as Array).size() == PlayerData.SLOT_COUNT and not saved.has("slot_capacity") and not (saved.equipped as Array).has("mana_discharge"), saved.equipped)

	data.equipped = loadout
	Events.loadout_changed.emit()
	await _reset()
	await _test_mana_discharge()
	await _test_max_stats()


func _test_mana_discharge() -> void:
	var p: Player = game.player
	var md: ManaDischarge = game.ultimates.get_ability("mana_discharge")
	var cfg: Dictionary = Config.ultimates.mana_discharge
	_check("Mana Discharge deals minimal damage", cfg.damage > 0.0 and cfg.damage < Config.combat.attack_damage * 0.5, cfg.damage)

	# Full energy: a real wave, sized by MAX energy, that hurts a little.
	await _reset()
	var target: DummyEnemy = _first_enemy(false)
	target.patrol = false
	await _frames(3)
	p.global_position = target.global_position + Vector2(-90, 0)
	await _frames(2)
	p.health.set_energy(100.0)
	var hp := target.health
	await _cast_neutral()
	_check("Spell alone casts Mana Discharge and drains ALL energy", is_zero_approx(p.health.energy) and is_equal_approx(md.consumed, 100.0) and p.state_name() == "cast",
		[p.health.energy, md.consumed, p.state_name()])
	await _frames(40)
	_check("a full discharge is a real wave sized by max energy",
		not md.failed and is_equal_approx(md.max_radius, cfg.radius_per_energy * p.health.get_max_energy()), [md.failed, md.max_radius])
	_check("the wave deals its minimal damage", is_equal_approx(hp - target.health, cfg.damage), hp - target.health)

	# Partial energy above the cost: still drains everything.
	await _reset()
	p.health.set_energy(70.0)
	await _cast_neutral()
	_check("Mana Discharge always drains everything (70 of 100)", is_zero_approx(p.health.energy) and is_equal_approx(md.consumed, 70.0) and not md.failed,
		[p.health.energy, md.consumed])
	await _frames(40)

	# The radius grows with the max energy (upgrades).
	var base: float = p.health.base_max_energy
	_check("the wave radius scales with max energy", is_equal_approx(md.wave_radius(200.0), md.wave_radius(100.0) * 2.0))
	p.health.set_base_max_energy(200.0)
	p.health.set_energy(200.0)
	await _cast_neutral()
	await _frames(15)
	_check("a bigger energy capacity gives a bigger wave", is_equal_approx(md.max_radius, cfg.radius_per_energy * 200.0), md.max_radius)
	await _frames(30)
	p.health.set_base_max_energy(base)

	# Too little energy: it still casts, drains the rest, and fizzles.
	await _reset()
	target = _first_enemy(false)
	target.patrol = false
	await _frames(3)
	p.global_position = target.global_position + Vector2(-40, 0)
	await _frames(2)
	p.health.set_energy(cfg.cost * 0.5)
	hp = target.health
	await _cast_neutral()
	_check("a low-energy discharge still casts and drains the rest", is_zero_approx(p.health.energy) and p.state_name() == "cast", [p.health.energy, p.state_name()])
	var ran := false
	var gone_after := -1
	for i in 40:
		await _frames(1)
		ran = ran or md.is_running
		if ran and not md.is_running:
			gone_after = i
			break
	_check("a failed discharge fizzles: a tiny ring, gone almost at once",
		md.failed and md.max_radius <= cfg.fizzle_radius and gone_after >= 0 and gone_after <= 15, [md.failed, md.max_radius, gone_after])
	_check("a failed discharge deals no damage", is_equal_approx(target.health, hp), target.health)
	p.health.set_energy(0.0)
	await _frames(10)
	await _cast_neutral()
	_check("even with no energy at all it casts (and fails)", p.state_name() == "cast" and md.failed, p.state_name())
	await _frames(30)


func _test_max_stats() -> void:
	var p: Player = game.player
	var h := p.health
	var exported := {}
	for prop in h.get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR and prop.name in ["base_max_health", "base_max_energy"]:
			exported[prop.name] = true
	_check("max health and max energy are exported stats (Inspector)", exported.size() == 2, exported)
	var hp_base := h.base_max_health
	var en_base := h.base_max_energy
	h.set_base_max_health(150.0)
	h.set_base_max_energy(120.0)
	_check("changing the max stats changes the limits (bonuses on top)",
		is_equal_approx(h.get_max_health(), 150.0 + h.max_health_bonus) and is_equal_approx(h.get_max_energy(), 120.0 + h.max_energy_bonus))
	h.set_energy(120.0)
	h.set_base_max_energy(50.0)
	_check("lowering max energy clamps the current energy", is_equal_approx(h.energy, 50.0 + h.max_energy_bonus), h.energy)
	h.set_base_max_health(hp_base)
	h.set_base_max_energy(en_base)
	h.full_heal()


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
	await _cast_spell("meteor_slam", PlayerData.SLOT_DOWN)
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
	await _cast_spell("meteor_slam", PlayerData.SLOT_DOWN)
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
	_check("GUIDELINES.md has Rule D (solid boundaries) and Rule E (open secret exits)",
		doc.contains("## Rule D — Boundaries require solid walls") and doc.contains("## Rule E — Secret room exits look open")
		and doc.contains("## Rule F — No celebrations"))
	# Rule D: every hidden pocket is closed by solid wall on all other sides.
	var open_pockets := []
	for rid in ["test_room", "upper_room"]:
		game.load_room(rid)
		for wall in game.hidden_pockets:
			if not _pocket_closed(wall):
				open_pockets.append([rid, wall.secret_id])
	_check("Rule D: every hidden pocket is closed by solid wall", open_pockets.is_empty(), open_pockets)
	await _reset()


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
	_check("finding a pocket plays no effect (Rule F)", game.effects.play_counts == fx_before, game.effects.play_counts)
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
	# Rule D: the pocket's far end is a solid wall, and the player can see it.
	Input.action_press(&"move_left")
	await _frames(60)
	Input.action_release(&"move_left")
	await _frames(40)
	var far_wall := Vector2(wall.pocket_rect.position.x - 16.0, floor_y - 16.0)
	_check("Rule D: a solid wall closes the far end of the west pocket",
		game.room.is_solid_at(far_wall) and p.get_rect().position.x >= wall.pocket_rect.position.x - 0.5, [p.global_position, wall.pocket_rect])
	_check("Rule D: that boundary wall is on screen, never a screen edge over void",
		cam.view_rect().position.x <= wall.pocket_rect.position.x - 32.0 + 0.5, [cam.view_rect(), wall.pocket_rect])

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
	_check("entry side: semi-transparent", entry.visible and doorway.shown_visual() == entry and is_equal_approx(entry.modulate.a, 0.5), entry.modulate)
	_check("a secret doorway has no collision and no tile",
		not game.room.is_solid_at(doorway.get_rect().get_center()) and doorway.find_children("*", "CollisionObject2D").is_empty())
	var secrets_before: int = game.world.secrets.size()
	var trips := 0
	for trip in 2: # Back and forth twice: it never disappears.
		await _walk_galleries_to_vault(doorway)
		if game.room_id != "hidden_vault":
			break
		var back: SecretDoorway = game.secret_doorways[0]
		_check("Rule E (trip %d): the exit looks like a standard open doorway, nothing drawn" % (trip + 1),
			not back.is_entry() and back.shown_visual() == null and not back.has_node("ExitVisual")
			and _gap_is_open(back.get_rect()) and _doorway_drawn_items(back) == 0,
			[back.side, _doorway_drawn_items(back)])
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


## True when every cell of a doorway gap is open: no tile at all, not solid.
func _gap_is_open(rect: Rect2) -> bool:
	var tiles: TileMapLayer = game.room.tiles
	for y in range(int(rect.position.y) + 16, int(rect.end.y), 32):
		var at := Vector2(rect.get_center().x, y)
		if game.room.is_solid_at(at) or tiles.get_cell_source_id(tiles.local_to_map(tiles.to_local(at))) != -1:
			return false
	return true


## Visible drawable nodes under a secret doorway (0 = it draws nothing).
func _doorway_drawn_items(doorway: SecretDoorway) -> int:
	var count := 0
	for item in doorway.find_children("*", "CanvasItem", true, false):
		if (item as CanvasItem).is_visible_in_tree() and (item is Sprite2D or item is Polygon2D or item is Control or item is Line2D):
			count += 1
	return count


## Rule D for pockets: every cell around a hidden pocket is solid wall,
## except the hidden pocket wall itself.
func _pocket_closed(wall: HiddenPocketWall) -> bool:
	var ring := wall.pocket_rect.grow(32.0)
	for y in range(int(ring.position.y) + 16, int(ring.end.y), 32):
		for x in range(int(ring.position.x) + 16, int(ring.end.x), 32):
			var at := Vector2(x, y)
			if wall.pocket_rect.has_point(at) or wall.get_rect().has_point(at):
				continue
			if not game.room.is_solid_at(at):
				return false
	return true


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
	await _cast_spell("meteor_slam", PlayerData.SLOT_DOWN)
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


func _test_grapple() -> void:
	var p: Player = game.player
	var hook: GrappleHook = game.combat.grapple
	var g = Config.grapple
	var aim := func(ay: int, facing: int, airborne := true) -> Vector2:
		return GrappleHook.aim_vector(GrappleHook.resolve_aim(ay, airborne), facing)
	var mode := GrappleHook.resolve_aim
	var diag := Vector2(1, -1).normalized()
	_check("grapple case 3: no direction (or Left / Right) fires straight ahead, toward facing, grounded or airborne",
		aim.call(0, 1) == Vector2.RIGHT and aim.call(0, -1) == Vector2.LEFT and aim.call(0, 1, false) == Vector2.RIGHT
		and mode.call(0, true) == GrappleHook.Aim.HORIZONTAL and mode.call(0, false) == GrappleHook.Aim.HORIZONTAL)
	_check("grapple case 1: Up fires straight up (pull), grounded or airborne",
		aim.call(-1, 1) == Vector2.UP and aim.call(-1, -1, false) == Vector2.UP
		and mode.call(-1, true) == GrappleHook.Aim.UP and mode.call(-1, false) == GrappleHook.Aim.UP)
	_check("grapple case 2: Down in the air is a swing, 45 degrees up toward the facing side",
		mode.call(1, true) == GrappleHook.Aim.SWING and aim.call(1, 1).is_equal_approx(diag)
		and aim.call(1, -1).is_equal_approx(Vector2(-diag.x, diag.y)))
	_check("grapple case 3: Down on the ground is no swing (straight ahead, pull)",
		mode.call(1, false) == GrappleHook.Aim.HORIZONTAL and aim.call(1, 1, false) == Vector2.RIGHT)
	_check("grapple: the range is short (8 tiles)", is_equal_approx(g.max_range, 256.0), g.max_range)
	_check("grapple: the hook has a forgiving tolerance", g.hook_radius >= 12.0 and g.hazard_radius < g.hook_radius, [g.hook_radius, g.hazard_radius])
	var god: bool = Config.upgrades.god_mode
	Config.upgrades.god_mode = false
	var latches := [0]
	var enemy_latches := [0]
	var deflects := [0]
	var bounces := [0]
	var swing_ends := []
	var on_latch := func(_a: Vector2, e: bool) -> void:
		latches[0] += 1
		if e:
			enemy_latches[0] += 1
	var on_deflect := func(_a: Vector2) -> void: deflects[0] += 1
	var on_bounce := func(_a: Vector2) -> void: bounces[0] += 1
	var on_swing_end := func(reason: String) -> void: swing_ends.append(reason)
	Events.grapple_latched.connect(on_latch)
	Events.grapple_deflected.connect(on_deflect)
	Events.grapple_bounced.connect(on_bounce)
	Events.grapple_swing_ended.connect(on_swing_end)

	# Horizontal: hook the shaft's left wall. The player hangs still while the
	# hook flies, is pulled to the wall and gets the double jump back.
	await _reset()
	p.global_position = Vector2(150, 420)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(1)
	p.air_jumps_used = 1 # Double jump already spent.
	Input.action_press(&"move_left")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_left")
	_check("grapple: Left held turns the player, and the hook fires straight ahead toward facing (left)", hook.dir == Vector2.LEFT and p.facing == -1, [hook.dir, p.facing])
	var hold_y := p.global_position.y
	var drift := 0.0
	var held := true
	while hook.is_flying():
		held = held and p.state_name() == "grapple"
		drift = maxf(drift, absf(p.global_position.y - hold_y))
		await _frames(1)
	_check("grapple: the player hangs still in the air while the hook flies", held and drift < 0.5, [held, drift])
	var pulled := false
	var min_x := p.global_position.x
	for i in 45:
		pulled = pulled or hook.is_pulling()
		min_x = minf(min_x, p.global_position.x)
		await _frames(1)
	_check("grapple: the hook latches on a wall and pulls the player", pulled and latches[0] == 1, [pulled, latches[0]])
	_check("grapple: the pull reaches the wall", min_x <= 32.0 + Player.WIDTH / 2.0 + g.arrive_distance + 1.0, min_x)
	_check("grapple: normal movement resumes after the pull", p.state_name() == "normal", p.state_name())
	_check("grapple: a latched pull refreshes the double jump", p.air_jumps_used == 0, p.air_jumps_used)
	await _frames(15)
	_check("grapple: the hook comes back and cools down", hook.is_idle(), hook.phase)

	# Wall slide: sliding faces AWAY from the wall, but holding toward it
	# and throwing turns the player at once and fires into the wall.
	await _reset()
	p.global_position = Vector2(32 + Player.WIDTH / 2.0 + 1.0, 320)
	p.velocity = Vector2.ZERO
	Input.action_press(&"move_left")
	await _frames(20)
	var slid := [p.wall_sliding, p.facing]
	var at_throw := []
	var on_fire := func(_o: Vector2, d: Vector2) -> void: at_throw.append([d, p.facing])
	Events.grapple_fired.connect(on_fire)
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_left")
	Events.grapple_fired.disconnect(on_fire)
	_check("grapple: holding Left during a wall slide fires left (the player turns on the throw frame)",
		slid == [true, 1] and at_throw.size() == 1 and at_throw[0] == [Vector2.LEFT, -1], [slid, at_throw])
	await _frames(30)
	game.combat.reset()

	# A buffered throw keeps the press frame's input and airborne state:
	# Down pressed in the air, released before the hook is ready, still swings.
	await _reset()
	p.global_position = Vector2(1300, 200)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(1)
	hook.cooldown = 0.08 # Not ready yet: the press is buffered.
	Input.action_press(&"move_down")
	Input.action_press(&"grapple")
	await _frames(2)
	var buffered := hook.is_idle()
	Input.action_release(&"move_down")
	Input.action_release(&"grapple")
	await _frames(5)
	_check("grapple: a buffered throw uses the press frame's input (Down in the air = swing)",
		buffered and not hook.is_idle() and hook.swing_mode and hook.dir.is_equal_approx(Vector2(1, -1).normalized()), [buffered, hook.phase, hook.swing_mode, hook.dir])
	game.combat.reset()

	# No direction: straight out toward the facing side, onto the pillar.
	await _reset()
	p.global_position = Vector2(100, 420)
	p.velocity = Vector2.ZERO
	p.facing = 1
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	_check("grapple: no direction fires horizontally toward the facing side", hook.dir == Vector2.RIGHT and not hook.swing_mode, hook.dir)
	var max_x := p.global_position.x
	for i in 45:
		max_x = maxf(max_x, p.global_position.x)
		await _frames(1)
	_check("grapple: the horizontal pull reaches the pillar", max_x >= 192.0 - Player.WIDTH / 2.0 - g.arrive_distance - 1.0, max_x)

	# Forgiving: a horizontal throw that passes just under the pillar's
	# bottom edge still catches it (a side ray).
	await _reset()
	p.global_position = Vector2(100, 672)
	p.velocity = Vector2.ZERO
	p.facing = 1
	latches[0] = 0
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	for i in 20:
		if not hook.is_flying():
			break
		await _frames(1)
	_check("grapple: the forgiving hook catches an edge just beside its path",
		latches[0] == 1 and hook.is_latched() and absf(hook.anchor.x - 192.0) < 1.0 and hook.anchor.y < 640.0,
		[latches[0], hook.phase, hook.anchor])
	game.combat.reset()

	# Up onto a one-way platform: the pull ends standing on it.
	await _reset()
	p.global_position = Vector2(100, 380)
	p.velocity = Vector2.ZERO
	latches[0] = 0
	await _frames(1)
	Input.action_press(&"move_up")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_up")
	_check("grapple: Up held fires straight up", hook.dir == Vector2.UP, hook.dir)
	await _frames(60)
	var plank_top := 5.0 * 32.0
	_check("grapple: latches a one-way platform and lands the player on it",
		latches[0] == 1 and p.grounded and absf(p.global_position.y - plank_top) < 2.0 and game.room.standing_on_one_way_only(p.get_rect()),
		[latches[0], p.grounded, p.global_position])

	# Up to a solid ceiling: the underside of the central hanging wall.
	await _reset()
	p.global_position = Vector2(992, 703)
	p.velocity = Vector2.ZERO
	await _frames(5)
	Input.action_press(&"move_up")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_up")
	var min_top := p.get_rect().position.y
	for i in 45:
		min_top = minf(min_top, p.get_rect().position.y)
		await _frames(1)
	_check("grapple: pulls up to a ceiling", latches[0] == 2 and min_top <= 576.0 + g.arrive_distance + 1.0, [latches[0], min_top])

	# Cancels: jump (a free jump: the double jump stays), a hit, a reset.
	await _start_wall_pull()
	_check("grapple: pulling (cancel setup)", hook.is_pulling() and p.state_name() == "grapple", [hook.phase, p.state_name()])
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	_check("grapple: jump cancels the pull and jumps", p.state_name() == "normal" and p.velocity.y < -300.0 and not hook.is_latched(), [p.state_name(), p.velocity])
	_check("grapple: the cancel jump keeps the double jump", p.air_jumps_used == 0, p.air_jumps_used)
	await _start_wall_pull()
	p.receive_hit(5.0, p.global_position.x + 10.0)
	_check("grapple: a hit ends the pull (not invulnerable)", p.state_name() == "hurt" and not hook.is_latched(), [p.state_name(), hook.phase])
	await _start_wall_pull()
	game.combat.reset()
	_check("grapple: a reset (room load) drops the hook at once", p.state_name() == "normal" and hook.is_idle(), [p.state_name(), hook.phase])

	# Out of range: the hook flies back, no pull, and the hold ends.
	await _reset()
	p.global_position = Vector2(600, 100)
	p.velocity = Vector2.ZERO
	latches[0] = 0
	Input.action_press(&"move_right")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_right")
	var far := 0.0
	var any_pull := false
	for i in 30:
		far = maxf(far, hook.tip.distance_to(hook.rope_origin(p)))
		any_pull = any_pull or hook.is_latched()
		await _frames(1)
	_check("grapple: a miss flies back at max range, without a pull", not any_pull and latches[0] == 0 and far <= g.max_range + 40.0 and hook.is_idle(),
		[any_pull, latches[0], far, hook.phase])
	_check("grapple: after a miss the player falls again", p.state_name() == "normal" and p.global_position.y > 110.0, [p.state_name(), p.global_position])

	# Hazards: wall spikes and ceiling spikes deflect the hook; no latch, no pull.
	await _reset()
	var hp := p.health.health
	p.global_position = Vector2(1700, 390)
	p.velocity = Vector2.ZERO
	deflects[0] = 0
	latches[0] = 0
	Input.action_press(&"move_right")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_right")
	any_pull = false
	for i in 30:
		any_pull = any_pull or hook.is_latched()
		await _frames(1)
	_check("grapple: wall spikes deflect the hook (no latch, no pull)", deflects[0] == 1 and latches[0] == 0 and not any_pull and hook.is_idle(),
		[deflects[0], latches[0], any_pull, hook.phase])
	await _reset()
	for e in game.enemies:
		if e is DummyEnemy:
			e.patrol = false
	p.global_position = Vector2(1232, 703)
	p.velocity = Vector2.ZERO
	await _frames(5)
	Input.action_press(&"move_up")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_up")
	any_pull = false
	for i in 30:
		any_pull = any_pull or hook.is_latched()
		await _frames(1)
	_check("grapple: ceiling spikes deflect the hook (no latch, no pull)", deflects[0] == 2 and latches[0] == 0 and not any_pull,
		[deflects[0], latches[0], any_pull])
	_check("grapple: a deflected hook never hurts the player", is_equal_approx(p.health.health, hp) and p.state_name() == "normal",
		[p.health.health, p.state_name()])
	var wall_spike: Vector2 = game.room.cell_center(Vector2i(57, 11))
	var ceiling_spike: Vector2 = game.room.cell_center(Vector2i(36, 14))
	_check("grapple: wall and ceiling spikes are hazards on the right side of their tile",
		game.room.find_hazard(Rect2(wall_spike + Vector2(10, 0), Vector2.ONE)).has_area()
		and not game.room.find_hazard(Rect2(wall_spike + Vector2(-12, 0), Vector2.ONE)).has_area()
		and game.room.find_hazard(Rect2(ceiling_spike + Vector2(0, -10), Vector2.ONE)).has_area()
		and not game.room.find_hazard(Rect2(ceiling_spike + Vector2(0, 12), Vector2.ONE)).has_area())
	_check("grapple: anchors next to floor spikes are refused", not hook.anchor_is_safe(Vector2(640, 736)) and hook.anchor_is_safe(Vector2(400, 704)))
	_check("grapple: a rope across ceiling or wall spikes is obstructed; a clear one is not",
		hook.rope_obstructed(Vector2(1200, 500), Vector2(1200, 400)) and hook.rope_obstructed(Vector2(1800, 368), Vector2(1850, 368))
		and not hook.rope_obstructed(Vector2(1100, 500), Vector2(1100, 600)))

	# Hidden pocket (Type 1): the hook never reaches into an undiscovered pocket.
	var west: HiddenPocketWall = null
	for wall in game.hidden_pockets:
		if wall.secret_id == "halls_west_alcove":
			west = wall
	if west and not west.discovered:
		p.global_position = Vector2(150, 703)
		p.velocity = Vector2.ZERO
		await _frames(5)
		Input.action_press(&"move_left")
		Input.action_press(&"grapple")
		await _frames(2)
		Input.action_release(&"grapple")
		Input.action_release(&"move_left")
		var lowest_x := INF
		for i in 30:
			if hook.phase == "fly" or hook.is_latched():
				lowest_x = minf(lowest_x, hook.tip.x)
			await _frames(1)
		_check("grapple: an undiscovered hidden pocket wall stops the hook like terrain", lowest_x >= west.get_rect().end.x - 1.0, lowest_x)

	# Enemy: no damage on contact; pulled to the safe distance, a near-pogo
	# rebound, and only then the standard attack damage.
	await _reset()
	var dummy: DummyEnemy = _first_enemy(false)
	dummy.patrol = false
	await _frames(20)
	p.global_position = dummy.global_position + Vector2(-170, 0)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(5)
	var enemy_hp := dummy.health
	var my_hp := p.health.health
	var ground_y := p.global_position.y
	bounces[0] = 0
	var hp_at_bounce := [-1.0]
	var on_bounce_hp := func(_a: Vector2) -> void: hp_at_bounce[0] = dummy.health
	Events.grapple_bounced.connect(on_bounce_hp)
	var sources := []
	var on_hit := func(info: Dictionary) -> void: sources.append(info.source)
	Events.hit_landed.connect(on_hit)
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	var enemy_pull := false
	var hurt_while_pulling := false
	var min_gap := INF
	var peak := ground_y
	for i in 70:
		await _frames(1)
		if hook.is_pulling() and hook.on_enemy():
			enemy_pull = true
			hurt_while_pulling = hurt_while_pulling or dummy.health < enemy_hp
		min_gap = minf(min_gap, dummy.get_rect().position.x - p.get_rect().end.x)
		peak = minf(peak, p.global_position.y)
	Events.hit_landed.disconnect(on_hit)
	Events.grapple_bounced.disconnect(on_bounce_hp)
	var pogo_height: float = pow(Config.combat.pogo_velocity, 2.0) / (2.0 * Config.movement.gravity)
	_check("grapple: the player is pulled toward the hooked enemy", enemy_pull)
	_check("grapple: no damage when the hook touches the enemy", enemy_pull and not hurt_while_pulling)
	_check("grapple: the pull stops short of the enemy's contact hitbox", min_gap >= g.enemy_safe_margin - 1.0, min_gap)
	_check("grapple: reaching the enemy rebounds the player nearly a full pogo high",
		bounces[0] == 1 and ground_y - peak >= pogo_height * 0.8, [bounces[0], ground_y - peak, pogo_height])
	_check("grapple: the enemy takes the standard attack damage only after the bounce",
		is_equal_approx(hp_at_bounce[0], enemy_hp) and is_equal_approx(enemy_hp - dummy.health, Config.combat.attack_damage) and sources == ["grapple"],
		[hp_at_bounce[0], enemy_hp - dummy.health, sources])
	_check("grapple: no contact damage from the hooked enemy", is_equal_approx(p.health.health, my_hp) and p.state_name() == "normal",
		[p.health.health, my_hp, p.state_name()])

	# A cancelled enemy pull deals no damage.
	await _reset()
	dummy = _first_enemy(false)
	dummy.patrol = false
	await _frames(20)
	p.global_position = dummy.global_position + Vector2(-200, 0)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(5)
	enemy_hp = dummy.health
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	for i in 20:
		if hook.is_pulling():
			break
		await _frames(1)
	await _frames(2)
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	await _frames(30)
	_check("grapple: a cancelled enemy pull deals no damage", is_equal_approx(dummy.health, enemy_hp) and not hook.is_latched(),
		[dummy.health, enemy_hp, hook.phase])

	# Forgiving on enemies: the throw passes 8 px above the dummy's head and still hooks it.
	await _reset()
	dummy = _first_enemy(false)
	dummy.patrol = false
	await _frames(20)
	var head := dummy.get_rect().position.y
	p.global_position = Vector2(dummy.global_position.x - 170.0, head - 8.0 - GrappleHook.HAND_OFFSET.y + Player.HEIGHT / 2.0)
	p.velocity = Vector2.ZERO
	p.facing = 1
	enemy_latches[0] = 0
	await _frames(1)
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	for i in 20:
		if not hook.is_flying():
			break
		await _frames(1)
	_check("grapple: the forgiving hook catches an enemy just beside its path", enemy_latches[0] == 1 and hook.on_enemy(), [enemy_latches[0], hook.phase])
	game.combat.reset()

	# Down on the ground: no swing.
	await _reset()
	p.global_position = Vector2(480, 703)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(5)
	Input.action_press(&"move_down")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_down")
	_check("grapple: Down + grapple on the ground throws straight out, no swing", hook.dir == Vector2.RIGHT and not hook.swing_mode, [hook.dir, hook.swing_mode])
	game.combat.reset()

	# Swing: Down in the air, 45 degrees up to the ceiling, then a pendulum.
	await _start_swing()
	var st: GrappleState = p.fsm.states["grapple"]
	_check("grapple: Down in the air throws a swing at 45 degrees", hook.swing_mode and hook.dir.is_equal_approx(diag), [hook.swing_mode, hook.dir])
	_check("grapple: the swing hook latches (no pull)", hook.is_swinging() and p.state_name() == "grapple", [hook.phase, p.state_name()])
	var start_y := p.get_center().y
	var length := st.rope_length
	var dev := 0.0
	var right_x := -INF
	var right_top := INF
	for i in 75:
		await _frames(1)
		if not hook.is_swinging():
			break
		dev = maxf(dev, absf(p.get_center().distance_to(hook.anchor) - length))
		right_x = maxf(right_x, p.get_center().x)
		if p.get_center().x > hook.anchor.x:
			right_top = minf(right_top, p.get_center().y)
	_check("grapple: the swing keeps a fixed rope length", hook.is_swinging() and dev < 1.5, [hook.phase, dev])
	_check("grapple: the swing arcs past the anchor and climbs the far side (no damping)",
		right_x > hook.anchor.x + 100.0 and absf(right_top - start_y) < 8.0, [right_x - hook.anchor.x, right_top, start_y])
	p.air_jumps_used = 1
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	_check("grapple: jump lets go of the swing and jumps", swing_ends.back() == "input" and p.state_name() == "normal"
		and p.velocity.y < -300.0 and not hook.is_latched(), [swing_ends, p.state_name(), p.velocity])
	_check("grapple: letting go of a swing refreshes the double jump", p.air_jumps_used == 0, p.air_jumps_used)

	await _start_swing()
	await _frames(10)
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	_check("grapple: the grapple key lets go of the swing, keeping its momentum",
		swing_ends.back() == "input" and p.state_name() == "normal" and p.velocity.length() > 100.0, [swing_ends, p.velocity])

	await _start_swing()
	await _frames(5)
	p.receive_hit(5.0, p.global_position.x + 10.0)
	_check("grapple: damage lets go of the swing", swing_ends.back() == "interrupted" and p.state_name() == "hurt" and not hook.is_latched(),
		[swing_ends, p.state_name(), hook.phase])

	await _start_swing()
	var mid: Vector2 = (hook.rope_origin(p) + hook.anchor) / 2.0
	var blocker: Enemy = game.spawn_enemy_kind("flyer", mid + Vector2(0, 15))
	(blocker as DummyEnemy).patrol = false
	await _frames(3)
	_check("grapple: an enemy across the rope cuts the swing", swing_ends.back() == "obstructed" and not hook.is_latched(), [swing_ends, hook.phase])
	game.remove_enemy(blocker)

	# Terrain: swinging into the pillar lets go.
	await _reset()
	p.global_position = Vector2(60, 420)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(1)
	Input.action_press(&"move_down")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_down")
	var swung := false
	for i in 90:
		swung = swung or hook.is_swinging()
		if swung and not hook.is_swinging():
			break
		await _frames(1)
	_check("grapple: swinging into a wall lets go", swung and swing_ends.back() == "terrain" and p.state_name() == "normal",
		[swung, swing_ends, p.state_name()])

	Events.grapple_latched.disconnect(on_latch)
	Events.grapple_deflected.disconnect(on_deflect)
	Events.grapple_bounced.disconnect(on_bounce)
	Events.grapple_swing_ended.disconnect(on_swing_end)
	Config.upgrades.god_mode = god


## Grapple test helper: in open air, Down + grapple (facing right) swings
## from the ceiling. Waits until the swing has started.
func _start_swing() -> void:
	var p: Player = game.player
	await _reset()
	p.global_position = Vector2(1300, 200)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(1)
	Input.action_press(&"move_down")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_down")
	for i in 20:
		if game.combat.grapple.is_swinging():
			break
		await _frames(1)
	await _frames(1) # The state picks the swing up on its next step.


## Grapple test helper: throws the hook left at the shaft wall and waits for the pull.
func _start_wall_pull() -> void:
	var p: Player = game.player
	await _reset()
	p.global_position = Vector2(180, 420)
	p.velocity = Vector2.ZERO
	Input.action_press(&"move_left")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_left")
	for i in 20:
		if game.combat.grapple.is_pulling():
			break
		await _frames(1)
	await _frames(2)


## Puts a spell in a directional slot (ignoring the checkpoint rule) and
## casts it: Spell + that slot's direction (Side: toward the facing side).
## A direction key that is already held stays held afterwards.
func _cast_spell(ability_id: String, slot := PlayerData.SLOT_UP) -> void:
	var p: Player = game.player
	game.ultimates.equip(slot, ability_id, true)
	var dir: StringName = [&"move_up", &"move_right" if p.facing > 0 else &"move_left", &"move_down"][slot]
	var held := Input.is_action_pressed(dir)
	Input.action_press(dir)
	Input.action_press(&"spell")
	await _frames(2)
	Input.action_release(&"spell")
	if not held:
		Input.action_release(dir)


## Casts the neutral spell (Spell with no direction).
func _cast_neutral() -> void:
	Input.action_press(&"spell")
	await _frames(2)
	Input.action_release(&"spell")


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




## Puts the player's center at `center`, still, facing `facing`.
func _place_center(center: Vector2, facing: int) -> void:
	var p: Player = game.player
	p.global_position += center - p.get_center()
	p.velocity = Vector2.ZERO
	p.facing = facing


## Throws the hook straight right at the hold peg from the air and waits for
## the hold. Returns true once the player hangs from it.
func _hang_from_peg(peg: GrapplePeg) -> bool:
	var hook: GrappleHook = game.combat.grapple
	await _reset()
	game.combat.reset()
	_place_center(peg.global_position + Vector2(-80, 0) - GrappleHook.HAND_OFFSET, 1)
	await _frames(1)
	_place_center(peg.global_position + Vector2(-80, 0) - GrappleHook.HAND_OFFSET, 1)
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	for i in 60:
		if hook.is_holding():
			return true
		await _frames(1)
	return false


func _test_grapple_pegs() -> void:
	var p: Player = game.player
	var hook: GrappleHook = game.combat.grapple
	await _reset()
	var hold_peg := game.room.get_node_or_null("Objects/GrapplePeg2") as GrapplePeg
	var swing_peg := game.room.get_node_or_null("Objects/GrapplePeg1") as GrapplePeg
	_check("pegs: the test room has a hold peg and a swing peg 45 degrees up-right of it",
		hold_peg != null and swing_peg != null and (swing_peg.global_position - hold_peg.global_position).normalized().is_equal_approx(Vector2(1, -1).normalized()),
		[hold_peg, swing_peg])
	if hold_peg == null or swing_peg == null:
		return
	var masks_clear := (p.collision_mask & GrapplePeg.MASK) == 0
	for e in game.enemies:
		masks_clear = masks_clear and (e.collision_mask & GrapplePeg.MASK) == 0
	_check("pegs: alone on layer 7, and no player or enemy collides with that layer",
		hold_peg.collision_layer == GrapplePeg.MASK and hold_peg.collision_mask == 0 and masks_clear and ProjectSettings.get_setting("layer_names/2d_physics/layer_7") == "grapple_peg",
		[hold_peg.collision_layer, hold_peg.collision_mask, p.collision_mask])
	# The body passes straight through a peg.
	_place_center(hold_peg.global_position + Vector2(-60, 0), 1)
	var through := not p.test_move(p.global_transform, Vector2(120, 0))
	_check("pegs: the player's body passes through a peg", through)

	# Mode B: a standard throw pulls to the peg and then HOLDS there, still.
	var held := await _hang_from_peg(hold_peg)
	var at := p.global_position
	var still := true
	for i in 30:
		still = still and hook.is_holding() and p.state_name() == "grapple" and p.velocity == Vector2.ZERO
		await _frames(1)
	_check("pegs: a standard throw pulls the player to the peg and the hook stays attached",
		held and hook.is_latched() and hook.anchor == hold_peg.global_position and p.get_center().distance_to(hook.hang_point()) < 1.0,
		[held, hook.phase, hook.anchor, p.get_center()])
	_check("pegs: the hold is static (no gravity, zero velocity, no drift)", still and p.global_position.distance_to(at) < 0.01, [still, p.global_position - at])
	Input.action_press(&"move_left")
	await _frames(2)
	var turned_left := p.facing == -1 and hook.is_holding()
	Input.action_release(&"move_left")
	Input.action_press(&"move_right")
	await _frames(2)
	var turned_right := p.facing == 1 and hook.is_holding()
	Input.action_release(&"move_right")
	_check("pegs: Left / Right only turn the player during a hold", turned_left and turned_right and p.global_position.distance_to(at) < 0.01, [turned_left, turned_right])

	# Reachable in play: standing on the block left of the pit, a plain
	# throw right reaches the hold peg.
	await _reset()
	game.combat.reset()
	p.global_position = Vector2(1390, 607)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(3)
	var on_block := p.grounded
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	var ledge_hold := false
	for i in 60:
		ledge_hold = ledge_hold or hook.is_holding()
		await _frames(1)
	_check("pegs: the hold peg is reachable from the block left of the pit (plain throw right)", on_block and ledge_hold, [on_block, hook.phase, p.get_center()])
	game.combat.reset()

	# Any other action lets go at once (and still does its job).
	var released := {}
	for action in [&"jump", &"move_down", &"move_up", &"attack", &"grapple", &"dash", &"spell"]:
		if not await _hang_from_peg(hold_peg):
			released[action] = "no hold"
			continue
		await _frames(2)
		Input.action_press(action)
		await _frames(2)
		Input.action_release(action)
		var ok := not hook.is_latched() and p.state_name() != "grapple"
		if action == &"jump":
			ok = ok and p.velocity.y < 0.0
		elif action == &"dash":
			ok = ok and p.state_name() == "dash"
		elif action == &"grapple":
			ok = ok and not hook.is_flying() # Lets go only; no new throw.
		released[action] = [ok, p.state_name(), hook.phase] if not ok else true
		await _frames(10)
	var all_released := true
	for action in released:
		all_released = all_released and released[action] is bool and released[action]
	_check("pegs: Jump, Down, Up, Attack, Grapple, Dash and Spell each end the hold at once", all_released, released)

	# Mode A: a swing throw (Down in the air) swings around the peg.
	await _reset()
	game.combat.reset()
	for e in game.enemies: # Out of the hook's path and the arc.
		e.patrol = false
		e.global_position = Vector2(200, 100)
	for i in 60:
		if p.state_name() == "normal":
			break
		await _frames(1)
	var start := swing_peg.global_position + Vector2(-100, 100) - GrappleHook.HAND_OFFSET
	_place_center(start, 1)
	await _frames(1)
	_place_center(start, 1)
	var swing_log := []
	var on_fired := func(o: Vector2, d: Vector2) -> void: swing_log.append(["fired", o, d])
	var on_latched := func(a: Vector2, _e: bool) -> void: swing_log.append(["latched", a])
	var on_ended := func(r: String) -> void: swing_log.append(["ended", r])
	Events.grapple_fired.connect(on_fired)
	Events.grapple_latched.connect(on_latched)
	Events.grapple_swing_ended.connect(on_ended)
	Input.action_press(&"move_down")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_down")
	for i in 20:
		if hook.is_swinging():
			break
		await _frames(1)
	await _frames(1)
	var gs: GrappleState = p.fsm.states["grapple"]
	var rope := gs.rope_length
	var dev := 0.0
	var moved := 0.0
	for i in 20:
		if not hook.is_swinging():
			break
		dev = maxf(dev, absf(p.get_center().distance_to(hook.anchor) - rope))
		moved = maxf(moved, p.get_center().distance_to(start))
		await _frames(1)
	_check("pegs: a swing throw (Down in the air) swings around the peg on a fixed rope",
		hook.is_swinging() and hook.on_peg() and hook.anchor == swing_peg.global_position and dev < 1.5 and moved > 20.0,
		[hook.phase, hook.anchor, dev, moved, swing_log])
	Events.grapple_fired.disconnect(on_fired)
	Events.grapple_latched.disconnect(on_latched)
	Events.grapple_swing_ended.disconnect(on_ended)
	game.combat.reset()
	await _reset()


## Waits up to `frames` steps for `cond`; returns whether it came true.
func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await _frames(1)
	return cond.call()


func _objects_of(kind: Variant, variant := "") -> Array:
	var list := []
	for node in game.room.get_objects():
		if is_instance_of(node, kind) and (variant == "" or node.kind == variant):
			list.append(node)
	return list


## A real jump toward `target` (a Platform): full jump, Right held until the
## player is over the target, then a landing check. Returns true when the
## player stands on it.
func _jump_onto(target: Platform, double := false) -> bool:
	var p: Player = game.player
	Input.action_press(&"jump")
	Input.action_press(&"move_right")
	await _frames(2)
	var jumped_again := false
	for i in 90:
		if p.global_position.x >= target.global_position.x - 8.0:
			Input.action_release(&"move_right")
		if double and not jumped_again and p.velocity.y > 0.0:
			Input.action_release(&"jump")
			await _frames(1)
			Input.action_press(&"jump")
			jumped_again = true
		if i > 4 and target.supports(p):
			break
		await _frames(1)
	Input.action_release(&"jump")
	Input.action_release(&"move_right")
	return target.supports(p)


## A plain throw (no direction) right; returns true once the hook holds a peg.
func _throw_to_hold() -> bool:
	var hook: GrappleHook = game.combat.grapple
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	return await _until(func() -> bool: return hook.is_holding(), 60)


func _test_lava_room() -> void:
	var p: Player = game.player
	var hook: GrappleHook = game.combat.grapple
	var god: bool = Config.upgrades.god_mode
	Config.upgrades.god_mode = false
	game.combat.reset()
	game.load_room("lava_room", "west")
	await _frames(3)
	var room: Room = game.room
	var bounds: Rect2 = room.get_bounds()

	# Layout: lava over the whole floor between the two doorway ledges.
	var lavas: Array = _objects_of(Lava)
	var lava_rect := Rect2()
	for lava in lavas:
		lava_rect = lava.get_rect() if not lava_rect.has_area() else lava_rect.merge(lava.get_rect())
	var floor_y := lava_rect.end.y
	_check("lava room: lava covers the floor except the entrance and exit ledges",
		lavas.size() >= 1 and is_equal_approx(lava_rect.position.x, 5 * 32.0) and is_equal_approx(lava_rect.end.x, 59 * 32.0)
		and room.is_solid_at(Vector2(100, floor_y - 16)) and room.is_solid_at(Vector2(1950, floor_y - 16)), [lava_rect])
	var on_floor := true
	for lava in lavas:
		for x in range(int(lava.global_position.x) + 16, int(lava.global_position.x + lava.size.x), 32):
			on_floor = on_floor and room.is_solid_at(Vector2(x, lava.global_position.y + lava.size.y + 16))
	_check("lava room: lava lies only on solid floor (floor-only hazard)", on_floor)
	_check("lava room: a high, open ceiling over the course", bounds.size.y >= 18 * 32 and not room.is_solid_at(Vector2(1000, 3 * 32)), bounds)
	var doors: Array = room.get_doors()
	_check("lava room: entrance west (Upper Galleries), exit east (Hidden Vault)",
		doors.size() == 2 and _door("west") != null and _door("west").target_room == "upper_room"
		and _door("east") != null and _door("east").target_room == "hidden_vault", doors.size())
	var kinds := {}
	for node in _objects_of(Platform):
		kinds["platform " + node.kind] = kinds.get("platform " + node.kind, 0) + 1
	for node in _objects_of(GrapplePeg):
		kinds["peg " + node.kind] = kinds.get("peg " + node.kind, 0) + 1
	_check("lava room: the course uses every platform and peg kind",
		kinds.get("platform standard", 0) >= 1 and kinds.get("platform moving", 0) >= 1 and kinds.get("platform breakable", 0) >= 1
		and kinds.get("peg standard", 0) >= 1 and kinds.get("peg moving", 0) >= 1 and kinds.get("peg breakable", 0) >= 1, kinds)

	# Visual distinction: each kind has its own colors (and markings).
	var plat_colors := {}
	for kind in ["standard", "moving", "breakable"]:
		var node: Platform = load(PLATFORM_SCENE_PATHS[kind]).instantiate()
		plat_colors[kind] = (node.get_node("Visual/Body") as Polygon2D).color
		node.free()
	var peg_colors := {}
	for kind in ["standard", "moving", "breakable"]:
		var node: GrapplePeg = load(PEG_SCENE_PATHS[kind]).instantiate()
		var tex := (node.get_node("Visual") as Sprite2D).texture as GradientTexture2D
		peg_colors[kind] = tex.gradient.get_color(1)
		node.free()
	_check("visuals: standard, moving and breakable platforms and pegs look different",
		plat_colors.values().size() == 3 and plat_colors.standard != plat_colors.moving and plat_colors.moving != plat_colors.breakable and plat_colors.standard != plat_colors.breakable
		and peg_colors.standard != peg_colors.moving and peg_colors.moving != peg_colors.breakable and peg_colors.standard != peg_colors.breakable,
		[plat_colors, peg_colors])

	# Lava: touching it hurts and sends the player back to safe ground.
	var respawns := []
	var pogos := []
	var on_respawn := func(_pl: Node, from: Vector2, to: Vector2) -> void: respawns.append([from, to])
	var on_pogo := func(pos: Vector2, _h: bool) -> void: pogos.append(pos)
	Events.player_hazard_respawn.connect(on_respawn)
	Events.pogo_bounced.connect(on_pogo)
	p.health.full_heal()
	var hp := p.health.health
	p.global_position = Vector2(700, floor_y - 60)
	p.velocity = Vector2.ZERO
	await _until(func() -> bool: return not respawns.is_empty(), 60)
	_check("lava: touching it deals hazard damage and returns the player to safe ground",
		respawns.size() == 1 and p.health.health < hp and respawns[0][1].x < 5 * 32.0, [respawns, p.health.health])
	await _frames(10)

	# No pogo: a down-attack over lava never bounces; the player falls in.
	respawns.clear()
	p.global_position = Vector2(900, floor_y - 90)
	p.velocity = Vector2(0, 200)
	await _frames(1)
	Input.action_press(&"move_down")
	Input.action_press(&"attack")
	await _frames(2)
	Input.action_release(&"attack")
	await _until(func() -> bool: return not respawns.is_empty(), 60)
	Input.action_release(&"move_down")
	_check("lava: a pogo over lava never bounces; it falls in and takes the hazard respawn",
		pogos.is_empty() and respawns.size() == 1, [pogos, respawns])
	_check("lava: the pogo check skips lava (it only sees spikes)",
		room.find_hazard(lava_rect, false) == Rect2() and room.find_hazard(lava_rect).has_area())
	Events.player_hazard_respawn.disconnect(on_respawn)
	Events.pogo_bounced.disconnect(on_pogo)
	await _frames(10)

	# A full run with real input, left to right, no teleports.
	game.load_room("lava_room", "west")
	await _frames(5)
	room = game.room
	var standard: Array = _objects_of(Platform, "standard")
	standard.sort_custom(func(a, b) -> bool: return a.global_position.x < b.global_position.x)
	var plat_a: Platform = standard[0]
	var plat_c: Platform = standard[1]
	var movers: Array = _objects_of(Platform, "moving")
	movers.sort_custom(func(a, b) -> bool: return a.global_position.x < b.global_position.x)
	var plat_b: Platform = movers[0]
	var plat_e: Platform = movers[1]
	var plat_d: Platform = _objects_of(Platform, "breakable")[0]
	var peg1: GrapplePeg = _objects_of(GrapplePeg, "standard")[0]
	var peg2: GrapplePeg = _objects_of(GrapplePeg, "moving")[0]
	var peg3: GrapplePeg = _objects_of(GrapplePeg, "breakable")[0]
	var fell := [0]
	var on_fall := func(_pl: Node, _f: Vector2, _t: Vector2) -> void: fell[0] += 1
	Events.player_hazard_respawn.connect(on_fall)
	var steps := {}
	# 1. West ledge -> standard platform A.
	Input.action_press(&"move_right")
	await _until(func() -> bool: return p.global_position.x >= 5 * 32.0 - 16.0, 120)
	Input.action_release(&"move_right")
	steps["1 ledge -> A"] = await _jump_onto(plat_a)
	# 2. A -> moving platform B (wait until it is near), then ride it.
	Input.action_press(&"move_right")
	await _until(func() -> bool: return p.global_position.x >= plat_a.get_rect().end.x - 14.0, 60)
	Input.action_release(&"move_right")
	await _until(func() -> bool: return plat_b.get_rect().position.x <= 400.0, 300)
	steps["2 A -> moving B"] = await _jump_onto(plat_b)
	var ride_from := p.global_position.x - plat_b.global_position.x
	var rode := await _until(func() -> bool: return plat_b.global_position.x >= plat_b.mover.start.x + 120.0, 300)
	steps["2b rides B"] = rode and plat_b.supports(p) and absf(p.global_position.x - plat_b.global_position.x - ride_from) < 2.0
	# 3. Throw at peg P1 from B: hold.
	steps["3 B -> hold P1"] = await _throw_to_hold() and hook.target_peg == peg1
	await _frames(5)
	# 4. Jump from the hold to standard platform C.
	steps["4 P1 -> C"] = await _jump_onto(plat_c)
	# 5. Throw at moving peg P2 when it is low: hold, ride it up.
	Input.action_press(&"move_right")
	await _until(func() -> bool: return p.global_position.x >= plat_c.get_rect().end.x - 14.0, 60)
	Input.action_release(&"move_right")
	await _frames(4)
	await _until(func() -> bool: return absf(peg2.global_position.y - hook.rope_origin(p).y) < 6.0, 300)
	steps["5 C -> hold moving P2"] = await _throw_to_hold() and hook.target_peg == peg2
	var tether := 0.0
	var high := await _until(func() -> bool:
		tether = maxf(tether, p.get_center().distance_to(hook.hang_point()))
		return peg2.global_position.y <= peg2.mover.start.y - 120.0, 300)
	steps["5b the hold rides P2 up"] = high and hook.is_holding() and tether < 2.0
	# 6. Jump from P2 to breakable platform D (double jump).
	steps["6 P2 -> breakable D"] = await _jump_onto(plat_d, true)
	# 7. Throw at breakable peg P3 from D before D crumbles.
	Input.action_press(&"move_right")
	await _until(func() -> bool: return p.global_position.x >= plat_d.get_rect().end.x - 14.0, 30)
	Input.action_release(&"move_right")
	steps["7 D -> hold breakable P3"] = await _throw_to_hold() and hook.target_peg == peg3
	# 8. Jump right before P3 crumbles: E or the east ledge.
	Input.action_press(&"jump")
	Input.action_press(&"move_right")
	var landed := await _until(func() -> bool: return p.grounded and p.global_position.x > plat_e.mover.start.x - plat_e.size.x / 2.0, 120)
	Input.action_release(&"jump")
	await _until(func() -> bool: return p.global_position.x >= 61 * 32.0, 240)
	Input.action_release(&"move_right")
	steps["8 P3 -> E / east ledge -> relic"] = landed and game.world.has_relic("ember_heart")
	steps["no fall into the lava on the way"] = fell[0] == 0
	Events.player_hazard_respawn.disconnect(on_fall)
	var run_ok := true
	for k in steps:
		run_ok = run_ok and steps[k]
	_check("lava room: a full run across with real input (both platform and peg kinds, no lava)", run_ok, steps)

	# Breakable platform: crumbles after its delay, drops the player, comes back.
	game.load_room("lava_room", "west")
	await _frames(3)
	plat_d = _objects_of(Platform, "breakable")[0]
	p.global_position = Vector2(plat_d.global_position.x, plat_d.top_y() - 1.0)
	p.velocity = Vector2.ZERO
	await _until(func() -> bool: return plat_d.supports(p), 20)
	var t0 := Time.get_ticks_msec()
	var stood := plat_d.supports(p)
	var held_until := 0
	for i in 200:
		if not plat_d.solid:
			break
		held_until = i
		await _frames(1)
	await _frames(3)
	_check("breakable platform: stays for its delay, then crumbles and drops the player",
		stood and not plat_d.solid and not plat_d.visible and absf(held_until / 60.0 - plat_d.crumble_delay) < 0.1 and not plat_d.supports(p),
		[stood, held_until, plat_d.solid])
	game.combat.reset()
	p.global_position = Vector2(80, floor_y - 40)
	p.velocity = Vector2.ZERO
	var back := await _until(func() -> bool: return plat_d.solid, int((plat_d.respawn_time + 0.5) * 60))
	_check("breakable platform: comes back after its respawn time", back and plat_d.visible)

	# Breakable peg: the hook lets go when it crumbles; it comes back.
	peg3 = _objects_of(GrapplePeg, "breakable")[0]
	plat_d = _objects_of(Platform, "breakable")[0]
	await _reset_in_room(Vector2(plat_d.get_rect().end.x - 12.0, plat_d.top_y() - 1.0))
	var peg_held := await _throw_to_hold()
	var let_go := await _until(func() -> bool: return not hook.is_latched(), int((peg3.crumble_delay + 0.3) * 60))
	_check("breakable peg: crumbles after its delay and the hook lets go (the player drops)",
		peg_held and let_go and not peg3.active and peg3.collision_layer == 0 and p.state_name() != "grapple", [peg_held, let_go, peg3.active, p.state_name()])
	var peg_back := await _until(func() -> bool: return peg3.active, int((peg3.respawn_time + 0.5) * 60))
	_check("breakable peg: comes back after its respawn time", peg_back and peg3.visible and peg3.collision_layer == GrapplePeg.MASK)

	# Swing tether on a moving peg: the rope anchor follows the peg.
	peg2 = _objects_of(GrapplePeg, "moving")[0]
	await _reset_in_room(Vector2(1100, 400))
	var start := peg2.global_position + Vector2(-70, 70) - GrappleHook.HAND_OFFSET # Clear of the lava.
	p.global_position += start - p.get_center()
	p.velocity = Vector2.ZERO
	p.facing = 1
	Input.action_press(&"move_down")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_down")
	var swung := await _until(func() -> bool: return hook.is_swinging(), 30)
	var follows := true
	for i in 15:
		if not hook.is_swinging():
			break
		follows = follows and hook.anchor.distance_to(peg2.global_position) < 0.01
		await _frames(1)
	_check("moving peg: a swing's rope anchor follows the moving peg", swung and follows and hook.on_peg(), [swung, follows, hook.phase])
	game.combat.reset()

	# Hook on a moving platform (from below, Up): the anchor rides along.
	var plat_b2: Platform = _objects_of(Platform, "moving")[0]
	for b2 in _objects_of(Platform, "moving"):
		if b2.global_position.x < plat_b2.global_position.x:
			plat_b2 = b2
	await _reset_in_room(Vector2(plat_b2.global_position.x, plat_b2.top_y() + 90.0))
	var under := plat_b2.global_position.x
	p.global_position.x = under
	Input.action_press(&"move_up")
	Input.action_press(&"grapple")
	await _frames(2)
	Input.action_release(&"grapple")
	Input.action_release(&"move_up")
	var latched_b := await _until(func() -> bool: return hook.is_latched(), 20)
	var offset := hook.anchor - plat_b2.global_position
	var rides := true
	for i in 6:
		if not hook.is_latched():
			break
		await _frames(1)
		rides = rides and (hook.anchor - plat_b2.global_position).distance_to(offset) < 0.01
	_check("moving platform: a hook on it keeps its anchor on the platform as it moves",
		latched_b and rides and hook.anchor_platform == plat_b2, [latched_b, rides, hook.phase])
	game.combat.reset()

	Config.upgrades.god_mode = god
	if game.world.has_relic("ember_heart"): # Undo the reward for the tests that follow.
		game.world.relics.erase("ember_heart")
		p.health.max_energy_bonus -= 20.0
	await _reset()


## Puts the player at `feet` in the current room, still, facing right.
func _reset_in_room(feet: Vector2) -> void:
	var p: Player = game.player
	game.combat.reset()
	p.fsm.change("normal")
	p.global_position = feet
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(3)
	p.global_position = feet
	p.velocity = Vector2.ZERO

## Sends a real keyboard event (physical key), like a key press on hardware.
func _key_event(key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## The actions in the Input Map that a physical key triggers.
func _actions_for(key: Key) -> Array:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.pressed = true
	var found := []
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_") and InputMap.event_is_action(e, action, true):
			found.append(String(action))
	return found


func _test_keybindings() -> void:
	Settings.reset_controls()
	var wasd := []
	for key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		wasd.append_array(_actions_for(key))
		for action in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			if InputMap.event_is_action(e, action, true):
				wasd.append(String(action))
	_check("keys: W, A, S and D trigger nothing by default (no hidden WASD)", wasd.is_empty(), wasd)
	var seen := {}
	var dupes := []
	var extra := []
	for action in Settings.REBINDABLE:
		var n_keys := 0
		var n_buttons := 0
		for e in InputMap.action_get_events(action):
			var id := ""
			if e is InputEventKey:
				n_keys += 1
				id = "key %d" % e.physical_keycode
			elif e is InputEventJoypadButton:
				n_buttons += 1
				id = "button %d" % e.button_index
			if id != "":
				if seen.has(id):
					dupes.append([id, seen[id], action])
				seen[id] = action
		if n_keys != 1 or n_buttons != 1:
			extra.append([action, n_keys, n_buttons])
	_check("keys: every action has exactly one key and one gamepad button", extra.is_empty(), extra)
	_check("keys: no key or button is bound to two actions", dupes.is_empty(), dupes)

	# Conflict: Heal takes Spell's key. Spell gets Heal's old key (a swap).
	Settings.rebind("heal", KEY_U)
	_check("keys: binding a taken key moves it (Heal gets U, Spell gets L)",
		Settings.key_name("heal") == "U" and Settings.key_name("spell") == "L" and _actions_for(KEY_U) == ["heal"] and _actions_for(KEY_L) == ["spell"],
		[Settings.key_name("heal"), Settings.key_name("spell"), _actions_for(KEY_U), _actions_for(KEY_L)])
	Settings.rebind_button("grapple", JOY_BUTTON_A)
	_check("keys: binding a taken gamepad button swaps it too (Grapple gets A, Jump gets L3)",
		Settings.button_name("grapple") == "A" and Settings.button_name("jump") == "L3", [Settings.button_name("grapple"), Settings.button_name("jump")])
	_check("keys: the fixed debug keys cannot be taken (R stays Reset Room)",
		not Settings.rebind("jump", KEY_R) and Settings.key_name("jump") == "Space" and _actions_for(KEY_R) == ["reset_room"], [Settings.key_name("jump"), _actions_for(KEY_R)])
	Settings.reset_controls()

	# A saved conflict (e.g. an old settings file): the customized action keeps
	# the key, the other one is left unbound.
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "heal", int(KEY_U))
	cfg.save(Settings.config_path)
	Settings.load_settings()
	Settings.apply()
	_check("keys: a saved conflict unbinds the other action (Spell shows '-', U only heals)",
		Settings.key_name("heal") == "U" and Settings.key_name("spell") == "-" and _actions_for(KEY_U) == ["heal"],
		[Settings.key_name("heal"), Settings.key_name("spell"), _actions_for(KEY_U)])
	Settings.reset_controls()

	# Grapple on S: S throws the hook and is not Down (no swing, no pogo, no
	# down-aim). Tested with real key events, in the air.
	var p: Player = game.player
	var hook: GrappleHook = game.combat.grapple
	Settings.rebind("grapple", KEY_S)
	_check("keys: S bound to Grapple triggers only Grapple", _actions_for(KEY_S) == ["grapple"] and Settings.key_name("move_down") == "Down",
		[_actions_for(KEY_S), Settings.key_name("move_down")])
	await _reset()
	p.global_position = Vector2(1300, 200)
	p.velocity = Vector2.ZERO
	p.facing = 1
	await _frames(1)
	_key_event(KEY_S, true)
	await _frames(1)
	var down_held := Input.is_action_pressed(&"move_down") or p.input.axis_y() != 0
	await _frames(1)
	_key_event(KEY_S, false)
	_check("keys: Grapple on S fires the hook straight ahead in the air, not as a Down swing",
		not down_held and not hook.is_idle() and not hook.swing_mode and hook.dir == Vector2.RIGHT and game.combat.attack.is_empty(),
		[down_held, hook.phase, hook.swing_mode, hook.dir])
	game.combat.reset()
	# Now give S to Aim down: it leaves Grapple (Grapple gets Down instead).
	Settings.rebind("move_down", KEY_S)
	_check("keys: S moved to Aim down triggers only Aim down; Grapple takes the old key",
		_actions_for(KEY_S) == ["move_down"] and Settings.key_name("grapple") == "Down", [_actions_for(KEY_S), Settings.key_name("grapple")])
	_key_event(KEY_S, true)
	var down_now := Input.is_action_pressed(&"move_down") and not Input.is_action_pressed(&"grapple")
	_key_event(KEY_S, false)
	_check("keys: S held is Down once it is bound to Aim down", down_now)
	Settings.reset_controls()
	await _reset()

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
	for card in inv.pool_cards:
		if card.ability.id == ability_id:
			card.grab_focus()
	await _frames(1)


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


# ---------- Progression: low start, potions, scrolls, meditation altars ----------

## A brand-new game: low maximums, no equippable spell, every slot locked,
## Mana Discharge alone on the neutral input (it works even at low energy).
func _test_starting_state() -> void:
	var p: Player = game.player
	var h := p.health
	var data: PlayerData = game.player_data
	var manager: UltimateManager = game.ultimates
	_check("a new game starts with low max health and max energy",
		is_equal_approx(h.get_max_health(), HealthEnergy.STARTING_MAX_HEALTH) and is_equal_approx(h.get_max_energy(), HealthEnergy.STARTING_MAX_ENERGY)
		and h.get_max_health() < 100.0 and h.get_max_energy() < 100.0 and is_equal_approx(h.health, h.get_max_health()),
		[h.get_max_health(), h.get_max_energy(), h.health])
	_check("a new game knows ZERO equippable spells", data.unlocked.is_empty() and manager.unlocked_abilities().is_empty(), data.unlocked)
	var all_locked := true
	for slot in PlayerData.SLOT_COUNT:
		all_locked = all_locked and not data.is_slot_open(slot) and manager.get_slot(slot) == null
	_check("every Up / Side / Down slot starts locked and empty", all_locked, data.open_slots)
	manager.set_known("nova_burst", true)
	_check("a locked slot refuses a spell, even from debug tools",
		not manager.equip(PlayerData.SLOT_UP, "nova_burst", true) and data.equipped[PlayerData.SLOT_UP] == "", data.equipped)
	manager.set_known("nova_burst", false)
	_check("Mana Discharge is fixed to the neutral input from the start",
		manager.neutral_spell() != null and manager.neutral_spell().id == PlayerData.NEUTRAL_SPELL and manager.neutral_spell().fixed)
	var cross: SpellCross = game.hud.spell_cross
	_check("the HUD cross shows padlocks on the locked slots and Mana Discharge in the center",
		(cross.card("Up") as SpellNodeView).locked and (cross.card("Left") as SpellNodeView).locked
		and (cross.card("Down") as SpellNodeView).locked and not (cross.card("Center") as SpellNodeView).locked)

	# Spell + a direction on a locked slot casts nothing.
	var denied := []
	var on_denied := func(_a: RefCounted, reason: String) -> void: denied.append(reason)
	Events.ultimate_denied.connect(on_denied)
	h.set_energy(40.0)
	Input.action_press(&"move_up")
	Input.action_press(&"spell")
	await _frames(2)
	Input.action_release(&"spell")
	Input.action_release(&"move_up")
	Events.ultimate_denied.disconnect(on_denied)
	_check("Spell + Up on a locked slot casts nothing", denied.has("locked") and is_equal_approx(h.energy, 40.0) and p.state_name() == "normal",
		[denied, h.energy, p.state_name()])
	await _frames(10)

	# Mana Discharge at the low starting energy: a real wave, then a fizzle.
	var md: ManaDischarge = manager.get_ability("mana_discharge")
	h.set_energy(h.get_max_energy())
	await _cast_neutral()
	await _frames(20)
	_check("Mana Discharge works with the low starting energy (wave sized by the small max)",
		is_zero_approx(h.energy) and not md.failed and is_equal_approx(md.max_radius, Config.ultimates.mana_discharge.radius_per_energy * h.get_max_energy()),
		[h.energy, md.failed, md.max_radius])
	await _frames(30)
	h.set_energy(5.0)
	await _cast_neutral()
	await _frames(5)
	_check("Mana Discharge still casts at very low energy (drains and fizzles)", is_zero_approx(h.energy) and md.failed, [h.energy, md.failed])
	await _frames(40)

	var scrolls := _objects_of(SpellScroll)
	var altar: MeditationAltar = _objects_of(MeditationAltar)[0] if not _objects_of(MeditationAltar).is_empty() else null
	_check("the Testing Halls hold Spell Scrolls and a Meditation Altar, all unused",
		scrolls.size() >= 2 and scrolls.all(func(s: SpellScroll) -> bool: return not s.collected and s.visible) and altar != null and not altar.spent,
		[scrolls.size(), altar])


## Gives the player everything the older checks expect: all spells known,
## every slot open, the default loadout, and 100 / 100 maximums.
func _grant_test_kit() -> void:
	var h: HealthEnergy = game.player.health
	game.grant_full_kit()
	h.set_base_max_health(100.0)
	h.set_base_max_energy(100.0)
	h.full_heal()


func _test_progression() -> void:
	var p: Player = game.player
	var h := p.health
	var data: PlayerData = game.player_data
	var manager: UltimateManager = game.ultimates
	var saved_bonus := [h.max_health_bonus, h.max_energy_bonus]

	# Back to a fresh start (same game instance).
	game.new_game()
	data.unlocked.clear()
	data.equipped = PlayerData.empty_slots()
	data.open_slots = PlayerData.locked_slots()
	h.set_base_max_health(HealthEnergy.STARTING_MAX_HEALTH)
	h.set_base_max_energy(HealthEnergy.STARTING_MAX_ENERGY)
	h.max_health_bonus = 0.0
	h.max_energy_bonus = 0.0
	Events.loadout_changed.emit()
	await _reset()

	# --- Every room together: scrolls teach every spell once, altars open every slot ---
	var scroll_spells := []
	var altar_slots := []
	var health_potions := 0
	var mana_potions := 0
	for rid in game.ROOM_SCENES:
		var scene_root: Node = (game.ROOM_SCENES[rid] as PackedScene).instantiate()
		for node in scene_root.get_node("Objects").get_children():
			if node is SpellScroll:
				scroll_spells.append(node.spell_id)
			elif node is MeditationAltar:
				altar_slots.append(node.slot_name)
			elif node is Potion:
				if node.stat == "max_energy":
					mana_potions += 1
				else:
					health_potions += 1
		scene_root.free()
	var equippable := []
	for id in manager.abilities:
		if not manager.abilities[id].fixed:
			equippable.append(id)
	scroll_spells.sort()
	equippable.sort()
	_check("one Spell Scroll per equippable spell is scattered in the world", scroll_spells == equippable, scroll_spells)
	altar_slots.sort()
	_check("three Meditation Altars open the Down, Side and Up slots", altar_slots == ["down", "side", "up"], altar_slots)
	_check("Health and Mana Potions are placed in the world", health_potions >= 2 and mana_potions >= 2, [health_potions, mana_potions])

	# --- Potions: distinct looks, permanent growth ---
	var hp_potion: Potion = null
	var mp_potion: Potion = null
	for relic in game.relics:
		if relic is Potion:
			if relic.stat == "max_health" and hp_potion == null:
				hp_potion = relic
			elif relic.stat == "max_energy" and mp_potion == null:
				mp_potion = relic
	_check("the Testing Halls hold a Health Potion and a Mana Potion", hp_potion != null and mp_potion != null)
	var hp_body: Polygon2D = hp_potion.get_node("Visual/Body")
	var mp_body: Polygon2D = mp_potion.get_node("Visual/Body")
	var mc := mp_body.color
	_check("the Mana Potion is blue", mc.b > 0.8 and mc.b > mc.r + 0.4 and mc.b > mc.g + 0.2, mc)
	_check("the Health Potion is red", hp_body.color.r > hp_body.color.b + 0.4, hp_body.color)
	var hp_box := _poly_bounds(hp_body.polygon)
	var mp_box := _poly_bounds(mp_body.polygon)
	_check("the two potions have different bottle shapes (the Mana Potion is a tall, narrow bottle)",
		hp_body.polygon.size() != mp_body.polygon.size() and mp_box.size.y / mp_box.size.x > hp_box.size.y / hp_box.size.x + 0.2
		and mp_potion.get_node_or_null("Visual/Lip") != null and hp_potion.get_node_or_null("Visual/Lip") == null, [hp_box, mp_box])

	h.take_damage(20.0)
	var max_hp := h.get_max_health()
	p.global_position = hp_potion.global_position
	await _frames(4)
	_check("a Health Potion raises max health for good and heals fully",
		hp_potion.collected and is_equal_approx(h.get_max_health(), max_hp + Config.progression.health_potion_amount)
		and is_equal_approx(h.health, h.get_max_health()) and game.world.has_relic(hp_potion.relic_id), [h.get_max_health(), h.health])
	var max_en := h.get_max_energy()
	p.global_position = mp_potion.global_position
	await _frames(4)
	_check("a Mana Potion raises max energy for good",
		mp_potion.collected and is_equal_approx(h.get_max_energy(), max_en + Config.progression.mana_potion_amount), h.get_max_energy())
	var hp_id := hp_potion.relic_id
	game.load_room("upper_room", "floor")
	await _frames(2)
	game.load_room("test_room", "east")
	await _frames(2)
	var still_gone := false
	for relic in game.relics:
		if relic is Potion and relic.relic_id == hp_id:
			still_gone = relic.collected and not relic.visible
	_check("a drunk potion never comes back", still_gone)
	await _reset()

	# --- Spell Scrolls ---
	var scroll: SpellScroll = null
	for s in _objects_of(SpellScroll):
		if s.spell_id == "nova_burst":
			scroll = s
	_check("a Spell Scroll lies near the start", scroll != null)
	var learned := []
	var on_learned := func(id: String) -> void: learned.append(id)
	Events.spell_learned.connect(on_learned)
	p.global_position = scroll.global_position
	await _frames(4)
	Events.spell_learned.disconnect(on_learned)
	_check("collecting a scroll teaches its spell for good",
		scroll.collected and not scroll.visible and data.is_unlocked("nova_burst") and learned == ["nova_burst"]
		and manager.unlocked_abilities().size() == 1, [learned, data.unlocked])
	_check("a learned spell still needs an open slot", not manager.equip(PlayerData.SLOT_UP, "nova_burst", true))
	game.load_room("upper_room", "floor")
	await _frames(2)
	game.load_room("test_room", "east")
	await _frames(2)
	var scroll_back := false
	for s in _objects_of(SpellScroll):
		if s.spell_id == "nova_burst":
			scroll_back = not s.collected
	_check("a collected scroll does not come back", not scroll_back)
	await _reset()

	# --- Meditation altar ---
	var altar: MeditationAltar = _objects_of(MeditationAltar)[0]
	_check("the first altar opens the Up slot", altar.get_slot() == PlayerData.SLOT_UP and altar.prompt == "Concentrate", [altar.slot_name, altar.prompt])
	_check("the player has a meditation animation", p.animator.animation_player.has_animation("meditate"))
	p.global_position = altar.global_position + Vector2(10, 0)
	await _frames(3)
	_check("standing at the altar offers to meditate", game.focused_interactable == altar)
	await _hold(&"interact", 2)
	await _frames(6)
	_check("interacting starts the meditation (state and animation)",
		p.state_name() == "meditate" and p.animator.current == "meditate" and is_equal_approx(p.global_position.x, altar.global_position.x),
		[p.state_name(), p.animator.current, p.global_position.x])
	_check("the slot is still locked during the meditation", not data.is_slot_open(PlayerData.SLOT_UP))
	_check("no prompt shows while kneeling", not altar.highlighted and not altar.can_interact())
	p.receive_hit(5.0, p.global_position.x - 10.0, false, true)
	await _frames(2)
	_check("a hit interrupts the meditation: nothing opens",
		p.state_name() != "meditate" and not data.is_slot_open(PlayerData.SLOT_UP) and not altar.spent, [p.state_name(), data.open_slots])
	await _frames(70)
	h.full_heal()
	p.global_position = altar.global_position
	await _frames(3)
	var finished := []
	var on_finished := func(_a: Node, slot: int) -> void: finished.append(slot)
	Events.meditation_finished.connect(on_finished)
	await _hold(&"interact", 2)
	var frames := int(Config.progression.meditation_time * 60.0) + 20
	await _frames(frames)
	Events.meditation_finished.disconnect(on_finished)
	_check("a full meditation opens the Up slot for good",
		data.is_slot_open(PlayerData.SLOT_UP) and finished == [PlayerData.SLOT_UP] and p.state_name() == "normal", [data.open_slots, finished, p.state_name()])
	_check("a spent altar offers nothing more", altar.spent and not altar.can_interact() and game.focused_interactable != altar)
	_check("the other slots stay locked", not data.is_slot_open(PlayerData.SLOT_SIDE) and not data.is_slot_open(PlayerData.SLOT_DOWN))
	_check("the HUD cross unlocks the Up node", not (game.hud.spell_cross.card("Up") as SpellNodeView).locked)

	# Equip the learned spell at the saved checkpoint and cast it.
	await _reset()
	p.at_checkpoint = true
	_check("a learned spell goes on the opened slot at the checkpoint", manager.equip(PlayerData.SLOT_UP, "nova_burst"))
	_check("a locked slot still refuses it", not manager.equip(PlayerData.SLOT_SIDE, "nova_burst"))
	h.set_energy(h.get_max_energy())
	var before := h.energy
	Input.action_press(&"move_up")
	Input.action_press(&"spell")
	await _frames(2)
	Input.action_release(&"spell")
	Input.action_release(&"move_up")
	_check("Spell + Up casts the equipped spell", is_equal_approx(h.energy, before - Config.ultimates.nova_burst.cost), h.energy)
	await _frames(40)

	# Inventory: a locked node cannot take a spell.
	game.inventory.toggle()
	await _frames(2)
	game.inventory.switch_tab(1)
	await _frames(1)
	game.inventory.pending_ability_id = "nova_burst"
	game.inventory.press_node("Down")
	_check("the inventory refuses a locked slot", data.equipped[PlayerData.SLOT_DOWN] == "" and (game.inventory.cross.card("Down") as AbilityCard).locked)
	game.inventory.pending_ability_id = ""
	game.inventory.toggle()
	await _frames(2)

	# --- Saves keep the progression ---
	var saved: Dictionary = game.make_save_data()
	_check("a save stores the open slots", saved.get("open_slots", []) == [true, false, false], saved.get("open_slots"))
	data.open_slots = PlayerData.locked_slots()
	data.unlocked.clear()
	data.equipped = PlayerData.empty_slots()
	game.apply_save_data(saved)
	await _frames(3)
	p.fsm.change("normal")
	_check("loading restores learned spells, open slots and the loadout",
		data.is_unlocked("nova_burst") and data.open_slots == [true, false, false] and data.equipped[PlayerData.SLOT_UP] == "nova_burst",
		[data.unlocked, data.open_slots, data.equipped])
	_check("loading restores the potion growth",
		is_equal_approx(h.max_health_bonus, Config.progression.health_potion_amount) and is_equal_approx(h.max_energy_bonus, Config.progression.mana_potion_amount))
	var spent_after_load := false
	for a in game.altars:
		if a.get_slot() == PlayerData.SLOT_UP:
			spent_after_load = a.spent
	_check("after loading, the used altar stays spent", spent_after_load)
	var old_save := saved.duplicate()
	old_save.erase("open_slots")
	game.apply_save_data(old_save)
	await _frames(3)
	p.fsm.change("normal")
	_check("a save from before progression loads with every slot open", data.open_slots == [true, true, true], data.open_slots)

	# Restore the kit for the remaining checks.
	game.new_game()
	_grant_test_kit()
	h.max_health_bonus = saved_bonus[0]
	h.max_energy_bonus = saved_bonus[1]
	h.full_heal()
	await _reset()


func _poly_bounds(points: PackedVector2Array) -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO)
	for pt in points:
		r = r.expand(pt)
	return r


# ---------- Movement items and tutorial popups ----------

## A new game has no movement ability: no double jump, dash, wall slide or hook.
func _test_no_movement_at_start() -> void:
	var p: Player = game.player
	var data: PlayerData = game.player_data
	_check("a new game knows no movement ability", data.movement.is_empty()
		and PlayerData.MOVEMENT.all(func(id: String) -> bool: return not p.can_use(id)), data.movement)
	await _reset()
	await _hold(&"dash", 2)
	_check("without the Dash item, Dash does nothing", p.state_name() != "dash", p.state_name())
	Input.action_press(&"jump")
	await _frames(15)
	Input.action_release(&"jump")
	await _frames(3)
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	_check("without the Double Jump item, there is no second jump", p.air_jumps_used == 0, p.air_jumps_used)
	await _frames(90)
	p.global_position = Vector2(32 + Player.WIDTH / 2.0 + 1.0, 320) # Next to the left wall.
	p.velocity = Vector2.ZERO
	Input.action_press(&"move_left")
	await _frames(20)
	_check("without the Wall Climb item, there is no wall slide", not p.wall_sliding and p.velocity.y > Config.movement.wall_slide_speed, [p.wall_sliding, p.velocity.y])
	Input.action_release(&"move_left")
	await _frames(90)
	await _reset()
	await _hold(&"grapple", 2)
	_check("without the Grappling Hook item, the hook stays home", game.combat.grapple.phase == "idle" and p.state_name() == "normal", game.combat.grapple.phase)
	await _frames(10)


## Opens the popup through real play and checks the rules: full screen, the
## game paused, a drawing for it, ANY key closes it (after the short guard),
## and that key does nothing in the game.
func _expect_tutorial(id: String, label: String) -> void:
	var p: Player = game.player
	var pop: TutorialPopup = game.tutorial
	_check("%s opens the '%s' tutorial" % [label, id], pop.is_open() and pop.current == id, pop.current)
	if not pop.is_open():
		return
	var vp := pop.screen.get_viewport_rect().size
	_check("the '%s' tutorial covers the whole screen with a drawing" % id,
		pop.screen.visible and pop.screen.size.is_equal_approx(vp) and pop.has_method("_draw_" + id), [pop.screen.size, vp])
	var x := p.global_position.x
	var t: float = game.playtime
	Input.action_press(&"move_right")
	await _frames(20)
	Input.action_release(&"move_right")
	_check("the game is paused under the '%s' tutorial" % id, is_equal_approx(p.global_position.x, x) and is_equal_approx(game.playtime, t), p.global_position.x)
	await _frames(5)
	var y := p.global_position.y
	_key_event(KEY_SPACE, true) # Jump's key: closes the popup and must not jump.
	await _frames(3)
	_key_event(KEY_SPACE, false)
	await _frames(3)
	_check("any key closes the '%s' tutorial, and that key does nothing else" % id,
		not pop.is_open() and not p.is_jumping and p.global_position.y >= y - 1.0, [pop.is_open(), p.global_position.y - y])
	await _frames(5)


func _pickup_for(ability: String) -> AbilityPickup:
	for pk in game.ability_pickups:
		if pk.ability == ability:
			return pk
	return null


func _test_tutorials() -> void:
	var p: Player = game.player
	var h := p.health
	var data: PlayerData = game.player_data
	var pop: TutorialPopup = game.tutorial
	var seen_before := data.seen_tutorials.duplicate()
	_check("no tutorial showed while tutorials were off", seen_before.is_empty() and not pop.is_open(), seen_before)
	_check("the learning hooks exist for move, jump, heal and Mana Discharge",
		game.has_method("learn_move") and game.has_method("learn_jump") and game.has_method("learn_heal") and game.has_method("learn_mana_discharge")
		and ["move", "jump", "heal", "mana_discharge"].all(func(id: String) -> bool: return pop.TITLES.has(id) and pop.has_method("_draw_" + id)))

	# Every movement item exists once in the world.
	var found := []
	for rid in game.ROOM_SCENES:
		var scene_root: Node = (game.ROOM_SCENES[rid] as PackedScene).instantiate()
		for node in scene_root.get_node("Objects").get_children():
			if node is AbilityPickup:
				found.append(node.ability)
		scene_root.free()
	found.sort()
	var expected := PlayerData.MOVEMENT.duplicate()
	expected.sort()
	_check("one item per movement ability is placed in the world", found == expected, found)

	game.new_game()
	await _reset()
	game.tutorials_enabled = true
	data.movement.clear()
	Events.loadout_changed.emit()
	await _frames(2)
	_check("items of unknown abilities are back", _pickup_for("dash") != null and not _pickup_for("dash").collected)

	# --- The three movement items in the Testing Halls ---
	for ability in ["wall_climb", "double_jump", "dash"]:
		await _reset()
		var pk := _pickup_for(ability)
		p.global_position = pk.global_position
		await _frames(3)
		_check("collecting the item teaches %s" % ability, pk.collected and data.has_movement(ability) and p.can_use(ability))
		await _expect_tutorial(ability, "the %s item" % ability)
	# The guard: a key pressed right away does not skip the popup unseen.
	data.seen_tutorials.erase("dash")
	game.show_tutorial("dash")
	_key_event(KEY_Z, true)
	await _frames(2)
	_key_event(KEY_Z, false)
	_check("a key pressed in the first instant does not skip the popup", pop.is_open())
	await _frames(20)
	_key_event(KEY_Z, true)
	await _frames(2)
	_key_event(KEY_Z, false)
	_check("an unbound key closes it too (any key)", not pop.is_open())
	await _frames(5)
	# Only the first time.
	data.movement.erase("dash")
	Events.loadout_changed.emit()
	await _reset()
	p.global_position = _pickup_for("dash").global_position
	await _frames(3)
	_check("the second time, no popup", data.has_movement("dash") and not pop.is_open())
	await _reset()
	await _hold(&"dash", 2)
	_check("the collected Dash works", p.state_name() == "dash", p.state_name())
	await _frames(30)

	# --- The Grappling Hook item in the Upper Galleries ---
	game.load_room("upper_room", "floor")
	await _frames(60)
	var hook := _pickup_for("grapple")
	p.global_position = hook.global_position
	await _frames(3)
	_check("collecting the Grappling Hook item teaches the hook", data.has_movement("grapple") and p.can_use("grapple"))
	await _expect_tutorial("grapple", "the Grappling Hook item")

	# --- Potions, scroll and altar (fresh progression in the Testing Halls) ---
	game.new_game()
	game.ultimates.set_known("nova_burst", false)
	data.open_slots[PlayerData.SLOT_UP] = false
	Events.loadout_changed.emit()
	await _reset()
	for relic in game.relics:
		if relic is Potion and relic.stat == "max_health":
			p.global_position = relic.global_position
			break
	await _frames(3)
	await _expect_tutorial("health_potion", "the first Health Potion")
	for relic in game.relics:
		if relic is Potion and relic.stat == "max_energy":
			p.global_position = relic.global_position
			break
	await _frames(3)
	await _expect_tutorial("mana_potion", "the first Mana Potion")
	await _reset()
	for s in game.scrolls:
		if s.spell_id == "nova_burst":
			p.global_position = s.global_position
	await _frames(3)
	await _expect_tutorial("spell_scroll", "the first Spell Scroll")
	await _reset()
	var altar: MeditationAltar = game.altars[0]
	p.global_position = altar.global_position
	await _frames(3)
	await _hold(&"interact", 2)
	_check("the first meditation opens the concentration tutorial and waits", pop.current == "meditation" and p.state_name() == "meditate"
		and not data.is_slot_open(PlayerData.SLOT_UP), [pop.current, p.state_name()])
	await _expect_tutorial("meditation", "the first altar")
	await _frames(int(Config.progression.meditation_time * 60.0) + 20)
	_check("after the tutorial the meditation completes", data.is_slot_open(PlayerData.SLOT_UP) and p.state_name() == "normal", p.state_name())

	# --- Saves ---
	var saved: Dictionary = game.make_save_data()
	_check("a save stores the movement abilities and the seen tutorials",
		(saved.get("movement", []) as Array).has("grapple") and (saved.get("tutorials", []) as Array).has("meditation"))
	data.movement.clear()
	data.seen_tutorials.clear()
	game.apply_save_data(saved)
	await _frames(3)
	p.fsm.change("normal")
	_check("loading restores the movement abilities and the seen tutorials", data.has_movement("dash") and data.seen_tutorials.has("spell_scroll"))
	var old_save := saved.duplicate()
	old_save.erase("movement")
	game.apply_save_data(old_save)
	await _frames(3)
	p.fsm.change("normal")
	_check("a save from before the movement items keeps every movement ability",
		PlayerData.MOVEMENT.all(func(id: String) -> bool: return data.has_movement(id)), data.movement)
	_check("the basic-action hooks were never invoked in play",
		not ["move", "jump", "heal", "mana_discharge"].any(func(id: String) -> bool: return data.seen_tutorials.has(id)), data.seen_tutorials)

	# Back to the full kit, tutorials off.
	game.tutorials_enabled = false
	game.new_game()
	_grant_test_kit()
	h.max_health_bonus = 0.0
	h.max_energy_bonus = 0.0
	h.full_heal()
	await _reset()


# ---------- Bestiary: modular enemies, deflect / parry, the testing hall ----------

const BESTIARY_KINDS := ["weak", "strong", "flyer", "swooper", "charger", "thrower", "brute", "ambusher",
	"shellback", "urchin", "turret", "orb_sentry", "hopper", "crawler", "phalanx"]


func _beast(kind: String) -> Enemy:
	for e in game.enemies:
		if e.kind == kind:
			return e
	return null


## Into the Bestiary with every enemy fresh at home.
func _fresh_bestiary() -> void:
	if game.room_id != "bestiary":
		game.load_room("bestiary", "ceiling")
		await _frames(20)
	game.reset_enemies()
	game.combat.projectiles.clear()
	await _frames(3)


func _put(at: Vector2, facing := 1) -> void:
	var p: Player = game.player
	p.global_position = at
	p.velocity = Vector2.ZERO
	p.fsm.change("normal")
	p.facing = facing
	p.health.iframe_timer = 0.0
	p.health.full_heal()


func _shots_of(owner: Node) -> Array:
	return game.combat.projectiles.list.filter(func(pr: Dictionary) -> bool: return pr.owner == owner and pr.hostile)


func _swing(facing: int) -> void:
	game.player.facing = facing
	Input.action_press(&"attack")
	await _frames(2)
	Input.action_release(&"attack")


func _test_bestiary() -> void:
	var p: Player = game.player
	var h := p.health
	var god: bool = Config.upgrades.god_mode
	Config.upgrades.god_mode = true

	# --- The hall: one chamber per enemy type, in a row, very long ---
	var scene_root: Node = (game.ROOM_SCENES["bestiary"] as PackedScene).instantiate()
	var kinds := []
	var xs := []
	for m in scene_root.get_node("EnemySpawns").get_children():
		kinds.append(String(m.get_meta("kind")))
		xs.append(m.position.x)
	var signs := 0
	for node in scene_root.get_node("Objects").get_children():
		if node is ChamberSign:
			signs += 1
	scene_root.free()
	var expected_kinds := BESTIARY_KINDS.duplicate()
	expected_kinds.sort()
	kinds.sort()
	_check("the Bestiary holds every non-boss enemy type exactly once (old and new, 15)", kinds == expected_kinds, kinds)
	_check("each chamber has a sign", signs == BESTIARY_KINDS.size(), signs)
	for kind in BESTIARY_KINDS:
		_check("the '%s' kind is registered" % kind, game.ENEMY_SCENES.has(kind))

	# --- Way in: drop through the plank in the Testing Halls floor ---
	await _reset()
	var gap: Door = _door("floor")
	_check("the Testing Halls floor has a gap down to the Bestiary", gap != null and gap.target_room == "bestiary")
	_put(Vector2(gap.global_position.x, 704.0))
	await _frames(10)
	_check("the plank over the gap holds the player", p.grounded and game.room_id == "test_room", [p.grounded, p.global_position])
	Input.action_press(&"move_down")
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	Input.action_release(&"move_down")
	_check("Down + Jump drops through the plank into the Bestiary", await _until(func() -> bool: return game.room_id == "bestiary", 90), game.room_id)
	_check("the arrival lands on the platform under the ceiling gap (Rule A)",
		await _until(func() -> bool: return p.grounded, 60) and p.global_position.y < 150.0, p.global_position)
	var room_w: float = game.room.get_bounds().size.x
	_check("the Bestiary is a very long hall", room_w > 10000.0, room_w)
	# Chambers: a divider hangs between every two neighbouring enemies.
	var homes := []
	for kind in BESTIARY_KINDS:
		var e := _beast(kind)
		homes.append(e.home.x if e else -1.0)
	var separated := true
	for i in homes.size() - 1:
		var wall := false
		var x: float = homes[i] + 16.0
		while x < homes[i + 1]:
			if game.room.is_solid_at(Vector2(x, 5 * 32 + 16)) and game.room.is_solid_at(Vector2(x, 13 * 32 + 16)):
				wall = true
			x += 32.0
		separated = separated and wall
	var ordered := homes.duplicate()
	ordered.sort()
	_check("every enemy has its own chamber, in order (dividers with a curb between them)", separated and ordered == homes, homes)
	# Way out: jump from the top platform back up through the gap.
	Input.action_press(&"jump")
	await _frames(20)
	Input.action_release(&"jump")
	_check("jumping up the gap returns to the Testing Halls beside the plank (Rule B)",
		await _until(func() -> bool: return game.room_id == "test_room" and p.grounded, 120) and not game.last_ejection.is_empty(), game.room_id)

	# --- Old enemies in their chambers ---
	await _fresh_bestiary()
	for kind in ["weak", "strong", "flyer"]:
		var e := _beast(kind)
		_check("the old '%s' enemy stands in its Bestiary chamber" % kind, e != null and e.alive)

	# --- Deflect rule ---
	var proj: ProjectileSystem = game.combat.projectiles
	_put(Vector2(200, 448))
	await _frames(5)
	proj.spawn({"position": p.get_center() + Vector2(40, 0), "velocity": Vector2(-5, 0), "hostile": true, "deflectable": true, "life": 5.0})
	var probe: Dictionary = proj.list.back()
	h.set_energy(h.get_max_energy())
	await _cast_neutral()
	await _frames(10)
	_check("magic never deflects: Mana Discharge leaves a deflectable shot hostile", probe.hostile and not probe.deflected)
	_put(Vector2(200, 448))
	probe.pos = p.get_center() + Vector2(36, 0)
	await _swing(1)
	await _frames(6)
	_check("a melee swing deflects a deflectable shot (it turns friendly)", not probe.hostile and probe.deflected and probe.source == "deflect")
	proj.spawn({"position": p.get_center() + Vector2(36, 0), "velocity": Vector2(-5, 0), "hostile": true, "deflectable": false, "life": 5.0, "damage": 1.0})
	var hard: Dictionary = proj.list.back()
	await _frames(20)
	await _swing(1)
	await _frames(3)
	_check("a swing passes through a non-deflectable shot", hard.hostile and not hard.deflected)
	proj.clear()

	# --- 1. Swooper: floats, then flies at the player in range ---
	await _fresh_bestiary()
	var sw: BaseEnemy = _beast("swooper")
	_check("the swooper floats at home while the player is away", sw.state == "idle" and sw.home_distance() < 80.0, sw.state)
	_put(Vector2(sw.home.x - 60.0, 448))
	await _until(func() -> bool: return sw.state == "chase", 90)
	var d0: float = sw.target_distance()
	await _frames(25)
	_check("in range, the swooper flies directly at the player", sw.state == "chase" and sw.target_distance() < d0 - 20.0, [sw.state, d0, sw.target_distance()])

	# --- 2. Charger: stands, then rushes at high speed ---
	await _fresh_bestiary()
	var ch: ChargerEnemy = _beast("charger")
	await _frames(10)
	_check("the charger stands its ground while the player is away", ch.state == "idle" and absf(ch.velocity.x) < 1.0)
	_put(Vector2(ch.global_position.x - 230.0, 448))
	var top_speed := 0.0
	var saw_windup := false
	var from_x := ch.global_position.x
	for i in 90:
		await _frames(1)
		saw_windup = saw_windup or ch.state == "windup"
		top_speed = maxf(top_speed, absf(ch.velocity.x))
	_check("in proximity, the charger paws (telegraph) and charges at high speed",
		saw_windup and top_speed >= ch.charge_speed * 0.9 and from_x - ch.global_position.x > 100.0, [saw_windup, top_speed])

	# --- 3. Thrower: deflectable projectiles, swatted back into it ---
	await _fresh_bestiary()
	var th: ThrowerEnemy = _beast("thrower")
	_put(Vector2(th.global_position.x - 240.0, 448), 1)
	var shot: Dictionary = {}
	for i in 150:
		await _frames(1)
		var shots := _shots_of(th)
		if not shots.is_empty():
			shot = shots[0]
			break
	_check("the thrower throws a projectile at the player", not shot.is_empty())
	_check("the thrower's projectile is deflectable", not shot.is_empty() and shot.deflectable)
	if not shot.is_empty():
		for i in 90:
			if p.get_center().distance_to(shot.pos) < 62.0:
				break
			await _frames(1)
		await _swing(1)
		await _frames(4)
		_check("a melee swing sends the thrown projectile back", shot.deflected and not shot.hostile)
		var hurt := await _until(func() -> bool: return th.health < th.max_health, 90)
		_check("the deflected projectile hits the thrower", hurt, th.health)
	proj.clear()

	# --- 4. Brute: a non-deflectable smash for double damage ---
	await _fresh_bestiary()
	var br: BruteEnemy = _beast("brute")
	Config.upgrades.god_mode = false
	_put(Vector2(br.global_position.x - 56.0, 448), 1)
	var hp0 := h.health
	var smashed := false
	for i in 120:
		if br.state == "windup" and i % 12 == 0:
			await _swing(1) # Try to parry: a swing cannot stop the club.
		else:
			await _frames(1)
		if h.health < hp0:
			smashed = true
			break
	_check("the brute's smash cannot be parried", smashed and not br.parried, [smashed, br.state])
	_check("the brute's smash deals double damage", is_equal_approx(hp0 - h.health, Config.combat.contact_damage * 2.0), hp0 - h.health)
	Config.upgrades.god_mode = true
	await _frames(40)

	# --- 5. Ambusher: vanish, ghost behind the player, strike; parry it ---
	await _fresh_bestiary()
	var am: AmbusherEnemy = _beast("ambusher")
	Config.upgrades.god_mode = false
	_put(Vector2(am.global_position.x - 150.0, 448), 1)
	var vanished := await _until(func() -> bool: return am.state == "vanish", 60)
	_check("the ambusher vanishes when it spots the player (untouchable)", vanished and not am.hitbox_active())
	var ghosted := await _until(func() -> bool: return am.state == "ghost", 40)
	_check("a semi-transparent ghost appears BEHIND the player",
		ghosted and am.visual_alpha < 0.6 and signf(am.global_position.x - p.global_position.x) == -p.facing and not am.hitbox_active(),
		[am.global_position.x - p.global_position.x, p.facing, am.visual_alpha])
	hp0 = h.health
	await _until(func() -> bool: return am.state == "recover", 60)
	_check("it materializes and strikes", h.health < hp0, hp0 - h.health)
	# Second ambush: turn and swing at the ghost in time to parry.
	await _frames(20)
	_put(Vector2(p.global_position.x, 448), 1)
	await _until(func() -> bool: return am.state == "appear", 400)
	hp0 = h.health
	await _swing(int(signf(am.global_position.x - p.global_position.x)))
	await _frames(15)
	_check("a swing at the right moment parries its strike (deflectable)", am.parried and is_equal_approx(h.health, hp0), [am.parried, hp0 - h.health])
	Config.upgrades.god_mode = true

	# --- 6. Shellback: immune from the sides, hurt from above ---
	await _fresh_bestiary()
	var sb: BaseEnemy = _beast("shellback")
	var blocks := [0]
	var on_block := func(_e: Node, _d: Vector2) -> void: blocks[0] += 1
	Events.enemy_blocked.connect(on_block)
	_put(Vector2(sb.global_position.x - 48.0, 448), 1)
	await _frames(2)
	await _swing(1)
	await _frames(25)
	_put(Vector2(sb.global_position.x + 48.0, 448), -1)
	await _frames(2)
	await _swing(-1)
	await _frames(25)
	_check("side hits bounce off the shellback's plates (both sides)", is_equal_approx(sb.health, sb.max_health) and blocks[0] >= 2, [sb.health, blocks[0]])
	_put(Vector2(sb.global_position.x, sb.global_position.y - 70.0))
	Input.action_press(&"move_down")
	await _swing(1)
	await _frames(6)
	Input.action_release(&"move_down")
	_check("a down strike from above hurts it", sb.health < sb.max_health, sb.health)
	Events.enemy_blocked.disconnect(on_block)
	await _frames(30)

	# --- 7. Urchin: a burst of non-deflectable spikes when too close ---
	await _fresh_bestiary()
	var ur: UrchinEnemy = _beast("urchin")
	_put(Vector2(ur.global_position.x - 300.0, 448))
	await _frames(40)
	_check("the urchin waits while the player keeps away", _shots_of(ur).is_empty())
	_put(Vector2(ur.global_position.x - 90.0, 448))
	await _until(func() -> bool: return not _shots_of(ur).is_empty(), 60)
	var spikes := _shots_of(ur)
	var dirs := {}
	for s in spikes:
		dirs[roundi(rad_to_deg((s.vel as Vector2).angle()))] = true
	_check("too close: it fires spikes in all directions", ur.last_burst == 8 and spikes.size() >= ur.spike_count - 1 and dirs.size() == spikes.size(),
		[ur.last_burst, spikes.size()])
	_check("its spikes are non-deflectable", spikes.all(func(s: Dictionary) -> bool: return not s.deflectable))
	proj.clear()

	# --- 8. Turret: aims and fires non-deflectable bolts at the player ---
	await _fresh_bestiary()
	var tu: TurretEnemy = _beast("turret")
	_put(Vector2(tu.global_position.x - 300.0, 448), 1)
	await _until(func() -> bool: return not _shots_of(tu).is_empty(), 120)
	var bolts := _shots_of(tu)
	var aimed := not bolts.is_empty() and (bolts[0].vel as Vector2).normalized().dot((p.get_center() - (bolts[0].pos as Vector2)).normalized()) > 0.9
	_check("the turret fires straight at the player", aimed)
	_check("the turret's bolts are non-deflectable", not bolts.is_empty() and not bolts[0].deflectable)
	proj.clear()

	# --- 9. Orb sentry: orbs in the 4 cardinal directions ---
	await _fresh_bestiary()
	var os: OrbSentryEnemy = _beast("orb_sentry")
	_put(Vector2(os.home.x - 200.0, 448))
	await _until(func() -> bool: return _shots_of(os).size() >= 4, 240)
	var orbs := _shots_of(os)
	var cardinal := {}
	for o in orbs:
		var v: Vector2 = (o.vel as Vector2).normalized()
		cardinal[Vector2(roundf(v.x), roundf(v.y))] = true
	_check("the floating sentry fires orbs Up, Down, Left and Right",
		orbs.size() == 4 and cardinal.size() == 4 and cardinal.has(Vector2.UP) and cardinal.has(Vector2.DOWN) and cardinal.has(Vector2.LEFT) and cardinal.has(Vector2.RIGHT), cardinal.keys())
	_check("its orbs are non-deflectable", orbs.all(func(o: Dictionary) -> bool: return not o.deflectable))
	_check("it floats in place", os.home_distance() < 20.0, os.home_distance())
	proj.clear()

	# --- 10. Hopper: random short hops ---
	await _fresh_bestiary()
	var ho: HopperEnemy = _beast("hopper")
	_put(Vector2(200, 448))
	var highest := ho.global_position.y
	for i in 360:
		await _frames(1)
		highest = minf(highest, ho.global_position.y)
	_check("the hopper hops again and again", ho.hops >= 3, ho.hops)
	_check("its hops leave the floor and stay short (near home)", highest < ho.home.y - 40.0 and ho.home_distance() < ho.leash_range, [highest, ho.home_distance()])

	# --- 11. Bonus: wall-crawler circles its rock and drops on the player ---
	await _fresh_bestiary()
	var cr: CrawlerEnemy = _beast("crawler")
	_put(Vector2(200, 448))
	var normals := {}
	for i in 480:
		await _frames(1)
		normals[cr.normal] = true
	_check("the crawler creeps around its rock: floor, walls and ceiling", cr.turns >= 4 and normals.size() == 4, [cr.turns, normals.keys()])
	await _until(func() -> bool: return cr.normal == Vector2.DOWN and absf(cr.contact.x - cr.home.x) < 40.0, 600)
	_put(Vector2(cr.contact.x, 448))
	var dropped := await _until(func() -> bool: return cr.state == "fall", 30)
	_check("hanging upside down above the player, it drops", dropped, cr.state)
	_check("it lands and crawls on", await _until(func() -> bool: return cr.state == "crawl" and cr.normal == Vector2.UP, 90), cr.state)

	# --- 12. Bonus: shield phalanx, front blocked, back and top open ---
	await _fresh_bestiary()
	var ph: PhalanxEnemy = _beast("phalanx")
	var front: int = ph.facing
	_put(Vector2(ph.global_position.x + front * 52.0, 448), -front)
	await _frames(2)
	await _swing(-front)
	await _frames(8)
	_check("the phalanx's shield blocks a hit from the front", is_equal_approx(ph.health, ph.max_health), ph.health)
	_put(Vector2(ph.global_position.x - front * 52.0, 448), front)
	await _frames(2)
	await _swing(front)
	await _frames(8)
	_check("from behind it is open", ph.health < ph.max_health, ph.health)
	var hp_ph := ph.health
	await _frames(int(ph.turn_delay * 60.0) + 20)
	_check("it turns to face the player only after a delay", ph.facing == -front, ph.facing)
	_put(Vector2(ph.global_position.x, ph.global_position.y - 80.0))
	Input.action_press(&"move_down")
	await _swing(1)
	await _frames(6)
	Input.action_release(&"move_down")
	_check("over the shield (from above) it is open too", ph.health < hp_ph, ph.health)

	# --- Modularity: every new kind is a BaseEnemy with the shared rig ---
	await _fresh_bestiary()
	var modular := true
	for kind in BESTIARY_KINDS.slice(3):
		var e := _beast(kind)
		modular = modular and e is BaseEnemy and e.get_node_or_null("Flip/Rig") is EnemyRig and e.combat != null
	_check("every new enemy type extends BaseEnemy and draws through EnemyRig", modular)

	Config.upgrades.god_mode = god
	proj.clear()
	await _reset()
