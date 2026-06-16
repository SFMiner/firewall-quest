# === SkillDef.gd ===
# A class ability, loaded from data/skills.json. Combat resolution reads `effects`
# in M3; M1 just needs them as typed, queryable data.
class_name SkillDef
extends RefCounted

var id: String = ""
var name: String = ""
var tier: String = "sanitized"  # sanitized | unlocked
var mp_cost: int = 3
var target: String = "enemy"    # enemy | all_enemies | ally | ally_downed | party | self
var power: int = 0              # base value scaled by WIT for damage/heal effects
var effects: Array = []         # list of effect dicts {kind, ...}
var description: String = ""


static func from_dict(data: Dictionary) -> SkillDef:
	var s: SkillDef = SkillDef.new()
	s.id = data.get("id", "")
	s.name = data.get("name", "")
	s.tier = data.get("tier", "sanitized")
	s.mp_cost = int(data.get("mp_cost", 3))
	s.target = data.get("target", "enemy")
	s.power = int(data.get("power", 0))
	s.effects = data.get("effects", [])
	s.description = data.get("description", "")
	return s
