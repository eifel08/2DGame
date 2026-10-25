class_name DebugOverlay
extends CanvasLayer
## Debug panel, toggled with F1 or ` (backquote).
## Fully data-driven: add a row to TOGGLES, SLIDERS or the actions list and it
## appears. Controls edit Config live, so changes apply on the next frame.
## The Spells section lists every registered ability: tick which ones the
## player knows (Mana Discharge is fixed and always known).
## Controls never steal gameplay keys. For keyboard-only use press F2 while
## the panel is open: the game pauses, arrows move between controls,
## Enter/Space toggles or presses, Left/Right moves sliders. F2 again resumes.

const TOGGLES := [
	["upgrades.double_jump", "Double Jump"],
	["upgrades.dash", "Dash"],
	["upgrades.wall_jump", "Wall Jump"],
	["upgrades.grapple", "Grapple Hook"],
	["upgrades.god_mode", "God Mode"],
	["debug.show_hitboxes", "Hitboxes & Stats"],
	["debug.show_anim_labels", "Anim States"],
	["debug.screen_shake", "Screen Shake"],
	["debug.paused", "Pause"],
	["combat.hazard_to_safe_ground", "Spikes → Safe Ground"],
	["map.auto_mark_rooms", "Map: Auto-Mark Rooms"],
	["map.show_player_marker", "Map: Player Marker"],
	["map.precise_player_marker", "Map: Precise Marker"],
]

const SLIDERS := [
	{"group": "Movement"},
	{"path": "movement.max_run_speed", "label": "Move Speed", "min": 80, "max": 600, "step": 5},
	{"path": "movement.ground_accel", "label": "Ground Accel", "min": 500, "max": 8000, "step": 50},
	{"path": "movement.jump_velocity", "label": "Jump Force", "min": 300, "max": 1300, "step": 10},
	{"path": "movement.jump_cut_mul", "label": "Jump Cut Mult", "min": 0, "max": 1, "step": 0.02},
	{"path": "movement.double_jump_velocity", "label": "Double Jump", "min": 200, "max": 1200, "step": 10},
	{"path": "movement.gravity", "label": "Gravity", "min": 600, "max": 5000, "step": 50},
	{"path": "movement.coyote_time", "label": "Coyote Time", "min": 0, "max": 0.4, "step": 0.01},
	{"path": "movement.jump_buffer_time", "label": "Jump Buffer", "min": 0, "max": 0.4, "step": 0.01},
	{"path": "movement.wall_slide_speed", "label": "Wall Slide Spd", "min": 20, "max": 500, "step": 5},
	{"path": "movement.wall_climb_jump_vel_x", "label": "Climb Jump Push", "min": 0, "max": 500, "step": 10},
	{"path": "movement.dash_speed", "label": "Dash Speed", "min": 300, "max": 1400, "step": 10},
	{"path": "movement.dash_cooldown", "label": "Dash Cooldown", "min": 0, "max": 2, "step": 0.05},
	{"group": "Combat"},
	{"path": "combat.attack_damage", "label": "Attack Damage", "min": 1, "max": 100, "step": 1},
	{"path": "combat.pogo_velocity", "label": "Pogo Bounce", "min": 200, "max": 1200, "step": 10},
	{"path": "combat.hitstop_on_hit", "label": "Hitstop (hit)", "min": 0, "max": 0.3, "step": 0.01},
	{"path": "combat.shake_on_hit", "label": "Shake (hit)", "min": 0, "max": 1, "step": 0.02},
	{"path": "combat.contact_damage", "label": "Contact Dmg", "min": 0, "max": 100, "step": 1},
	{"group": "Grapple Hook"},
	{"path": "grapple.max_range", "label": "Hook Range", "min": 64, "max": 800, "step": 8},
	{"path": "grapple.hook_speed", "label": "Hook Speed", "min": 300, "max": 3000, "step": 50},
	{"path": "grapple.pull_speed", "label": "Pull Speed", "min": 200, "max": 2000, "step": 20},
	{"path": "grapple.pull_accel", "label": "Pull Accel", "min": 500, "max": 15000, "step": 100},
	{"path": "grapple.hook_radius", "label": "Hook Tolerance", "min": 0, "max": 32, "step": 1},
	{"path": "grapple.enemy_safe_margin", "label": "Enemy Safe Gap", "min": 0, "max": 64, "step": 1},
	{"path": "grapple.enemy_bounce_mul", "label": "Enemy Bounce (x pogo)", "min": 0, "max": 1.5, "step": 0.05},
	{"path": "grapple.cooldown", "label": "Hook Cooldown", "min": 0, "max": 2, "step": 0.05},
	{"group": "Vitals & Energy"},
	{"path": "vitals.energy_per_hit", "label": "Energy / Hit", "min": 0, "max": 50, "step": 1},
	{"path": "vitals.energy_gain_mul", "label": "Energy Gain Rate", "min": 0, "max": 5, "step": 0.1},
	{"path": "vitals.iframe_duration", "label": "I-Frame Time", "min": 0, "max": 3, "step": 0.05},
	{"path": "vitals.heal_chunk_health", "label": "Heal Chunk HP", "min": 5, "max": 100, "step": 1},
	{"path": "vitals.heal_chunk_energy", "label": "Heal Chunk Energy", "min": 5, "max": 100, "step": 1},
	{"path": "vitals.heal_chunk_time", "label": "Heal Chunk Time", "min": 0.2, "max": 3, "step": 0.05},
	{"path": "vitals.heal_chunk_pause", "label": "Heal Pause", "min": 0.05, "max": 1.5, "step": 0.05},
	{"group": "Camera"},
	{"path": "camera.look_delay", "label": "Look Delay", "min": 0, "max": 1, "step": 0.05},
	{"path": "camera.look_distance", "label": "Look Distance", "min": 0, "max": 300, "step": 5},
	{"group": "Time"},
	{"path": "debug.time_scale", "label": "Time Scale", "min": 0.1, "max": 1.5, "step": 0.05},
]

