extends Node
## Placeholder sound effects (autoload "Sfx"). The sounds are synthesized at
## startup, so the project needs no audio files yet. Replace any of them with
## real audio by assigning a stream, e.g.
##   Sfx.streams["boss_roar"] = load("res://audio/boss_roar.ogg")
## All effects play on the "SFX" bus; a "Music" bus is created for later use.
## Volumes are controlled by the Settings autoload.

const MIX_RATE := 22050
const PLAYER_COUNT := 8

var streams := {} ## name -> AudioStream
var last_played := "" ## For tests and debugging.
var play_counts := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)
	_build_placeholders()


func play(sound: String, pitch := 1.0) -> void:
	last_played = sound
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var stream: AudioStream = streams.get(sound)
	if stream == null:
		return
	var player := _free_player()
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


func count(sound: String) -> int:
	return play_counts.get(sound, 0)


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0]


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


# ---------- Placeholder synthesis ----------

func _build_placeholders() -> void:
	streams = {
		"hit": _wav(_tone(420, 180, 0.08, "square", 0.3, 0.3)),
		"pogo": _wav(_tone(300, 640, 0.09, "sine", 0.4)),
		"hurt": _wav(_tone(220, 90, 0.18, "square", 0.35, 0.4)),
		"death": _wav(_tone(330, 55, 0.8, "saw", 0.4, 0.25)),
		"save": _wav(_concat([_tone(523, 523, 0.1, "sine", 0.35), _tone(784, 784, 0.22, "sine", 0.35)])),
		"spawn": _wav(_tone(110, 520, 0.55, "sine", 0.3, 0.2)),
		"door": _wav(_tone(200, 120, 0.25, "sine", 0.25, 0.7)),
		"break": _wav(_tone(180, 60, 0.35, "square", 0.45, 0.8)),
		"secret": _wav(_concat([_tone(659, 659, 0.1), _tone(831, 831, 0.1), _tone(988, 988, 0.1), _tone(1319, 1319, 0.35)])),
		"relic": _wav(_concat([_tone(440, 440, 0.12), _tone(880, 880, 0.4)])),
		"boss_roar": _wav(_tone(170, 42, 1.5, "saw", 0.6, 0.55)),
		"victory": _wav(_concat([_tone(523, 523, 0.12, "square", 0.28), _tone(659, 659, 0.12, "square", 0.28),
			_tone(784, 784, 0.12, "square", 0.28), _tone(1047, 1047, 0.5, "square", 0.28)])),
		"ui_move": _wav(_tone(880, 880, 0.03, "sine", 0.12)),
		"ui_confirm": _wav(_tone(660, 990, 0.07, "sine", 0.22)),
	}


## One tone sliding from f0 to f1 Hz. wave: sine / square / saw; noise mixes
## in white noise (0..1). Short attack, smooth decay.
func _tone(f0: float, f1: float, duration: float, wave := "sine", volume := 0.35, noise := 0.0) -> PackedFloat32Array:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / MIX_RATE
		var v := sin(phase)
		if wave == "square":
			v = signf(v)
		elif wave == "saw":
			v = fmod(phase / TAU, 1.0) * 2.0 - 1.0
		v = lerpf(v, randf_range(-1.0, 1.0), noise)
		var env := minf(1.0, float(i) / (0.008 * MIX_RATE)) * pow(1.0 - t, 1.6)
		out[i] = v * env * volume
	return out


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in parts:
		out.append_array(part)
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
