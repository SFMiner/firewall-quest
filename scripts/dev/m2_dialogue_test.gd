# === m2_dialogue_test.gd ===
# Validates that welcometon.dialogue compiles and Gerald's firewall-branched lines
# resolve against GameManager game-state. Run as a scene (autoloads needed):
#   Godot ... res://scenes/dev/M2DialogueTest.tscn --quit-after 90
extends Node

var _failures: int = 0


func _ready() -> void:
	await _run()
	print("M2 DIALOGUE RESULT: %s" % ("PASS" if _failures == 0 else "FAIL(%d)" % _failures))
	get_tree().quit(_failures)


func _run() -> void:
	var res: DialogueResource = load("res://dialogue/welcometon.dialogue")
	_check("dialogue resource loaded", res != null)

	GameManager.firewall_power = 100
	var line_100: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "gerald", [GameManager])
	_check("100%% -> foam line (got: %s)" % _short(line_100), line_100 != null and "foam" in line_100.text)

	GameManager.firewall_power = 50
	var line_50: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "gerald", [GameManager])
	_check("50%% -> swords line (got: %s)" % _short(line_50), line_50 != null and "Swords" in line_50.text)

	GameManager.firewall_power = 0
	var line_0: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "gerald", [GameManager])
	_check("0%% -> emporium line (got: %s)" % _short(line_0), line_0 != null and "EMPORIUM" in line_0.text)

	var cerys: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "cerys", [GameManager])
	_check("cerys title resolves (speaker: %s)" % (cerys.character if cerys else "<null>"), cerys != null and cerys.character == "Cerys")


func _short(line: DialogueLine) -> String:
	return line.text.substr(0, 24) if line != null else "<null>"


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