var game: Node
var panel: PanelContainer
var readout: Label
var _bindings: Array[Dictionary] = [] ## {path, control, value_label}
var _readout_timer := 0.0
var _focusables: Array[Control] = []
var _known_checks := {} ## ability id -> CheckBox ("player knows this spell")
var navigating := false ## Keyboard navigation mode (pauses the game).


func setup(p_game: Node) -> void:
	game = p_game
	_build()
	panel.visible = false
	Events.loadout_changed.connect(func() -> void: refresh())


func toggle() -> void:
	panel.visible = not panel.visible
	if not panel.visible:
		set_navigating(false)
	Config.debug.overlay_open = panel.visible
	if panel.visible:
		refresh()


func _actions() -> Array:
	return [
		["Spawn Dummy", func() -> void: game.spawn_enemy(false)],
		["Spawn Flyer", func() -> void: game.spawn_enemy(true)],
		["Spawn Strong", func() -> void: game.spawn_enemy(false, "strong")],
		["Go to Boss Room", func() -> void: game.load_room("boss_room", "west")],
		["Go to Test Room", func() -> void: game.load_room("test_room", "east")],
		["New Game (reset world)", func() -> void: game.new_game()],
		["Reset Enemies", func() -> void: game.reset_enemies()],
		["Full Heal", func() -> void: game.player.health.full_heal()],
		["Take Damage", func() -> void: game.player.receive_hit(15.0, game.player.global_position.x - game.player.facing, false, true)],
		["Max Energy", func() -> void: game.player.health.set_energy(game.player.health.get_max_energy())],
		["Empty Energy", func() -> void: game.player.health.set_energy(0.0)],
		["+100 Shards", func() -> void: game.player_data.add_currency(100)],
		["+10 Max Health", func() -> void: game.player.health.max_health_bonus += 10.0],
		["+20 Max Energy", func() -> void: game.player.health.max_energy_bonus += 20.0],
		["Reset Growth", func() -> void:
			game.player.health.max_health_bonus = 0.0
			game.player.health.max_energy_bonus = 0.0],
		["Learn Movement", func() -> void:
			for ability_id in PlayerData.MOVEMENT:
				game.player_data.learn_movement(ability_id)
			Events.loadout_changed.emit()],
		["Reset Tutorials", func() -> void: game.player_data.seen_tutorials.clear()],
		["Map: Acquire This Zone", func() -> void:
			var zone: MapZone = game.map_state.current_zone()
			if zone:
				game.acquire_map(zone.zone_id)],
		["Map: Mark Pending Rooms", func() -> void: game.map_state.mark_pending()],
		["Map: Reveal All Zones", func() -> void:
			for zone in game.atlas.zones:
				game.acquire_map(zone.zone_id)
				for r in zone.rooms:
					game.map_state.mark_room(r.room_id)],
		["Map: Forget Map", func() -> void:
			game.map_state.new_game()
			game.map_state.enter_room(game.room_id)],
		["Reset Player", func() -> void: game.reset_player()],
		["Reset Room", func() -> void: game.reset_room()],
		["Restore Defaults", func() -> void: game.restore_defaults()],
	]


# ---------- UI construction ----------

