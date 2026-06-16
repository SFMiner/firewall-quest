# === m4_test.gd ===
# Milestone 4 validation: mini-quest flow, the VICE_PRINCIPAL survival mechanic,
# and the world reaction at firewall 75 (Iron Sword stock, Gerald's new bark,
# Zone 1 unlocked / filter lifts).
#   Godot ... res://scenes/dev/M4Test.tscn --quit-after 200
extends Node

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_reset()
	_test_quest_flow()
	await _test_boss_survival()
	_test_world_reaction()
	await _test_gerald_bark_75()
	print("=== M4 TEST: %d/%d checks passed ===" % [_checks - _failures, _checks])
	print("M4 RESULT: %s" % ("PASS" if _failures == 0 else "FAIL(%d)" % _failures))
	get_tree().quit(_failures)


func _reset() -> void:
	GameManager.firewall_power = 100
	GameManager.flags = {}
	GameManager.bosses_defeated.clear()
	GameManager.current_zone = "zone1"
	GameManager.player_state = PlayerState.create("Hero", "fighter")


func _test_quest_flow() -> void:
	print("- mini-quest (turnips) flag flow")
	var ps: PlayerState = GameManager.player_state
	Quests.start_quest("turnips")
	_check("quest active after start", Quests.quest_active("turnips"))
	Quests.set_quest_stage("turnips", 2)
	_check("stage advances to 2 (found)", Quests.quest_stage("turnips") == 2)
	var xp_before: int = ps.xp
	Quests.complete_quest("turnips")
	_check("quest done", Quests.quest_done("turnips"))
	_check("quest XP awarded (+20)", ps.xp == xp_before + 20)
	var board: Array[String] = Quests.zone_quest_status("zone1")
	_check("quest board marks it complete", "[x] The Misplaced Turnips" in board)


func _test_boss_survival() -> void:
	print("- VICE_PRINCIPAL defeated by surviving (out of forms)")
	GameManager.firewall_power = 100
	var ps: PlayerState = PlayerState.create("Hero", "fighter")
	GameManager.player_state = ps
	var party: Array[Combatant] = [Combatant.from_player(ps)]
	var boss: Combatant = Combatant.from_enemy(DataLoader.get_enemy("vice_principal"), 100)
	var enemies: Array[Combatant] = [boss]
	_check("boss starts with 5 forms", boss.special.get("forms", 0) == 5)
	_check("flee is blocked vs boss", boss.is_boss)
	var sys: CombatSystem = CombatSystem.new()
	add_child(sys)
	# Player only defends — win must come from the boss running out of forms.
	sys.awaiting_action.connect(func(_c: Combatant) -> void: sys.submit_action.call_deferred("defend"))
	sys.start(party, enemies)
	var result: String = await sys.combat_ended
	_check("won by survival (victory)", result == "victory")
	_check("player survived", party[0].is_alive())
	sys.queue_free()


func _test_world_reaction() -> void:
	print("- world reaction: boss reward drops firewall to 75")
	GameManager.firewall_power = 100
	GameManager.bosses_defeated.clear()
	var ps: PlayerState = PlayerState.create("Hero", "fighter")
	GameManager.player_state = ps
	var boss: Combatant = Combatant.from_enemy(DataLoader.get_enemy("vice_principal"), 100)
	Combat._apply_results("victory", [boss])
	_check("firewall 100 -> 75", GameManager.firewall_power == 75)
	_check("Administrative Override obtained", "administrative_override" in ps.inventory)
	_check("Zone 1 now unlocked (filter lifts)", DataLoader.get_zone("zone1").is_unlocked(75))
	var stock_ids: Array[String] = []
	for item: ItemDef in DataLoader.items_available(75):
		stock_ids.append(item.id)
	_check("Iron Sword now purchasable", "iron_sword" in stock_ids)
	_check("Welcometon stays accessible", DataLoader.get_zone("welcometon").is_unlocked(75))


func _test_gerald_bark_75() -> void:
	print("- Gerald's bark updates at 75%")
	GameManager.firewall_power = 75
	var res: DialogueResource = load("res://dialogue/welcometon.dialogue")
	var line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "gerald", [GameManager])
	_check("Gerald mentions real swords", line != null and "real swords" in line.text)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
