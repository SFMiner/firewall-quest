# === m3_test.gd ===
# Milestone 3 validation: combat resolution, skills, rewards/level-up, defeat
# respawn, and boss firewall reduction. Drives CombatSystem directly (no UI).
#   Godot ... res://scenes/dev/M3Test.tscn --quit-after 200
extends Node

var _failures: int = 0
var _checks: int = 0
var _skill_used: bool = false


func _ready() -> void:
	await _test_attack_win()
	await _test_skill_win()
	_test_rewards_and_levelup()
	_test_defeat_respawn()
	_test_boss_firewall()
	print("=== M3 TEST: %d/%d checks passed ===" % [_checks - _failures, _checks])
	print("M3 RESULT: %s" % ("PASS" if _failures == 0 else "FAIL(%d)" % _failures))
	get_tree().quit(_failures)


func _test_attack_win() -> void:
	print("- attack win vs Sorry Goblin")
	GameManager.firewall_power = 100
	var ps: PlayerState = PlayerState.create("Hero", "fighter")
	var party: Array[Combatant] = [Combatant.from_player(ps)]
	var enemies: Array[Combatant] = [Combatant.from_enemy(DataLoader.get_enemy("goblin"), 100)]
	var sys: CombatSystem = _make_system()
	sys.awaiting_action.connect(func(_c: Combatant) -> void: sys.submit_action.call_deferred("attack"))
	sys.start(party, enemies)
	var result: String = await sys.combat_ended
	_check("result victory", result == "victory")
	_check("goblin defeated", not enemies[0].is_alive())
	_check("player survived", party[0].is_alive())
	sys.queue_free()


func _test_skill_win() -> void:
	print("- skill win (Mage Hypothesis costs MP)")
	GameManager.firewall_power = 100
	var ps: PlayerState = PlayerState.create("Mage", "mage")
	var party: Array[Combatant] = [Combatant.from_player(ps)]
	var enemies: Array[Combatant] = [Combatant.from_enemy(DataLoader.get_enemy("goblin"), 100)]
	var combatant: Combatant = party[0]
	var sys: CombatSystem = _make_system()
	_skill_used = false
	sys.awaiting_action.connect(func(_c: Combatant) -> void:
		if not _skill_used:
			_skill_used = true
			sys.submit_action.call_deferred("skill", null, "hypothesis")
		else:
			sys.submit_action.call_deferred("attack"))
	sys.start(party, enemies)
	var result: String = await sys.combat_ended
	_check("skill battle won", result == "victory")
	_check("MP was spent (< 10)", combatant.mp < 10)
	sys.queue_free()


func _test_rewards_and_levelup() -> void:
	print("- rewards + level up at 100 XP")
	var ps: PlayerState = PlayerState.create("Hero", "fighter")
	ps.xp = 90
	GameManager.player_state = ps
	var goblin: Combatant = Combatant.from_enemy(DataLoader.get_enemy("goblin"), 100)
	Combat._apply_results("victory", [goblin])
	_check("XP reward = 10", Combat.last_rewards.get("xp", 0) == 10)
	_check("Bytes awarded (>=2)", Combat.last_rewards.get("bytes", 0) >= 2)
	_check("leveled up (90->100 = L2)", Combat.last_rewards.get("leveled", false))
	_check("player now level 2", ps.level == 2)


func _test_defeat_respawn() -> void:
	print("- defeat -> respawn at hub, full heal, no permadeath")
	var ps: PlayerState = PlayerState.create("Hero", "fighter")
	ps.hp = 0
	GameManager.player_state = ps
	GameManager.current_zone = "zone1"
	Combat._apply_results("defeat", [])
	_check("HP restored to max", ps.hp == ps.max_hp())
	_check("respawned in welcometon", GameManager.current_zone == "welcometon")


func _test_boss_firewall() -> void:
	print("- boss kill reduces firewall power")
	GameManager.firewall_power = 100
	GameManager.bosses_defeated.clear()
	var ps: PlayerState = PlayerState.create("Hero", "fighter")
	GameManager.player_state = ps
	var boss: Combatant = Combatant.from_enemy(DataLoader.get_enemy("vice_principal"), 100)
	Combat._apply_results("victory", [boss])
	_check("firewall 100 -> 75", GameManager.firewall_power == 75)
	_check("boss XP = 100", Combat.last_rewards.get("xp", 0) == 100)
	_check("boss recorded", "vice_principal" in GameManager.bosses_defeated)


func _make_system() -> CombatSystem:
	var sys: CombatSystem = CombatSystem.new()
	add_child(sys)
	return sys


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
