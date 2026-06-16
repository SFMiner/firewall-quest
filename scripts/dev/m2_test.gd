# === m2_test.gd ===
# Milestone 2 validation: a new run builds Welcometon with the expected entities,
# the shop purchase flow works, and an Inn-style save round-trips. Run as a scene:
#   Godot ... res://scenes/dev/M2Test.tscn --quit-after 120
extends Node

const EXPLORE_SCENE: PackedScene = preload("res://scenes/explore/ExploreScene.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/ui/Shop.tscn")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	await _run()
	print("=== M2 TEST: %d/%d checks passed ===" % [_checks - _failures, _checks])
	print("M2 RESULT: %s" % ("PASS" if _failures == 0 else "FAIL(%d)" % _failures))
	get_tree().quit(_failures)


func _run() -> void:
	# --- New game ---
	var ps: PlayerState = PlayerState.create("Kevin", "rogue")
	GameManager.player_state = ps
	GameManager.firewall_power = 100
	GameManager.current_zone = "welcometon"
	GameManager.bosses_defeated.clear()
	GameManager.flags = {}
	PartyManager.start_solo(ps.to_dict())
	_check("gauge reads 100", GameManager.firewall_power == 100)
	_check("solo party of one", PartyManager.party_size() == 1)

	# --- Welcometon builds ---
	var explore: ExploreScene = EXPLORE_SCENE.instantiate()
	add_child(explore)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("player in 'player' group", get_tree().get_nodes_in_group("player").size() == 1)
	_check("4 NPCs placed", get_tree().get_nodes_in_group("npc").size() == 4)
	_check("10 interactables (4 NPC + 6 POI)", get_tree().get_nodes_in_group("interactable").size() == 10)

	var gerald: NPC = _find_npc("gerald")
	_check("Gerald exists", gerald != null)
	if gerald != null:
		_check("Gerald name", gerald.npc_name == "Gerald the Blacksmith")
		_check("Gerald interact prompt", gerald.interact_prompt() == "Talk to Gerald the Blacksmith")

	# --- Shop: buy a Foam Sword ---
	ps.bytes = 50
	var shop: Shop = SHOP_SCENE.instantiate()
	add_child(shop)
	shop.open()
	await get_tree().process_frame
	shop._on_buy("foam_sword")
	_check("Foam Sword equipped", ps.equipped_weapon == "foam_sword")
	_check("Bytes deducted 50->45", ps.bytes == 45)
	_check("PWR includes weapon (+1)", ps.stat("pwr") == 5)  # rogue L1 pwr 4 + foam 1
	shop._on_close_pressed()
	_check("ui unblocked after shop", GameManager.ui_blocking == false)

	# --- Save (as the Inn would) and restore ---
	var saved: bool = SaveManager.save()
	_check("save succeeded", saved)
	# Simulate a fresh boot + Continue.
	GameManager.player_state = null
	GameManager.firewall_power = 0
	var data: Dictionary = SaveManager.load_game()
	GameManager.apply_save_dict(data)
	_check("class restored", GameManager.player_state.class_id == "rogue")
	_check("name restored", GameManager.player_state.player_name == "Kevin")
	_check("weapon restored", GameManager.player_state.equipped_weapon == "foam_sword")
	_check("bytes restored", GameManager.player_state.bytes == 45)
	_check("firewall restored to 100", GameManager.firewall_power == 100)
	_check("zone restored", GameManager.current_zone == "welcometon")


func _find_npc(id: String) -> NPC:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if n is NPC and n.npc_id == id:
			return n
	return null


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
