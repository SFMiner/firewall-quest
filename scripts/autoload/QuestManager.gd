# === QuestManager.gd ===
# Lightweight flag-based quests. Stages live in GameManager.flags under "q_<id>".
# Stage 0 = not started, 1+ = in progress, DONE = complete. Methods are named so
# .dialogue files can drive quests directly (the NPC passes Quests as a game state).
# Autoload — `Quests`.
extends Node

signal quest_updated(quest_id: String, stage: int)

const DONE: int = 99


func start_quest(quest_id: String) -> void:
	if quest_stage(quest_id) == 0:
		set_quest_stage(quest_id, 1)


func set_quest_stage(quest_id: String, stage: int) -> void:
	GameManager.flags["q_" + quest_id] = stage
	quest_updated.emit(quest_id, stage)


func quest_stage(quest_id: String) -> int:
	return int(GameManager.flags.get("q_" + quest_id, 0))


func quest_active(quest_id: String) -> bool:
	var s: int = quest_stage(quest_id)
	return s >= 1 and s < DONE


func quest_done(quest_id: String) -> bool:
	return quest_stage(quest_id) >= DONE


## Finish a quest and award its XP (once).
func complete_quest(quest_id: String) -> void:
	if quest_done(quest_id):
		return
	set_quest_stage(quest_id, DONE)
	var xp: int = _quest_xp(quest_id)
	if GameManager.player_state != null:
		GameManager.player_state.add_xp(xp)


## All quests for the current zone with their state, for the quest board.
func zone_quest_status(zone_id: String) -> Array[String]:
	var out: Array[String] = []
	var zone: ZoneDef = DataLoader.get_zone(zone_id)
	if zone == null:
		return out
	for q: Dictionary in zone.quests:
		var id: String = q.get("id", "")
		var mark: String = "[x]" if quest_done(id) else ("[~]" if quest_active(id) else "[ ]")
		out.append("%s %s" % [mark, q.get("name", id)])
	return out


func _quest_xp(quest_id: String) -> int:
	var q: Dictionary = DataLoader.get_quest(quest_id)
	return int(q.get("xp", 20)) if not q.is_empty() else 20
