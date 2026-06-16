# === Credits.gd ===
# Shown after ADMIN-9 falls: a short roll, then the post-game "build something"
# prompt (the hook into the mod editor, M7). Returns to the title.
extends CanvasLayer

const CREDITS_TEXT: String = """FIREWALL QUEST

The world is real again.
The kids are home.
The game is still there, waiting.


A farewell gift.
The joke was the point.
The heart was real.


This world is yours now.
Build something."""


func _ready() -> void:
	GameManager.ui_blocking = true
	%Text.text = CREDITS_TEXT


func _on_return_pressed() -> void:
	GameManager.ui_blocking = false
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
