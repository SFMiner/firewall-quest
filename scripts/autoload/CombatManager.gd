# === CombatManager.gd ===
# Orchestrates encounters: builds combatants, shows the CombatScene, awaits the
# result, then applies rewards (XP/Bytes/level, firewall on boss kills) or respawn
# on defeat. Autoload — `Combat`.
extends Node

signal encounter_finished(result: String)

const COMBAT_SCENE: PackedScene = preload("res://scenes/combat/CombatScene.tscn")
## Per CLAUDE.md "NEXT TASK — Layer 2": no response from a remote player's turn
## for this long auto-Defends; after REMOTE_AI_STRIKES consecutive timeouts (or
## a stale heartbeat) the host's simple AI takes over that player's turns.
const REMOTE_ACTION_TIMEOUT: float = 30.0
const REMOTE_AI_STRIKES: int = 3
## Boss HP multiplier for a party of n: 1 + BOSS_SCALE_PER_EXTRA * (n - 1).
const BOSS_SCALE_PER_EXTRA: float = 0.6

var _active: bool = false
## Populated after each victory: {xp, bytes, leveled}.
var last_rewards: Dictionary = {}

# === Shared-party combat (host relay state) ===
var _mp_turn_owner: String = ""
var _mp_zone_id: String = ""
var _mp_log_tail: Array[String] = []
var _remote_timeouts: Dictionary = {}  # owner_id -> consecutive timeout count

# === Shared-party combat (guest viewer state) ===
var _viewer_layer: CanvasLayer = null
var _viewer_scene: CombatScene = null
var _viewer_open: bool = false


func _ready() -> void:
	PartyManager.combat_state_changed.connect(_on_remote_combat_changed)


## Run a battle against the given enemy ids. Returns "victory"/"defeat"/"fled".
func run_encounter(enemy_ids: Array) -> String:
	if _active:
		return "busy"
	_active = true
	GameManager.ui_blocking = true
	var party: Array[Combatant] = _build_party()
	var enemies: Array[Combatant] = _build_enemies(enemy_ids)
	# Host the combat UI on a CanvasLayer so it renders in screen space — immune to
	# the explore Camera2D's zoom/pan — and above the explore HUD (layer 2).
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 5
	get_tree().root.add_child(layer)
	var scene: CombatScene = COMBAT_SCENE.instantiate()
	layer.add_child(scene)
	scene.setup(party, enemies)
	var result: String = await scene.finished
	layer.queue_free()
	_apply_results(result, enemies)
	GameManager.ui_blocking = false
	_active = false
	encounter_finished.emit(result)
	return result


## Shared-party combat (host-authoritative). Builds the MP party from
## PartyManager.members **filtered to `zone_id`** (only players actually
## standing where the fight happened join it), runs the real CombatSystem
## locally, relays remote players' turns by polling the shared `combat.actions`
## blob, and pushes a display snapshot to the room on every change so guests
## can render it. If the host itself isn't in `zone_id`, it runs the fight
## headlessly — no full-screen takeover on a screen that isn't part of it.
func run_shared_encounter(enemy_ids: Array, zone_id: String) -> String:
	if _active:
		return "busy"
	if not PartyManager.is_host:
		return "not_host"
	_active = true
	_remote_timeouts.clear()
	_mp_log_tail.clear()
	_mp_zone_id = zone_id
	var party: Array[Combatant] = _build_mp_party(zone_id)
	var enemies: Array[Combatant] = _build_mp_enemies(enemy_ids, party.size())
	var system: CombatSystem = CombatSystem.new()
	add_child(system)
	_wire_relay(system)
	_wire_snapshot_push(system)
	var show_locally: bool = zone_id == GameManager.current_zone
	var layer: CanvasLayer = null
	var scene: CombatScene = null
	if show_locally:
		GameManager.ui_blocking = true
		layer = CanvasLayer.new()
		layer.layer = 5
		get_tree().root.add_child(layer)
		scene = COMBAT_SCENE.instantiate()
		layer.add_child(scene)
		scene.setup_for_host(party, enemies, system, PartyManager.local_id)
	system.start(party, enemies)
	var result: String = await (scene.finished if show_locally else system.combat_ended)
	system.queue_free()
	if layer != null:
		layer.queue_free()
	_apply_results(result, enemies)
	await _push_final_rewards()
	if show_locally:
		GameManager.ui_blocking = false
	_active = false
	encounter_finished.emit(result)
	return result


