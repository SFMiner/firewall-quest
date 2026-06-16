# === MainMenu.gd ===
# Title screen. New Game / Continue / Join Code (multiplayer, disabled until M6) /
# Quit. Emits intent signals; Main.gd owns what actually happens on each.
extends Control

signal new_game_requested()
signal continue_requested()

@onready var _continue_button: Button = %ContinueButton
@onready var _join_button: Button = %JoinButton


func _ready() -> void:
	# Continue is only available when a save exists.
	_continue_button.disabled = not SaveManager.has_save()
	# Multiplayer join lands in M6.
	_join_button.disabled = true


func _on_new_game_pressed() -> void:
	Audio.sfx("menu")
	new_game_requested.emit()


func _on_continue_pressed() -> void:
	Audio.sfx("menu")
	continue_requested.emit()


func _on_settings_pressed() -> void:
	Audio.sfx("menu")
	var panel: Control = preload("res://scenes/ui/SettingsPanel.tscn").instantiate()
	add_child(panel)


func _on_quit_pressed() -> void:
	Audio.sfx("menu")
	get_tree().quit()
