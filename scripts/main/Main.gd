# === Main.gd ===
# Persistent root / scene-flow owner. Boots into the main menu and swaps the
# active "screen" (menu -> character creation -> lobby -> explore) below itself,
# mirroring the persistent-root pattern.
extends Node

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main/MainMenu.tscn")
const CHARACTER_CREATION_SCENE: PackedScene = preload("res://scenes/main/CharacterCreation.tscn")
const EXPLORE_SCENE: PackedScene = preload("res://scenes/explore/ExploreScene.tscn")
const LOBBY_SCENE: PackedScene = preload("res://scenes/main/Lobby.tscn")
const JOIN_DIALOG_SCENE: PackedScene = preload("res://scenes/main/JoinDialog.tscn")

# Carried through character creation: "solo" | "host" | "join".
var _pending_mode: String = "solo"
var _pending_code: String = ""

var _current_screen: Node = null


func _ready() -> void:
	_show_main_menu()


func _show_main_menu() -> void:
	var menu: Control = MAIN_MENU_SCENE.instantiate()
	menu.new_game_requested.connect(_on_new_game)
	menu.continue_requested.connect(_on_continue)
	menu.host_requested.connect(_on_host)
	menu.join_requested.connect(_on_join)
	_set_screen(menu)


# === Entry points ===
func _on_new_game() -> void:
	_pending_mode = "solo"
	_show_character_creation()


func _on_host() -> void:
	_pending_mode = "host"
	_show_character_creation()


func _on_join() -> void:
	var dialog: JoinDialog = JOIN_DIALOG_SCENE.instantiate()
	dialog.code_entered.connect(func(code: String) -> void:
		_pending_mode = "join"
		_pending_code = code
		_show_character_creation())
	dialog.cancelled.connect(_show_main_menu)
	_set_screen(dialog)


func _on_continue() -> void:
	var data: Dictionary = SaveManager.load_game()
	if data.is_empty():
		return
	GameManager.apply_save_dict(data)
	PartyManager.start_solo(GameManager.player_state.to_dict())
	_enter_explore()


func _show_character_creation() -> void:
	var creation: CharacterCreation = CHARACTER_CREATION_SCENE.instantiate()
	creation.confirmed.connect(_on_character_confirmed)
	_set_screen(creation)


# Character confirmed -> branch on the pending mode.
func _on_character_confirmed(player_name: String, class_id: String, portrait: String) -> void:
	var ps: PlayerState = PlayerState.create(player_name, class_id)
	ps.flags["portrait"] = portrait
	GameManager.player_state = ps
	GameManager.bosses_defeated.clear()
	GameManager.flags = {}
	match _pending_mode:
		"host":
			var code: String = await PartyManager.host_room(ps.to_dict())
			if code.is_empty():
				_show_main_menu()
				return
			_show_lobby()
		"join":
			var ok: bool = await PartyManager.join_room(_pending_code, ps.to_dict())
			if not ok:
				_show_main_menu()
				return
			_show_lobby()
		_:
			GameManager.firewall_power = 100
			GameManager.current_zone = "welcometon"
			PartyManager.start_solo(ps.to_dict())
			_enter_explore()


func _show_lobby() -> void:
	var lobby: Lobby = LOBBY_SCENE.instantiate()
	lobby.start_game.connect(_on_lobby_start)
	lobby.cancelled.connect(_show_main_menu)
	_set_screen(lobby)


# Host pressed Start, or a guest saw the room go live: adopt the room's shared
# world state and drop everyone into the world.
func _on_lobby_start() -> void:
	GameManager.firewall_power = int(PartyManager.game_state.get("firewall_power", 100))
	GameManager.current_zone = PartyManager.game_state.get("zone", "welcometon")
	_enter_explore()


func _enter_explore() -> void:
	var explore: ExploreScene = EXPLORE_SCENE.instantiate()
	explore.player_defeated.connect(_on_player_defeated)
	explore.zone_change_requested.connect(_on_zone_change_requested)
	_set_screen(explore)


func _on_zone_change_requested(zone_id: String) -> void:
	GameManager.current_zone = zone_id
	_enter_explore()


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
