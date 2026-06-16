# === Stats.gd ===
# The single home for stat / leveling / skill-scaling math (GDD section 4).
# Pure static functions — no state.
#
# NOTE: the GDD's section-13 sample save (level-3 rogue = HP26/MP16/PWR5/...) is
# illustrative and does NOT match the section-4 growth formula. The formula here
# is authoritative: it is the actual game rule. Growth applies (level - 1) times.
class_name Stats
extends RefCounted

const MAX_LEVEL: int = 10
const XP_PER_LEVEL: int = 100

# Per-level growth (GDD section 4).
const HP_PER_LEVEL: int = 2
const MP_PER_LEVEL: int = 2
const OTHER_PER_LEVEL: int = 1       # pwr, spd, def, wit each +1/level
const PRIMARY_BONUS_PER_LEVEL: int = 1  # extra +1 to the class primary stat

const STAT_KEYS: Array[String] = ["hp", "mp", "pwr", "spd", "def", "wit"]


## Character level for a given total XP. level = floor(xp / 100) + 1, capped at 10.
static func level_for_xp(total_xp: int) -> int:
	return clampi(total_xp / XP_PER_LEVEL + 1, 1, MAX_LEVEL)


## Minimum total XP required to be at a given level.
static func xp_for_level(level: int) -> int:
	return maxi(0, (clampi(level, 1, MAX_LEVEL) - 1) * XP_PER_LEVEL)


## XP still needed to reach the next level (0 at max level).
static func xp_to_next(total_xp: int) -> int:
	var level: int = level_for_xp(total_xp)
	if level >= MAX_LEVEL:
		return 0
	return xp_for_level(level + 1) - total_xp


## Compute max stats for a class at a level from its base stats + growth.
## Returns a dict with all STAT_KEYS. Equipment mods are applied separately.
static func compute_stats(class_def: ClassDef, level: int) -> Dictionary:
	var lvl: int = clampi(level, 1, MAX_LEVEL)
	var growth_steps: int = lvl - 1
	var base: Dictionary = class_def.base_stats
	var primary: String = class_def.primary_stat
	var out: Dictionary = {}
	for key: String in STAT_KEYS:
		var start: int = int(base.get(key, 0))
		var per_level: int = _growth_for(key)
		if key == primary:
			per_level += PRIMARY_BONUS_PER_LEVEL
		out[key] = start + per_level * growth_steps
	return out


## Apply flat equipment stat mods on top of a computed stat dict (returns a copy).
static func apply_equipment(base_stats: Dictionary, mods: Array) -> Dictionary:
	var out: Dictionary = base_stats.duplicate()
	for mod: Dictionary in mods:
		for key: String in mod.keys():
			out[key] = int(out.get(key, 0)) + int(mod[key])
	return out


## Skill effectiveness multiplier from WIT: base * (1 + WIT/10).
static func skill_multiplier(wit: int) -> float:
	return 1.0 + float(wit) / 10.0


## A skill's effective damage/heal value: round(power * multiplier(wit)).
static func skill_value(power: int, wit: int) -> int:
	return int(round(float(power) * skill_multiplier(wit)))


static func _growth_for(stat_key: String) -> int:
	match stat_key:
		"hp": return HP_PER_LEVEL
		"mp": return MP_PER_LEVEL
		_: return OTHER_PER_LEVEL
