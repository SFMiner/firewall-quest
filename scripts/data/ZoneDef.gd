# === ZoneDef.gd ===
# A zone / area, loaded from data/zones/<id>.json.
class_name ZoneDef
extends RefCounted

var id: String = ""
var display_name: String = ""
var is_hub: bool = false
var always_real: bool = false
var unlock_firewall_max: int = 100
var music: Dictionary = {}
var palette: Dictionary = {}
var npcs: Array[String] = []
var enemies: Array[String] = []
var points_of_interest: Array[String] = []
var boss: String = ""
var boss_intro: String = ""
var quests: Array = []
var tilemap: String = ""


static func from_dict(data: Dictionary) -> ZoneDef:
	var z: ZoneDef = ZoneDef.new()
	z.id = data.get("id", "")
	z.display_name = data.get("display_name", "")
	z.is_hub = data.get("is_hub", false)
	z.always_real = data.get("always_real", false)
	z.unlock_firewall_max = int(data.get("unlock_firewall_max", 100))
	z.music = data.get("music", {})
	z.palette = data.get("palette", {})
	z.boss = str(data.get("boss", "")) if data.get("boss") != null else ""
	z.boss_intro = str(data.get("boss_intro", "")) if data.get("boss_intro") != null else ""
	z.quests = data.get("quests", [])
	z.tilemap = data.get("tilemap", "")
	for n: String in data.get("npcs", []):
		z.npcs.append(n)
	for en: String in data.get("enemies", []):
		z.enemies.append(en)
	for p: String in data.get("points_of_interest", []):
		z.points_of_interest.append(p)
	return z


## Is this zone "real" (unlocked) right now?
func is_unlocked(firewall_power: int) -> bool:
	return always_real or firewall_power <= unlock_firewall_max


## "sanitized" or "unlocked" palette/music key for the current state.
func state_key(firewall_power: int) -> String:
	return "unlocked" if is_unlocked(firewall_power) else "sanitized"
