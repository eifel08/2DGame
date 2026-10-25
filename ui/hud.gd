class_name Hud
extends Control
## Screen-space HUD, clean by default:
##   - smooth health bar (no numbers)
##   - energy bar with a color-coded threshold mark per spell in the loadout
##     (Mana Discharge and the Up / Side / Down slots). Colors follow energy
##     tiers (Config.ENERGY_TIERS), not specific spells.
##   - the spell cross (child node SpellCross, a D-pad diagram): Mana
##     Discharge in the center, the Up and Down slots above and below, the
##     Side slot on BOTH the left and the right. The Spell key shows in its
##     top-left corner.
##   - shard (currency) counter, top-right
## Exact health / energy numbers appear only in stats mode (Config.stats_visible()).

const BAR_W := 260.0
const CROSS_CELL := 22.0
const CROSS_GAP := 3.0
const CROSS_POS := Vector2(326.0, 13.0)

var player: Player
var ultimates: UltimateManager
var data: PlayerData
var smooth_health := -1.0 ## Main bar: eases toward the real value.
var ghost_health := -1.0 ## Trailing bar that shows recent damage.
var denied_flash := 0.0
var damage_flash := 0.0
var shard_pulse := 0.0
var boss_provider: Callable = func() -> Node: return null ## Returns the active boss or null.
var spell_cross: SpellCross


func setup(p_player: Player, p_ultimates: UltimateManager, p_data: PlayerData) -> void:
	player = p_player
	ultimates = p_ultimates
	data = p_data
	Events.ultimate_denied.connect(func(_a: RefCounted, _r: String) -> void: denied_flash = 0.35)
	Events.health_damaged.connect(func(_amount: float) -> void: damage_flash = 0.3)
	Events.currency_collected.connect(func(_amount: int, _pos: Vector2) -> void: shard_pulse = 0.25)
	spell_cross = SpellCross.new()
	spell_cross.name = "SpellCross"
	spell_cross.position = CROSS_POS
	add_child(spell_cross)
	spell_cross.build(ultimates, false, CROSS_CELL, CROSS_GAP)


