# === EnemyEncounter.gd ===
# A roaming/placed enemy in the overworld. Walking into it starts a battle.
# On victory/flee it's consumed; on defeat the caller handles respawn.
class_name EnemyEncounter
extends Area2D

signal resolved(result: String)

@export var enemy_ids: Array[String] = []

var _triggered: bool = false


func _ready() -> void:
	add_to_group("encounter")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true
	_run()


func _run() -> void:
	var result: String = await Combat.run_encounter(enemy_ids)
	resolved.emit(result)
	if result == "victory" or result == "fled":
		queue_free()
	else:
		_triggered = false
