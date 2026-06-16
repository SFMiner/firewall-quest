# === CombatManager.gd ===
# Orchestrates encounters: builds combatants, shows the CombatScene, awaits the
# result, then applies rewards (XP/Bytes/level, firewall on boss kills) or respawn
# on defeat. Autoload — `Combat`.
extends Node

signal encounter_finished(result: String)

const COMBAT_SCENE: PackedScene = preload("res://scenes/combat/CombatScene.tscn")

var _active: bool = false
## Populated after each victory: {xp, bytes, leveled}.
var last_rewards: Dictionary = {}


## Run a battle against the given enemy ids. Returns "victory"/"defeat"/"fled".
func run_encounter(enemy_ids: Array) -> String:
	if _active:
		return "busy"
	_active = true
	GameManager.ui_blocking = true
	var party: Array[Combatant] = _build_party()
	var enemies: Array[Combatant] = _build_enemies(enemy_ids)
	var scene: CombatScene = COMBAT_SCENE.instantiate()
	get_tree().root.add_child(scene)
	scene.setup(party, enemies)
	var result: String = await scene.finished
	scene.queue_free()
	_apply_results(result, enemies)
	GameManager.ui_blocking = false
	_active = false
	encounter_finished.emit(result)
	return result


# Apply a boss's victory rewards without a combat (e.g. the Wellness Counselor's
# dialogue-battle resolves her instead of fighting).
func resolve_boss(boss_id: String) -> void:
	var ed: EnemyDef = DataLoader.get_enemy(boss_id)
	if ed == null:
		return
	var c: Combatant = Combatant.from_enemy(ed, GameManager.firewall_power)
	c.hp = 0
	_award_victory([c])


func _build_party() -> Array[Combatant]:
	var arr: Array[Combatant] = []
	if GameManager.player_state != null:
		arr.append(Combatant.from_player(GameManager.player_state))
	return arr


func _build_enemies(enemy_ids: Array) -> Array[Combatant]:
	var arr: Array[Combatant] = []
	for id: String in enemy_ids:
		var ed: EnemyDef = DataLoader.get_enemy(id)
		if ed != null:
			arr.append(Combatant.from_enemy(ed, GameManager.firewall_power))
	return arr


func _apply_results(result: String, enemies: Array[Combatant]) -> void:
	last_rewards = {"xp": 0, "bytes": 0, "leveled": false}
	if result == "victory":
		_award_victory(enemies)
	elif result == "defeat":
		_respawn()


func _award_victory(enemies: Array[Combatant]) -> void:
	var ps: PlayerState = GameManager.player_state
	var xp: int = 0
	var bytes: int = 0
	for e: Combatant in enemies:
		if e.enemy_def == null:
			continue
		xp += e.enemy_def.xp
		bytes += e.enemy_def.roll_bytes()
		if not e.enemy_def.defeat_drop.is_empty() and ps != null:
			ps.inventory.append(e.enemy_def.defeat_drop)
		if e.enemy_def.firewall_boss:
			GameManager.defeat_firewall_boss(e.enemy_def.id)
	var leveled: bool = false
	if ps != null:
		ps.bytes += bytes
		leveled = ps.add_xp(xp)
	last_rewards = {"xp": xp, "bytes": bytes, "leveled": leveled}


# No permadeath: full heal and return to the hub (nearest save point).
func _respawn() -> void:
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.recompute_stats()
		ps.hp = ps.max_hp()
		ps.mp = ps.max_mp()
	GameManager.current_zone = "welcometon"
