# === ItemDef.gd ===
# An item (consumable or equipment), loaded from data/items.json.
class_name ItemDef
extends RefCounted

var id: String = ""
var name: String = ""
var type: String = "consumable"  # consumable | equipment
var slot: String = ""            # weapon | armor (equipment only)
var cost: int = 0
var unlock_firewall_max: int = 100  # available while GameManager.firewall_power <= this
var sanitized: bool = false
var stat_mods: Dictionary = {}   # equipment: {stat: amount}
var effect: Dictionary = {}      # consumable: {kind, ...}
var description: String = ""


static func from_dict(data: Dictionary) -> ItemDef:
	var i: ItemDef = ItemDef.new()
	i.id = data.get("id", "")
	i.name = data.get("name", "")
	i.type = data.get("type", "consumable")
	i.slot = data.get("slot", "")
	i.cost = int(data.get("cost", 0))
	i.unlock_firewall_max = int(data.get("unlock_firewall_max", 100))
	i.sanitized = data.get("sanitized", false)
	i.stat_mods = data.get("stat_mods", {})
	i.effect = data.get("effect", {})
	i.description = data.get("description", "")
	return i


func is_equipment() -> bool:
	return type == "equipment"


## True when this item is purchasable at the given firewall power.
func is_available(firewall_power: int) -> bool:
	return firewall_power <= unlock_firewall_max