func _build_mp_party(zone_id: String) -> Array[Combatant]:
	var arr: Array[Combatant] = []
	for m: Dictionary in PartyManager.members:
		if m.get("zone", "") != zone_id:
			continue
		var owner_id: String = m.get("id", "")
		var ps: PlayerState
		if owner_id == PartyManager.local_id and GameManager.player_state != null:
			ps = GameManager.player_state
		else:
			ps = PlayerState.from_dict(m.get("data", {}))
		arr.append(Combatant.from_player(ps, owner_id))
	return arr


func _build_mp_enemies(enemy_ids: Array, party_size: int) -> Array[Combatant]:
	var arr: Array[Combatant] = _build_enemies(enemy_ids)
	if party_size > 1:
		var mult: float = 1.0 + BOSS_SCALE_PER_EXTRA * float(party_size - 1)
		for c: Combatant in arr:
			if c.is_boss:
				c.max_hp = int(round(c.max_hp * mult))
				c.hp = c.max_hp
	return arr


# === Host relay: take remote players' turns on their behalf ===
func _wire_relay(system: CombatSystem) -> void:
	system.awaiting_action.connect(_on_relay_awaiting_action.bind(system))


func _on_relay_awaiting_action(c: Combatant, system: CombatSystem) -> void:
	if c.owner_id != "" and c.owner_id != PartyManager.local_id:
		_relay_remote_turn(system, c)


func _relay_remote_turn(system: CombatSystem, c: Combatant) -> void:
	if not c.ai_controlled and _is_member_offline(c.owner_id):
		c.ai_controlled = true
	if c.ai_controlled:
		_take_ai_action(system, c)
		return
	var act: Dictionary = await _await_remote_action(c.owner_id)
	if system.result != "ongoing":
		return
	if act.is_empty():
		_note_timeout(c)
		if c.ai_controlled:
			_take_ai_action(system, c)
		else:
			system.submit_action("defend")
		return
	_remote_timeouts[c.owner_id] = 0
	var target_idx: int = int(act.get("target_index", -1))
	var target: Combatant = system.enemies[target_idx] if target_idx >= 0 and target_idx < system.enemies.size() else null
	system.submit_action(act.get("action", "defend"), target, act.get("skill_id", ""), act.get("item_id", ""))


func _await_remote_action(owner_id: String) -> Dictionary:
	var elapsed: float = 0.0
	while elapsed < REMOTE_ACTION_TIMEOUT:
		var actions: Dictionary = PartyManager.game_state.get("combat", {}).get("actions", {})
		if actions.has(owner_id):
			var act: Dictionary = actions[owner_id]
			actions.erase(owner_id)
			return act
		await get_tree().create_timer(0.4).timeout
		elapsed += 0.4
	return {}


func _note_timeout(c: Combatant) -> void:
	var n: int = int(_remote_timeouts.get(c.owner_id, 0)) + 1
	_remote_timeouts[c.owner_id] = n
	if n >= REMOTE_AI_STRIKES:
		c.ai_controlled = true


func _is_member_offline(owner_id: String) -> bool:
	for m: Dictionary in PartyManager.members:
		if m.get("id", "") == owner_id:
			return not m.get("online", true)
	return true


## Simple takeover AI: attack the lowest-HP enemy.
func _take_ai_action(system: CombatSystem, c: Combatant) -> void:
	if system.result != "ongoing":
		return
	var target: Combatant = system._lowest_hp(system._living(system.enemies))
	system.submit_action("attack", target)


# === Host: push a display snapshot to the room on every change ===
func _wire_snapshot_push(system: CombatSystem) -> void:
	system.combat_log.connect(_on_mp_log)
	system.turn_started.connect(_on_mp_turn_started.bind(system))
	system.state_changed.connect(func() -> void: _push_snapshot(system))
	system.awaiting_action.connect(func(_c: Combatant) -> void: _push_snapshot(system))
	system.combat_ended.connect(func(_r: String) -> void: _push_snapshot(system))


