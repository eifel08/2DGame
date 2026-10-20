class_name Hud
extends Control
## Screen-space HUD: a smooth health bar, the shared energy meter with a cost
## marker for every ultimate, the equipped ultimate, dash cooldown and hints.
## Exact numbers (health, energy) appear only when Config.stats_visible().

const BAR_W := 260.0

var player: Player
var ultimates: UltimateManager
var smooth_health := -1.0 ## Main bar: eases toward the real value.
var ghost_health := -1.0 ## Trailing bar that shows recent damage.
var denied_flash := 0.0
var damage_flash := 0.0


func setup(p_player: Player, p_ultimates: UltimateManager) -> void:
	player = p_player
	ultimates = p_ultimates
	Events.ultimate_denied.connect(func(_a: RefCounted, _r: String) -> void: denied_flash = 0.35)
	Events.health_damaged.connect(func(_amount: float) -> void: damage_flash = 0.3)


func _process(delta: float) -> void:
	if player == null:
		return
	denied_flash -= delta
	damage_flash -= delta
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
	var x := 20.0
	var y := 18.0

	# Health
	_label(font, "HP", Vector2(x, y + 12))
	_bar(Rect2(x + 28, y, BAR_W, 14), [
		[ghost_health / h.get_max_health(), Color(1, 1, 1, 0.33)],
		[smooth_health / h.get_max_health(), Color.WHITE if damage_flash > 0.0 else Color("#ff5e6c")],
	])
	var stats := Config.stats_visible()
	if stats:
		draw_string(font, Vector2(x + 28 + BAR_W + 8, y + 12), "%.1f / %.0f" % [h.health, h.get_max_health()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd0d0"))

	# Energy
	var ey := y + 22.0
	var active := ultimates.get_active()
	var ready := h.can_afford(active.get_cost())
	var energy_col := Color("#4fd1ff")
	if denied_flash > 0.0:
		energy_col = Color("#ff5e6c")
	elif player.is_channeling_heal:
		energy_col = Color("#8dffb0")
	_label(font, "EN", Vector2(x, ey + 12))
	_bar(Rect2(x + 28, ey, BAR_W, 14), [[h.energy / h.get_max_energy(), energy_col]])
	if stats:
		draw_string(font, Vector2(x + 28 + BAR_W + 8, ey + 12), "%.1f / %.0f" % [h.energy, h.get_max_energy()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8f4ff"))
	# Cost markers for every ultimate; the equipped one is highlighted.
	for ability in ultimates.abilities:
		var mx := x + 28.0 + BAR_W * minf(1.0, ability.get_cost() / h.get_max_energy())
		if ability == active:
			draw_rect(Rect2(roundf(mx) - 1.0, ey - 4.0, 3.0, 22.0), Color.WHITE)
		else:
			draw_rect(Rect2(roundf(mx), ey - 1.0, 1.0, 16.0), Color(1, 1, 1, 0.35))

	# Equipped ultimate
	var uy := ey + 36.0
	draw_string(font, Vector2(x, uy), "ULT  " + active.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, active.color)
	var status := "needs %d" % roundi(active.get_cost())
	if active.is_running and active.status_text() != "":
		status = "ACTIVE " + active.status_text()
	elif ready:
		status = "READY [U/Q]"
	draw_string(font, Vector2(x, uy + 15), "%s · cost %d · %s   [Tab] switch" % [active.kind, roundi(active.get_cost()), status],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE if ready else Color("#8890a8"))

	# Dash cooldown
	if Config.upgrades.dash:
		var cd := clampf(player.dash_cooldown_timer / maxf(0.001, Config.movement.dash_cooldown), 0.0, 1.0)
		draw_rect(Rect2(x, uy + 24, 60, 4), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(x, uy + 24, 60 * (1.0 - cd), 4), Color("#8890a8") if cd > 0.0 else Color("#d9f6ff"))
		draw_string(font, Vector2(x + 66, uy + 30), "dash", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8890a8"))

	# Hints and status
	var view := size
	draw_string(font, Vector2(0, view.y - 12),
		"Move ←→/AD · Jump Space/Z · Attack J/X · Dash K/C/Shift · Heal hold L/V · Ult U/Q · Debug F1/`",
		HORIZONTAL_ALIGNMENT_RIGHT, view.x - 14, 11, Color(1, 1, 1, 0.55))
	if Config.upgrades.god_mode:
		draw_string(font, Vector2(0, 24), "GOD MODE", HORIZONTAL_ALIGNMENT_RIGHT, view.x - 14, 12, Color("#ffd43b"))
	if Config.debug.paused:
		draw_string(font, Vector2(0, view.y / 2.0), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, view.x, 22)


func _label(font: Font, text: String, pos: Vector2) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8cee6"))


func _bar(rect: Rect2, fills: Array) -> void:
	draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.55))
	for f in fills:
		var w := clampf(f[0], 0.0, 1.0) * rect.size.x
		draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), f[1])
