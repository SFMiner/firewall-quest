# === ClassDef.gd ===
# A playable character class, loaded from data/classes.json.
class_name ClassDef
extends RefCounted

var id: String = ""
var sanitized_name: String = ""
var unlocked_name: String = ""
var role: String = ""
var primary_stat: String = "pwr"
var base_stats: Dictionary = {}
var sanitized_skill: String = ""
var unlocked_skills: Array[String] = []
var portrait: String = ""


static func from_dict(data: Dictionary) -> ClassDef:
	var c: ClassDef = ClassDef.new()
	c.id = data.get("id", "")
	c.sanitized_name = data.get("sanitized_name", "")
	c.unlocked_name = data.get("unlocked_name", "")
	c.role = data.get("role", "")
	c.primary_stat = data.get("primary_stat", "pwr")
	c.base_stats = data.get("base_stats", {})
	c.sanitized_skill = data.get("sanitized_skill", "")
	c.portrait = data.get("portrait", "")
	for s: String in data.get("unlocked_skills", []):
		c.unlocked_skills.append(s)
	return c


## Display name for the current world state (sanitized until the firewall lifts).
func display_name(firewall_power: int) -> String:
	return sanitized_name if firewall_power > 0 else unlocked_name
