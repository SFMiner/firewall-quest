# === PlayerState.gd ===
# A single player character's persistent state. Derived max stats are recomputed
# from class + level + equipment; current HP/MP are tracked separately so combat
# damage persists. Serializes to the GDD section-13 save schema (extended with
# equipped_armor, since Shield/Steel Armor occupy an armor slot).
class_name PlayerState
extends RefCounted

const SAVE_VERSION: String = "1.0"

var player_name: String = ""
var class_id: String = "fighter"
var level: int = 1
var xp: int = 0
var bytes: int = 0

# Current (mutable) pools; max values live in `max_stats`.
var hp: int = 0
var mp: int = 0

# Derived max stats {hp, mp, pwr, spd, def, wit} after level + equipment.
var max_stats: Dictionary = {}

var equipped_weapon: String = ""
var equipped_armor: String = ""
var inventory: Array[String] = []
var flags: Dictionary = {}


## Build a fresh level-1 character of the given class, fully healed.
static func create(p_name: String, p_class_id: String) -> PlayerState:
	var ps: PlayerState = PlayerState.new()
	ps.player_name = p_name
	ps.class_id = p_class_id
	ps.level = 1
	ps.xp = 0
	ps.bytes = 0
	ps.recompute_stats()
	ps.hp = ps.max_hp()
	ps.mp = ps.max_mp()
	return ps


## Recompute max_stats from class base + level growth + equipped gear.
func recompute_stats() -> void:
	var class_def: ClassDef = DataLoader.get_class_def(class_id)
	if class_def == null:
		push_error("PlayerState: unknown class '%s'" % class_id)
		return
	level = Stats.level_for_xp(xp)
	var base: Dictionary = Stats.compute_stats(class_def, level)
	var mods: Array = _equipment_mods()
	max_stats = Stats.apply_equipment(base, mods)
	# Clamp current pools to new maxima.
	hp = clampi(hp, 0, max_hp()) if hp > 0 else max_hp()
	mp = clampi(mp, 0, max_mp()) if max_stats.has("mp") else mp


func max_hp() -> int:
	return int(max_stats.get("hp", 0))

func max_mp() -> int:
	return int(max_stats.get("mp", 0))

func stat(key: String) -> int:
	return int(max_stats.get(key, 0))


## Award XP and re-derive level/stats. Returns true if the level changed.
func add_xp(amount: int) -> bool:
	var old_level: int = level
	xp += maxi(0, amount)
	recompute_stats()
	return level != old_level


func equip(item_id: String) -> void:
	var item: ItemDef = DataLoader.get_item(item_id)
	if item == null or not item.is_equipment():
		return
	if item.slot == "weapon":
		equipped_weapon = item_id
	elif item.slot == "armor":
		equipped_armor = item_id
	recompute_stats()


func _equipment_mods() -> Array:
	var mods: Array = []
	for item_id: String in [equipped_weapon, equipped_armor]:
		if item_id.is_empty():
			continue
		var item: ItemDef = DataLoader.get_item(item_id)
		if item != null:
			mods.append(item.stat_mods)
	return mods


# === Serialization (GDD section 13 schema) ===
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"player_name": player_name,
		"class": class_id,
		"level": level,
		"xp": xp,
		"bytes": bytes,
		"stats": {
			"hp": hp, "max_hp": max_hp(),
			"mp": mp, "max_mp": max_mp(),
			"pwr": stat("pwr"), "spd": stat("spd"),
			"def": stat("def"), "wit": stat("wit"),
		},
		"equipped_weapon": equipped_weapon,
		"equipped_armor": equipped_armor,
		"inventory": inventory,
		"flags": flags,
	}


static func from_dict(data: Dictionary) -> PlayerState:
	var ps: PlayerState = PlayerState.new()
	ps.player_name = data.get("player_name", "")
	ps.class_id = data.get("class", "fighter")
	ps.xp = int(data.get("xp", 0))
	ps.bytes = int(data.get("bytes", 0))
	ps.equipped_weapon = data.get("equipped_weapon", "")
	ps.equipped_armor = data.get("equipped_armor", "")
	ps.flags = data.get("flags", {})
	for item_id: String in data.get("inventory", []):
		ps.inventory.append(item_id)
	# Re-derive maxima from class + level + equipment, then restore current pools.
	ps.recompute_stats()
	var stats: Dictionary = data.get("stats", {})
	ps.hp = int(stats.get("hp", ps.max_hp()))
	ps.mp = int(stats.get("mp", ps.max_mp()))
	return ps
