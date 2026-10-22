extends Node
## Player settings (autoload "Settings"): audio volumes, screen shake,
## fullscreen and keyboard bindings. Stored in user://settings.cfg and applied
## on startup. The settings panel (ui/settings_panel.gd) edits these.

## Actions whose main keyboard key can be rebound in the settings menu.
const REBINDABLE: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"jump", "attack", "dash", "heal", "grapple", "spell", "interact", "inventory", "pause",
]
const LABELS := {
	"move_left": "Move left", "move_right": "Move right", "move_up": "Aim up", "move_down": "Aim down",
	"jump": "Jump", "attack": "Attack", "dash": "Dash", "heal": "Heal", "grapple": "Grapple", "interact": "Interact / Save",
	"spell": "Spell (+ direction)",
	"inventory": "Inventory", "pause": "Pause",
}

var config_path := "user://settings.cfg"
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 0.9
var screen_shake := true
var fullscreen := false
var _default_events := {} ## action -> Array[InputEvent] from the project Input Map
var _custom_keys := {} ## action -> physical keycode replacing the first key


func _ready() -> void:
	for action in REBINDABLE:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action)
	load_settings()
	apply()


func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	Config.debug.screen_shake = screen_shake
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	for action in _default_events:
		_apply_binding(action)


## Changes one setting ("master_volume", "screen_shake", ...), applies and saves it.
func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save_settings()


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


# ---------- Key bindings ----------

## Display name of the main keyboard key of an action.
func key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode)
	return "-"


func rebind(action: String, physical_keycode: Key) -> void:
	_custom_keys[action] = physical_keycode
	_apply_binding(action)
	save_settings()


func reset_controls() -> void:
	_custom_keys.clear()
	for action in _default_events:
		_apply_binding(action)
	save_settings()


## Rebuilds an action from its defaults, swapping the first key if rebound.
func _apply_binding(action: String) -> void:
	InputMap.action_erase_events(action)
	var replaced := false
	for e in _default_events[action]:
		if e is InputEventKey and not replaced and _custom_keys.has(action):
			var key := InputEventKey.new()
			key.physical_keycode = _custom_keys[action]
			InputMap.action_add_event(action, key)
			replaced = true
		else:
			InputMap.action_add_event(action, e)


# ---------- Persistence ----------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in ["master_volume", "music_volume", "sfx_volume", "screen_shake", "fullscreen"]:
		cfg.set_value("settings", key, get(key))
	for action in _custom_keys:
		cfg.set_value("keys", action, int(_custom_keys[action]))
	cfg.save(config_path)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	for key in ["master_volume", "music_volume", "sfx_volume", "screen_shake", "fullscreen"]:
		set(key, cfg.get_value("settings", key, get(key)))
	_custom_keys.clear()
	if cfg.has_section("keys"):
		for action in cfg.get_section_keys("keys"):
			if _default_events.has(action):
				_custom_keys[action] = cfg.get_value("keys", action)
