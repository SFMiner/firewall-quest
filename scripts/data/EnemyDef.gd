# === EnemyDef.gd ===
# An enemy, loaded from data/enemies.json. Carries a sanitized and an unlocked
# stat block; which one is live depends on the zone's firewall state.
class_name EnemyDef
extends RefCounted

var id: String = ""
var zone: String = ""
var tier: String = "standard"  # standard | elite | boss
var xp: int = 0
var bytes_min: int = 0
var bytes_max: int = 0
var firewall_boss: bool = false
var final_boss: bool = false
var recruitable: bool = false
var defeat_drop: String = ""
var defeat_mechanic: String = ""
var sanitized: Dictionary = {}
var unlocked: Dictionary = {}


static func from_dict(data: Dictionary) -> EnemyDef:
	var e: EnemyDef = EnemyDef.new()
	e.id = data.get("id", "")
	e.zone = data.get("zone", "")
	e.tier = data.get("tier", "standard")
	e.xp = int(data.get("xp", 0))
	e.bytes_min = int(data.get("bytes_min", 0))
	e.bytes_max = int(data.get("bytes_max", 0))
	e.firewall_boss = data.get("firewall_boss", false)
	e.final_boss = data.get("final_boss", false)
	e.recruitable = data.get("recruitable", false)
	e.defeat_drop = data.get("defeat_drop", "")
	e.defeat_mechanic = data.get("defeat_mechanic", "")
	e.sanitized = data.get("sanitized", {})
	e.unlocked = data.get("unlocked", {})
	return e


## The live stat block for the given firewall power (sanitized while > 0,
## except bosses/zone4 which read the same block for both states).
func stats_for(firewall_power: int) -> Dictionary:
	return sanitized if firewall_power > 0 else unlocked


## Roll a Bytes drop within the configured range.
func roll_bytes() -> int:
	if bytes_max <= 0:
		return 0
	return randi_range(bytes_min, bytes_max)
