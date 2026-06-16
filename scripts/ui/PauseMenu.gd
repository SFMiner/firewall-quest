# === PauseMenu.gd ===
# Explore pause overlay: Resume / Settings / Save / Quit to Title. Holds
# GameManager.ui_blocking while open so the world is frozen.
extends CanvasLayer

signal resumed()

@onready var _feedback: Label = %Feedback


func _ready() -> void:
	GameManager.ui_blocking = true


func _on_resume_pressed() -> void:
	Audio.sfx("menu")
	GameManager.ui_blocking = false
	resumed.emit()
	queue_free()


func _on_settings_pressed() -> void:
	Audio.sfx("menu")
	var panel: Control = preload("res://scenes/ui/SettingsPanel.tscn").instantiate()
	add_child(panel)


func _on_save_pressed() -> void:
	Audio.sfx("coin")
	_feedback.text = "Game saved." if SaveManager.save() else "Save failed."


func _on_title_pressed() -> void:
	Audio.sfx("menu")
	GameManager.ui_blocking = false
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
