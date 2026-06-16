# === m5_test.gd ===
# Milestone 5 validation: full firewall 100->0 boss chain, the Wellness Counselor
# dialogue-battle resolution, ADMIN-9 phase transitions, and Stack Overflow's
# turn-limit overflow.
#   Godot ... res://scenes/dev/M5Test.tscn --quit-after 200
extends Node

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_test_full_progression()
	await _test_wellness_dialogue_battle()
	_test_admin9_phases()
	await _test_stack_overflow()
	print("=== M5 TEST: %d/%d checks passed ===" % [_checks - _failures, _checks])
	print("M5 RESULT: %s" % ("PASS" if _failures == 0 else "FAIL(%d)" % _failures))
	get_tree().quit(_failures)


func _test_full_progression() -> void:
	print("- full firewall 100 -> 0 across all four bosses")
	GameManager.firewall_power = 100
	GameManager.flags = {}
	GameManager.bosses_defeated.clear()
	GameManager.player_state = PlayerState.create("Hero", "fighter")
	Combat.resolve_boss("vice_principal")
	_check("VP -> firewall 75", GameManager.firewall_power == 75)
	_check("Administrative Override dropped", "administrative_override" in GameManager.player_state.inventory)
	Combat.resolve_boss("wellness_counselor")
	_check("Counselor -> firewall 50", GameManager.firewall_power == 50)
	_check("Counselor is recruitable", DataLoader.get_enemy("wellness_counselor").recruitable)
	Combat.resolve_boss("hall_monitor_prime")
	_check("Hall Monitor -> firewall 25", GameManager.firewall_power == 25)
	Combat.resolve_boss("admin_9")
	_check("ADMIN-9 -> firewall 0", GameManager.firewall_power == 0)
	_check("all four bosses recorded", GameManager.bosses_defeated.size() == 4)
	_check("ADMIN-9 is the final boss", DataLoader.get_enemy("admin_9").final_boss)


func _test_wellness_dialogue_battle() -> void:
	print("- Wellness Counselor survey resolves via dialogue")
	GameManager.flags = {}
	var res: DialogueResource = load("res://dialogue/zone2.dialogue")
	var states: Array = [GameManager, Quests]
	var key: String = "wellness_counselor"
	var line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, key, states)
	var guard: int = 0
	while line != null and guard < 40:
		guard += 1
		if line.responses.size() > 0:
			key = line.responses[0].next_id
		else:
			key = line.next_id
		if key.is_empty():
			break
		line = await DialogueManager.get_next_dialogue_line(res, key, states)
	_check("survey set the resolved flag", GameManager.get_flag("boss_resolved_wellness_counselor"))


func _test_admin9_phases() -> void:
	print("- ADMIN-9 escalates through 3 phases")
	var sys: CombatSystem = CombatSystem.new()
	add_child(sys)
	var admin: Combatant = Combatant.from_enemy(DataLoader.get_enemy("admin_9"), 0)
	sys.party = []
	sys.enemies = [admin]
	_check("starts in phase 1", int(admin.special.get("phase", 0)) == 1)
	admin.hp = int(admin.max_hp * 0.6)
	sys._maybe_phase(admin)
	_check("escalates to phase 2 at <=66%", int(admin.special.phase) == 2)
	admin.hp = int(admin.max_hp * 0.3)
	sys._maybe_phase(admin)
	_check("overrides to phase 3 at <=33%", int(admin.special.phase) == 3)
	sys.queue_free()


func _test_stack_overflow() -> void:
	print("- Stack Overflow overflows if not killed by turn 5")
	GameManager.firewall_power = 0
	var ps: PlayerState = PlayerState.create("Hero", "fighter")
	GameManager.player_state = ps
	var party: Array[Combatant] = [Combatant.from_player(ps)]
	var enemies: Array[Combatant] = [Combatant.from_enemy(DataLoader.get_enemy("stack_overflow"), 0)]
	var sys: CombatSystem = CombatSystem.new()
	add_child(sys)
	# Player only defends -> can't kill it -> it overflows and wipes the party.
	sys.awaiting_action.connect(func(_c: Combatant) -> void: sys.submit_action.call_deferred("defend"))
	sys.start(party, enemies)
	var result: String = await sys.combat_ended
	_check("unchecked Stack Overflow wipes the party", result == "defeat")
	sys.queue_free()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
