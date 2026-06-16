# === m1_test.gd ===
# Headless validation for Milestone 1: data loading, leveling math, WIT scaling,
# equipment, and the save round-trip. Run as a scene so autoloads are available:
#   Godot_v4.6-stable_win64.exe --headless --path . res://scenes/dev/M1Test.tscn --quit-after 60
extends Node

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	print("=== M1 TEST START ===")
	_test_data_loads()
	_test_leveling()
	_test_wit_scaling()
	_test_equipment()
	_test_save_round_trip()
	print("=== M1 TEST: %d/%d checks passed ===" % [_checks - _failures, _checks])
	if _failures == 0:
		print("M1 RESULT: PASS")
	else:
		print("M1 RESULT: FAIL (%d)" % _failures)
	get_tree().quit(_failures)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _eq(label: String, got: Variant, want: Variant) -> void:
	_check("%s (got %s, want %s)" % [label, str(got), str(want)], got == want)


func _test_data_loads() -> void:
	print("- data loads")
	DataLoader.load_all()
	_eq("class count", DataLoader.all_classes().size(), 5)
	_check("rogue exists", DataLoader.get_class_def("rogue") != null)
	_check("foam_sword exists", DataLoader.get_item("foam_sword") != null)
	_check("hypothesis skill exists", DataLoader.get_skill("hypothesis") != null)
	_check("goblin enemy exists", DataLoader.get_enemy("goblin") != null)
	_check("welcometon zone exists", DataLoader.get_zone("welcometon") != null)
	_check("gerald npc exists", not DataLoader.get_npc("gerald").is_empty())


func _test_leveling() -> void:
	print("- leveling math (formula authoritative; section-13 sample is illustrative)")
	_eq("level for 0 xp", Stats.level_for_xp(0), 1)
	_eq("level for 100 xp", Stats.level_for_xp(100), 2)
	_eq("level for 215 xp", Stats.level_for_xp(215), 3)
	_eq("level cap at 900", Stats.level_for_xp(900), 10)
	_eq("level cap above 900", Stats.level_for_xp(5000), 10)

	var rogue: PlayerState = PlayerState.create("Kevin", "rogue")
	rogue.add_xp(215)
	_eq("rogue level", rogue.level, 3)
	# Formula: base 20/10/4/4/2/3, growth_steps=2, primary=spd (+1 extra/level).
	_eq("rogue hp", rogue.max_hp(), 24)
	_eq("rogue mp", rogue.max_mp(), 14)
	_eq("rogue pwr", rogue.stat("pwr"), 6)
	_eq("rogue spd", rogue.stat("spd"), 8)
	_eq("rogue def", rogue.stat("def"), 4)
	_eq("rogue wit", rogue.stat("wit"), 5)


func _test_wit_scaling() -> void:
	print("- WIT skill scaling")
	_eq("multiplier(5)", Stats.skill_multiplier(5), 1.5)
	_eq("skill_value(12, 5)", Stats.skill_value(12, 5), 18)
	_eq("skill_value(10, 0)", Stats.skill_value(10, 0), 10)


func _test_equipment() -> void:
	print("- equipment mods")
	var fighter: PlayerState = PlayerState.create("Tank", "fighter")
	var base_pwr: int = fighter.stat("pwr")
	var base_def: int = fighter.stat("def")
	fighter.equip("foam_sword")
	_eq("foam_sword +1 pwr", fighter.stat("pwr"), base_pwr + 1)
	fighter.equip("shield")
	_eq("shield +2 def", fighter.stat("def"), base_def + 2)


func _test_save_round_trip() -> void:
	print("- save round-trip")
	var ps: PlayerState = PlayerState.create("Kevin", "rogue")
	ps.add_xp(215)
	ps.bytes = 42
	ps.equip("foam_sword")
	ps.inventory = ["health_potion", "smoke_bomb"]
	ps.hp = 20

	GameManager.player_state = ps
	GameManager.firewall_power = 75
	GameManager.current_zone = "zone1"
	GameManager.bosses_defeated = ["vice_principal"]
	GameManager.flags = { "met_cerys": true, "found_plague_mask": false }

	var before: Dictionary = SaveManager._collect_save_data()
	var saved: bool = SaveManager.save()
	_check("save() succeeded", saved)

	var loaded: Dictionary = SaveManager.load_game()
	_check("load returned data", not loaded.is_empty())
	_eq("firewall_power persisted", int(loaded.get("firewall_power", -1)), 75)
	_eq("bytes persisted", int(loaded.get("bytes", -1)), 42)

	# Reconstruct a PlayerState and confirm it serializes identically.
	var restored: PlayerState = PlayerState.from_dict(loaded)
	var after: Dictionary = restored.to_dict()
	_eq("player_name round-trips", after.get("player_name"), before.get("player_name"))
	_eq("class round-trips", after.get("class"), before.get("class"))
	_eq("level round-trips", after.get("level"), before.get("level"))
	_eq("stats round-trip", JSON.stringify(after.get("stats")), JSON.stringify(before.get("stats")))
	_eq("equipped_weapon round-trips", after.get("equipped_weapon"), "foam_sword")
	_eq("inventory round-trips", JSON.stringify(after.get("inventory")), JSON.stringify(["health_potion", "smoke_bomb"]))
