# === Settings.gd ===
# Player preferences: audio volumes, UI text size, color-blind mode. Persisted to
# user://settings.cfg and applied at boot. Autoload — `Settings` (registered after
# Audio, which it configures).
extends Node

const PATH: String = "user://settings.cfg"
const THEME_PATH: String = "res://assets/ui/theme.tres"

# Text size presets (theme default_font_size).
const SIZE_SMALL: int = 16
const SIZE_MEDIUM: int = 20
const SIZE_LARGE: int = 26

signal changed()

var music_db: float = -8.0
var sfx_db: float = -4.0
var text_size: int = SIZE_MEDIUM
var colorblind: bool = false


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	Audio.set_music_volume_db(music_db)
	Audio.set_sfx_volume_db(sfx_db)
	var theme: Theme = load(THEME_PATH)
	if theme != null:
		theme.default_font_size = text_size
	changed.emit()


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "music_db", music_db)
	cfg.set_value("audio", "sfx_db", sfx_db)
	cfg.set_value("ui", "text_size", text_size)
	cfg.set_value("ui", "colorblind", colorblind)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_db = cfg.get_value("audio", "music_db", music_db)
	sfx_db = cfg.get_value("audio", "sfx_db", sfx_db)
	text_size = cfg.get_value("ui", "text_size", text_size)
	colorblind = cfg.get_value("ui", "colorblind", colorblind)
