# === SaveManager.gd ===
# Persists a single-player save. Detects platform at runtime and routes to
# localStorage (web, via JavaScriptBridge) or user:// (desktop). Autoload — `SaveManager`.
# STUB: round-trips an in-memory dictionary; real schema wiring lands in M1.
extends Node

const SAVE_VERSION: String = "1.0"
const USER_SAVE_PATH: String = "user://save.json"
const LOCALSTORAGE_KEY: String = "firewall_quest_save"

## True when running the HTML5 export (localStorage path) vs desktop (user://).
var _is_web: bool = false


func _ready() -> void:
	_is_web = OS.get_name() == "Web"


## Serialize current game state and persist it. Returns true on success.
func save() -> bool:
	var data: Dictionary = _collect_save_data()
	var json: String = JSON.stringify(data)
	if _is_web:
		return _write_localstorage(json)
	return _write_user_file(json)


## Load persisted state into the game. Returns the parsed dict, or {} if none.
func load_game() -> Dictionary:
	var json: String = _read_localstorage() if _is_web else _read_user_file()
	if json.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(json)
	if parsed is Dictionary:
		return parsed
	return {}


func has_save() -> bool:
	if _is_web:
		return not _read_localstorage().is_empty()
	return FileAccess.file_exists(USER_SAVE_PATH)


# === Save payload (flat GDD section-13 schema: player fields + world state) ===
func _collect_save_data() -> Dictionary:
	var data: Dictionary = {}
	if GameManager.player_state != null:
		data = GameManager.player_state.to_dict()
	data["version"] = SAVE_VERSION
	data["firewall_power"] = GameManager.firewall_power
	data["current_zone"] = GameManager.current_zone
	data["bosses_defeated"] = GameManager.bosses_defeated
	# World/story flags live at the top level (override PlayerState's own flags key).
	data["flags"] = GameManager.flags
	return data


# === Desktop (user://) ===
func _write_user_file(json: String) -> bool:
	var f: FileAccess = FileAccess.open(USER_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open %s for writing" % USER_SAVE_PATH)
		return false
	f.store_string(json)
	f.close()
	return true


func _read_user_file() -> String:
	if not FileAccess.file_exists(USER_SAVE_PATH):
		return ""
	var f: FileAccess = FileAccess.open(USER_SAVE_PATH, FileAccess.READ)
	if f == null:
		return ""
	var json: String = f.get_as_text()
	f.close()
	return json


# === Web (localStorage via JavaScriptBridge) ===
func _write_localstorage(json: String) -> bool:
	if not _has_js_bridge():
		return false
	var js: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
	if js == null:
		return false
	js.setItem(LOCALSTORAGE_KEY, json)
	return true


func _read_localstorage() -> String:
	if not _has_js_bridge():
		return ""
	var js: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
	if js == null:
		return ""
	var value: Variant = js.getItem(LOCALSTORAGE_KEY)
	return str(value) if value != null else ""


func _has_js_bridge() -> bool:
	return _is_web and OS.has_feature("web")
