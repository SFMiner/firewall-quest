# === Main.gd ===
# Persistent root / scene-flow owner. Boots into the main menu and swaps the
# active "screen" (menu -> character creation -> explore -> combat) below itself,
# mirroring the persistent-root pattern. M0: only the menu exists; New Game and
# Continue are stubbed until M2 wires character creation + the explore scene.
extends Node

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main/MainMenu.tscn")

var _current_screen: Node = null


func _ready() -> void:
	_show_main_menu()


func _show_main_menu() -> void:
	var menu: Control = MAIN_MENU_SCENE.instantiate()
	menu.new_game_requested.connect(_on_new_game)
	menu.continue_requested.connect(_on_continue)
	_set_screen(menu)


# STUB: character creation + explore scene land in M2.
func _on_new_game() -> void:
	print("[Main] New Game requested — character creation arrives in M2.")


# STUB: load save then enter explore scene (M2).
func _on_continue() -> void:
	var data: Dictionary = SaveManager.load_game()
	print("[Main] Continue requested — loaded save keys: %s" % str(data.keys()))


# Replace the active screen, freeing the previous one.
func _set_screen(screen: Node) -> void:
	if _current_screen != null and is_instance_valid(_current_screen):
		_current_screen.queue_free()
	_current_screen = screen
	add_child(screen)
