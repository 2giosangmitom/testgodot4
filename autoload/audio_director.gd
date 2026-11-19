extends Node
## Central audio playback. Resolves short names to files and tolerates missing assets
## (warns once) so gameplay works before Track D delivers audio.
##
## Name resolution: play_sfx("door_creak") -> res://assets/audio/sfx/door_creak.(ogg|wav)
## ambience -> assets/audio/amb/, music -> assets/audio/music/, voice -> assets/audio/voice/

const DIRS := {
	"sfx": "res://assets/audio/sfx/",
	"amb": "res://assets/audio/amb/",
	"music": "res://assets/audio/music/",
	"voice": "res://assets/audio/voice/",
}
const EXTS := ["ogg", "wav", "mp3"]

var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _amb_players: Dictionary = {}       # layer -> AudioStreamPlayer
var _music: AudioStreamPlayer
var _voice: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = _make_player("Music")
	_voice = _make_player("Voice")

func get_stream(kind: String, name: String) -> AudioStream:
	var key := kind + "/" + name
	if _cache.has(key):
		return _cache[key]
	for ext in EXTS:
		var path: String = DIRS[kind] + name + "." + ext
		if ResourceLoader.exists(path):
			_cache[key] = load(path)
			return _cache[key]
	if not _warned.has(key):
		_warned[key] = true
		push_warning("AudioDirector: missing %s '%s'" % [kind, name])
	return null

## 2D one-shot. Returns the player (or null).
func play_sfx(name: String, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> AudioStreamPlayer:
	var s := get_stream("sfx", name)
	if s == null:
		return null
	var p := _make_player(bus)
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()
	return p

## Positional one-shot at a world position.
func play_sfx_3d(name: String, position: Vector3, volume_db := 0.0, pitch := 1.0, bus := "SFX", max_distance := 20.0) -> AudioStreamPlayer3D:
	var s := get_stream("sfx", name)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_distance
	p.unit_size = 3.0
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	root.add_child(p)
	p.global_position = position
	p.finished.connect(p.queue_free)
	p.play()
	return p

## Looping ambience on a named layer (e.g. "base", "hum", "rain"). Crossfades.
func play_ambience(name: String, layer := "base", volume_db := 0.0, fade := 1.5) -> void:
	var s := get_stream("amb", name)
	stop_ambience(layer, fade)
	if s == null:
		return
	_set_loop(s)
	var p := _make_player("Amb")
	p.stream = s
	p.volume_db = -60.0
	p.play()
	_amb_players[layer] = p
	create_tween().tween_property(p, "volume_db", volume_db, fade)

func stop_ambience(layer := "base", fade := 1.5) -> void:
	if not _amb_players.has(layer):
		return
	var p: AudioStreamPlayer = _amb_players[layer]
	_amb_players.erase(layer)
	var t := create_tween()
	t.tween_property(p, "volume_db", -60.0, fade)
	t.tween_callback(p.queue_free)

func stop_all_ambience(fade := 1.5) -> void:
	for layer in _amb_players.keys():
		stop_ambience(layer, fade)

func play_music(name: String, volume_db := 0.0, fade := 2.0) -> void:
	var s := get_stream("music", name)
	if s == null:
		return
	_set_loop(s)
	_music.stream = s
	_music.volume_db = -60.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", volume_db, fade)

func stop_music(fade := 2.0) -> void:
	var t := create_tween()
	t.tween_property(_music, "volume_db", -60.0, fade)
	t.tween_callback(_music.stop)

## Plays a voice line by dialogue key. Returns its length in seconds (0 if missing).
func play_voice(key: String) -> float:
	var s := get_stream("voice", key)
	if s == null:
		return 0.0
	_voice.stream = s
	_voice.play()
	return s.get_length()

func stop_voice() -> void:
	_voice.stop()

func is_voice_playing() -> bool:
	return _voice.playing

func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func _set_loop(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if s.loop_end <= 0:
			s.loop_end = int(s.get_length() * s.mix_rate)
