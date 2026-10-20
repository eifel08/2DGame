extends Node
## Sound effects (autoload "Sfx", the scene audio/sfx.tscn). Each sound is
## its own AudioStreamPlayer child, named after the sound ("hit", "boss_roar",
## ...), on the "SFX" bus. Gameplay code only calls Sfx.play("name").
##
## The streams are placeholder tones in audio/sfx/<name>.wav, made by
## tools/build_assets.gd. To use real audio, overwrite the .wav with the same
## name, or select the node in audio/sfx.tscn and drop a file on its Stream.
## A new sound = a new AudioStreamPlayer child. Volumes: Settings autoload.

var last_played := "" ## For tests and debugging.
var play_counts := {}


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")


func play(sound: String, pitch := 1.0) -> void:
	last_played = sound
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var player := get_node_or_null(sound) as AudioStreamPlayer
	if player == null or player.stream == null:
		return
	player.pitch_scale = pitch
	player.play()


func count(sound: String) -> int:
	return play_counts.get(sound, 0)


func has_sound(sound: String) -> bool:
	var player := get_node_or_null(sound) as AudioStreamPlayer
	return player != null and player.stream != null


## The bus layout (default_bus_layout.tres) has both buses; this is a fallback.
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


## Releases the streams on quit so no playback is left holding them.
func _exit_tree() -> void:
	for player in get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
