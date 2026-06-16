# === MainMenu.gd ===
# Title screen. Emits intent signals; Main.gd owns what actually happens on each.
# Co-op (Host/Join) requires a configured Supabase backend.
extends Control

signal new_game_requested()
signal continue_requested()
signal host_requested()
signal join_requested()

@onready var _continue_button: Button = %ContinueButton
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton


func _ready() -> void:
	# Continue is only available when a save exists.
	_continue_button.disabled = not SaveManager.has_save()
	# Co-op needs the backend configured (res://supabase.cfg).
	var online: bool = SupabaseManager.is_configured
	_host_button.disabled = not online
	_join_button.disabled = not online
	if not online:
		_host_button.tooltip_text = "Co-op needs a Supabase backend (see supabase.cfg)."
		_join_button.tooltip_text = _host_button.tooltip_text


func _on_new_game_pressed() -> void:
	Audio.sfx("menu")
	new_game_requested.emit()


func _on_continue_pressed() -> void:
	Audio.sfx("menu")
	continue_requested.emit()


func _on_host_pressed() -> void:
	Audio.sfx("menu")
	host_requested.emit()


func _on_join_pressed() -> void:
	Audio.sfx("menu")
	join_requested.emit()


func _on_settings_pressed() -> void:
	Audio.sfx("menu")
	var panel: Control = preload("res://scenes/ui/SettingsPanel.tscn").instantiate()
	add_child(panel)


func _on_quit_pressed() -> void:
	Audio.sfx("menu")
	get_tree().quit()
