# === Combatant.gd ===
# One participant in a battle (a party member or an enemy). Pure logic/state;
# the combat UI binds visuals to it. Built from a PlayerState or an EnemyDef.
#
# Statuses are a flat list of dicts:
#   {kind="buff"/"debuff", stat, amount, turns, name}
#   {kind="stun"/"sleep", turns}
#   {kind="poison", amount, turns}
class_name Combatant
extends RefCounted

var id: String = ""
var display_name: String = ""
var is_player: bool = false
var is_boss: bool = false
var behavior: String = ""

# Visuals: "lpc" (sprite_ref = char name) or "battler" (sprite_ref = texture path).
var sprite_kind: String = "battler"
var sprite_ref: String = ""

var max_hp: int = 1
var max_mp: int = 0
var hp: int = 1
var mp: int = 0

# Base stats (status modifiers applied via eff()).
var pwr: int = 0
var spd: int = 0
var def: int = 0
var wit: int = 0

var defending: bool = false
var statuses: Array[Dictionary] = []

# Back-references for persisting results / data lookups.
var player_state: PlayerState = null
var enemy_def: EnemyDef = null


static func from_player(ps: PlayerState) -> Combatant:
	var c: Combatant = Combatant.new()
	c.id = "player"
	c.is_player = true
	c.player_state = ps
	var class_def: ClassDef = DataLoader.get_class_def(ps.class_id)
	c.display_name = ps.player_name
	c.sprite_kind = "lpc"
	c.sprite_ref = ps.class_id
	c.max_hp = ps.max_hp()
	c.max_mp = ps.max_mp()
	c.hp = ps.hp
	c.mp = ps.mp
	c.pwr = ps.stat("pwr")
	c.spd = ps.stat("spd")
	c.def = ps.stat("def")
	c.wit = ps.stat("wit")
	return c


static func from_enemy(enemy_def: EnemyDef, firewall_power: int) -> Combatant:
	var c: Combatant = Combatant.new()
	var s: Dictionary = enemy_def.stats_for(firewall_power)
	c.id = enemy_def.id
	c.enemy_def = enemy_def
	c.is_boss = enemy_def.tier == "boss"
	c.behavior = s.get("behavior", "basic")
	c.display_name = s.get("name", enemy_def.id)
	c.sprite_kind = "battler"
	c.sprite_ref = "res://assets/enemies/%s.png" % s.get("sprite", enemy_def.id)
	c.max_hp = int(s.get("hp", 1))
	c.hp = c.max_hp
	c.max_mp = 0
	c.mp = 0
	c.pwr = int(s.get("pwr", 1))
	c.spd = int(s.get("spd", 1))
	c.def = int(s.get("def", 0))
	c.wit = int(s.get("wit", 0))
	return c


func is_alive() -> bool:
	return hp > 0


## Effective stat after buffs/debuffs (never below 0).
func eff(stat: String) -> int:
	var base: int = get(stat)
	var delta: int = 0
	for st: Dictionary in statuses:
		if st.get("stat", "") == stat:
			if st.kind == "buff":
				delta += int(st.amount)
			elif st.kind == "debuff":
				delta -= int(st.amount)
	return maxi(0, base + delta)


func take_damage(amount: int) -> int:
	var dealt: int = maxi(0, amount)
	hp = maxi(0, hp - dealt)
	return dealt


func heal(amount: int) -> int:
	var before: int = hp
	hp = mini(max_hp, hp + maxi(0, amount))
	return hp - before


func spend_mp(amount: int) -> bool:
	if mp < amount:
		return false
	mp -= amount
	return true


func restore_mp(amount: int) -> void:
	mp = mini(max_mp, mp + amount)


func is_disabled() -> bool:
	return has_status("stun") or has_status("sleep")


func has_status(kind: String) -> bool:
	for st: Dictionary in statuses:
		if st.kind == kind:
			return true
	return false


func add_status(status: Dictionary) -> void:
	statuses.append(status)


## End-of-turn upkeep: poison damage, then decrement/expire durations.
## Returns log lines describing what happened.
func tick_statuses() -> Array[String]:
	var log: Array[String] = []
	var remaining: Array[Dictionary] = []
	for st: Dictionary in statuses:
		if st.kind == "poison" and is_alive():
			var dmg: int = take_damage(int(st.get("amount", 1)))
			log.append("%s takes %d poison damage." % [display_name, dmg])
		st.turns = int(st.get("turns", 1)) - 1
		if st.turns > 0:
			remaining.append(st)
		else:
			log.append("%s's %s wears off." % [display_name, st.get("name", st.kind)])
	statuses = remaining
	return log


## Write combat results (current HP/MP) back to the source PlayerState.
func sync_to_player() -> void:
	if is_player and player_state != null:
		player_state.hp = hp
		player_state.mp = mp
