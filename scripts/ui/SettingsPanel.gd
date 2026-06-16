# === SettingsPanel.gd ===
# Audio volumes, text size, color-blind mode. Writes through to Settings and
# persists immediately. Reusable from the main menu and the pause menu.
class_name SettingsPanel
extends Control

signal closed()

@onready var _music: HSlider = %MusicSlider
@onready var _sfx: HSlider = %SfxSlider
@onready var _size: OptionButton = %SizeOption
@onready var _colorblind: CheckButton = %ColorblindCheck

var _sizes: Array[int] = [Settings.SIZE_SMALL, Settings.SIZE_MEDIUM, Settings.SIZE_LARGE]


func _ready() -> void:
	_music.value = Settings.music_db
	_sfx.value = Settings.sfx_db
	for label: String in ["Small", "Medium", "Large"]:
		_size.add_item(label)
	_size.selected = maxi(0, _sizes.find(Settings.text_size))
	_colorblind.button_pressed = Settings.colorblind
	_music.value_changed.connect(_on_music_changed)
	_sfx.value_changed.connect(_on_sfx_changed)
	_size.item_selected.connect(_on_size_selected)
	_colorblind.toggled.connect(_on_colorblind_toggled)


func _on_music_changed(v: float) -> void:
	Settings.music_db = v
	Settings.apply()
	Settings.save_settings()


func _on_sfx_changed(v: float) -> void:
	Settings.sfx_db = v
	Settings.apply()
	Settings.save_settings()
	Audio.sfx("menu")


func _on_size_selected(index: int) -> void:
	Settings.text_size = _sizes[index]
	Settings.apply()
	Settings.save_settings()


func _on_colorblind_toggled(on: bool) -> void:
	Settings.colorblind = on
	Settings.apply()
	Settings.save_settings()


func _on_back_pressed() -> void:
	Audio.sfx("menu")
	closed.emit()
	queue_free()
