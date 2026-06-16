# === SupabaseManager.gd ===
# Single wrapper for all Supabase backend calls (multiplayer rooms, mod registry,
# cloud saves). Keeps the backend interface clean and testable. Autoload — `SupabaseManager`.
# STUB: methods are async-shaped and return mock data so callers can be written
# now; real HTTPRequest / JavaScriptBridge wiring lands in M6.
extends Node

## Set from .env at startup (never commit secrets). Empty until M6.
var _url: String = ""
var _anon_key: String = ""

## True once configured with real credentials.
var is_configured: bool = false


func _ready() -> void:
	# Real config load (.env / export var) happens in M6. Stub stays offline.
	is_configured = false


# === Multiplayer rooms (M6) ===
## Create a room and return its 4-char join code. STUB returns a mock code.
func create_room(host_id: String) -> String:
	await _mock_delay()
	return "MOCK"


## Join an existing room by code. STUB always "succeeds" offline.
func join_room(code: String, player_id: String) -> bool:
	await _mock_delay()
	return false


# === Mod registry (M7) ===
## Fetch published mods. STUB returns an empty list.
func fetch_mods() -> Array:
	await _mock_delay()
	return []


## Upload a mod's sanitized JSON. STUB no-ops. Real sanitization is server-side (M7).
func upload_mod(mod_json: Dictionary) -> bool:
	await _mock_delay()
	return false


# === Cloud saves (M6) ===
func push_save(player_id: String, save_data: Dictionary) -> bool:
	await _mock_delay()
	return false


func pull_save(player_id: String) -> Dictionary:
	await _mock_delay()
	return {}


# A one-frame await so stubbed async calls behave like the real ones.
func _mock_delay() -> void:
	await get_tree().process_frame
