extends Node
## Player settings (autoload "Settings"): audio volumes, screen shake,
## fullscreen and key bindings. Stored in user://settings.cfg and applied
## on startup. The settings panel (ui/settings_panel.gd) edits these.
##
## Bindings. Each rebindable action has exactly ONE keyboard key and ONE
## gamepad button (plus fixed stick axes for movement). The defaults are the
## project Input Map. There are no hidden extra keys: a key triggers an
## action only if the settings list shows it there.
## No duplicates: binding a key (or button) that another action holds gives
## that action the rebound action's old key (a swap). If there was none, the
## other action is left unbound ("-"). Keys of the fixed debug actions
## (RESERVED) cannot be taken.

## Actions whose keyboard key and gamepad button can be rebound.
const REBINDABLE: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"jump", "attack", "dash", "heal", "grapple", "spell", "interact", "inventory", "map", "pause",
]
const LABELS := {
	"move_left": "Move left", "move_right": "Move right", "move_up": "Aim up", "move_down": "Aim down",
	"jump": "Jump", "attack": "Attack", "dash": "Dash", "heal": "Heal", "grapple": "Grapple", "interact": "Interact / Save",
	"spell": "Spell (+ direction)",
	"inventory": "Inventory", "map": "Map (hold)", "pause": "Pause",
}

var config_path := "user://settings.cfg"
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 0.9
var screen_shake := true
var fullscreen := false
## Fixed actions that are live during play: their keys cannot be rebound to.
const RESERVED: Array[String] = ["toggle_debug", "debug_navigate", "reset_room"]

var _default_events := {} ## action -> Array[InputEvent] from the project Input Map
var _default_keys := {} ## action -> Key (KEY_NONE: none)
var _default_buttons := {} ## action -> JoyButton (JOY_BUTTON_INVALID: none)
var keys := {} ## action -> Key in effect (KEY_NONE: unbound)
var buttons := {} ## action -> JoyButton in effect (JOY_BUTTON_INVALID: unbound)
var _reserved_keys: Array[Key] = []


func _ready() -> void:
	for action in REBINDABLE:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action)
			_default_keys[action] = KEY_NONE
			_default_buttons[action] = JOY_BUTTON_INVALID
			for e in _default_events[action]:
				if e is InputEventKey and _default_keys[action] == KEY_NONE:
					_default_keys[action] = e.physical_keycode
				elif e is InputEventJoypadButton and _default_buttons[action] == JOY_BUTTON_INVALID:
					_default_buttons[action] = e.button_index
	for action in RESERVED:
		if InputMap.has_action(action):
			for e in InputMap.action_get_events(action):
				if e is InputEventKey:
					_reserved_keys.append(e.physical_keycode)
	keys = _default_keys.duplicate()
	buttons = _default_buttons.duplicate()
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

## Display name of an action's keyboard key ("-" when unbound).
func key_name(action: String) -> String:
	var key: Key = keys.get(action, KEY_NONE)
	return OS.get_keycode_string(key) if key != KEY_NONE else "-"


const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
}


## Display name of an action's gamepad button ("-" when unbound).
func button_name(action: String) -> String:
	var button: int = buttons.get(action, JOY_BUTTON_INVALID)
	if button == JOY_BUTTON_INVALID:
		return "-"
	return BUTTON_NAMES.get(button, "Btn %d" % button)


## Binds `key` to `action`. The action that held it gets this action's old
## key. Returns false (nothing changes) for a reserved key.
func rebind(action: String, key: Key) -> bool:
	if key in _reserved_keys:
		return false
	_assign(keys, action, key)
	save_settings()
	return true


## Same for a gamepad button.
func rebind_button(action: String, button: JoyButton) -> bool:
	_assign(buttons, action, button)
	save_settings()
	return true


## The action whose key is `key`, or "" when no rebindable action has it.
func action_for_key(key: Key) -> String:
	for action in keys:
		if keys[action] == key:
			return action
	return ""


func reset_controls() -> void:
	keys = _default_keys.duplicate()
	buttons = _default_buttons.duplicate()
	for action in _default_events:
		_apply_binding(action)
	save_settings()


## Gives `value` to `action`; whoever held it takes the action's old value.
func _assign(map: Dictionary, action: String, value: int) -> void:
	var old: int = map[action]
	for other in map:
		if other != action and map[other] == value:
			map[other] = old
			_apply_binding(other)
	map[action] = value
	_apply_binding(action)


## Rebuilds an action: its one key, its one button and the default stick
## axes. Every other default key or button is dropped.
func _apply_binding(action: String) -> void:
	InputMap.action_erase_events(action)
	if keys[action] != KEY_NONE:
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)
	if buttons[action] != JOY_BUTTON_INVALID:
		var button := InputEventJoypadButton.new()
		button.button_index = buttons[action]
		InputMap.action_add_event(action, button)
	for e in _default_events[action]:
		if not (e is InputEventKey or e is InputEventJoypadButton):
			InputMap.action_add_event(action, e)


## After loading: a key or button held twice stays with the action that was
## customized; the other one is unbound.
func _resolve_duplicates(map: Dictionary, defaults: Dictionary, none: int) -> void:
	for action in map:
		if map[action] == none:
			continue
		for other in map:
			if other != action and map[other] == map[action]:
				var loser: String = other if map[other] == defaults[other] else action
				map[loser] = none


# ---------- Persistence ----------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in ["master_volume", "music_volume", "sfx_volume", "screen_shake", "fullscreen"]:
		cfg.set_value("settings", key, get(key))
	for action in keys:
		if keys[action] != _default_keys[action]:
			cfg.set_value("keys", action, int(keys[action]))
		if buttons[action] != _default_buttons[action]:
			cfg.set_value("buttons", action, int(buttons[action]))
	cfg.save(config_path)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	for key in ["master_volume", "music_volume", "sfx_volume", "screen_shake", "fullscreen"]:
		set(key, cfg.get_value("settings", key, get(key)))
	keys = _default_keys.duplicate()
	buttons = _default_buttons.duplicate()
	for action in cfg.get_section_keys("keys") if cfg.has_section("keys") else []:
		if keys.has(action) and not int(cfg.get_value("keys", action)) in _reserved_keys:
			keys[action] = int(cfg.get_value("keys", action))
	for action in cfg.get_section_keys("buttons") if cfg.has_section("buttons") else []:
		if buttons.has(action):
			buttons[action] = int(cfg.get_value("buttons", action))
	_resolve_duplicates(keys, _default_keys, KEY_NONE)
	_resolve_duplicates(buttons, _default_buttons, JOY_BUTTON_INVALID)
