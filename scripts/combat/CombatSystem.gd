# === CombatSystem.gd ===
# Turn-based battle engine. Drives an async round/turn loop: enemies act via AI,
# players act when the UI submits an action. Emits signals the CombatScene binds
# to. Pure rules — no visuals.
class_name CombatSystem
extends Node

signal combat_log(text: String)
signal turn_started(combatant: Combatant)
signal state_changed()
signal awaiting_action(combatant: Combatant)
signal combat_ended(result: String)  # "victory" | "defeat" | "fled"

signal _action_submitted()

const STANDARD_MP_REGEN: int = 2
const FLEE_CHANCE: float = 0.6

var party: Array[Combatant] = []
var enemies: Array[Combatant] = []
var result: String = "ongoing"

var _pending: Dictionary = {}


func start(p_party: Array[Combatant], p_enemies: Array[Combatant]) -> void:
	party = p_party
	enemies = p_enemies
	result = "ongoing"
	_run()


## Called by the UI to resolve the current player's turn.
func submit_action(action: String, target: Combatant = null, skill_id: String = "", item_id: String = "") -> void:
	_pending = {"action": action, "target": target, "skill_id": skill_id, "item_id": item_id}
	_action_submitted.emit()


# === Main loop ===
func _run() -> void:
	combat_log.emit("Battle begins!")
	while result == "ongoing":
		for c: Combatant in _initiative():
			if not c.is_alive() or result != "ongoing":
				continue
			turn_started.emit(c)
			c.defending = false
			if c.is_disabled():
				combat_log.emit("%s can't move!" % c.display_name)
			elif c.is_player:
				awaiting_action.emit(c)
				await _action_submitted
				_apply_action(c, _pending)
			else:
				_take_enemy_turn(c)
			state_changed.emit()
			_check_end()
			if result != "ongoing":
				break
		if result == "ongoing":
			_end_of_round()
	_finish()


func _initiative() -> Array[Combatant]:
	var living: Array[Combatant] = []
	for c: Combatant in _all():
		if c.is_alive():
			living.append(c)
	living.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.eff("spd") == b.eff("spd"):
			return a.is_player and not b.is_player
		return a.eff("spd") > b.eff("spd"))
	return living


func _end_of_round() -> void:
	for c: Combatant in _all():
		if not c.is_alive():
			continue
		c.restore_mp(STANDARD_MP_REGEN)
		for line: String in c.tick_statuses():
			combat_log.emit(line)
	_check_end()
	state_changed.emit()


# === Action resolution ===
func _apply_action(actor: Combatant, action: Dictionary) -> void:
	match action.get("action", ""):
		"attack":
			_do_attack(actor, action.get("target"))
		"defend":
			actor.defending = true
			combat_log.emit("%s defends." % actor.display_name)
		"skill":
			_do_skill(actor, DataLoader.get_skill(action.get("skill_id", "")), action.get("target"))
		"item":
			_do_item(actor, action.get("item_id", ""))
		"flee":
			_try_flee(actor)


func _do_attack(actor: Combatant, target: Combatant) -> void:
	if target == null or not target.is_alive():
		target = _first_living(_opponents_of(actor))
	if target == null:
		return
	var raw: int = maxi(1, actor.eff("pwr") - target.eff("def"))
	if target.defending:
		raw = maxi(1, int(ceil(raw / 2.0)))
	var dealt: int = target.take_damage(raw)
	combat_log.emit("%s hits %s for %d." % [actor.display_name, target.display_name, dealt])


func _do_skill(actor: Combatant, skill: SkillDef, target: Combatant) -> void:
	if skill == null:
		return
	if not actor.spend_mp(skill.mp_cost):
		combat_log.emit("%s lacks the MP." % actor.display_name)
		return
	combat_log.emit("%s uses %s!" % [actor.display_name, skill.name])
	for effect: Dictionary in skill.effects:
		_apply_effect(actor, skill, effect, target)


