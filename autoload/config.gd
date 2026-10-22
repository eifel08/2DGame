extends Node
## Every tunable value in one place (autoload "Config").
## The debug overlay edits these live and all systems read them each frame,
## so changes apply instantly. Units: pixels, seconds, px/s, px/s^2.


class Upgrades:
	var double_jump := true
	var dash := true
	var wall_jump := true
	var grapple := true
	var god_mode := false


class Movement:
	var max_run_speed := 270.0
	var ground_accel := 2600.0 ## How fast top speed is reached on the ground.
	var ground_decel := 3400.0 ## How fast the player stops when input is released.
	var air_accel := 1900.0
	var air_decel := 1100.0
	var turn_boost := 1.6 ## Extra acceleration when reversing direction.

	var gravity := 2100.0 ## Slightly low: more reaction time for pogo chains.
	var fall_gravity_mul := 1.55 ## Heavier fall = less floaty arc.
	var max_fall_speed := 760.0
	var apex_threshold := 70.0 ## |vy| under this while holding jump = hang time.
	var apex_gravity_mul := 0.6

	var jump_velocity := 760.0
	var jump_cut_mul := 0.42 ## Releasing jump early multiplies upward speed by this.
	var double_jump_velocity := 660.0
	var coyote_time := 0.1
	var jump_buffer_time := 0.12

	var wall_slide_speed := 130.0 ## Wall friction: max fall speed while pressing into a wall.
	var wall_jump_vel_x := 380.0
	var wall_climb_jump_vel_x := 210.0 ## Smaller push when holding toward the wall (climbing).
	var wall_climb_lock_time := 0.06
	var wall_jump_vel_y := 700.0
	var wall_jump_lock_time := 0.16 ## Reduced air control right after a wall jump.
	var wall_coyote_time := 0.1

	var dash_speed := 780.0
	var dash_duration := 0.15
	var dash_cooldown := 0.45


class Combat:
	var attack_damage := 20.0
	var attack_duration := 0.26
	var attack_active_start := 0.02
	var attack_active_end := 0.13
	var attack_cooldown := 0.3
	var attack_buffer_time := 0.16 ## Forgiving: an attack pressed slightly early still fires.
	## Pogo leniency: the downward swing has a wider/taller hitbox and stays
	## active longer than side or up swings, so bounces are easy to land.
	var pogo_hitbox := Vector2(78, 80)
	var pogo_active_end := 0.2
	var pogo_velocity := 640.0
	var recoil_velocity := 170.0 ## Push-back when a side attack connects.
	var enemy_knockback := 260.0
	var hitstop_on_hit := 0.07
	var hitstop_on_hurt := 0.14
	var shake_on_hit := 0.22
	var shake_on_hurt := 0.5
	var contact_damage := 15.0
	var hazard_damage := 20.0
	## true: spikes send the player back to the last safe ground (default).
	## false: to the last checkpoint. Dying always respawns at the checkpoint.
	var hazard_to_safe_ground := true


## Grappling hook (combat/grapple_hook.gd, player/states/grapple_state.gd).
class Grapple:
	var max_range := 256.0 ## How far the hook flies before it comes back (8 tiles: short and precise).
	var hook_speed := 1500.0 ## Flight speed of the hook tip.
	var retract_speed := 2400.0 ## Speed of the tip coming back after a miss or a pull.
	var hook_radius := 5.0 ## Size of the tip when it checks for enemies.
	var pull_speed := 880.0 ## Top speed while being pulled.
	var pull_accel := 5200.0 ## Ease-in toward pull_speed, so the pull starts smoothly.
	var pull_max_time := 0.9 ## Safety net: a pull never lasts longer.
	var arrive_distance := 4.0 ## Closer than this to the stop point ends the pull.
	var exit_speed_mul := 0.35 ## Share of the pull speed kept after a pull to a wall or ceiling.
	## Gap kept between the player and an enemy's contact hitbox at the end of
	## a pull, so a hooked enemy is never touched (no contact damage).
	var enemy_safe_margin := 18.0
	var enemy_knockback_mul := 0.5 ## Knockback on a hooked enemy, relative to melee.
	## Rebound at the end of an enemy pull, like a pogo: up, and a little away.
	var enemy_bounce_velocity := 560.0
	var enemy_bounce_recoil := 120.0
	var cooldown := 0.3 ## After the hook is back, before it can fire again.
	var buffer_time := 0.1 ## A press slightly before the hook is ready still fires.


class Vitals:
	var max_health := 100.0
	var max_energy := 100.0
	var energy_per_hit := 11.0
	var energy_gain_mul := 1.0
	var iframe_duration := 1.0
	var heal_windup := 0.2 ## Channel delay before energy starts draining.
	## Chunk healing: each chunk drains heal_chunk_energy over heal_chunk_time
	## and restores heal_chunk_health only when it completes.
	var heal_chunk_health := 25.0
	var heal_chunk_energy := 33.0
	var heal_chunk_time := 0.9
	var heal_chunk_pause := 0.4 ## Safe window after a chunk before the next one starts.


