class_name DebugOverlay
extends CanvasLayer
## Debug panel, toggled with F1 or ` (backquote).
## Fully data-driven: add a row to TOGGLES, SLIDERS or the actions list and it
## appears. Controls edit Config live, so changes apply on the next frame.
## All controls use FOCUS_NONE so they never steal gameplay keys.

const TOGGLES := [
	["upgrades.double_jump", "Double Jump"],
	["upgrades.dash", "Dash"],
	["upgrades.wall_jump", "Wall Slide / Jump"],
	["upgrades.god_mode", "God Mode"],
	["debug.show_hitboxes", "Show Hitboxes"],
	["debug.show_anim_labels", "Anim States"],
	["debug.screen_shake", "Screen Shake"],
	["debug.paused", "Pause"],
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
	{"path": "movement.dash_speed", "label": "Dash Speed", "min": 300, "max": 1400, "step": 10},
	{"path": "movement.dash_cooldown", "label": "Dash Cooldown", "min": 0, "max": 2, "step": 0.05},
	{"group": "Combat"},
	{"path": "combat.attack_damage", "label": "Attack Damage", "min": 1, "max": 100, "step": 1},
	{"path": "combat.pogo_velocity", "label": "Pogo Bounce", "min": 200, "max": 1200, "step": 10},
	{"path": "combat.hitstop_on_hit", "label": "Hitstop (hit)", "min": 0, "max": 0.3, "step": 0.01},
	{"path": "combat.shake_on_hit", "label": "Shake (hit)", "min": 0, "max": 1, "step": 0.02},
	{"path": "combat.contact_damage", "label": "Contact Dmg", "min": 0, "max": 100, "step": 1},
	{"group": "Vitals & Energy"},
	{"path": "vitals.energy_per_hit", "label": "Energy / Hit", "min": 0, "max": 50, "step": 1},
	{"path": "vitals.energy_gain_mul", "label": "Energy Gain Rate", "min": 0, "max": 5, "step": 0.1},
	{"path": "vitals.iframe_duration", "label": "I-Frame Time", "min": 0, "max": 3, "step": 0.05},
	{"path": "vitals.heal_energy_per_second", "label": "Heal Drain /s", "min": 5, "max": 150, "step": 1},
	{"path": "vitals.health_per_energy", "label": "HP per Energy", "min": 0.1, "max": 3, "step": 0.05},
	{"group": "Time"},
	{"path": "debug.time_scale", "label": "Time Scale", "min": 0.1, "max": 1.5, "step": 0.05},
]

var game: Node
var panel: PanelContainer
var readout: Label
var ult_select: OptionButton
var _bindings: Array[Dictionary] = [] ## {path, control, value_label}
var _readout_timer := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	_build()
	panel.visible = false
	Events.ultimate_changed.connect(func(_a: RefCounted) -> void: refresh())


func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		refresh()


func _actions() -> Array:
	return [
		["Spawn Dummy", func() -> void: game.spawn_enemy(false)],
		["Spawn Flyer", func() -> void: game.spawn_enemy(true)],
		["Reset Enemies", func() -> void: game.reset_enemies()],
		["Full Heal", func() -> void: game.player.health.full_heal()],
		["Take Damage", func() -> void: game.player.receive_hit(15.0, game.player.global_position.x - game.player.facing, false, true)],
		["Max Energy", func() -> void: game.player.health.set_energy(game.player.health.get_max_energy())],
		["Empty Energy", func() -> void: game.player.health.set_energy(0.0)],
		["Next Ultimate", func() -> void: game.ultimates.cycle(1)],
		["Reset Player", func() -> void: game.reset_player()],
		["Reset Room", func() -> void: game.reset_room()],
		["Restore Defaults", func() -> void: game.restore_defaults()],
	]


# ---------- UI construction ----------

func _build() -> void:
	panel = PanelContainer.new()
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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "DEBUG  ·  F1 / `"
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
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action: Callable = a[1]
		btn.pressed.connect(func() -> void:
			action.call()
			refresh())
		buttons.add_child(btn)

	# Ultimates: equipped selection + per-ability cost
	box.add_child(_header("Ultimate Abilities"))
	ult_select = OptionButton.new()
	ult_select.focus_mode = Control.FOCUS_NONE
	ult_select.fit_to_longest_item = false
	ult_select.clip_text = true
	for ability in game.ultimates.abilities:
		ult_select.add_item("%s (%s)" % [ability.display_name, ability.kind])
	ult_select.item_selected.connect(func(i: int) -> void: game.ultimates.set_active_index(i))
	box.add_child(_row("Equipped", ult_select, null))
	for ability in game.ultimates.abilities:
		box.add_child(_slider({"path": "ultimates.%s.cost" % ability.id, "label": ability.display_name + " cost", "min": 0, "max": 100, "step": 1}))

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
	box.add_child(readout)


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
	for b in _bindings:
		var v: Variant = Config.get_value(b.path)
		if b.control is CheckBox:
			b.control.set_pressed_no_signal(bool(v))
		else:
			b.control.set_value_no_signal(float(v))
			b.value_label.text = _format(float(v))
	ult_select.select(game.ultimates.active_index)


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
	var running: Array = game.ultimates.abilities.filter(func(a: UltimateAbility) -> bool: return a.is_running) \
		.map(func(a: UltimateAbility) -> String: return a.display_name)
	var alive: int = game.enemies.filter(func(e: Node) -> bool: return e.alive).size()
	var active: UltimateAbility = game.ultimates.get_active()
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
		"health       %.1f / %.0f" % [h.health, h.get_max_health()],
		"energy       %.1f / %.0f" % [h.energy, h.get_max_energy()],
		"i-frames     %.2f  invuln %s %s" % [maxf(0.0, h.iframe_timer), h.is_invulnerable(), h.invuln_flags.keys()],
		"modifiers    %s" % (", ".join(PackedStringArray(p.modifiers.keys())) if not p.modifiers.is_empty() else "-"),
		"ultimate     %s (cost %d)" % [active.display_name, roundi(active.get_cost())],
		"running      %s" % (", ".join(PackedStringArray(running)) if not running.is_empty() else "-"),
		"enemies      %d alive / %d" % [alive, game.enemies.size()],
	])
