# === GameManager.gd ===
# Global world state for Firewall Quest. The single source of truth for the
# firewall-power "sanitation layer" that everything keys off (shop stock, NPC
# lines, palette, zone unlocks). Autoload singleton — access as `GameManager`.
extends Node

## Emitted whenever firewall_power changes. Listeners (HUD, NPCs, shop, palette)
## react to the new value. old_value lets transitions animate the delta.
signal firewall_power_changed(new_value: int, old_value: int)

## Emitted when a zone crosses from locked to unlocked.
signal zone_unlocked(zone_id: String)

## Emitted when a story/quest flag flips, so UI can refresh.
signal flag_changed(flag: String, value: bool)

## World-state spine: 100 = fully sanitized, 0 = fully unlocked (final area open).
## Reduced by 25 per Firewall Boss defeated.
var firewall_power: int = 100

## Id of the zone the player currently occupies (e.g. "welcometon", "zone1").
var current_zone: String = "welcometon"

## Firewall bosses defeated this run (e.g. ["vice_principal"]).
var bosses_defeated: Array[String] = []

## Arbitrary story flags (met_cerys, found_plague_mask, ...).
var flags: Dictionary = {}

## The active player character. Populated at character creation (M2); restored
## from a save on Continue.
var player_state: PlayerState = null

## True while a blocking UI (dialogue, shop, menu) is open. Exploration input
## (movement, interaction) must early-return while this is set.
var ui_blocking: bool = false

## True to suppress roaming enemy encounters (e.g. during the Hall Monitor lure puzzle).
var encounters_paused: bool = false


## Reduce firewall power by one boss-worth (clamped 0–100) and fire signals.
func defeat_firewall_boss(boss_id: String) -> void:
	if boss_id in bosses_defeated:
		return
	bosses_defeated.append(boss_id)
	var old_value: int = firewall_power
	firewall_power = clampi(firewall_power - 25, 0, 100)
	firewall_power_changed.emit(firewall_power, old_value)


## True once a zone's gating threshold has been reached. Thresholds follow the
## GDD world-state table (zone1 at <=75, zone2 at <=50, zone3 at <=25, zone4 at 0).
func is_zone_unlocked(zone_id: String) -> bool:
	match zone_id:
		"welcometon": return true
		"zone1": return firewall_power <= 75
		"zone2": return firewall_power <= 50
		"zone3": return firewall_power <= 25
		"zone4": return firewall_power <= 0
		_: return false


## Set a story flag and notify listeners.
func set_flag(flag: String, value: bool = true) -> void:
	if flags.get(flag, false) == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: String) -> bool:
	return flags.get(flag, false)


## Adopt a firewall value pushed by the host (multiplayer guests). Emits the
## change signal so the HUD/filter react, without re-running defeat logic.
func adopt_firewall_power(value: int) -> void:
	if value == firewall_power:
		return
	var old_value: int = firewall_power
	firewall_power = value
	firewall_power_changed.emit(firewall_power, old_value)


## Restore world + player state from a loaded (flat) save dict.
func apply_save_dict(data: Dictionary) -> void:
	firewall_power = int(data.get("firewall_power", 100))
	current_zone = data.get("current_zone", "welcometon")
	bosses_defeated.clear()
	for boss_id: String in data.get("bosses_defeated", []):
		bosses_defeated.append(boss_id)
	flags = data.get("flags", {})
	player_state = PlayerState.from_dict(data)