class CameraCfg:
	## Look up / down: hold Up or Down while standing still to pan the view.
	var look_delay := 0.3 ## Hold this long first, so quick taps (aimed attacks) never move the view.
	var look_distance := 160.0 ## How far the view pans; always clamped to the room bounds.
	var look_speed := 4.0 ## Easing rate toward the look offset (twice as fast back).


class DebugFlags:
	var show_hitboxes := false
	var show_anim_labels := false
	var screen_shake := true
	var paused := false
	var time_scale := 1.0
	var overlay_open := false ## Set by the debug overlay while it is visible.


var upgrades: Upgrades
var movement: Movement
var combat: Combat
var grapple: Grapple
var vitals: Vitals
var debug: DebugFlags
var camera: CameraCfg
## One block per ultimate, keyed by ability id. `cost` is fully configurable.
var ultimates: Dictionary


func _init() -> void:
	restore_defaults()


func restore_defaults() -> void:
	upgrades = Upgrades.new()
	movement = Movement.new()
	combat = Combat.new()
	grapple = Grapple.new()
	vitals = Vitals.new()
	debug = DebugFlags.new()
	camera = CameraCfg.new()
	ultimates = {
		"nova_burst": {"cost": 33.0, "cast_time": 0.35, "damage": 45.0, "radius": 230.0, "expand_time": 0.3},
		"spirit_volley": {"cost": 50.0, "cast_time": 0.2, "count": 10.0, "damage": 12.0, "interval": 0.04, "speed": 460.0, "homing": 7.0},
		"ascendant_form": {"cost": 100.0, "cast_time": 0.6, "duration": 8.0, "damage_mul": 2.0, "speed_mul": 1.25, "range_mul": 1.45},
		"comet_dash": {"cost": 25.0, "cast_time": 0.08, "speed": 1150.0, "duration": 0.3, "damage": 30.0, "burst_damage": 18.0, "burst_radius": 100.0},
		# Repulse Aegis: `cost` is the minimum; a cast consumes the whole meter.
		# Repulse Aegis: a parry. No wind-up; the counter window is tiny, so it
		# must be cast right before an enemy touches you. Enemy contact only.
		"repulse_aegis": {"cost": 20.0, "cast_time": 0.0, "window": 0.2, "counter_range": 6.0, "reflect_mul": 1.5, "guard_iframes": 0.6},
		# Stasis Field: a short-range emergency escape, not area control.
		"stasis_field": {"cost": 80.0, "cast_time": 0.05, "radius": 90.0, "duration": 0.8},
		"radiant_lance": {"cost": 60.0, "cast_time": 0.2, "damage": 55.0, "length": 560.0, "width": 26.0, "duration": 0.3},
		# Meteor Slam: cast on the ground, it first hops up (`hop_velocity`, at
		# most `hop_time`) - a VULNERABLE wind-up - then dives invulnerable.
		# No cast wind-up: in the air it dives at once.
		"meteor_slam": {"cost": 30.0, "cast_time": 0.0, "hop_velocity": 520.0, "hop_time": 0.3, "speed": 1400.0, "max_time": 1.2,
			"dive_damage": 20.0, "slam_damage": 50.0, "slam_radius": 140.0, "land_iframes": 0.35},
	}


## Energy tiers for the color-coded meter. Colors follow cost brackets, not
## specific abilities, so whatever is slotted later reads correctly.
const ENERGY_TIERS := [
	{"max": 25.0, "color": Color("#6ee7a8")},
	{"max": 50.0, "color": Color("#ffd166")},
	{"max": 75.0, "color": Color("#ff9f43")},
	{"max": INF, "color": Color("#ff5e8a")},
]


func energy_tier_color(cost: float) -> Color:
	for tier in ENERGY_TIERS:
		if cost <= tier.max:
			return tier.color
	return Color.WHITE


## Exact numbers (health, energy, damage) are shown only in debug mode:
## when hitboxes/stats are toggled on, or while the debug overlay is open.
func stats_visible() -> bool:
	return debug.show_hitboxes or debug.overlay_open


## Reads a dotted path such as "movement.jump_velocity" or "ultimates.nova_burst.cost".
func get_value(path: String) -> Variant:
	var target: Variant = self
	for key in path.split("."):
		target = target[key] if target is Dictionary else target.get(key)
	return target


func set_value(path: String, value: Variant) -> void:
	var keys := path.split(".")
	var target: Variant = self
	for i in keys.size() - 1:
		target = target[keys[i]] if target is Dictionary else target.get(keys[i])
	var last := keys[keys.size() - 1]
	if target is Dictionary:
		target[last] = value
	else:
		target.set(last, value)
