# === Main.gd ===
# Persistent root / scene-flow owner. Boots into the main menu and swaps the
# active "screen" (menu -> character creation -> explore) below itself, mirroring
# the persistent-root pattern.
extends Node

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main/MainMenu.tscn")
const CHARACTER_CREATION_SCENE: PackedScene = preload("res://scenes/main/CharacterCreation.tscn")
const EXPLORE_SCENE: PackedScene = preload("res://scenes/explore/ExploreScene.tscn")

var _current_screen: Node = null


func _ready() -> void:
	_show_main_menu()


func _show_main_menu() -> void:
	var menu: Control = MAIN_MENU_SCENE.instantiate()
	menu.new_game_requested.connect(_on_new_game)
	menu.continue_requested.connect(_on_continue)
	_set_screen(menu)


# New Game -> character creation.
func _on_new_game() -> void:
	var creation: CharacterCreation = CHARACTER_CREATION_SCENE.instantiate()
	creation.confirmed.connect(_on_character_confirmed)
	_set_screen(creation)


# Character confirmed -> build state, start a fresh run in Welcometon.
func _on_character_confirmed(player_name: String, class_id: String, portrait: String) -> void:
	var ps: PlayerState = PlayerState.create(player_name, class_id)
	ps.flags["portrait"] = portrait
	GameManager.player_state = ps
	GameManager.firewall_power = 100
	GameManager.current_zone = "welcometon"
	GameManager.bosses_defeated.clear()
	GameManager.flags = {}
	PartyManager.start_solo(ps.to_dict())
	_enter_explore()


# Continue -> restore save, resume in the saved zone.
func _on_continue() -> void:
	var data: Dictionary = SaveManager.load_game()
	if data.is_empty():
		return
	GameManager.apply_save_dict(data)
	PartyManager.start_solo(GameManager.player_state.to_dict())
	_enter_explore()


func _enter_explore() -> void:
	var explore: ExploreScene = EXPLORE_SCENE.instantiate()
	explore.player_defeated.connect(_on_player_defeated)
	_set_screen(explore)


# After a defeat, Combat has healed the player and set the zone to the hub;
# rebuild the explore scene there (respawn at the nearest save point).
func _on_player_defeated() -> void:
	_enter_explore()


# Replace the active screen, freeing the previous one.
func _set_screen(screen: Node) -> void:
	if _current_screen != null and is_instance_valid(_current_screen):
		_current_screen.queue_free()
	_current_screen = screen
	add_child(screen)
