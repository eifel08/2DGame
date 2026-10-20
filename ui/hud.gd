class_name Hud
extends Control
## Screen-space HUD, clean by default:
##   - smooth health bar (no numbers)
##   - energy bar with a color-coded threshold mark per equipped ultimate.
##     Colors follow energy tiers (Config.ENERGY_TIERS), not specific spells,
##     so whatever is slotted later shows its minimum energy clearly.
##   - shard (currency) counter, top-right
## Exact health / energy numbers appear only in stats mode (Config.stats_visible()).

const BAR_W := 260.0

var player: Player
var ultimates: UltimateManager
var data: PlayerData
var smooth_health := -1.0 ## Main bar: eases toward the real value.
var ghost_health := -1.0 ## Trailing bar that shows recent damage.
var denied_flash := 0.0
var damage_flash := 0.0
var shard_pulse := 0.0


func setup(p_player: Player, p_ultimates: UltimateManager, p_data: PlayerData) -> void:
	player = p_player
	ultimates = p_ultimates
	data = p_data
	Events.ultimate_denied.connect(func(_a: RefCounted, _r: String) -> void: denied_flash = 0.35)
	Events.health_damaged.connect(func(_amount: float) -> void: damage_flash = 0.3)
	Events.currency_collected.connect(func(_amount: int, _pos: Vector2) -> void: shard_pulse = 0.25)


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
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var font := ThemeDB.fallback_font
	var h := player.health
	var stats := Config.stats_visible()
	var x := 20.0
	var y := 18.0
	var bx := x + 28.0

	# Health
	_label(font, "HP", Vector2(x, y + 12))
	_bar(Rect2(bx, y, BAR_W, 14), [
		[ghost_health / h.get_max_health(), Color(1, 1, 1, 0.33)],
		[smooth_health / h.get_max_health(), Color.WHITE if damage_flash > 0.0 else Color("#ff5e6c")],
	])
	if stats:
		draw_string(font, Vector2(bx + BAR_W + 8, y + 12), "%.1f / %.0f" % [h.health, h.get_max_health()],
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
	_draw_thresholds(font, bx, ey, h)
	if stats:
		draw_string(font, Vector2(bx + BAR_W + 8, ey + 12), "%.1f / %.0f" % [h.energy, h.get_max_energy()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8f4ff"))

	# Dash cooldown pip (no text).
	if Config.upgrades.dash:
		var cd := clampf(player.dash_cooldown_timer / maxf(0.001, Config.movement.dash_cooldown), 0.0, 1.0)
		draw_rect(Rect2(bx, ey + 34, 40, 3), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(bx, ey + 34, 40 * (1.0 - cd), 3), Color("#8890a8") if cd > 0.0 else Color("#d9f6ff"))

	# Currency (top-right).
	var view := size
	var scale := 1.0 + maxf(0.0, shard_pulse) * 1.2
	var icon := Vector2(view.x - 92, 26)
	var r := 6.0 * scale
	draw_colored_polygon(PackedVector2Array([icon + Vector2(0, -r * 1.3), icon + Vector2(r, 0), icon + Vector2(0, r * 1.3), icon + Vector2(-r, 0)]), Coin.COLOR)
	draw_string(font, Vector2(icon.x + 14, icon.y + 6), str(data.currency), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffe9b0"))
	if Config.upgrades.god_mode:
		draw_string(font, Vector2(0, 52), "GOD MODE", HORIZONTAL_ALIGNMENT_RIGHT, view.x - 14, 11, Color("#ffd43b"))

	# Control hints (bottom).
	draw_string(font, Vector2(0, view.y - 12),
		"Move ←→/AD · Jump Space · Attack J · Dash K · Heal hold L · Ultimates 1-4 · Interact E · Inventory I/Tab · Debug F1/`",
		HORIZONTAL_ALIGNMENT_RIGHT, view.x - 14, 10, Color(1, 1, 1, 0.5))
	if Config.debug.paused:
		draw_string(font, Vector2(0, view.y / 2.0), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, view.x, 22)


## One mark per equipped slot at its cost, colored by energy tier, with the
## hotkey number underneath. Bright when affordable, dim when not.
func _draw_thresholds(font: Font, bx: float, ey: float, h: HealthEnergy) -> void:
	for slot in PlayerData.SLOT_COUNT:
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
		draw_string(font, Vector2(mx - 10.0, ey + 30.0), str(slot + 1), HORIZONTAL_ALIGNMENT_CENTER, 21, 10, Color(col, 1.0 if ready else 0.5))


func _label(font: Font, text: String, pos: Vector2) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8cee6"))


func _bar(rect: Rect2, fills: Array) -> void:
	draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.55))
	for f in fills:
		var w := clampf(f[0], 0.0, 1.0) * rect.size.x
		draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), f[1])