func _on_mp_log(line: String) -> void:
	_mp_log_tail.append(line)
	if _mp_log_tail.size() > 8:
		_mp_log_tail = _mp_log_tail.slice(_mp_log_tail.size() - 8)


func _on_mp_turn_started(c: Combatant, system: CombatSystem) -> void:
	_mp_turn_owner = c.owner_id
	_push_snapshot(system)


func _push_snapshot(system: CombatSystem) -> void:
	if not PartyManager.is_host:
		return
	var combat: Dictionary = PartyManager.game_state.get("combat", {})
	var actions: Dictionary = combat.get("actions", {})
	var combatants: Array = []
	for c: Combatant in system.party:
		combatants.append(c.to_snapshot())
	for c: Combatant in system.enemies:
		combatants.append(c.to_snapshot())
	var snapshot: Dictionary = {
		"active": system.result == "ongoing",
		"zone": _mp_zone_id,
		"party_count": system.party.size(),
		"combatants": combatants,
		"turn_owner": _mp_turn_owner,
		"log": _mp_log_tail,
		"result": system.result,
		"actions": actions,
	}
	PartyManager.host_set("combat", snapshot)


## Pushed once more right after rewards are computed (combat_ended's snapshot
## fires before _apply_results runs), so guests can apply the same XP/Bytes.
func _push_final_rewards() -> void:
	if not PartyManager.is_host:
		return
	var combat: Dictionary = PartyManager.game_state.get("combat", {})
	combat["rewards"] = last_rewards
	await PartyManager.host_set("combat", combat)


# === Host: pick up encounter requests from guests ===
func _maybe_start_requested_encounter() -> void:
	if _active:
		return
	var combat: Dictionary = PartyManager.game_state.get("combat", {})
	var req: Dictionary = combat.get("requested", {})
	if req.is_empty():
		return
	var enemy_ids: Array = req.get("enemy_ids", [])
	var zone_id: String = req.get("zone", "")
	combat.erase("requested")
	PartyManager.game_state["combat"] = combat
	run_shared_encounter(enemy_ids, zone_id)


# === Guest: open/close a read-only viewer when the host's combat is active ===
func _on_remote_combat_changed() -> void:
	if PartyManager.is_host:
		_maybe_start_requested_encounter()
		return
	if _viewer_open:
		return
	var combat: Dictionary = PartyManager.game_state.get("combat", {})
	if combat.get("active", false) and combat.get("zone", "") == GameManager.current_zone:
		_open_viewer()


func _open_viewer() -> void:
	_viewer_open = true
	GameManager.ui_blocking = true
	_viewer_layer = CanvasLayer.new()
	_viewer_layer.layer = 5
	get_tree().root.add_child(_viewer_layer)
	_viewer_scene = COMBAT_SCENE.instantiate()
	_viewer_layer.add_child(_viewer_scene)
	_viewer_scene.finished.connect(_close_viewer)
	_viewer_scene.setup_viewer()


func _close_viewer(result: String) -> void:
	_apply_guest_rewards(result)
	if _viewer_scene != null and is_instance_valid(_viewer_scene):
		_viewer_scene.queue_free()
	if _viewer_layer != null and is_instance_valid(_viewer_layer):
		_viewer_layer.queue_free()
	_viewer_scene = null
	_viewer_layer = null
	_viewer_open = false
	GameManager.ui_blocking = false
	encounter_finished.emit(result)


func _apply_guest_rewards(result: String) -> void:
	last_rewards = {"xp": 0, "bytes": 0, "leveled": false}
	if result == "victory":
		var combat: Dictionary = PartyManager.game_state.get("combat", {})
		var rewards: Dictionary = combat.get("rewards", {})
		var ps: PlayerState = GameManager.player_state
		var xp: int = int(rewards.get("xp", 0))
		var bytes: int = int(rewards.get("bytes", 0))
		var leveled: bool = false
		if ps != null:
			ps.bytes += bytes
			leveled = ps.add_xp(xp)
		last_rewards = {"xp": xp, "bytes": bytes, "leveled": leveled}
	elif result == "defeat":
		_respawn()


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