func _process(delta: float) -> void:
	if player == null:
		return
	denied_flash -= delta
	damage_flash -= delta
	shard_pulse -= delta
	var hp := player.health.health
	if smooth_health < 0.0:
		smooth_health = hp
		ghost_health = hp
	smooth_health = lerpf(smooth_health, hp, minf(1.0, delta * 14.0))
	ghost_health = hp if ghost_health < hp else lerpf(ghost_health, hp, minf(1.0, delta * 3.0))
	spell_cross.refresh(player.health.get_max_energy(), player.health.energy)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var font := ThemeDB.fallback_font
	# Backing panel: marks the HUD corner as UI, not as open room space.
	draw_rect(Rect2(8, 8, CROSS_POS.x + spell_cross.size.x + 2.0, CROSS_POS.y + spell_cross.size.y + 2.0), Color(0.02, 0.03, 0.07, 0.55))
	var h := player.health
	var stats := Config.stats_visible()
	var x := 20.0
	var y := 18.0
	var bx := x + 28.0

	# Health
	_label(font, "HP", Vector2(x, y + 12))
	var max_hp := h.get_max_health()
	_bar(Rect2(bx, y, BAR_W, 14), [
		[ghost_health / max_hp, Color(1.0, 0.37, 0.42, 0.35)],
		[smooth_health / max_hp, Color("#ffc2c8") if damage_flash > 0.0 else Color("#ff5e6c")],
	])
	# Pending heal: the chunk being channeled, in white. It only becomes red
	# health when the chunk completes; an interrupted chunk makes it vanish.
	var red_end := minf(smooth_health, h.health)
	var pending_end := h.health + h.pending_heal
	if pending_end > red_end + 0.01:
		var x0 := bx + BAR_W * clampf(red_end / max_hp, 0.0, 1.0)
		var x1 := bx + BAR_W * clampf(pending_end / max_hp, 0.0, 1.0)
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 80.0)
		draw_rect(Rect2(x0, y, x1 - x0, 14), Color(1, 1, 1, pulse))
	if stats:
		draw_string(font, Vector2(stats_x(), y + 12), "%.1f / %.0f" % [h.health, h.get_max_health()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd0d0"))

	# Energy
	var ey := y + 22.0
	var energy_col := Color("#4fd1ff")
	if denied_flash > 0.0:
		energy_col = Color("#ff5e6c")
	elif player.is_channeling_heal:
		energy_col = Color("#8dffb0")
	_label(font, "EN", Vector2(x, ey + 12))
	_bar(Rect2(bx, ey, BAR_W, 14), [[h.energy / h.get_max_energy(), energy_col]])
	if heal_ready():
		_draw_heal_glow(Rect2(bx, ey, BAR_W, 14), h)
	_draw_thresholds(font, bx, ey, h)
	if stats:
		draw_string(font, Vector2(stats_x(), ey + 12), "%.1f / %.0f" % [h.energy, h.get_max_energy()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8f4ff"))

	# The Spell key, in the empty top-left corner of the cross.
	draw_string(font, CROSS_POS + Vector2(1, 11), spell_key_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8))

	# Dash cooldown pip (no text), under the energy bar.
	if player.can_use("dash"):
		var cd := clampf(player.dash_cooldown_timer / maxf(0.001, Config.movement.dash_cooldown), 0.0, 1.0)
		var dy := ey + 26.0
		draw_rect(Rect2(bx, dy, 40, 3), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(bx, dy, 40 * (1.0 - cd), 3), Color("#8890a8") if cd > 0.0 else Color("#d9f6ff"))

	# Currency (top-right).
	var view := size
	var scale := 1.0 + maxf(0.0, shard_pulse) * 1.2
	var icon := Vector2(view.x - 92, 26)
	var r := 6.0 * scale
	draw_colored_polygon(PackedVector2Array([icon + Vector2(0, -r * 1.3), icon + Vector2(r, 0), icon + Vector2(0, r * 1.3), icon + Vector2(-r, 0)]), Coin.COLOR)
	draw_string(font, Vector2(icon.x + 14, icon.y + 6), str(data.currency), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffe9b0"))
	if Config.upgrades.god_mode:
		draw_string(font, Vector2(0, 52), "GOD MODE", HORIZONTAL_ALIGNMENT_RIGHT, view.x - 14, 11, Color("#ffd43b"))

	_draw_boss_bar(font)
	if player.state_name() == "trance":
		var a := 0.45 + 0.35 * sin(Time.get_ticks_msec() / 260.0)
		draw_string(font, Vector2(0, size.y * 0.72), "Press any button", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(0.85, 0.95, 1.0, a))

	# Control hints (bottom).
	draw_string(font, Vector2(0, view.y - 12),
		"Move ←→/AD · Jump Space · Attack J · Dash K · Heal hold L · Grapple H · Spell %s (+ ↑ ← → ↓) · Interact E · Inventory I/Tab · Debug F1/`" % spell_key_label(),
		HORIZONTAL_ALIGNMENT_RIGHT, view.x - 14, 10, Color(1, 1, 1, 0.5))
	if Config.debug.paused:
		draw_string(font, Vector2(0, view.y / 2.0), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, view.x, 22)


## One mark per spell in the loadout at its energy threshold, colored by
## energy tier (no numbers). Bright when affordable, dim when not. Empty slots
## have no mark, so the bar always reflects the current loadout.
func _draw_thresholds(_font: Font, bx: float, ey: float, h: HealthEnergy) -> void:
	for slot in [UltimateManager.NEUTRAL, PlayerData.SLOT_UP, PlayerData.SLOT_SIDE, PlayerData.SLOT_DOWN]:
		var ability := ultimates.get_slot(slot)
		if ability == null:
			continue
		var cost := ability.get_cost()
		var mx := roundf(bx + BAR_W * clampf(cost / h.get_max_energy(), 0.0, 1.0))
		var col := Config.energy_tier_color(cost)
		var ready := h.can_afford(cost)
		if ready:
			draw_rect(Rect2(mx - 3.0, ey - 5.0, 7.0, 24.0), Color(col, 0.3))
		draw_rect(Rect2(mx - 1.0, ey - 4.0, 3.0, 22.0), Color(col, 1.0 if ready else 0.45))


## True when the energy meter holds enough for one full heal chunk.
func heal_ready() -> bool:
	return player != null and player.health.energy >= Config.vitals.heal_chunk_energy - 0.0001


## Heal readiness: a pulsing green glow around the energy bar plus a light
## sweep across the filled part, shown whenever a full heal chunk is affordable.
func _draw_heal_glow(bar: Rect2, h: HealthEnergy) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	var glow := Color("#8dffb0")
	for i in 3:
		draw_rect(bar.grow(3.0 + i * 2.0), Color(glow, (0.45 - i * 0.13) * (0.6 + 0.4 * pulse)), false, 2.0)
	var filled := bar.size.x * clampf(h.energy / h.get_max_energy(), 0.0, 1.0)
	var sweep_x := bar.position.x + fmod(t * 160.0, maxf(1.0, filled + 40.0)) - 20.0
	var x0 := clampf(sweep_x, bar.position.x, bar.position.x + filled)
	var x1 := clampf(sweep_x + 18.0, bar.position.x, bar.position.x + filled)
	if x1 > x0:
		draw_rect(Rect2(x0, bar.position.y, x1 - x0, bar.size.y), Color(1, 1, 1, 0.35))
	# Mark where a heal chunk's cost sits on the bar.
	var cx := bar.position.x + bar.size.x * clampf(Config.vitals.heal_chunk_energy / h.get_max_energy(), 0.0, 1.0)
	draw_rect(Rect2(cx - 1.0, bar.end.y + 2.0, 3.0, 3.0), Color(glow, 0.9))


## Boss health bar at the top center while a boss fight runs (no numbers).
func _draw_boss_bar(font: Font) -> void:
	var boss: Node = boss_provider.call()
	if boss == null:
		return
	var view := size
	var w := view.x * 0.4
	var bar := Rect2((view.x - w) / 2.0 + 40.0, 36.0, w, 10.0)
	draw_string(font, Vector2(bar.position.x, bar.position.y - 6.0), boss.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e6dcff"))
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(bar.position, Vector2(w * clampf(boss.health / boss.max_health, 0.0, 1.0), bar.size.y)),
		Color("#b06cff") if boss.phase == 2 else Color("#8a6cff"))
	draw_rect(Rect2(bar.position.x + w * 0.5 - 1.0, bar.position.y, 2.0, bar.size.y), Color(1, 1, 1, 0.35)) # Phase 2 mark.


## Debug numbers sit right of the spell cross.
func stats_x() -> float:
	return CROSS_POS.x + spell_cross.size.x + 10.0


## The keyboard key bound to the Spell button ("U" by default), shortened to fit.
func spell_key_label() -> String:
	var key := Settings.key_name(String(UltimateManager.SPELL_ACTION))
	return key if key.length() <= 3 else key.substr(0, 3)


func _label(font: Font, text: String, pos: Vector2) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8cee6"))


func _bar(rect: Rect2, fills: Array) -> void:
	draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.55))
	for f in fills:
		var w := clampf(f[0], 0.0, 1.0) * rect.size.x
		draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), f[1])