func _build() -> void:
	panel = PanelContainer.new()
	panel.layout_direction = Control.LAYOUT_DIRECTION_LTR
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -330.0
	panel.offset_right = -6.0
	panel.offset_top = 6.0
	panel.offset_bottom = -6.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.93)
	style.border_color = Color("#2f375c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.default_font_size = 11
	panel.theme = theme
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "DEBUG  ·  F1 / `   ·  F2 keyboard"
	title.add_theme_color_override("font_color", Color("#ffd43b"))
	box.add_child(title)

	# Upgrades & toggles
	box.add_child(_header("Upgrades & Toggles"))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for t in TOGGLES:
		var check := CheckBox.new()
		check.text = t[1]
		check.focus_mode = Control.FOCUS_NONE
		_focusables.append(check)
		var path: String = t[0]
		check.toggled.connect(func(on: bool) -> void: Config.set_value(path, on))
		grid.add_child(check)
		_bindings.append({"path": path, "control": check})

	# Quick actions
	box.add_child(_header("Quick Actions"))
	var buttons := GridContainer.new()
	buttons.columns = 2
	box.add_child(buttons)
	for a in _actions():
		var btn := Button.new()
		btn.text = a[0]
		btn.focus_mode = Control.FOCUS_NONE
		_focusables.append(btn)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action: Callable = a[1]
		btn.pressed.connect(func() -> void:
			action.call()
			refresh())
		buttons.add_child(btn)

	# Spells: known pool, quick loadout tools
	box.add_child(_build_spells())

	# Ultimates: per-ability energy cost
	box.add_child(_header("Ultimate Costs"))
	for ability in game.ultimates.abilities.values():
		box.add_child(_slider({"path": "ultimates.%s.cost" % ability.id, "label": ability.display_name, "min": 0, "max": 100, "step": 1}))

	# Tunables
	for def in SLIDERS:
		if def.has("group"):
			box.add_child(_header(def.group))
		else:
			box.add_child(_slider(def))

	# Live readout
	box.add_child(_header("Live State"))
	readout = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace", "Consolas", "Menlo"])
	readout.add_theme_font_override("font", mono)
	readout.add_theme_font_size_override("font_size", 10)
	# Wrap long lines instead of widening the panel past the screen edge.
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(readout)


## Spell management: one "known" checkbox per equippable spell, and
## loadout shortcuts that ignore the checkpoint rule.
func _build_spells() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	section.add_child(_header("Spells (known)"))

	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	for ability: UltimateAbility in game.ultimates.abilities.values():
		if ability.fixed:
			continue # Mana Discharge is always known.
		var check := CheckBox.new()
		check.text = ability.display_name
		check.tooltip_text = "%s · %s" % [ability.kind, ability.description]
		check.add_theme_color_override("font_color", ability.color)
		check.focus_mode = Control.FOCUS_NONE
		_focusables.append(check)
		var ability_id := ability.id
		check.toggled.connect(func(on: bool) -> void: game.ultimates.set_known(ability_id, on))
		grid.add_child(check)
		_known_checks[ability_id] = check

	var buttons := GridContainer.new()
	buttons.columns = 2
	section.add_child(buttons)
	var tools := [
		["Know All Spells", func() -> void:
			for ability_id in game.ultimates.abilities:
				game.ultimates.set_known(ability_id, true)],
		["Forget All Spells", func() -> void:
			for ability_id in game.ultimates.abilities:
				game.ultimates.set_known(ability_id, false)], # Fixed spells stay.
		["Auto-Equip Known", func() -> void: game.ultimates.auto_equip()],
		["Open All Slots", func() -> void:
			for slot in PlayerData.SLOT_COUNT:
				game.ultimates.open_slot(slot)],
		["Full Kit", func() -> void: game.grant_full_kit()],
		["Clear Loadout", func() -> void:
			for slot in PlayerData.SLOT_COUNT:
				game.ultimates.unequip(slot, true)],
	]
	for t in tools:
		var btn := Button.new()
		btn.text = t[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_focusables.append(btn)
		var action: Callable = t[1]
		btn.pressed.connect(func() -> void:
			action.call()
			refresh())
		buttons.add_child(btn)
	return section


## Keyboard mode: controls become focusable and the game pauses.
func set_navigating(on: bool) -> void:
	navigating = on and panel.visible
	for c in _focusables:
		c.focus_mode = Control.FOCUS_ALL if navigating else Control.FOCUS_NONE
	if navigating and not _focusables.is_empty():
		_focusables[0].grab_focus()
	elif get_viewport():
		get_viewport().gui_release_focus()


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", Color("#7fa2ff"))
	return l


func _row(text: String, control: Control, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 112
	l.clip_text = true
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if value_label:
		value_label.custom_minimum_size.x = 44
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
	return row


func _slider(def: Dictionary) -> HBoxContainer:
	var slider := HSlider.new()
	slider.min_value = def.min
	slider.max_value = def.max
	slider.step = def.step
	slider.focus_mode = Control.FOCUS_NONE
	_focusables.append(slider)
	var value_label := Label.new()
	var path: String = def.path
	slider.value_changed.connect(func(v: float) -> void:
		Config.set_value(path, v)
		value_label.text = _format(v))
	_bindings.append({"path": path, "control": slider, "value_label": value_label})
	return _row(def.label, slider, value_label)


# ---------- Sync ----------

## Pulls current Config values into the controls.
func refresh() -> void:
	Config.debug.overlay_open = panel.visible
	for b in _bindings:
		var v: Variant = Config.get_value(b.path)
		if b.control is CheckBox:
			b.control.set_pressed_no_signal(bool(v))
		else:
			b.control.set_value_no_signal(float(v))
			b.value_label.text = _format(float(v))
	var data: PlayerData = game.player_data
	for ability_id in _known_checks:
		_known_checks[ability_id].set_pressed_no_signal(data.is_unlocked(ability_id))


func _format(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.2f" % v


func _process(delta: float) -> void:
	if panel == null or not panel.visible:
		return
	_readout_timer -= delta
	if _readout_timer > 0.0:
		return
	_readout_timer = 0.1
	var p: Player = game.player
	var h := p.health
	var running: Array = game.ultimates.abilities.values().filter(func(u: UltimateAbility) -> bool: return u.is_running) \
		.map(func(u: UltimateAbility) -> String: return u.display_name)
	var alive: int = game.enemies.filter(func(e: Node) -> bool: return e.alive).size()
	var slots := PackedStringArray()
	for slot in [UltimateManager.NEUTRAL, PlayerData.SLOT_UP, PlayerData.SLOT_SIDE, PlayerData.SLOT_DOWN]:
		var u: UltimateAbility = game.ultimates.get_slot(slot)
		var slot_name: String = "neutral" if slot == UltimateManager.NEUTRAL else PlayerData.SLOT_NAMES[slot]
		slots.append("%s:%s(%d)" % [slot_name, u.display_name if u else "-", roundi(u.get_cost()) if u else 0])
	var cp: Node = game.current_checkpoint
	readout.text = "\n".join([
		"fps          %d" % Engine.get_frames_per_second(),
		"state        %s%s" % [p.state_name(), (" + attack:" + p.attack_dir) if p.attack_dir != "" else ""],
		"animation    %s" % p.animator.current,
		"pos          %.1f, %.1f" % [p.global_position.x, p.global_position.y],
		"vel          %.1f, %.1f" % [p.velocity.x, p.velocity.y],
		"grounded     %s  wall %d  sliding %s" % [p.grounded, p.wall_dir, p.wall_sliding],
		"coyote       %.2f  buffer %.2f" % [maxf(0.0, p.coyote_timer), maxf(0.0, p.jump_buffer_timer)],
		"air jumps    %d  air dash used %s" % [p.air_jumps_used, p.air_dash_used],
		"dash cd      %.2f" % maxf(0.0, p.dash_cooldown_timer),
		"health       %.1f / %.0f  pending %.1f" % [h.health, h.get_max_health(), h.pending_heal],
		"energy       %.1f / %.0f" % [h.energy, h.get_max_energy()],
		"i-frames     %.2f  invuln %s %s" % [maxf(0.0, h.iframe_timer), h.is_invulnerable(), h.invuln_flags.keys()],
		"modifiers    %s" % (", ".join(PackedStringArray(p.modifiers.keys())) if not p.modifiers.is_empty() else "-"),
		"spells       %s" % " ".join(slots),
		"known        %s" % ", ".join(PackedStringArray(game.player_data.unlocked)),
		"open slots   %s" % str(game.player_data.open_slots),
		"movement     %s" % (", ".join(PackedStringArray(game.player_data.movement)) if not game.player_data.movement.is_empty() else "-"),
		"running      %s" % (", ".join(PackedStringArray(running)) if not running.is_empty() else "-"),
		"shards       %d" % game.player_data.currency,
		"checkpoint   %s  at checkpoint %s" % [cp.name if cp else "-", p.at_checkpoint],
		"enemies      %d alive / %d" % [alive, game.enemies.size()],
		"room         %s  arena %s" % [game.room_id, game.arena_director.state],
		"world        dead %s  bosses %s  arenas %s" % [game.world.dead_enemies, game.world.defeated_bosses.keys(), game.world.cleared_arenas.keys()],
	])