func _apply_effect(actor: Combatant, skill: SkillDef, effect: Dictionary, target: Combatant) -> void:
	var targets: Array[Combatant] = _resolve_targets(actor, skill.target, target)
	match effect.get("kind", ""):
		"damage":
			var base: int = skill.power
			if effect.has("random_min"):
				base = randi_range(int(effect.random_min), int(effect.random_max))
			var val: int = Stats.skill_value(base, actor.eff("wit"))
			if effect.has("multiplier"):
				val = int(round(val * float(effect.multiplier)))
			for t: Combatant in targets:
				var dealt: int = t.take_damage(maxi(1, val))
				combat_log.emit("%s takes %d." % [t.display_name, dealt])
		"heal":
			var amount: int = Stats.skill_value(skill.power, actor.eff("wit"))
			for t: Combatant in targets:
				var healed: int = t.heal(amount)
				combat_log.emit("%s recovers %d HP." % [t.display_name, healed])
		"stun", "sleep":
			for t: Combatant in targets:
				t.add_status({"kind": effect.kind, "turns": int(effect.get("turns", 1)) + 1})
				combat_log.emit("%s is %sed!" % [t.display_name, effect.kind])
		"buff":
			for t: Combatant in targets:
				t.add_status({"kind": "buff", "stat": effect.stat, "amount": int(effect.amount), "turns": int(effect.get("turns", 3)) + 1, "name": effect.get("name", "Buff")})
				combat_log.emit("%s gains %s." % [t.display_name, effect.get("name", "a buff")])
		"debuff":
			for t: Combatant in targets:
				t.add_status({"kind": "debuff", "stat": effect.stat, "amount": int(effect.amount), "turns": int(effect.get("turns", 3)) + 1, "name": effect.get("name", "Debuff")})
				combat_log.emit("%s is weakened (%s)." % [t.display_name, effect.stat.to_upper()])
		"steal":
			var loot: int = randi_range(2, 5)
			if actor.is_player and actor.player_state != null:
				actor.player_state.bytes += loot
			combat_log.emit("%s borrows %d Bytes (without asking)." % [actor.display_name, loot])


func _do_item(actor: Combatant, item_id: String) -> void:
	var item: ItemDef = DataLoader.get_item(item_id)
	if item == null:
		return
	if actor.is_player and actor.player_state != null:
		actor.player_state.inventory.erase(item_id)
	var effect: Dictionary = item.effect
	match effect.get("kind", ""):
		"heal":
			combat_log.emit("%s heals %d HP." % [actor.display_name, actor.heal(int(effect.amount))])
		"restore_mp":
			actor.restore_mp(int(effect.amount))
			combat_log.emit("%s restores %d MP." % [actor.display_name, int(effect.amount)])
		"flee_guarantee":
			combat_log.emit("%s vanishes in smoke." % actor.display_name)
			result = "fled"
		_:
			combat_log.emit("%s uses %s." % [actor.display_name, item.name])


func _try_flee(actor: Combatant) -> void:
	var has_boss: bool = false
	for e: Combatant in enemies:
		if e.is_boss and e.is_alive():
			has_boss = true
	if has_boss:
		combat_log.emit("There's no fleeing from this fight!")
		return
	if randf() < FLEE_CHANCE:
		combat_log.emit("%s flees!" % actor.display_name)
		result = "fled"
	else:
		combat_log.emit("%s couldn't escape!" % actor.display_name)


# === Enemy AI ===
func _take_enemy_turn(enemy: Combatant) -> void:
	# Flee when low (unlocked goblin behavior), non-boss only.
	if enemy.behavior == "flee_when_low" and not enemy.is_boss and enemy.hp < enemy.max_hp * 0.3:
		if randf() < 0.5:
			combat_log.emit("%s flees the battle!" % enemy.display_name)
			enemy.hp = 0  # leaves the fight
			return
	var target: Combatant = _lowest_hp(_living(party))
	if target != null:
		_do_attack(enemy, target)


# === Targeting helpers ===
func _resolve_targets(actor: Combatant, target_kind: String, single: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	match target_kind:
		"all_enemies":
			return _living(_opponents_of(actor))
		"party":
			return _living(party if actor.is_player else enemies)
		"self":
			out.append(actor)
		"ally", "ally_downed":
			out.append(single if single != null else actor)
		_:
			var t: Combatant = single if single != null else _first_living(_opponents_of(actor))
			if t != null:
				out.append(t)
	return out


func _opponents_of(c: Combatant) -> Array[Combatant]:
	return enemies if c.is_player else party


func _living(group: Array[Combatant]) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in group:
		if c.is_alive():
			out.append(c)
	return out


func _first_living(group: Array[Combatant]) -> Combatant:
	for c: Combatant in group:
		if c.is_alive():
			return c
	return null


func _lowest_hp(group: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for c: Combatant in group:
		if best == null or c.hp < best.hp:
			best = c
	return best


func _all() -> Array[Combatant]:
	var out: Array[Combatant] = []
	out.append_array(party)
	out.append_array(enemies)
	return out


# === End conditions ===
func _check_end() -> void:
	if result != "ongoing":
		return
	if _living(enemies).is_empty():
		result = "victory"
	elif _living(party).is_empty():
		result = "defeat"


func _finish() -> void:
	for c: Combatant in party:
		c.sync_to_player()
	combat_ended.emit(result)
