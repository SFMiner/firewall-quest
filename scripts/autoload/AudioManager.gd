# === AudioManager.gd ===
# Music + SFX. Music loops and persists across scene swaps; SFX are one-shots.
# CC0/royalty-free sources. Autoload — `Audio`. Safe to call from anywhere
# (no-ops gracefully if a stream is missing or audio is unavailable).
extends Node

const FILES: Dictionary = {
	"explore": "res://assets/audio/explore_music.mp3",
	"combat": "res://assets/audio/combat_music.mp3",
	"hit": "res://assets/audio/sfx_hit.mp3",
	"success": "res://assets/audio/sfx_success.mp3",
	"menu": "res://assets/audio/sfx_menu.mp3",
	"coin": "res://assets/audio/sfx_coin.mp3",
}
const MUSIC_KEYS: Array[String] = ["explore", "combat"]

var music_volume_db: float = -8.0
var sfx_volume_db: float = -4.0

var _music: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _streams: Dictionary = {}
var _current_key: String = ""


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	for key: String in FILES:
		var path: String = FILES[key]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if key in MUSIC_KEYS and stream is AudioStreamMP3:
				(stream as AudioStreamMP3).loop = true
			_streams[key] = stream


func play_music(key: String) -> void:
	if key == _current_key and _music.playing:
		return
	_current_key = key
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		_music.stop()
		return
	_music.stream = stream
	_music.volume_db = music_volume_db
	_music.play()


func stop_music() -> void:
	_music.stop()
	_current_key = ""


func sfx(key: String) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	_sfx.stream = stream
	_sfx.volume_db = sfx_volume_db
	_sfx.play()


func set_music_volume_db(db: float) -> void:
	music_volume_db = db
	_music.volume_db = db


func set_sfx_volume_db(db: float) -> void:
	sfx_volume_db = db
